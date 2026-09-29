import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/vehicle_parking_models.dart';
import '../../../services/app_session.dart';
import '../../../services/vehicles_parking_service.dart';
import '../../../theme/app_theme.dart';

/// Modal bottom sheet that allows residents to request a parking bay
/// from the society administration.
class RequestBaySheet extends StatefulWidget {
  final String societyId;
  final String flatId;
  final String? residentId;
  final List<VehicleItem> vehicles;
  final VehicleItem? initialVehicle;
  final VoidCallback onSubmitted;
  final VoidCallback onRegisterVehicle;

  const RequestBaySheet({
    super.key,
    required this.societyId,
    required this.flatId,
    this.residentId,
    required this.vehicles,
    this.initialVehicle,
    required this.onSubmitted,
    required this.onRegisterVehicle,
  });

  static Future<void> show(
    BuildContext context, {
    required String societyId,
    required String flatId,
    String? residentId,
    required List<VehicleItem> vehicles,
    VehicleItem? initialVehicle,
    required VoidCallback onSubmitted,
    required VoidCallback onRegisterVehicle,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RequestBaySheet(
        societyId: societyId,
        flatId: flatId,
        residentId: residentId,
        vehicles: vehicles,
        initialVehicle: initialVehicle,
        onSubmitted: onSubmitted,
        onRegisterVehicle: onRegisterVehicle,
      ),
    );
  }

  @override
  State<RequestBaySheet> createState() => _RequestBaySheetState();
}

class _RequestBaySheetState extends State<RequestBaySheet> {
  final _notesController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String? _selectedVehicleId;
  SlotCategory? _selectedCategory = SlotCategory.covered;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialVehicle != null) {
      _selectedVehicleId = widget.initialVehicle!.id;
    } else if (widget.vehicles.isNotEmpty) {
      // Pick first waitlisted vehicle by default if available
      final waitlisted = widget.vehicles.where((v) => !v.hasAllocatedSlot);
      if (waitlisted.isNotEmpty) {
        _selectedVehicleId = waitlisted.first.id;
      } else {
        _selectedVehicleId = widget.vehicles.first.id;
      }
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  /// Mirrors the society's configured cap rather than asserting a fixed
  /// number the admin may well have changed.
  String get _policyLine {
    final cap = VehiclesParkingService.instance.policyConfig?.maxSlotsPerFlat;
    if (cap == null) {
      return 'Bays are allotted by the society office as per availability.';
    }
    return 'Society policy permits up to $cap ${cap == 1 ? 'bay' : 'bays'} per flat.';
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    HapticFeedback.lightImpact();
    // Captured before Navigator.pop, which disposes this context's route.
    final messenger = ScaffoldMessenger.of(context);
    final palette = AppTheme.paletteFor(Theme.of(context).brightness);
    setState(() => _isSubmitting = true);

    final session = AppSession.instance;
    final flatSubtitle = session.flatSubtitle ?? 'Flat';
    final residentName = session.displayName ?? 'Resident';

    String? vehicleId;
    String vehicleDesc = 'General allocation';
    if (_selectedVehicleId != null && _selectedVehicleId != 'none') {
      final matching = widget.vehicles.where((v) => v.id == _selectedVehicleId);
      if (matching.isNotEmpty) {
        final v = matching.first;
        vehicleId = v.id;
        vehicleDesc = '${v.formattedPlate} (${v.makeModel})';
      }
    }

    final catText = _selectedCategory?.label ?? 'Any category';
    final notes = _notesController.text.trim();

    try {
      // The request itself is the record of truth — it lands in the
      // admin's review queue and carries its own status back to the
      // resident. The notification below is only a nudge.
      await VehiclesParkingService.instance.createBayRequest(
        societyId: widget.societyId,
        flatId: widget.flatId,
        residentId: widget.residentId,
        vehicleId: vehicleId,
        preferredCategory: _selectedCategory,
        notes: notes.isNotEmpty ? notes : null,
      );

      try {
        await Supabase.instance.client.from('notifications').insert({
          'society_id': widget.societyId,
          'title': 'Parking Bay Request',
          'body':
              '$residentName ($flatSubtitle) requested a $catText parking bay for $vehicleDesc.${notes.isNotEmpty ? ' Note: $notes' : ''}',
          'target_role': 'society_admin',
          // Must be one of notifications_type_check; 'parking_bay_request' is
          // added by migration 12, 'general' is the pre-migration fallback.
          'type': 'parking_bay_request',
          'entity_type': 'parking',
          'route': '/admin-vehicles',
          'is_read': false,
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (notifErr) {
        // A missing notifications row must not make a saved request look
        // failed. Retry once as 'general' for databases that predate the
        // migration-12 type, then give up quietly.
        debugPrint('Bay request notification insert failed: $notifErr');
        try {
          await Supabase.instance.client.from('notifications').insert({
            'society_id': widget.societyId,
            'title': 'Parking Bay Request',
            'body':
                '$residentName ($flatSubtitle) requested a $catText parking bay for $vehicleDesc.${notes.isNotEmpty ? ' Note: $notes' : ''}',
            'target_role': 'society_admin',
            'type': 'general',
            'entity_type': 'parking',
            'route': '/admin-vehicles',
            'is_read': false,
          });
        } catch (_) {}
      }

      if (!mounted) return;
      Navigator.pop(context);
      widget.onSubmitted();
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Request sent to the society office. You can track it under My bays.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('Error submitting bay request: $e');
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: palette.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (mounted) setState(() => _isSubmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    final flatSubtitle = AppSession.instance.flatSubtitle ?? 'My Flat';

    return Container(
      decoration: BoxDecoration(
        color: p.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: p.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.local_parking_rounded,
                      color: p.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Request Parking Bay',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'For $flatSubtitle',
                          style: textTheme.bodySmall?.copyWith(
                            color: p.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Select Vehicle ──────────────────────────────────
              Text(
                'Vehicle to park',
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              if (widget.vehicles.isEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.hairline),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 20, color: p.textSecondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'No vehicles registered yet. Register your vehicle so the office knows what bay size you need.',
                          style: textTheme.bodySmall?.copyWith(
                            color: p.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onRegisterVehicle();
                        },
                        child: const Text('Add vehicle'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ] else ...[
                Container(
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: p.hairline),
                  ),
                  child: Column(
                    children: [
                      ...widget.vehicles.map((v) {
                        final hasSlot = v.hasAllocatedSlot;
                        final isSelected = _selectedVehicleId == v.id;
                        return InkWell(
                          onTap: () {
                            setState(() {
                              _selectedVehicleId = v.id;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  margin: const EdgeInsets.only(right: 12),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? p.primary
                                          : p.textTertiary,
                                      width: isSelected ? 6 : 2,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${v.formattedPlate} · ${v.makeModel}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13.5,
                                          color: p.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${v.type.shortLabel} ${hasSlot ? '· Currently has Bay ${v.allocatedSlotNumber}' : '· Waitlisted'}',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: hasSlot
                                              ? p.success
                                              : p.warning,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const Divider(height: 1),
                      InkWell(
                        onTap: () => setState(() => _selectedVehicleId = 'none'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _selectedVehicleId == 'none'
                                        ? p.primary
                                        : p.textTertiary,
                                    width: _selectedVehicleId == 'none' ? 6 : 2,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  'General bay (vehicle will be registered later)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: p.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Bay Category Preference ─────────────────────────
              Text(
                'Preferred Category',
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Covered Bay'),
                    selected: _selectedCategory == SlotCategory.covered,
                    onSelected: (s) => setState(
                      () => _selectedCategory =
                          s ? SlotCategory.covered : null,
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('Open Bay'),
                    selected: _selectedCategory == SlotCategory.open,
                    onSelected: (s) => setState(
                      () => _selectedCategory =
                          s ? SlotCategory.open : null,
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('Any / No Preference'),
                    selected: _selectedCategory == null,
                    onSelected: (s) => setState(() => _selectedCategory = null),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Notes / Location preference ─────────────────────
              Text(
                'Special Requests or Notes (Optional)',
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notesController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText:
                      'e.g. Prefer basement parking near Tower A lift',
                  hintStyle: TextStyle(
                    color: p.textTertiary,
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: p.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: p.hairline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: p.hairline),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // ── Policy Info Callout ──────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: p.cardMuted,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.hairline),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 18,
                      color: p.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$_policyLine Allocations are confirmed by the society administration based on current availability and waitlist order.',
                        style: textTheme.bodySmall?.copyWith(
                          color: p.textSecondary,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Submit Button ────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: p.primary,
                    foregroundColor: p.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Submit Request to Office',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
