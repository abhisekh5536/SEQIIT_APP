import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../models/vehicle_parking_models.dart';
import '../../../services/app_session.dart';
import '../../../services/vehicles_parking_service.dart';
import '../../../theme/app_theme.dart';
import '../widgets/vehicle_parking_widgets.dart';
import 'add_edit_vehicle_sheet.dart';

class ResidentVehiclesParkingScreen extends StatefulWidget {
  final bool showBack;

  const ResidentVehiclesParkingScreen({super.key, this.showBack = true});

  @override
  State<ResidentVehiclesParkingScreen> createState() =>
      _ResidentVehiclesParkingScreenState();
}

class _ResidentVehiclesParkingScreenState
    extends State<ResidentVehiclesParkingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _isLoading = true;
  List<VehicleItem> _myVehicles = [];
  List<ParkingAllocationItem> _myAllocations = [];

  String get _flatId {
    final session = AppSession.instance;
    return session.primaryResidence?.flatId ??
        (session.myResidences.isNotEmpty
            ? session.myResidences.first.flatId
            : 'f-101');
  }

  String get _societyId {
    final session = AppSession.instance;
    return session.societyId ??
        session.primaryResidence?.societyId ??
        (session.myResidences.isNotEmpty
            ? session.myResidences.first.societyId
            : 'soc-1');
  }

  String? get _residentId {
    final session = AppSession.instance;
    return session.primaryResidence?.id ??
        (session.myResidences.isNotEmpty
            ? session.myResidences.first.id
            : null);
  }

  String get _flatSubtitle {
    final session = AppSession.instance;
    return session.flatSubtitle ?? 'My flat';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        VehiclesParkingService.instance.fetchMyFlatVehicles(_flatId),
        VehiclesParkingService.instance.fetchAllocations(
          societyId: _societyId,
          flatId: _flatId,
          status: AllocationStatus.active,
        ),
      ]);
      if (mounted) {
        setState(() {
          _myVehicles = results[0] as List<VehicleItem>;
          _myAllocations = results[1] as List<ParkingAllocationItem>;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openAddVehicleSheet([VehicleItem? vehicle]) {
    HapticFeedback.lightImpact();
    AddEditVehicleSheet.show(
      context,
      societyId: _societyId,
      flatId: _flatId,
      residentId: _residentId,
      existingVehicle: vehicle,
      onSaved: _loadData,
    );
  }

  Future<void> _confirmRemoveVehicle(VehicleItem v) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this vehicle?'),
        content: Text(
          '${v.makeModel} (${v.formattedPlate}) will stop appearing for gate clearance under $_flatSubtitle. You can re-register it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await VehiclesParkingService.instance.deactivateVehicle(
        vehicleId: v.id,
        societyId: _societyId,
      );
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final parkedCount = _myVehicles.where((v) => v.hasAllocatedSlot).length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ModuleHeader(
              title: 'Vehicles & Parking',
              subtitle: '$_flatSubtitle · $parkedCount bay${parkedCount == 1 ? '' : 's'} allotted',
              showBack: widget.showBack,
              actions: [
                IconButton(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Refresh',
                  style: IconButton.styleFrom(
                    backgroundColor: p.card,
                    side: BorderSide(color: p.hairline),
                  ),
                ),
              ],
            ),
            SegmentedTabs(
              controller: _tabController,
              labels: [
                'Vehicles (${_myVehicles.length})',
                'My bays (${_myAllocations.length})',
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildVehiclesTab(),
                        _buildBaysTab(),
                      ],
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddVehicleSheet(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add vehicle'),
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
      ),
    );
  }

  // ── Vehicles ────────────────────────────────────────────────

  Widget _buildVehiclesTab() {
    if (_myVehicles.isEmpty) {
      return ModuleEmptyState(
        icon: Icons.directions_car_outlined,
        title: 'No vehicles on this flat yet',
        message:
            'Add your car or two-wheeler once — the gate gets it for clearance and the office can allot a bay against it.',
        actionLabel: 'Add vehicle',
        onAction: () => _openAddVehicleSheet(),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        itemCount: _myVehicles.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) =>
            _VehicleRow(
              vehicle: _myVehicles[i],
              onEdit: () => _openAddVehicleSheet(_myVehicles[i]),
              onRemove: () => _confirmRemoveVehicle(_myVehicles[i]),
            ),
      ),
    );
  }

  // ── Bays ────────────────────────────────────────────────────

  Widget _buildBaysTab() {
    if (_myAllocations.isEmpty) {
      return ModuleEmptyState(
        icon: Icons.local_parking_outlined,
        title: 'No bay allotted yet',
        message:
            'Bays are allotted by the society office as per availability. Your vehicles above stay on the waitlist till then.',
        actionLabel: 'Request a bay',
        onAction: () => Navigator.pushNamed(context, '/complaints/raise'),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        itemCount: _myAllocations.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                'Allotments on $_flatSubtitle are maintained by the society office. For swaps or surrender, raise a helpdesk request.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.paletteFor(
                              Theme.of(context).brightness)
                          .textTertiary,
                      fontSize: 12,
                    ),
              ),
            );
          }
          return _BayRow(allocation: _myAllocations[i - 1]);
        },
      ),
    );
  }
}

/// One registered vehicle: plate on the left, status on the right,
/// model + bay line below — same density as the visitor rows.
class _VehicleRow extends StatelessWidget {
  final VehicleItem vehicle;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _VehicleRow({
    required this.vehicle,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.hairline),
        boxShadow: [
          BoxShadow(
            color: p.shadow.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    VehiclePlate(vehicle.formattedPlate),
                    const SizedBox(height: 8),
                    Text(
                      vehicle.makeModel,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _metaLine(vehicle),
                      style: textTheme.bodySmall?.copyWith(
                        color: p.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusDot(
                    color: vehicle.hasAllocatedSlot ? p.success : p.warning,
                    label: vehicle.hasAllocatedSlot
                        ? 'Bay ${vehicle.allocatedSlotNumber}'
                        : 'Waitlisted',
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: onEdit,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          child: Text(
                            'Edit',
                            style: TextStyle(
                              color: p.primary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: onRemove,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          child: Text(
                            'Remove',
                            style: TextStyle(
                              color: p.danger,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _metaLine(VehicleItem v) {
    final parts = <String>[v.type.shortLabel];
    if (v.color != null && v.color!.trim().isNotEmpty) {
      parts.add(v.color!.trim());
    }
    if (v.hasAllocatedSlot && v.allocatedSlotCategory != null) {
      parts.add('${v.allocatedSlotCategory!.label} bay');
    }
    return parts.join(' · ');
  }
}

class _BayRow extends StatelessWidget {
  final ParkingAllocationItem allocation;

  const _BayRow({required this.allocation});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    final since =
        DateFormat('d MMM yyyy').format(allocation.allocatedFrom);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.hairline),
        boxShadow: [
          BoxShadow(
            color: p.shadow.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 56,
            decoration: BoxDecoration(
              color: p.cardMuted,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.local_parking_rounded,
                  size: 16,
                  color: p.textSecondary,
                ),
                const SizedBox(height: 2),
                Text(
                  allocation.slotNumber,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${allocation.slotCategory.label} · ${allocation.slotVehicleType.shortLabel}',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Since $since'
                  '${allocation.vehicleNumber != null && allocation.vehicleNumber!.isNotEmpty ? ' · ${allocation.vehicleNumber} tied' : ''}',
                  style: textTheme.bodySmall?.copyWith(
                    color: p.textSecondary,
                    fontSize: 12,
                  ),
                ),
                if (allocation.notes != null &&
                    allocation.notes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    allocation.notes!.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: p.textTertiary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          StatusDot(color: p.success, label: 'Active'),
        ],
      ),
    );
  }
}
