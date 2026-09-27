import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../models/vehicle_parking_models.dart';
import '../../../services/app_session.dart';
import '../../../services/vehicles_parking_service.dart';
import '../../../theme/app_theme.dart';
import '../widgets/vehicle_parking_widgets.dart';
import 'add_edit_vehicle_sheet.dart';
import 'request_bay_sheet.dart';

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

  /// The flat's open request with the society office, or its most recent
  /// refusal. Read from the server, so it survives a reinstall and is the
  /// same on every device the resident signs in on.
  ParkingBayRequestItem? _bayRequest;
  String? _loadError;

  /// Empty when the account is not linked to a flat yet. Never a
  /// placeholder id — Postgres would reject it as a malformed uuid and the
  /// screen would show a confusing failure instead of a clear prompt.
  String get _flatId {
    final session = AppSession.instance;
    return session.primaryResidence?.flatId ??
        (session.myResidences.isNotEmpty
            ? session.myResidences.first.flatId
            : '');
  }

  String get _societyId {
    final session = AppSession.instance;
    return session.societyId ??
        session.primaryResidence?.societyId ??
        (session.myResidences.isNotEmpty
            ? session.myResidences.first.societyId
            : '');
  }

  bool get _isLinked => _flatId.isNotEmpty && _societyId.isNotEmpty;

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
    if (!_isLinked) {
      setState(() {
        _isLoading = false;
        _loadError = 'This account is not linked to a flat yet. '
            'Once the society office approves your flat, your vehicles and '
            'bays will show up here.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    final service = VehiclesParkingService.instance;
    try {
      final results = await Future.wait([
        service.fetchMyFlatVehicles(_flatId),
        service.fetchAllocations(
          societyId: _societyId,
          flatId: _flatId,
          status: AllocationStatus.active,
        ),
        service.fetchMyPendingBayRequest(
          societyId: _societyId,
          flatId: _flatId,
        ),
        service.fetchParkingPolicy(_societyId),
      ]);
      if (!mounted) return;
      setState(() {
        _myVehicles = results[0] as List<VehicleItem>;
        _myAllocations = results[1] as List<ParkingAllocationItem>;
        _bayRequest = results[2] as ParkingBayRequestItem?;
        _loadError = service.errorFor('myVehicles') ??
            service.errorFor('allocations');
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _withdrawRequest() async {
    final req = _bayRequest;
    if (req == null || !req.isPending) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw this request?'),
        content: const Text(
          'The society office will no longer see this bay request. '
          'You can raise a fresh one any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await VehiclesParkingService.instance.cancelBayRequest(
        requestId: req.id,
        societyId: _societyId,
        flatId: _flatId,
      );
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request withdrawn'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _openRequestBaySheet([VehicleItem? vehicle]) {
    HapticFeedback.lightImpact();
    RequestBaySheet.show(
      context,
      societyId: _societyId,
      flatId: _flatId,
      residentId: _residentId,
      vehicles: _myVehicles,
      initialVehicle: vehicle,
      onSubmitted: _loadData,
      onRegisterVehicle: () => _openAddVehicleSheet(),
    );
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
          '${v.makeModel} (${v.formattedPlate}) will stop appearing for gate clearance under $_flatSubtitle. You can re-register it later.'
          '${v.hasAllocatedSlot ? '\n\nBay ${v.allocatedSlotNumber} stays with your flat — it is simply no longer tied to this vehicle. Contact the society office to surrender it.' : ''}',
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
                  : _loadError != null
                      ? _buildErrorState(p)
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
      floatingActionButton: (_isLoading || _loadError != null)
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openAddVehicleSheet(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add vehicle'),
              backgroundColor: p.primary,
              foregroundColor: p.onPrimary,
            ),
    );
  }

  Widget _buildErrorState(AppPaletteData p) {
    return ModuleEmptyState(
      icon: _isLinked
          ? Icons.cloud_off_rounded
          : Icons.apartment_outlined,
      title: _isLinked ? 'Could not load your parking' : 'Flat not linked yet',
      message: _loadError!,
      actionLabel: _isLinked ? 'Retry' : null,
      onAction: _isLinked ? _loadData : null,
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
              // Only one request per flat can be open at a time, so hide the
              // button rather than let the tap fail server-side.
              onRequestBay: _bayRequest?.isPending == true
                  ? null
                  : () => _openRequestBaySheet(_myVehicles[i]),
              requestPending: _bayRequest?.isPending == true,
            ),
      ),
    );
  }

  // ── Bays ────────────────────────────────────────────────────

  Widget _buildBaysTab() {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    if (_myAllocations.isEmpty) {
      final req = _bayRequest;
      if (req != null) {
        return RefreshIndicator(
          onRefresh: _loadData,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              _buildRequestCard(p, textTheme, req),
              const SizedBox(height: 16),
              ModuleEmptyState(
                icon: Icons.local_parking_outlined,
                title: 'No bay allotted yet',
                message: req.isPending
                    ? 'Your request is with the society office. Once an administrator allots a bay, it appears here automatically.'
                    : 'Your last request was not taken forward. You can raise a fresh one when you are ready.',
                actionLabel: req.isPending ? null : 'Request a bay',
                onAction: req.isPending ? null : () => _openRequestBaySheet(),
              ),
            ],
          ),
        );
      }
      return ModuleEmptyState(
        icon: Icons.local_parking_outlined,
        title: 'No bay allotted yet',
        message:
            'Bays are allotted by the society office as per availability. Submit an allotment request to the admin for your flat.',
        actionLabel: 'Request a bay',
        onAction: () => _openRequestBaySheet(),
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
                'Allotments on $_flatSubtitle are maintained by the society office. For swaps or surrender, contact society admin.',
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

  Widget _buildRequestCard(
    AppPaletteData p,
    TextTheme textTheme,
    ParkingBayRequestItem req,
  ) {
    final pending = req.isPending;
    final accent = pending ? p.warning : p.danger;
    final requestedOn =
        DateFormat('d MMM yyyy, h:mm a').format(req.createdAt.toLocal());

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(req.status.icon, size: 20, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pending
                      ? 'Bay request with the society office'
                      : 'Bay request declined',
                  style: textTheme.titleSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              StatusDot(color: accent, label: req.status.label),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Vehicle: ${req.vehicleDisplay}',
            style: textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: p.textPrimary,
            ),
          ),
          Text(
            'Preference: ${req.categoryLabel}',
            style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
          ),
          if (req.notes != null && req.notes!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Note: "${req.notes!.trim()}"',
                style: textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: p.textSecondary,
                ),
              ),
            ),
          if (!pending &&
              req.reviewNotes != null &&
              req.reviewNotes!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Office said: ${req.reviewNotes!.trim()}',
                style: textTheme.bodySmall?.copyWith(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'Requested on $requestedOn',
            style: textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: p.textTertiary,
            ),
          ),
          if (pending) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _withdrawRequest,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.danger,
                    side: BorderSide(color: p.danger.withValues(alpha: 0.4)),
                    minimumSize: const Size(0, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Withdraw', style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
          ],
        ],
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
  final VoidCallback? onRequestBay;
  final bool requestPending;

  const _VehicleRow({
    required this.vehicle,
    required this.onEdit,
    required this.onRemove,
    this.onRequestBay,
    this.requestPending = false,
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
                        : requestPending
                            ? 'Request sent'
                            : 'No bay',
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
                      if (!vehicle.hasAllocatedSlot && onRequestBay != null) ...[
                        const SizedBox(width: 2),
                        InkWell(
                          onTap: onRequestBay,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: p.warning.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: p.warning.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.send_rounded,
                                    size: 12, color: p.warning),
                                const SizedBox(width: 4),
                                Text(
                                  'Request bay',
                                  style: TextStyle(
                                    color: p.warning,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
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
