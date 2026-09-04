import 'package:flutter/material.dart';

import '../../../models/vehicle_parking_models.dart';
import '../../../services/vehicles_parking_service.dart';
import '../../../theme/app_theme.dart';
import '../widgets/vehicle_parking_widgets.dart';

class BulkAddSlotsDialog extends StatefulWidget {
  final String societyId;
  final List<Map<String, dynamic>> blocks;
  final VoidCallback onGenerated;

  const BulkAddSlotsDialog({
    super.key,
    required this.societyId,
    required this.blocks,
    required this.onGenerated,
  });

  static Future<void> show(
    BuildContext context, {
    required String societyId,
    required List<Map<String, dynamic>> blocks,
    required VoidCallback onGenerated,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => BulkAddSlotsDialog(
        societyId: societyId,
        blocks: blocks,
        onGenerated: onGenerated,
      ),
    );
  }

  @override
  State<BulkAddSlotsDialog> createState() => _BulkAddSlotsDialogState();
}

class _BulkAddSlotsDialogState extends State<BulkAddSlotsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _prefix = TextEditingController(text: 'P-');
  final _from = TextEditingController(text: '1');
  final _to = TextEditingController(text: '20');

  String? _blockId;
  VehicleType _type = VehicleType.fourWheeler;
  SlotCategory _category = SlotCategory.covered;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _prefix.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  int get _count {
    final s = int.tryParse(_from.text.trim()) ?? 0;
    final e = int.tryParse(_to.text.trim()) ?? 0;
    if (e >= s && s > 0) return e - s + 1;
    return 0;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final s = int.parse(_from.text.trim());
    final e = int.parse(_to.text.trim());
    if (s > e) {
      setState(() => _error = '“From” can’t be after “To”.');
      return;
    }
    if ((e - s + 1) > 200) {
      setState(() => _error = 'At most 200 bays at a time.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final n = await VehiclesParkingService.instance.bulkCreateSlots(
        societyId: widget.societyId,
        prefix: _prefix.text.trim(),
        startNum: s,
        endNum: e,
        blockId: _blockId,
        vehicleType: _type,
        category: _category,
      );
      widget.onGenerated();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$n bays added')),
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

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: p.card,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SheetHeader(
                  title: 'Generate bays',
                  subtitle: 'One series at a time, e.g. P-01 to P-20.',
                ),
                const SizedBox(height: 14),
                if (_error != null) FormError(_error!),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const FieldLabel('Prefix'),
                          TextFormField(
                            controller: _prefix,
                            textCapitalization:
                                TextCapitalization.characters,
                            decoration: const InputDecoration(
                                hintText: 'P-', isDense: true),
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const FieldLabel('From'),
                          TextFormField(
                            controller: _from,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                hintText: '1', isDense: true),
                            onChanged: (_) => setState(() {}),
                            validator: (v) =>
                                (int.tryParse(v ?? '') ?? 0) <= 0
                                    ? 'Req.'
                                    : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const FieldLabel('To'),
                          TextFormField(
                            controller: _to,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                hintText: '20', isDense: true),
                            onChanged: (_) => setState(() {}),
                            validator: (v) =>
                                (int.tryParse(v ?? '') ?? 0) <= 0
                                    ? 'Req.'
                                    : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _count > 0
                      ? '$_count bays: ${_prefix.text.trim()}${_from.text.trim().padLeft(2, '0')} → ${_prefix.text.trim()}${_to.text.trim().padLeft(2, '0')}'
                      : 'Enter a valid range.',
                  style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                if (widget.blocks.isNotEmpty) ...[
                  const FieldLabel('Block'),
                  DropdownButtonFormField<String?>(
                    initialValue: _blockId,
                    isDense: true,
                    decoration: const InputDecoration(isDense: true),
                    items: [
                      const DropdownMenuItem(
                          value: null,
                          child: Text('No specific block')),
                      ...widget.blocks.map((b) => DropdownMenuItem(
                            value: b['id']?.toString(),
                            child:
                                Text(b['name']?.toString() ?? 'Block'),
                          )),
                    ],
                    onChanged: (v) => setState(() => _blockId = v),
                  ),
                  const SizedBox(height: 14),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const FieldLabel('Fits'),
                          DropdownButtonFormField<VehicleType>(
                            initialValue: _type,
                            isDense: true,
                            decoration:
                                const InputDecoration(isDense: true),
                            items: const [
                              DropdownMenuItem(
                                  value: VehicleType.fourWheeler,
                                  child: Text('4-wheeler')),
                              DropdownMenuItem(
                                  value: VehicleType.twoWheeler,
                                  child: Text('2-wheeler')),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => _type = v);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const FieldLabel('Shed'),
                          DropdownButtonFormField<SlotCategory>(
                            initialValue: _category,
                            isDense: true,
                            decoration:
                                const InputDecoration(isDense: true),
                            items: const [
                              DropdownMenuItem(
                                  value: SlotCategory.covered,
                                  child: Text('Covered')),
                              DropdownMenuItem(
                                  value: SlotCategory.open,
                                  child: Text('Open')),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _category = v);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text('Add $_count'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
