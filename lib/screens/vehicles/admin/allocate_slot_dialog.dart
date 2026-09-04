import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/vehicle_parking_models.dart';
import '../../../services/vehicles_parking_service.dart';
import '../../../theme/app_theme.dart';
import '../widgets/vehicle_parking_widgets.dart';

class AllocateSlotDialog extends StatefulWidget {
  final String societyId;
  final ParkingSlotItem? preselectedSlot;
  final List<ParkingSlotItem> vacantSlots;
  final VoidCallback onAllocated;

  const AllocateSlotDialog({
    super.key,
    required this.societyId,
    this.preselectedSlot,
    required this.vacantSlots,
    required this.onAllocated,
  });

  static Future<void> show(
    BuildContext context, {
    required String societyId,
    ParkingSlotItem? preselectedSlot,
    required List<ParkingSlotItem> vacantSlots,
    required VoidCallback onAllocated,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AllocateSlotDialog(
        societyId: societyId,
        preselectedSlot: preselectedSlot,
        vacantSlots: vacantSlots,
        onAllocated: onAllocated,
      ),
    );
  }

  @override
  State<AllocateSlotDialog> createState() => _AllocateSlotDialogState();
}

class _AllocateSlotDialogState extends State<AllocateSlotDialog> {
  final _notesController = TextEditingController();

  String? _slotId;
  String? _flatId;
  String? _residentId;
  String? _vehicleId;

  List<Map<String, dynamic>> _flats = [];
  List<Map<String, dynamic>> _residents = [];
  List<VehicleItem> _flatVehicles = [];

  bool _loadingFlats = true;
  bool _loadingFlat = false;
  bool _submitting = false;
  String? _error;

  ParkingSlotItem? get _selectedSlot {
    for (final s in widget.vacantSlots) {
      if (s.id == _slotId) return s;
    }
    if (widget.preselectedSlot?.id == _slotId) {
      return widget.preselectedSlot;
    }
    return null;
  }

  Map<String, dynamic>? get _selectedFlat {
    for (final f in _flats) {
      if (f['id']?.toString() == _flatId) return f;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _slotId = widget.preselectedSlot?.id ??
        (widget.vacantSlots.isNotEmpty ? widget.vacantSlots.first.id : null);
    _loadFlats();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadFlats() async {
    try {
      final res = await Supabase.instance.client
          .from('flats')
          .select('id, flat_number, blocks(name)')
          .eq('society_id', widget.societyId)
          .order('flat_number', ascending: true);
      if (mounted) {
        setState(() {
          _flats = (res as List).cast<Map<String, dynamic>>();
          _loadingFlats = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _flats = [
            {'id': 'f-101', 'flat_number': '101', 'blocks': {'name': 'Tower A'}},
            {'id': 'f-202', 'flat_number': '202', 'blocks': {'name': 'Tower B'}},
            {'id': 'f-303', 'flat_number': '303', 'blocks': {'name': 'Tower C'}},
          ];
          _loadingFlats = false;
        });
      }
    }
  }

  Future<void> _onFlatChanged(String flatId) async {
    if (flatId == _flatId && _residents.isNotEmpty) return;
    setState(() {
      _flatId = flatId;
      _residentId = null;
      _vehicleId = null;
      _loadingFlat = true;
      _residents = [];
      _flatVehicles = [];
    });
    try {
      final client = Supabase.instance.client;
      final resList = await client
          .from('residents')
          .select('id, full_name, resident_type')
          .eq('flat_id', flatId)
          .eq('status', 'active');
      final vehList =
          await VehiclesParkingService.instance.fetchMyFlatVehicles(flatId);
      if (mounted) {
        setState(() {
          _residents = (resList as List).cast<Map<String, dynamic>>();
          _flatVehicles = vehList;
          _loadingFlat = false;
          if (_residents.isNotEmpty) {
            _residentId = _residents.first['id']?.toString();
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _residents = [
            {'id': 'r-1', 'full_name': 'Flat Resident', 'resident_type': 'owner'},
          ];
          _loadingFlat = false;
        });
      }
    }
  }

  Future<void> _pickBay() async {
    HapticFeedback.lightImpact();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _BayPickerSheet(
        slots: widget.vacantSlots,
        selectedId: _slotId,
      ),
    );
    if (picked != null && mounted) setState(() => _slotId = picked);
  }

  Future<void> _pickFlat() async {
    HapticFeedback.lightImpact();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _FlatPickerSheet(
        flats: _flats,
        selectedId: _flatId,
      ),
    );
    if (picked != null && mounted) _onFlatChanged(picked);
  }

  Future<void> _submit() async {
    if (_slotId == null || _flatId == null) {
      setState(() => _error = 'Choose a bay and a flat to continue.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await VehiclesParkingService.instance.allocateSlot(
        societyId: widget.societyId,
        slotId: _slotId!,
        flatId: _flatId!,
        residentId: _residentId,
        vehicleId: _vehicleId,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
      );
      widget.onAllocated();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bay allotted')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.toString().replaceAll('Exception:', '').trim();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final slot = _selectedSlot;
    final flat = _selectedFlat;
    final canSubmit = _slotId != null && _flatId != null && !_submitting;

    return Container(
      padding:
          EdgeInsets.only(left: 20, right: 20, top: 12, bottom: bottomInset + 20),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: p.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const SheetHeader(
              title: 'Allot bay',
              subtitle: 'Vacant bays only. Flat-level unless tied to a vehicle.',
            ),
            const SizedBox(height: 16),
            if (_error != null) FormError(_error!),

            // ── Bay ──
            const FieldLabel('Bay', required: true),
            _SelectorTile(
              onTap: widget.vacantSlots.isEmpty ? null : _pickBay,
              child: slot == null
                  ? _placeholder(context, widget.vacantSlots.isEmpty
                      ? 'No vacant bays'
                      : 'Choose a bay…')
                  : Row(
                      children: [
                        _BayNumber(slot.slotNumber),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            [
                              if (slot.blockName.isNotEmpty) slot.blockName,
                              slot.category.label,
                              slot.vehicleType.shortLabel,
                            ].join(' · '),
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          'Change',
                          style: TextStyle(
                            color: p.primary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),

            // ── Flat ──
            const FieldLabel('Flat', required: true),
            if (_loadingFlats)
              const _LoadingTile()
            else
              _SelectorTile(
                onTap: _pickFlat,
                child: flat == null
                    ? _placeholder(context, 'Choose a flat…')
                    : Row(
                        children: [
                          Expanded(
                            child: Text(
                              _flatLabel(flat),
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            'Change',
                            style: TextStyle(
                              color: p.primary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
            const SizedBox(height: 8),

            // ── Resident + vehicle (appear once a flat is chosen) ──
            if (_flatId != null) ...[
              if (_loadingFlat)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(minHeight: 3),
                )
              else ...[
                if (_residents.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const FieldLabel('Resident'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _PersonChip(
                        label: 'Flat-level',
                        selected: _residentId == null,
                        onTap: () =>
                            setState(() => _residentId = null),
                      ),
                      for (final r in _residents)
                        _PersonChip(
                          label: r['full_name']?.toString() ?? 'Resident',
                          selected:
                              _residentId == r['id']?.toString(),
                          onTap: () => setState(() =>
                              _residentId = r['id']?.toString()),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                const FieldLabel('Vehicle'),
                if (_flatVehicles.isEmpty)
                  Text(
                    'No vehicles on this flat — allotment stays flat-level.',
                    style:
                        TextStyle(fontSize: 12, color: p.textTertiary),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: p.hairline),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _RadioRow(
                          title: 'No vehicle tied',
                          selected: _vehicleId == null,
                          onTap: () =>
                              setState(() => _vehicleId = null),
                        ),
                        Divider(
                            height: 1,
                            indent: 14,
                            endIndent: 14,
                            color: p.hairline),
                        for (final v in _flatVehicles) ...[
                          _RadioRow(
                            title: v.formattedPlate,
                            mono: true,
                            subtitle: v.makeModel,
                            selected: _vehicleId == v.id,
                            onTap: () =>
                                setState(() => _vehicleId = v.id),
                          ),
                          if (v.id != _flatVehicles.last.id)
                            Divider(
                                height: 1,
                                indent: 14,
                                endIndent: 14,
                                color: p.hairline),
                        ],
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 8),
            ],

            const SizedBox(height: 8),
            const FieldLabel('Note'),
            TextField(
              controller: _notesController,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'e.g. Second bay against deed, Tower B',
              ),
            ),
            const SizedBox(height: 16),

            // ── Summary + confirm ──
            if (slot != null && flat != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Bay ${slot.slotNumber} → ${_flatLabel(flat)}',
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: canSubmit ? _submit : null,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Allot bay'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context, String text) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return Text(
      text,
      style: TextStyle(fontSize: 13.5, color: p.textTertiary),
    );
  }

  String _flatLabel(Map<String, dynamic> f) {
    String label = 'Flat ${f['flat_number']}';
    final b = f['blocks'];
    if (b is Map && b['name'] != null) {
      label = '${b['name']} · $label';
    }
    return label;
  }
}

// ── Selector tile: looks like a field, opens a picker sheet ────

class _SelectorTile extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _SelectorTile({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.hairline),
          ),
          child: Row(
            children: [
              Expanded(child: child),
              const SizedBox(width: 8),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 22,
                color: p.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingTile extends StatelessWidget {
  const _LoadingTile();

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.hairline),
      ),
      child: LinearProgressIndicator(
        minHeight: 3,
        backgroundColor: p.cardMuted,
      ),
    );
  }
}

class _BayNumber extends StatelessWidget {
  final String text;

  const _BayNumber(this.text);

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: p.cardMuted,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: p.hairline),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 13,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _PersonChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PersonChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? p.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? p.primary : p.hairline,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? p.primary : p.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _RadioRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool mono;
  final bool selected;
  final VoidCallback onTap;

  const _RadioRow({
    required this.title,
    this.subtitle,
    this.mono = false,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: mono ? 'monospace' : null,
                      letterSpacing: mono ? 0.6 : null,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: p.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? p.primary : p.textTertiary,
                  width: selected ? 6 : 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bay picker sheet ────────────────────────────────────────────

class _BayPickerSheet extends StatefulWidget {
  final List<ParkingSlotItem> slots;
  final String? selectedId;

  const _BayPickerSheet({required this.slots, this.selectedId});

  @override
  State<_BayPickerSheet> createState() => _BayPickerSheetState();
}

class _BayPickerSheetState extends State<_BayPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final q = _query.trim().toLowerCase();
    final filtered = widget.slots.where((s) {
      if (q.isEmpty) return true;
      return s.slotNumber.toLowerCase().contains(q) ||
          s.blockName.toLowerCase().contains(q) ||
          s.category.label.toLowerCase().contains(q);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: p.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Choose a bay',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: Icon(Icons.close_rounded,
                      color: p.textSecondary),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: TextField(
              autofocus: false,
              decoration: InputDecoration(
                hintText: 'Search number, block…',
                prefixIcon:
                    const Icon(Icons.search_rounded, size: 20),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No vacant bays match.',
                      style: TextStyle(color: p.textSecondary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final s = filtered[i];
                      final sel = s.id == widget.selectedId;
                      return Material(
                        color: sel
                            ? p.primary.withValues(alpha: 0.07)
                            : p.card,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            Navigator.pop(context, s.id);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 11),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: sel ? p.primary : p.hairline,
                                width: sel ? 1.4 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                _BayNumber(s.slotNumber),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.blockName.isNotEmpty
                                            ? s.blockName
                                            : 'No block',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        '${s.category.label} · ${s.vehicleType.shortLabel}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: p.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (sel)
                                  Icon(Icons.check_rounded,
                                      color: p.primary, size: 20),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Flat picker sheet ───────────────────────────────────────────

class _FlatPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> flats;
  final String? selectedId;

  const _FlatPickerSheet({required this.flats, this.selectedId});

  @override
  State<_FlatPickerSheet> createState() => _FlatPickerSheetState();
}

class _FlatPickerSheetState extends State<_FlatPickerSheet> {
  String _query = '';

  String _label(Map<String, dynamic> f) {
    String label = 'Flat ${f['flat_number']}';
    final b = f['blocks'];
    if (b is Map && b['name'] != null) {
      label = '${b['name']} · $label';
    }
    return label;
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final q = _query.trim().toLowerCase();
    final filtered = widget.flats.where((f) {
      if (q.isEmpty) return true;
      return _label(f).toLowerCase().contains(q);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: p.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Choose a flat',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: Icon(Icons.close_rounded,
                      color: p.textSecondary),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search flat, tower…',
                prefixIcon:
                    const Icon(Icons.search_rounded, size: 20),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No flats match.',
                      style: TextStyle(color: p.textSecondary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: 6),
                    itemBuilder: (ctx, i) {
                      final f = filtered[i];
                      final sel =
                          f['id']?.toString() == widget.selectedId;
                      return Material(
                        color: sel
                            ? p.primary.withValues(alpha: 0.07)
                            : p.card,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            Navigator.pop(
                                context, f['id']?.toString());
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: sel ? p.primary : p.hairline,
                                width: sel ? 1.4 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _label(f),
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (sel)
                                  Icon(Icons.check_rounded,
                                      color: p.primary, size: 20),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
