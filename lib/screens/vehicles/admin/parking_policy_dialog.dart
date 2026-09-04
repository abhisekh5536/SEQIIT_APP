import 'package:flutter/material.dart';

import '../../../models/vehicle_parking_models.dart';
import '../../../services/vehicles_parking_service.dart';
import '../../../theme/app_theme.dart';
import '../widgets/vehicle_parking_widgets.dart';

class ParkingPolicyDialog extends StatefulWidget {
  final String societyId;
  final ParkingPolicyConfig currentConfig;
  final VoidCallback onSaved;

  const ParkingPolicyDialog({
    super.key,
    required this.societyId,
    required this.currentConfig,
    required this.onSaved,
  });

  static Future<void> show(
    BuildContext context, {
    required String societyId,
    required ParkingPolicyConfig currentConfig,
    required VoidCallback onSaved,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => ParkingPolicyDialog(
        societyId: societyId,
        currentConfig: currentConfig,
        onSaved: onSaved,
      ),
    );
  }

  @override
  State<ParkingPolicyDialog> createState() => _ParkingPolicyDialogState();
}

class _ParkingPolicyDialogState extends State<ParkingPolicyDialog> {
  late int _maxSlots;
  late bool _requireBinding;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _maxSlots = widget.currentConfig.maxSlotsPerFlat;
    _requireBinding = widget.currentConfig.requireVehicleBinding;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await VehiclesParkingService.instance.updateParkingPolicy(
        societyId: widget.societyId,
        maxSlotsPerFlat: _maxSlots,
        requireVehicleBinding: _requireBinding,
      );
      widget.onSaved();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Parking rules saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: p.card,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHeader(
              title: 'Parking rules',
              subtitle: 'Limits the office follows while allotting bays.',
            ),
            const SizedBox(height: 16),
            Text(
              'Bays allowed per flat',
              style: textTheme.labelMedium?.copyWith(
                color: p.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [1, 2, 3, 4].map((n) {
                final sel = _maxSlots == n;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _maxSlots = n),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: sel
                              ? p.primary.withValues(alpha: 0.12)
                              : p.cardMuted,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: sel ? p.primary : p.hairline,
                            width: sel ? 1.4 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '$n',
                            style: TextStyle(
                              color: sel ? p.primary : p.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 6),
            Text(
              'Applies to fresh allotments; existing ones stay as-is.',
              style: TextStyle(color: p.textTertiary, fontSize: 11.5),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: p.cardMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.hairline),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tie every bay to a vehicle',
                          style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700, fontSize: 13.5),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Flat-level allotments are blocked when on.',
                          style: textTheme.bodySmall?.copyWith(
                              color: p.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _requireBinding,
                    onChanged: (v) =>
                        setState(() => _requireBinding = v),
                  ),
                ],
              ),
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
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
