import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/society_models.dart';
import '../theme/app_theme.dart';

/// Modal bottom sheet / dialog to create or edit flat details.
class FlatEditBottomSheet extends StatefulWidget {
  final ResidenceUnit? unit;
  final List<String> availableBlocks;
  final String? initialBlock;
  final ValueChanged<ResidenceUnit> onSave;
  final ValueChanged<ResidenceUnit>? onDelete;

  const FlatEditBottomSheet({
    super.key,
    this.unit,
    required this.availableBlocks,
    this.initialBlock,
    required this.onSave,
    this.onDelete,
  });

  static Future<void> show(
    BuildContext context, {
    ResidenceUnit? unit,
    required List<String> availableBlocks,
    String? initialBlock,
    required ValueChanged<ResidenceUnit> onSave,
    ValueChanged<ResidenceUnit>? onDelete,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FlatEditBottomSheet(
        unit: unit,
        availableBlocks: availableBlocks,
        initialBlock: initialBlock,
        onSave: onSave,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<FlatEditBottomSheet> createState() => _FlatEditBottomSheetState();
}

class _FlatEditBottomSheetState extends State<FlatEditBottomSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _flatNumberController;
  late final TextEditingController _floorController;
  late final TextEditingController _sqftController;
  late final TextEditingController _parkingController;

  late String _selectedBlock;
  late int _selectedBhk;
  late String _selectedStatus;

  bool get _isEditing => widget.unit != null;

  @override
  void initState() {
    super.initState();
    final u = widget.unit;
    _selectedBlock = u?.tower ??
        widget.initialBlock ??
        (widget.availableBlocks.isNotEmpty ? widget.availableBlocks.first : 'A');
    _selectedBhk = u?.bhk ?? 2;
    _selectedStatus = u?.status ?? (u?.isOccupied == true ? 'occupied' : 'vacant');

    _flatNumberController = TextEditingController(text: u?.number ?? '$_selectedBlock-');
    _floorController = TextEditingController(text: u?.floor.toString() ?? '1');
    _sqftController = TextEditingController(text: u?.sqft.toString() ?? '1200');
    _parkingController = TextEditingController(text: u?.parking ?? '');
  }

  @override
  void dispose() {
    _flatNumberController.dispose();
    _floorController.dispose();
    _sqftController.dispose();
    _parkingController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.lightImpact();

    final flatNumber = _flatNumberController.text.trim();
    final floor = int.tryParse(_floorController.text.trim()) ?? 1;
    final sqft = int.tryParse(_sqftController.text.trim()) ?? 1000;
    final parking = _parkingController.text.trim().isEmpty
        ? null
        : _parkingController.text.trim();

    final updated = ResidenceUnit(
      id: widget.unit?.id ?? flatNumber,
      number: flatNumber,
      tower: _selectedBlock,
      floor: floor,
      bhk: _selectedBhk,
      sqft: sqft,
      parking: parking,
      status: _selectedStatus,
      residents: widget.unit?.residents ?? const [],
    );

    widget.onSave(updated);
    Navigator.pop(context);
  }

  void _confirmDelete() {
    if (widget.onDelete == null || widget.unit == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Flat?'),
        content: Text(
          'Are you sure you want to remove Flat ${widget.unit!.number}? '
          'This will unbind any residents assigned to this flat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              Navigator.pop(ctx); // Close dialog
              Navigator.pop(context); // Close bottom sheet
              widget.onDelete!(widget.unit!);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: p.hairline)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
            blurRadius: 30,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        14,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.textTertiary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Title & Close
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isEditing ? 'Edit Flat Details' : 'Add New Flat',
                        style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isEditing
                            ? 'Configure parameters for unit ${widget.unit!.number}'
                            : 'Register a new unit to the society register',
                        style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: p.cardMuted,
                      shape: const CircleBorder(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Block / Building Selector
              Text('Building / Tower Block', style: textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: widget.availableBlocks.map((block) {
                  final selected = _selectedBlock == block;
                  return ChoiceChip(
                    label: Text(block.startsWith('Tower') || block.startsWith('Block')
                        ? block
                        : 'Block $block'),
                    selected: selected,
                    selectedColor: p.primary.withValues(alpha: 0.18),
                    labelStyle: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? p.primary : p.textSecondary,
                    ),
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          _selectedBlock = block;
                          if (!_isEditing) {
                            _flatNumberController.text = '$block-';
                          }
                        });
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),

              // Flat Number & Floor
              Row(
                children: [
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Flat Number', style: textTheme.labelLarge),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _flatNumberController,
                          decoration: InputDecoration(
                            hintText: 'e.g. A-101',
                            prefixIcon: Icon(Icons.meeting_room_outlined, size: 18, color: p.textSecondary),
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Enter flat number' : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Floor', style: textTheme.labelLarge),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _floorController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: '1',
                            prefixIcon: Icon(Icons.stairs_outlined, size: 18, color: p.textSecondary),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Enter floor';
                            if (int.tryParse(v.trim()) == null) return 'Valid number';
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Configuration / BHK
              Text('Flat Configuration (BHK)', style: textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('1 BHK')),
                  ButtonSegment(value: 2, label: Text('2 BHK')),
                  ButtonSegment(value: 3, label: Text('3 BHK')),
                  ButtonSegment(value: 4, label: Text('4+ BHK')),
                ],
                selected: {_selectedBhk},
                onSelectionChanged: (val) => setState(() => _selectedBhk = val.first),
              ),
              const SizedBox(height: 18),

              // Super Built-up Area & Parking
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Area (Sq. Ft.)', style: textTheme.labelLarge),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _sqftController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: '1250',
                            suffixText: 'sqft',
                            prefixIcon: Icon(Icons.straighten_outlined, size: 18, color: p.textSecondary),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Enter area';
                            if (int.tryParse(v.trim()) == null) return 'Valid number';
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Parking Slot', style: textTheme.labelLarge),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _parkingController,
                          decoration: InputDecoration(
                            hintText: 'e.g. P-04',
                            prefixIcon: Icon(Icons.directions_car_outlined, size: 18, color: p.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Occupancy Status
              Text('Occupancy Status', style: textTheme.labelLarge),
              const SizedBox(height: 8),
              Row(
                children: [
                  _StatusOption(
                    label: 'Occupied',
                    icon: Icons.person_outline_rounded,
                    color: p.success,
                    isSelected: _selectedStatus == 'occupied',
                    onTap: () => setState(() => _selectedStatus = 'occupied'),
                  ),
                  const SizedBox(width: 10),
                  _StatusOption(
                    label: 'Vacant',
                    icon: Icons.door_front_door_outlined,
                    color: p.warning,
                    isSelected: _selectedStatus == 'vacant',
                    onTap: () => setState(() => _selectedStatus = 'vacant'),
                  ),
                  const SizedBox(width: 10),
                  _StatusOption(
                    label: 'Renovation',
                    icon: Icons.construction_outlined,
                    color: p.textSecondary,
                    isSelected: _selectedStatus == 'under_renovation',
                    onTap: () => setState(() => _selectedStatus = 'under_renovation'),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Action Buttons
              Row(
                children: [
                  if (_isEditing && widget.onDelete != null) ...[
                    IconButton.filledTonal(
                      onPressed: _confirmDelete,
                      style: IconButton.styleFrom(
                        backgroundColor: p.danger.withValues(alpha: 0.12),
                        foregroundColor: p.danger,
                        minimumSize: const Size(52, 52),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: p.primary,
                          foregroundColor: p.onPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: Text(
                          _isEditing ? 'Save Changes' : 'Add Flat',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _StatusOption({
    required this.label,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: isSelected ? color.withValues(alpha: 0.14) : p.cardMuted,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? color : p.hairline,
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: isSelected ? color : p.textSecondary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? color : p.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
