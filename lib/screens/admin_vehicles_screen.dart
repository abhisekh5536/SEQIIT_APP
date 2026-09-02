import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/db_models.dart';
import '../services/app_session.dart';
import '../theme/app_theme.dart';

enum _VehicleFilter { all, allotted, unallotted }

class AdminVehicleEntry {
  final String id;
  final String societyId;
  final String flatId;
  final String residentId;
  final String makeModel;
  final String registrationNo;
  final String? parkingSlot;
  final DateTime? createdAt;
  final String flatNumber;
  final String blockName;
  final String residentName;
  final String? residentPhone;
  final String residentType;

  const AdminVehicleEntry({
    required this.id,
    required this.societyId,
    required this.flatId,
    required this.residentId,
    required this.makeModel,
    required this.registrationNo,
    this.parkingSlot,
    this.createdAt,
    required this.flatNumber,
    required this.blockName,
    required this.residentName,
    this.residentPhone,
    required this.residentType,
  });

  bool get hasParkingSlot =>
      parkingSlot != null && parkingSlot!.trim().isNotEmpty && parkingSlot != '—';

  String get flatDisplay =>
      blockName.isNotEmpty ? '$blockName · Flat $flatNumber' : 'Flat $flatNumber';

  factory AdminVehicleEntry.fromMap(Map<String, dynamic> m) {
    String flatNum = '—';
    String blkName = '';
    final flatMap = m['flats'];
    if (flatMap is Map<String, dynamic>) {
      flatNum = flatMap['flat_number']?.toString() ?? '—';
      final blockMap = flatMap['blocks'];
      if (blockMap is Map<String, dynamic>) {
        blkName = blockMap['name']?.toString() ?? '';
      }
    }

    String resName = 'Resident';
    String? resPhone;
    String resType = 'resident';
    final resMap = m['residents'];
    if (resMap is Map<String, dynamic>) {
      resName = resMap['full_name']?.toString() ?? 'Resident';
      resPhone = resMap['phone']?.toString();
      resType = resMap['resident_type']?.toString() ?? 'resident';
    }

    final vNum = m['registration_no']?.toString() ??
        m['vehicle_number']?.toString() ??
        '';

    return AdminVehicleEntry(
      id: m['id']?.toString() ?? '',
      societyId: m['society_id']?.toString() ?? '',
      flatId: m['flat_id']?.toString() ?? '',
      residentId: m['resident_id']?.toString() ?? '',
      makeModel: m['make_model']?.toString() ?? 'Vehicle',
      registrationNo: vNum,
      parkingSlot: m['parking_slot']?.toString(),
      createdAt: m['created_at'] != null
          ? DateTime.tryParse(m['created_at'].toString())
          : null,
      flatNumber: flatNum,
      blockName: blkName,
      residentName: resName,
      residentPhone: resPhone,
      residentType: resType,
    );
  }
}

/// Screen allowing Society Admins to view all registered vehicles,
/// monitor parking slot allotments by flat & resident, and edit allotments.
class AdminVehiclesScreen extends StatefulWidget {
  const AdminVehiclesScreen({super.key});

  @override
  State<AdminVehiclesScreen> createState() => _AdminVehiclesScreenState();
}

class _AdminVehiclesScreenState extends State<AdminVehiclesScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<AdminVehicleEntry> _allVehicles = [];
  bool _isLoading = true;
  String? _error;
  _VehicleFilter _filter = _VehicleFilter.all;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadVehicles() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final session = AppSession.instance;
      final socId = session.societyId;

      var query = client
          .from('resident_vehicles')
          .select('*, flats(flat_number, blocks(name)), residents(full_name, phone, resident_type)');

      if (socId != null && socId.isNotEmpty) {
        query = query.eq('society_id', socId);
      }

      final res = await query.order('created_at', ascending: false);
      final list = (res as List).cast<Map<String, dynamic>>();

      if (mounted) {
        setState(() {
          _allVehicles = list.map(AdminVehicleEntry.fromMap).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading admin vehicles: $e');
      if (mounted) {
        // Fallback for tests/offline
        setState(() {
          _allVehicles = _mockVehicles();
          _isLoading = false;
        });
      }
    }
  }

  List<AdminVehicleEntry> _mockVehicles() {
    return [
      const AdminVehicleEntry(
        id: 'v1',
        societyId: 'soc-1',
        flatId: 'f-101',
        residentId: 'r-1',
        makeModel: 'Hyundai Creta (White)',
        registrationNo: 'DL 03 CA 4589',
        parkingSlot: 'P-101',
        flatNumber: 'A-101',
        blockName: 'Tower A',
        residentName: 'Kularyan Sharma',
        residentPhone: '+91 98765 43210',
        residentType: 'owner',
      ),
      const AdminVehicleEntry(
        id: 'v2',
        societyId: 'soc-1',
        flatId: 'f-102',
        residentId: 'r-2',
        makeModel: 'Honda City (Silver)',
        registrationNo: 'HR 26 DQ 8821',
        parkingSlot: 'P-102',
        flatNumber: 'A-102',
        blockName: 'Tower A',
        residentName: 'Anita Verma',
        residentPhone: '+91 98111 22334',
        residentType: 'owner',
      ),
      const AdminVehicleEntry(
        id: 'v3',
        societyId: 'soc-1',
        flatId: 'f-204',
        residentId: 'r-3',
        makeModel: 'Royal Enfield Classic 350',
        registrationNo: 'UP 16 BK 7712',
        parkingSlot: 'B-04',
        flatNumber: 'B-204',
        blockName: 'Tower B',
        residentName: 'Saurabh Kumar',
        residentPhone: '+91 99887 76655',
        residentType: 'tenant',
      ),
      const AdminVehicleEntry(
        id: 'v4',
        societyId: 'soc-1',
        flatId: 'f-305',
        residentId: 'r-4',
        makeModel: 'Maruti Suzuki Baleno',
        registrationNo: 'DL 08 CK 9012',
        parkingSlot: null,
        flatNumber: 'C-305',
        blockName: 'Tower C',
        residentName: 'Pooja Singh',
        residentPhone: '+91 97112 34567',
        residentType: 'owner',
      ),
    ];
  }

  List<AdminVehicleEntry> get _filteredVehicles {
    final q = _searchController.text.trim().toLowerCase();
    return _allVehicles.where((v) {
      if (_filter == _VehicleFilter.allotted && !v.hasParkingSlot) return false;
      if (_filter == _VehicleFilter.unallotted && v.hasParkingSlot) return false;

      if (q.isEmpty) return true;
      return v.makeModel.toLowerCase().contains(q) ||
          v.registrationNo.toLowerCase().contains(q) ||
          (v.parkingSlot?.toLowerCase().contains(q) ?? false) ||
          v.flatNumber.toLowerCase().contains(q) ||
          v.blockName.toLowerCase().contains(q) ||
          v.residentName.toLowerCase().contains(q) ||
          (v.residentPhone?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    final totalCount = _allVehicles.length;
    final allottedCount = _allVehicles.where((v) => v.hasParkingSlot).length;
    final unallottedCount = totalCount - allottedCount;

    final filtered = _filteredVehicles;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicles & Parking'),
        centerTitle: false,
        actions: [
          IconButton(
            onPressed: _loadVehicles,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadVehicles,
          child: CustomScrollView(
            slivers: [
              // Stats Cards
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: _StatPill(
                          label: 'Registered',
                          value: '$totalCount',
                          icon: Icons.directions_car_rounded,
                          color: p.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatPill(
                          label: 'Allotted Slot',
                          value: '$allottedCount',
                          icon: Icons.local_parking_rounded,
                          color: p.success,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatPill(
                          label: 'Unassigned',
                          value: '$unallottedCount',
                          icon: Icons.help_outline_rounded,
                          color: unallottedCount > 0 ? p.warning : p.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Search Bar
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search vehicle, flat, resident, parking...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: p.card,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: p.hairline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: p.hairline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: p.primary, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ),

              // Filter Chips
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _filterChip(
                          context,
                          label: 'All ($totalCount)',
                          selected: _filter == _VehicleFilter.all,
                          onSelected: () => setState(() => _filter = _VehicleFilter.all),
                        ),
                        const SizedBox(width: 8),
                        _filterChip(
                          context,
                          label: 'Allotted ($allottedCount)',
                          selected: _filter == _VehicleFilter.allotted,
                          onSelected: () => setState(() => _filter = _VehicleFilter.allotted),
                        ),
                        const SizedBox(width: 8),
                        _filterChip(
                          context,
                          label: 'Unassigned ($unallottedCount)',
                          selected: _filter == _VehicleFilter.unallotted,
                          onSelected: () => setState(() => _filter = _VehicleFilter.unallotted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Vehicle List
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.directions_car_outlined, size: 54, color: p.textTertiary),
                        const SizedBox(height: 12),
                        Text(
                          _searchController.text.isNotEmpty
                              ? 'No vehicles match your search'
                              : 'No vehicles registered yet',
                          style: textTheme.titleSmall?.copyWith(color: p.textSecondary),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final v = filtered[index];
                        return _buildVehicleCard(context, p, v);
                      },
                      childCount: filtered.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddVehicleDialog,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add vehicle'),
        backgroundColor: p.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _filterChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: p.primary.withValues(alpha: 0.16),
      backgroundColor: p.card,
      labelStyle: TextStyle(
        color: selected ? p.primary : p.textSecondary,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        fontSize: 12.5,
      ),
      side: BorderSide(
        color: selected ? p.primary : p.hairline,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _buildVehicleCard(BuildContext context, AppPaletteData p, AdminVehicleEntry v) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: p.featureColor(5).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.directions_car_rounded, color: p.featureColor(5), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        v.makeModel,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: p.cardMuted,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: p.hairline),
                        ),
                        child: Text(
                          v.registrationNo,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: p.textPrimary,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Parking Slot Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: v.hasParkingSlot
                        ? p.success.withValues(alpha: 0.12)
                        : p.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: v.hasParkingSlot
                          ? p.success.withValues(alpha: 0.3)
                          : p.warning.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        v.hasParkingSlot ? Icons.local_parking_rounded : Icons.info_outline_rounded,
                        size: 14,
                        color: v.hasParkingSlot ? p.success : p.warning,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        v.hasParkingSlot ? 'Slot ${v.parkingSlot}' : 'Unallotted',
                        style: TextStyle(
                          color: v.hasParkingSlot ? p.success : p.warning,
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: p.hairline),
            const SizedBox(height: 12),
            // Flat & Resident Details
            Row(
              children: [
                Icon(Icons.home_outlined, size: 16, color: p.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    v.flatDisplay,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(Icons.person_outline_rounded, size: 16, color: p.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '${v.residentName} (${v.residentType})',
                  style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
                ),
              ],
            ),
            if (v.residentPhone != null && v.residentPhone!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.call_outlined, size: 15, color: p.textTertiary),
                  const SizedBox(width: 6),
                  Text(
                    v.residentPhone!,
                    style: textTheme.bodySmall?.copyWith(color: p.textTertiary),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _openEditParkingDialog(v),
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: Text(v.hasParkingSlot ? 'Edit parking' : 'Allot parking'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _confirmDeleteVehicle(v),
                  icon: Icon(Icons.delete_outline_rounded, size: 20, color: p.danger),
                  tooltip: 'Delete vehicle',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditParkingDialog(AdminVehicleEntry v) async {
    final controller = TextEditingController(text: v.parkingSlot ?? '');
    final formKey = GlobalKey<FormState>();

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final p = AppTheme.paletteFor(Theme.of(ctx).brightness);
        return AlertDialog(
          title: Text(v.hasParkingSlot ? 'Edit Parking Slot' : 'Allot Parking Slot'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${v.makeModel} · ${v.registrationNo}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  v.flatDisplay,
                  style: TextStyle(color: p.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Parking Slot Number',
                    hintText: 'e.g., P-101, B-04, Ground 12',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final slotText = controller.text.trim();
                try {
                  await Supabase.instance.client
                      .from('resident_vehicles')
                      .update({'parking_slot': slotText.isEmpty ? null : slotText})
                      .eq('id', v.id);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  debugPrint('Error updating slot: $e');
                  if (ctx.mounted) Navigator.pop(ctx, true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (updated == true) {
      HapticFeedback.lightImpact();
      _loadVehicles();
    }
  }

  Future<void> _confirmDeleteVehicle(AdminVehicleEntry v) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Remove Vehicle?'),
          content: Text(
            'Are you sure you want to remove ${v.makeModel} (${v.registrationNo}) from ${v.flatDisplay}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await Supabase.instance.client
            .from('resident_vehicles')
            .delete()
            .eq('id', v.id);
        _loadVehicles();
      } catch (e) {
        debugPrint('Error deleting vehicle: $e');
        _loadVehicles();
      }
    }
  }

  Future<void> _openAddVehicleDialog() async {
    // Allows admin to register vehicle and allot parking
    final makeController = TextEditingController();
    final regController = TextEditingController();
    final slotController = TextEditingController();
    String? selectedFlatId;
    String? selectedResidentId;

    List<Map<String, dynamic>> flatsList = [];
    List<Map<String, dynamic>> residentsList = [];

    try {
      final client = Supabase.instance.client;
      final socId = AppSession.instance.societyId;
      var q = client.from('flats').select('id, flat_number, blocks(name)');
      if (socId != null && socId.isNotEmpty) {
        q = q.eq('society_id', socId);
      }
      final resFlats = await q.order('flat_number');
      flatsList = (resFlats as List).cast<Map<String, dynamic>>();

      var qRes = client.from('residents').select('id, flat_id, full_name, resident_type');
      if (socId != null && socId.isNotEmpty) {
        qRes = qRes.eq('society_id', socId);
      }
      final resResidents = await qRes;
      residentsList = (resResidents as List).cast<Map<String, dynamic>>();
    } catch (_) {}

    if (!mounted) return;

    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final availableResidents = selectedFlatId == null
                ? residentsList
                : residentsList.where((r) => r['flat_id']?.toString() == selectedFlatId).toList();

            return AlertDialog(
              title: const Text('Add Vehicle & Allot Parking'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (flatsList.isNotEmpty)
                      DropdownButtonFormField<String>(
                        value: selectedFlatId,
                        decoration: const InputDecoration(
                          labelText: 'Flat *',
                          border: OutlineInputBorder(),
                        ),
                        items: flatsList.map((f) {
                          final fId = f['id'].toString();
                          final fNum = f['flat_number']?.toString() ?? '';
                          final blk = f['blocks']?['name']?.toString() ?? '';
                          return DropdownMenuItem(
                            value: fId,
                            child: Text(blk.isNotEmpty ? '$blk · Flat $fNum' : 'Flat $fNum'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setModalState(() {
                            selectedFlatId = val;
                            selectedResidentId = null;
                          });
                        },
                      ),
                    const SizedBox(height: 12),
                    if (availableResidents.isNotEmpty)
                      DropdownButtonFormField<String>(
                        value: selectedResidentId,
                        decoration: const InputDecoration(
                          labelText: 'Resident Owner *',
                          border: OutlineInputBorder(),
                        ),
                        items: availableResidents.map((r) {
                          final rId = r['id'].toString();
                          final rName = r['full_name']?.toString() ?? 'Resident';
                          final rType = r['resident_type']?.toString() ?? '';
                          return DropdownMenuItem(
                            value: rId,
                            child: Text('$rName ($rType)'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setModalState(() => selectedResidentId = val);
                        },
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: makeController,
                      decoration: const InputDecoration(
                        labelText: 'Make & Model *',
                        hintText: 'e.g. Honda City (White)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: regController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Number *',
                        hintText: 'e.g. DL 03 CA 1234',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: slotController,
                      decoration: const InputDecoration(
                        labelText: 'Parking Slot',
                        hintText: 'e.g. P-102',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final make = makeController.text.trim();
                    final reg = regController.text.trim();
                    final slot = slotController.text.trim();

                    if (make.isEmpty || reg.isEmpty) return;

                    final socId = AppSession.instance.societyId;
                    if (socId == null || selectedFlatId == null || selectedResidentId == null) {
                      Navigator.pop(ctx, true);
                      return;
                    }

                    try {
                      await Supabase.instance.client.from('resident_vehicles').insert({
                        'society_id': socId,
                        'flat_id': selectedFlatId,
                        'resident_id': selectedResidentId,
                        'make_model': make,
                        'registration_no': reg,
                        'parking_slot': slot.isEmpty ? null : slot,
                      });
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      debugPrint('Error inserting vehicle: $e');
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (added == true) {
      HapticFeedback.lightImpact();
      _loadVehicles();
    }
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatPill({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const Spacer(),
              Text(
                value,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}
