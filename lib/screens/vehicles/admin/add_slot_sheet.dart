import 'package:flutter/material.dart';

import '../../../models/vehicle_parking_models.dart';
import '../../../services/vehicles_parking_service.dart';
import '../../../theme/app_theme.dart';
import '../widgets/vehicle_parking_widgets.dart';

class AddSlotSheet extends StatefulWidget {
  final String societyId;
  final List<Map<String, dynamic>> blocks;
  final VoidCallback onSaved;

  const AddSlotSheet({
    super.key,
    required this.societyId,
    required this.blocks,
    required this.onSaved,
  });

  static Future<void> show(
    BuildContext context, {
    required String societyId,
    required List<Map<String, dynamic>> blocks,
    required VoidCallback onSaved,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddSlotSheet(
        societyId: societyId,
        blocks: blocks,
        onSaved: onSaved,
      ),
    );
  }

  @override
  State<AddSlotSheet> createState() => _AddSlotSheetState();
}

class _AddSlotSheetState extends State<AddSlotSheet> {
  final _formKey = GlobalKey<FormState>();
  final _slotController = TextEditingController();
  String? _blockId;
  VehicleType _type = VehicleType.fourWheeler;
  SlotCategory _category = SlotCategory.covered;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _slotController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await VehiclesParkingService.instance.createSlot(
        societyId: widget.societyId,
        slotNumber: _slotController.text.trim(),
        blockId: _blockId,
        vehicleType: _type,
        category: _category,
      );
      widget.onSaved();
      if (mounted) Navigator.pop(context);
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

    return Container(
      padding:
          EdgeInsets.only(left: 20, right: 20, top: 12, bottom: bottomInset + 20),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Form(
        key: _formKey,
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
                title: 'Add a bay',
                subtitle: 'Painted number as marked on the floor.',
              ),
              const SizedBox(height: 16),
              if (_error != null) FormError(_error!),
              const FieldLabel('Bay number', required: true),
              TextFormField(
                controller: _slotController,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
                decoration: const InputDecoration(hintText: 'P-101, B1-04…'),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Enter the bay number'
                    : null,
              ),
              const SizedBox(height: 16),
              if (widget.blocks.isNotEmpty) ...[
                const FieldLabel('Block'),
                DropdownButtonFormField<String?>(
                  initialValue: _blockId,
                  decoration: const InputDecoration(hintText: 'Select block'),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('No specific block')),
                    ...widget.blocks.map((b) => DropdownMenuItem(
                          value: b['id']?.toString(),
                          child: Text(b['name']?.toString() ?? 'Block'),
                        )),
                  ],
                  onChanged: (v) => setState(() => _blockId = v),
                ),
                const SizedBox(height: 16),
              ],
              const FieldLabel('Fits'),
              _SegmentedChoice<VehicleType>(
                options: const [
                  _SegOpt(VehicleType.fourWheeler, '4-wheeler'),
                  _SegOpt(VehicleType.twoWheeler, '2-wheeler'),
                ],
                value: _type,
                onChanged: (v) => setState(() => _type = v),
              ),
              const SizedBox(height: 16),
              const FieldLabel('Shed'),
              _SegmentedChoice<SlotCategory>(
                options: const [
                  _SegOpt(SlotCategory.covered, 'Covered'),
                  _SegOpt(SlotCategory.open, 'Open'),
                ],
                value: _category,
                onChanged: (v) => setState(() => _category = v),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Add bay'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegOpt<T> {
  final T value;
  final String label;
  const _SegOpt(this.value, this.label);
}

class _SegmentedChoice<T> extends StatelessWidget {
  final List<_SegOpt<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  const _SegmentedChoice({
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return Container(
      decoration: BoxDecoration(
        color: p.cardMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          for (final opt in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(opt.value),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: value == opt.value ? p.card : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: value == opt.value
                        ? [
                            BoxShadow(
                              color: p.shadow.withValues(alpha: 0.06),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    opt.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: value == opt.value
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color:
                          value == opt.value ? p.textPrimary : p.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
