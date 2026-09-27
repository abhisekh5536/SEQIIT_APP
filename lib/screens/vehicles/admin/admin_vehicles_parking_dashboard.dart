import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/vehicle_parking_models.dart';
import '../../../services/app_session.dart';
import '../../../services/vehicles_parking_service.dart';
import '../../../theme/app_theme.dart';
import '../guard/vehicle_gate_lookup_screen.dart';
import '../widgets/vehicle_parking_widgets.dart';
import 'add_slot_sheet.dart';
import 'allocate_slot_dialog.dart';
import 'bulk_add_slots_dialog.dart';
import 'parking_policy_dialog.dart';

class AdminVehiclesParkingDashboard extends StatefulWidget {
  final bool showBack;

  const AdminVehiclesParkingDashboard({super.key, this.showBack = true});

  @override
  State<AdminVehiclesParkingDashboard> createState() =>
      _AdminVehiclesParkingDashboardState();
}

class _AdminVehiclesParkingDashboardState
    extends State<AdminVehiclesParkingDashboard>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _isLoading = true;
  String _selectedBlock = 'All';
  SlotStatus? _selectedStatus;
  VehicleType? _selectedType;

  String _vehicleQuery = '';
  bool _waitlistedOnly = false;

  List<Map<String, dynamic>> _blocks = [];

  String get _societyId => AppSession.instance.societyId ?? '';

  List<ParkingBayRequestItem> get _pendingRequests => VehiclesParkingService
      .instance.bayRequests
      .where((r) => r.isPending)
      .toList();

  int get _pendingRequestCount => _pendingRequests.length;

  List<String> get _tabLabels => [
        'Bays',
        _pendingRequestCount > 0 ? 'Requests ($_pendingRequestCount)' : 'Requests',
        'Allotted',
        'Vehicles',
        'Gate',
      ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this)
      ..addListener(() => setState(() {}));
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final service = VehiclesParkingService.instance;
    await Future.wait([
      service.fetchSlots(societyId: _societyId),
      service.fetchSocietyVehicles(societyId: _societyId),
      service.fetchAllocations(societyId: _societyId),
      service.fetchParkingPolicy(_societyId),
      service.fetchBayRequests(societyId: _societyId),
      _loadBlocks(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadBlocks() async {
    try {
      final client = Supabase.instance.client;
      final res = await client
          .from('blocks')
          .select('id, name')
          .eq('society_id', _societyId)
          .order('name', ascending: true);
      _blocks = (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      // Inventing "Tower A/B/C" here would let an admin create bays against
      // block ids that do not exist. Better an empty picker.
      debugPrint('AdminVehiclesParkingDashboard._loadBlocks error: $e');
      _blocks = [];
    }
  }

  void _openAllocate([ParkingSlotItem? slot]) {
    final vacant =
        VehiclesParkingService.instance.slots.where((s) => s.isVacant).toList();
    if (vacant.isEmpty && slot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No vacant bays right now')),
      );
      return;
    }
    AllocateSlotDialog.show(
      context,
      societyId: _societyId,
      preselectedSlot: slot,
      vacantSlots: vacant,
      onAllocated: _loadAll,
    );
  }

  void _openPolicy() {
    final cfg = VehiclesParkingService.instance.policyConfig ??
        ParkingPolicyConfig(societyId: _societyId);
    ParkingPolicyDialog.show(
      context,
      societyId: _societyId,
      currentConfig: cfg,
      onSaved: _loadAll,
    );
  }

  Future<void> _confirmVacate(
      ActiveSlotAllocation alloc, String slotNumber) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Vacate bay $slotNumber?'),
        content: Text(
          '${alloc.flatDisplay} will lose this bay and it will show as vacant for re-allotment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Vacate'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await VehiclesParkingService.instance.endAllocation(
          allocationId: alloc.allocationId,
          societyId: _societyId,
        );
        HapticFeedback.lightImpact();
        _loadAll();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not vacate: $e')),
          );
        }
      }
    }
  }

  Future<void> _updateSlotStatus(String slotId, SlotStatus status) async {
    try {
      await VehiclesParkingService.instance.updateSlotStatus(
        slotId: slotId,
        status: status,
        societyId: _societyId,
      );
      HapticFeedback.lightImpact();
      _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update status: $e')),
        );
      }
    }
  }

  Future<void> _confirmDeleteSlot(String slotId, String slotNumber) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete bay $slotNumber?'),
        content: const Text(
          'This will remove this bay from society parking inventory.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await VehiclesParkingService.instance.deleteSlot(
          slotId: slotId,
          societyId: _societyId,
        );
        HapticFeedback.lightImpact();
        _loadAll();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not delete bay: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final slots = VehiclesParkingService.instance.slots;
    final allocated = slots.where((s) => s.isAllocated).length;
    final subtitle = _isLoading
        ? 'Loading…'
        : '${slots.length} bays · $allocated allotted';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ModuleHeader(
              title: 'Parking & Vehicles',
              subtitle: subtitle,
              showBack: widget.showBack,
              actions: [
                IconButton(
                  onPressed: _openPolicy,
                  icon: const Icon(Icons.tune_rounded),
                  tooltip: 'Parking rules',
                  style: IconButton.styleFrom(
                    backgroundColor: p.card,
                    side: BorderSide(color: p.hairline),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _loadAll,
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
              labels: _tabLabels,
              highlighted: _pendingRequestCount > 0
                  ? {_tabLabels[1]}
                  : const {},
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildBaysTab(),
                        _buildRequestsTab(),
                        _buildAllottedTab(),
                        _buildVehiclesTab(),
                        VehicleGateLookupScreen(
                          societyId: _societyId,
                          showAppBar: false,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: _fabForTab(p),
    );
  }

  Widget? _fabForTab(AppPaletteData p) {
    if (_isLoading) return null;
    switch (_tabController.index) {
      case 0:
        return FloatingActionButton.extended(
          onPressed: () => AddSlotSheet.show(
            context,
            societyId: _societyId,
            blocks: _blocks,
            onSaved: _loadAll,
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add bay'),
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
        );
      case 2:
        return FloatingActionButton.extended(
          onPressed: () => _openAllocate(),
          icon: const Icon(Icons.key_rounded),
          label: const Text('Allot'),
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
        );
      default:
        return null;
    }
  }

  // ── TAB 1: Bays ─────────────────────────────────────────────

  Widget _buildBaysTab() {
    return AnimatedBuilder(
      animation: VehiclesParkingService.instance,
      builder: (context, _) {
        final all = VehiclesParkingService.instance.slots;
        final filtered = all.where((s) {
          if (_selectedBlock != 'All' &&
              s.blockName != _selectedBlock &&
              s.blockId != _selectedBlock) {
            return false;
          }
          if (_selectedStatus != null && s.status != _selectedStatus) {
            return false;
          }
          if (_selectedType != null && s.vehicleType != _selectedType) {
            return false;
          }
          return true;
        }).toList();

        final total = all.length;
        final allocated = all.where((s) => s.isAllocated).length;
        final vacant = all.where((s) => s.isVacant).length;

        return RefreshIndicator(
          onRefresh: _loadAll,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              _OccupancyCard(
                total: total,
                allocated: allocated,
                vacant: vacant,
                onGenerate: () => BulkAddSlotsDialog.show(
                  context,
                  societyId: _societyId,
                  blocks: _blocks,
                  onGenerated: _loadAll,
                ),
              ),
              const SizedBox(height: 12),
              _FilterRow(
                selectedBlock: _selectedBlock,
                blocks: _blocks,
                selectedStatus: _selectedStatus,
                selectedType: _selectedType,
                onBlock: (v) => setState(() => _selectedBlock = v),
                onStatus: (v) => setState(() => _selectedStatus = v),
                onType: (v) => setState(() => _selectedType = v),
                onClear: () => setState(() {
                  _selectedStatus = null;
                  _selectedType = null;
                  _selectedBlock = 'All';
                }),
              ),
              const SizedBox(height: 10),
              ModuleSectionHeader(
                title: 'Bays (${filtered.length})',
                trailing: _selectedBlock != 'All' ? _selectedBlock : null,
              ),
              const SizedBox(height: 8),
              if (filtered.isEmpty)
                const ModuleEmptyState(
                  icon: Icons.local_parking_outlined,
                  title: 'No bays match this view',
                  message: 'Add bays for the block, or clear the filters.',
                )
              else
                ...filtered.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _BayRow(
                        slot: s,
                        onAllot: () => _openAllocate(s),
                        onVacate: s.activeAllocation == null
                            ? null
                            : () => _confirmVacate(
                                s.activeAllocation!, s.slotNumber),
                        onSetStatus: (status) => _updateSlotStatus(s.id, status),
                        onDelete: s.isAllocated
                            ? null
                            : () => _confirmDeleteSlot(s.id, s.slotNumber),
                      ),
                    )),
            ],
          ),
        );
      },
    );
  }

  // ── TAB 2: Requests ─────────────────────────────────────────

  Widget _buildRequestsTab() {
    return AnimatedBuilder(
      animation: VehiclesParkingService.instance,
      builder: (context, _) {
        final all = VehiclesParkingService.instance.bayRequests;
        final pending = all.where((r) => r.isPending).toList();
        final decided = all.where((r) => r.isResolved).toList();

        if (all.isEmpty) {
          return const ModuleEmptyState(
            icon: Icons.inbox_rounded,
            title: 'No bay requests',
            message:
                'When a resident asks the office for a parking bay, it lands here for you to allot or decline.',
          );
        }

        return RefreshIndicator(
          onRefresh: _loadAll,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              if (pending.isNotEmpty) ...[
                ModuleSectionHeader(title: 'Awaiting review (${pending.length})'),
                const SizedBox(height: 8),
                ...pending.map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _BayRequestRow(
                        request: r,
                        onAllot: () => _allotForRequest(r),
                        onDecline: () => _declineRequest(r),
                      ),
                    )),
              ],
              if (decided.isNotEmpty) ...[
                const SizedBox(height: 6),
                ModuleSectionHeader(title: 'Decided (${decided.length})'),
                const SizedBox(height: 8),
                ...decided.map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _BayRequestRow(request: r),
                    )),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Opens the allotment dialog pre-aimed at the requesting flat. The
  /// request closes itself once the allocation lands (database trigger),
  /// so the admin never has to tick it off twice.
  void _allotForRequest(ParkingBayRequestItem req) {
    final vacant = VehiclesParkingService.instance.slots
        .where((s) => s.isVacant)
        .where((s) =>
            req.preferredCategory == null || s.category == req.preferredCategory)
        .toList();

    if (vacant.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            req.preferredCategory == null
                ? 'No vacant bays right now'
                : 'No vacant ${req.preferredCategory!.label.toLowerCase()} bays right now',
          ),
        ),
      );
      return;
    }

    AllocateSlotDialog.show(
      context,
      societyId: _societyId,
      vacantSlots: vacant,
      preselectedFlatId: req.flatId,
      preselectedVehicleId: req.vehicleId,
      onAllocated: _loadAll,
    );
  }

  Future<void> _declineRequest(ParkingBayRequestItem req) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline this request?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${req.residentName} · ${req.flatDisplay}'),
            const SizedBox(height: 14),
            TextField(
              controller: reasonCtrl,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason (shown to the resident)',
                hintText: 'e.g. No covered bays free; added to waitlist',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Decline'),
          ),
        ],
      ),
    );

    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (confirmed != true) return;

    if (reason.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please give the resident a reason')),
        );
      }
      return;
    }

    try {
      await VehiclesParkingService.instance.reviewBayRequest(
        requestId: req.id,
        societyId: _societyId,
        action: BayRequestStatus.rejected,
        reviewNotes: reason,
      );
      await _loadAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request declined')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  // ── TAB 3: Allotted ─────────────────────────────────────────

  Widget _buildAllottedTab() {
    return AnimatedBuilder(
      animation: VehiclesParkingService.instance,
      builder: (context, _) {
        final p = AppTheme.paletteFor(Theme.of(context).brightness);
        final active = VehiclesParkingService.instance.allocations
            .where((a) => a.isActive)
            .toList();
        if (active.isEmpty) {
          return ModuleEmptyState(
            icon: Icons.key_outlined,
            title: 'Nothing allotted yet',
            message: 'Allot a vacant bay to a flat to start the register.',
            actionLabel: 'Allot a bay',
            onAction: () => _openAllocate(),
          );
        }
        return RefreshIndicator(
          onRefresh: _loadAll,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            itemCount: active.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final a = active[i];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: p.hairline),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: p.cardMuted,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: p.hairline),
                      ),
                      child: Text(
                        a.slotNumber,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.flatDisplay,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${a.residentName}'
                            '${a.vehicleNumber != null && a.vehicleNumber!.isNotEmpty ? ' · ${a.vehicleNumber}' : ''}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: p.textSecondary,
                                  fontSize: 12,
                                ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _confirmVacate(
                        ActiveSlotAllocation(
                          allocationId: a.id,
                          flatId: a.flatId,
                          flatNumber: a.flatNumber,
                          blockName: a.blockName,
                        ),
                        a.slotNumber,
                      ),
                      child: Text(
                        'Vacate',
                        style: TextStyle(color: p.danger, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ── TAB 3: Vehicles directory ───────────────────────────────

  Widget _buildVehiclesTab() {
    return AnimatedBuilder(
      animation: VehiclesParkingService.instance,
      builder: (context, _) {
        final p = AppTheme.paletteFor(Theme.of(context).brightness);
        final all = VehiclesParkingService.instance.societyVehicles;
        final q = _vehicleQuery.trim().toLowerCase();
        final filtered = all.where((v) {
          if (_waitlistedOnly && v.hasAllocatedSlot) return false;
          if (q.isEmpty) return true;
          return v.vehicleNumber.toLowerCase().contains(q) ||
              v.makeModel.toLowerCase().contains(q) ||
              v.flatNumber.toLowerCase().contains(q) ||
              v.residentName.toLowerCase().contains(q);
        }).toList();
        final waitlisted = all.where((v) => !v.hasAllocatedSlot).length;

        return RefreshIndicator(
          onRefresh: _loadAll,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search plate, flat, resident…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: p.card,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: p.hairline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: p.hairline),
                  ),
                ),
                onChanged: (v) => setState(() => _vehicleQuery = v),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilterChip(
                    label: Text('Waitlisted ($waitlisted)'),
                    selected: _waitlistedOnly,
                    onSelected: (s) =>
                        setState(() => _waitlistedOnly = s),
                    visualDensity: VisualDensity.compact,
                  ),
                  const Spacer(),
                  Text(
                    '${filtered.length} vehicles',
                    style: TextStyle(color: p.textTertiary, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (filtered.isEmpty)
                const ModuleEmptyState(
                  icon: Icons.directions_car_outlined,
                  title: 'No vehicles found',
                  message: 'Try a different search, or clear the waitlist filter.',
                )
              else
                ...filtered.map((v) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _DirectoryRow(
                        vehicle: v,
                        onAllot: v.hasAllocatedSlot
                            ? null
                            : () => _openAllocate(),
                      ),
                    )),
            ],
          ),
        );
      },
    );
  }
}

// ── Pieces ────────────────────────────────────────────────────

class _OccupancyCard extends StatelessWidget {
  final int total;
  final int allocated;
  final int vacant;
  final VoidCallback onGenerate;

  const _OccupancyCard({
    required this.total,
    required this.allocated,
    required this.vacant,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    final frac = total > 0 ? allocated / total : 0.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  total == 0
                      ? 'No bays created yet'
                      : '$allocated of $total bays allotted',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
              InkWell(
                onTap: onGenerate,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(
                    'Generate…',
                    style: TextStyle(
                      color: p.primary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: frac,
              backgroundColor: p.cardMuted,
              color: p.primary,
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _stat(context, '$total', 'Total'),
              _divider(p),
              _stat(context, '$allocated', 'Allotted'),
              _divider(p),
              _stat(context, '$vacant', 'Vacant'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _divider(AppPaletteData p) =>
      Container(width: 1, height: 26, color: p.hairline);

  Widget _stat(BuildContext context, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.paletteFor(Theme.of(context).brightness)
                  .textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final String selectedBlock;
  final List<Map<String, dynamic>> blocks;
  final SlotStatus? selectedStatus;
  final VehicleType? selectedType;
  final ValueChanged<String> onBlock;
  final ValueChanged<SlotStatus?> onStatus;
  final ValueChanged<VehicleType?> onType;
  final VoidCallback onClear;

  const _FilterRow({
    required this.selectedBlock,
    required this.blocks,
    required this.selectedStatus,
    required this.selectedType,
    required this.onBlock,
    required this.onStatus,
    required this.onType,
    required this.onClear,
  });

  bool get _hasFilter =>
      selectedBlock != 'All' ||
      selectedStatus != null ||
      selectedType != null;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: p.hairline),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedBlock,
                    isDense: true,
                    icon: Icon(Icons.keyboard_arrow_down_rounded,
                        size: 18, color: p.textSecondary),
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                    items: [
                      // Exactly one item carries value 'All'. It doubles as
                      // the empty state, because a society with no blocks
                      // used to be offered invented "Tower A"/"Tower B"
                      // options that matched nothing and silently emptied
                      // the bay list.
                      DropdownMenuItem(
                        value: 'All',
                        child: Text(blocks.isEmpty
                            ? 'No blocks configured'
                            : 'All blocks'),
                      ),
                      ...blocks.map((b) {
                        final name = b['name']?.toString() ?? 'Block';
                        return DropdownMenuItem(
                          value: b['id']?.toString() == selectedBlock
                              ? selectedBlock
                              : name,
                          child: Text(name),
                        );
                      }),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      if (v == 'All') {
                        onBlock('All');
                        return;
                      }
                      final match = blocks.firstWhere(
                        (b) =>
                            (b['name']?.toString() ?? '') == v ||
                            (b['id']?.toString() ?? '') == v,
                        orElse: () => {'id': v, 'name': v},
                      );
                      onBlock(match['name']?.toString() ??
                          match['id']?.toString() ??
                          v);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _chip(context, 'Vacant', selectedStatus == SlotStatus.vacant,
                  () => onStatus(selectedStatus == SlotStatus.vacant ? null : SlotStatus.vacant)),
              const SizedBox(width: 6),
              _chip(context, 'Allotted', selectedStatus == SlotStatus.allocated,
                  () => onStatus(selectedStatus == SlotStatus.allocated ? null : SlotStatus.allocated)),
              const SizedBox(width: 6),
              _chip(context, '4W', selectedType == VehicleType.fourWheeler,
                  () => onType(selectedType == VehicleType.fourWheeler ? null : VehicleType.fourWheeler)),
              const SizedBox(width: 6),
              _chip(context, '2W', selectedType == VehicleType.twoWheeler,
                  () => onType(selectedType == VehicleType.twoWheeler ? null : VehicleType.twoWheeler)),
              if (_hasFilter) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: onClear,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 8),
                    child: Text(
                      'Clear',
                      style: TextStyle(
                        color: p.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(
      BuildContext context, String label, bool selected, VoidCallback onTap) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? p.primary : p.textSecondary,
      ),
      selectedColor: p.primary.withValues(alpha: 0.12),
      side: BorderSide(
        color: selected ? p.primary.withValues(alpha: 0.5) : p.hairline,
      ),
    );
  }
}

class _BayRow extends StatelessWidget {
  final ParkingSlotItem slot;
  final VoidCallback onAllot;
  final VoidCallback? onVacate;
  final ValueChanged<SlotStatus> onSetStatus;
  final VoidCallback? onDelete;

  const _BayRow({
    required this.slot,
    required this.onAllot,
    required this.onVacate,
    required this.onSetStatus,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    final alloc = slot.activeAllocation;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.cardMuted,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  slot.slotNumber,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  slot.vehicleType == VehicleType.twoWheeler ? '2W' : '4W',
                  style: TextStyle(
                    fontSize: 10,
                    color: p.textTertiary,
                    fontWeight: FontWeight.w600,
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        [
                          if (slot.blockName.isNotEmpty) slot.blockName,
                          slot.category.label,
                        ].join(' · '),
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    StatusDot(
                      color: slotStatusColor(slot.status, p),
                      label: slot.status.label,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                if (slot.isAllocated && alloc != null)
                  Text(
                    '${alloc.flatDisplay}'
                    '${alloc.residentName != null && alloc.residentName!.isNotEmpty ? ' · ${alloc.residentName}' : ''}'
                    '${alloc.vehicleNumber != null && alloc.vehicleNumber!.isNotEmpty ? ' · ${alloc.vehicleNumber}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: p.textSecondary,
                      fontSize: 12,
                    ),
                  )
                else if (slot.isVacant)
                  Text(
                    'Unoccupied — ready to allot',
                    style: textTheme.bodySmall?.copyWith(
                      color: p.textTertiary,
                      fontSize: 12,
                    ),
                  )
                else
                  Text(
                    slot.status.label,
                    style: textTheme.bodySmall?.copyWith(
                      color: p.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (slot.isVacant)
                      InkWell(
                        onTap: onAllot,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: p.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Allot',
                            style: TextStyle(
                              color: p.onPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                    else if (slot.isAllocated && onVacate != null)
                      InkWell(
                        onTap: onVacate,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 6),
                          child: Text(
                            'Vacate',
                            style: TextStyle(
                              color: p.danger,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                    else
                      InkWell(
                        onTap: () => onSetStatus(SlotStatus.vacant),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 6),
                          child: Text(
                            'Mark vacant',
                            style: TextStyle(
                              color: p.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    const Spacer(),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_horiz_rounded,
                          size: 20, color: p.textTertiary),
                      tooltip: 'Bay options',
                      onSelected: (val) {
                        switch (val) {
                          case 'vacant':
                            onSetStatus(SlotStatus.vacant);
                            break;
                          case 'maintenance':
                            onSetStatus(SlotStatus.maintenance);
                            break;
                          case 'reserved':
                            onSetStatus(SlotStatus.reserved);
                            break;
                          case 'delete':
                            onDelete?.call();
                            break;
                        }
                      },
                      itemBuilder: (ctx) => [
                        if (!slot.isVacant && !slot.isAllocated)
                          const PopupMenuItem(
                            value: 'vacant',
                            child: Row(
                              children: [
                                Icon(Icons.check_circle_outline_rounded,
                                    size: 18),
                                SizedBox(width: 8),
                                Text('Mark Vacant'),
                              ],
                            ),
                          ),
                        if (!slot.isUnderMaintenance && !slot.isAllocated)
                          const PopupMenuItem(
                            value: 'maintenance',
                            child: Row(
                              children: [
                                Icon(Icons.build_circle_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Mark Maintenance'),
                              ],
                            ),
                          ),
                        if (!slot.isReserved && !slot.isAllocated)
                          const PopupMenuItem(
                            value: 'reserved',
                            child: Row(
                              children: [
                                Icon(Icons.bookmark_border_rounded, size: 18),
                                SizedBox(width: 8),
                                Text('Mark Reserved'),
                              ],
                            ),
                          ),
                        if (onDelete != null)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline_rounded,
                                    size: 18, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Delete Bay',
                                    style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectoryRow extends StatelessWidget {
  final VehicleItem vehicle;
  final VoidCallback? onAllot;

  const _DirectoryRow({required this.vehicle, this.onAllot});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VehiclePlate(vehicle.formattedPlate, fontSize: 12),
                const SizedBox(height: 7),
                Text(
                  '${vehicle.makeModel}'
                  '${vehicle.color != null && vehicle.color!.isNotEmpty ? ' · ${vehicle.color}' : ''}',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${vehicle.flatDisplay} · ${vehicle.residentName}',
                  style: textTheme.bodySmall?.copyWith(
                    color: p.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusDot(
                color: vehicle.hasAllocatedSlot ? p.success : p.warning,
                label: vehicle.hasAllocatedSlot
                    ? vehicle.allocatedSlotNumber!
                    : 'Waitlisted',
              ),
              if (onAllot != null) ...[
                const SizedBox(height: 6),
                InkWell(
                  onTap: onAllot,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 6),
                    child: Text(
                      'Allot →',
                      style: TextStyle(
                        color: p.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One row in the admin's bay-request queue: who asked, for what, and the
/// two actions that resolve it.
class _BayRequestRow extends StatelessWidget {
  final ParkingBayRequestItem request;
  final VoidCallback? onAllot;
  final VoidCallback? onDecline;

  const _BayRequestRow({
    required this.request,
    this.onAllot,
    this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    final pending = request.isPending;

    final accent = switch (request.status) {
      BayRequestStatus.pending => p.warning,
      BayRequestStatus.approved => p.success,
      BayRequestStatus.rejected => p.danger,
      BayRequestStatus.cancelled => p.textTertiary,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.hairline),
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
                    Text(
                      request.residentName,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      request.flatDisplay,
                      style: textTheme.bodySmall?.copyWith(
                        color: p.primary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              StatusDot(color: accent, label: request.status.label),
            ],
          ),
          const SizedBox(height: 10),
          _line(p, Icons.directions_car_outlined, request.vehicleDisplay),
          _line(p, Icons.local_parking_outlined,
              'Prefers: ${request.categoryLabel}'),
          _line(p, Icons.schedule_rounded, _ago(request.createdAt)),
          if (request.notes != null && request.notes!.trim().isNotEmpty)
            _line(p, Icons.sticky_note_2_outlined, request.notes!.trim()),
          if (!pending &&
              request.reviewNotes != null &&
              request.reviewNotes!.trim().isNotEmpty)
            _line(p, Icons.reply_rounded, request.reviewNotes!.trim()),
          if (pending && (onAllot != null || onDecline != null)) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (onDecline != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDecline,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: p.danger,
                        side: BorderSide(color: p.danger.withValues(alpha: 0.45)),
                        minimumSize: const Size(0, 42),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                      child: const Text('Decline',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                if (onDecline != null && onAllot != null)
                  const SizedBox(width: 10),
                if (onAllot != null)
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: onAllot,
                      icon: const Icon(Icons.key_rounded, size: 16),
                      label: const Text('Allot a bay'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 42),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _line(AppPaletteData p, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: p.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, color: p.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  String _ago(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays} days ago';
  }
}
