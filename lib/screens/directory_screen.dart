import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/resident_data.dart';
import '../models/db_models.dart';
import '../models/society_models.dart';
import '../services/app_session.dart';
import '../theme/app_theme.dart';
import '../widgets/home_widgets.dart';
import '../widgets/resident_widgets.dart';

enum _StatusFilter { all, owner, tenant, family, vacant }

extension _StatusLabel on _StatusFilter {
  String get label => switch (this) {
        _StatusFilter.all => 'All',
        _StatusFilter.owner => 'Owners',
        _StatusFilter.tenant => 'Tenants',
        _StatusFilter.family => 'Family',
        _StatusFilter.vacant => 'Vacant',
      };
}

/// Resident & Flat Management — society register backed by Supabase.
///
/// - Admins: full rows from `public.residents` (phone/email/aadhar visible)
/// - Residents: limited view via `get_directory_public` RPC (name + flat + type only)
/// - Add Member: inserts into `public.residents` with all mandatory fields
class DirectoryScreen extends StatefulWidget {
  final bool showBack;

  const DirectoryScreen({super.key, this.showBack = false});

  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  List<ResidenceUnit> _units = [];
  List<String> _towers = [];
  List<BlockInfo> _blocks = [];
  List<FlatInfo> _flats = [];

  String _query = '';
  String? _tower;
  _StatusFilter _status = _StatusFilter.all;

  bool _isLoading = true;
  String? _error;
  bool _isMockMode = false;

  bool get _effectiveIsAdmin {
    if (_isMockMode) return true;
    try {
      return AppSession.instance.isAdmin;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    bool supabaseReady = false;
    try {
      Supabase.instance.client;
      supabaseReady = true;
    } catch (_) {
      supabaseReady = false;
    }
    if (!supabaseReady) {
      // Widget test / no supabase — show mock register immediately
      _units = List.of(sampleUnits);
      _towers = _units.map((u) => u.tower).toSet().toList()..sort();
      _isMockMode = true;
      _isLoading = false;
      _blocks = [];
      _flats = [];
    } else {
      _units = [];
      _towers = [];
      _isLoading = true;
      _loadData();
    }
    try {
      AppSession.instance.addListener(_onSessionChanged);
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      AppSession.instance.removeListener(_onSessionChanged);
    } catch (_) {}
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) _loadData();
  }

  bool get _hasFilters =>
      _query.isNotEmpty || _tower != null || _status != _StatusFilter.all;

  String _monthLabel(int m) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return months[m - 1];
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final session = AppSession.instance;
      if (!session.isLoaded && !session.isLoading) {
        await session.load();
      }
      final societyId = session.societyId;
      final isAdmin = session.isAdmin;

      if (societyId == null || societyId.isEmpty) {
        throw Exception('No society linked to this account. Ask your admin to add you as a resident.');
      }

      final client = Supabase.instance.client;

      // 1) Blocks
      final blocksRaw = await client
          .from('blocks')
          .select('id, society_id, name')
          .eq('society_id', societyId);
      final blocks = ((blocksRaw as List?) ?? [])
          .map((m) => BlockInfo.fromMap(m as Map<String, dynamic>))
          .where((b) => b.id.isNotEmpty)
          .toList();

      final blockIds = blocks.map((b) => b.id).where((id) => id.isNotEmpty).toList();
      List<FlatInfo> flats = [];
      if (blockIds.isNotEmpty) {
        final flatsRaw = await client
            .from('flats')
            .select('id, block_id, floor_number, flat_number, type, status')
            .inFilter('block_id', blockIds)
            .order('flat_number', ascending: true);
        flats = ((flatsRaw as List?) ?? [])
            .map((m) => FlatInfo.fromMap(m as Map<String, dynamic>))
            .where((f) => f.id.isNotEmpty && f.flatNumber.isNotEmpty)
            .toList();
      }

      // 2) Residents - admin full vs limited
      final Map<String, List<Resident>> residentsByFlat = {};

      if (isAdmin) {
        final resRaw = await client
            .from('residents')
            .select()
            .eq('society_id', societyId)
            .eq('status', 'active');
        final records = ((resRaw as List?) ?? [])
            .map((m) => ResidentRecord.fromMap(m as Map<String, dynamic>))
            .where((r) => r.id.isNotEmpty && r.flatId.isNotEmpty)
            .toList();
        for (final rec in records) {
          ResidentRole role;
          switch (rec.residentType) {
            case 'tenant':
              role = ResidentRole.tenant;
              break;
            case 'family':
              role = ResidentRole.family;
              break;
            default:
              role = ResidentRole.owner;
          }
          final resident = Resident(
            fullName: rec.fullName,
            role: role,
            phone: rec.phone,
            email: rec.email,
            memberSince: rec.createdAt != null
                ? '${_monthLabel(rec.createdAt!.month)} ${rec.createdAt!.year}'
                : (rec.agreementDate != null
                    ? '${_monthLabel(rec.agreementDate!.month)} ${rec.agreementDate!.year}'
                    : '—'),
            isPrimary: rec.isPrimary,
          );
          residentsByFlat.putIfAbsent(rec.flatId, () => []).add(resident);
        }
      } else {
        // Limited directory RPC - name + flat + type only
        final rpcRaw = await client
            .rpc('get_directory_public', params: {'p_society_id': societyId});
        final list = ((rpcRaw as List?) ?? []).cast<Map<String, dynamic>>();
        for (final m in list) {
          final flatId = m['flat_id']?.toString() ?? '';
          if (flatId.isEmpty) continue;
          final name = m['full_name']?.toString() ?? '';
          final type = m['resident_type']?.toString() ?? 'owner';
          ResidentRole role;
          switch (type) {
            case 'tenant':
              role = ResidentRole.tenant;
              break;
            case 'family':
              role = ResidentRole.family;
              break;
            default:
              role = ResidentRole.owner;
          }
          final resident = Resident(
            fullName: name.isEmpty ? 'Resident' : name,
            role: role,
            phone: null,
            email: null,
            memberSince: '—',
            isPrimary: (m['is_primary'] == true || m['is_primary'] == 1 || m['is_primary']?.toString() == 'true'),
          );
          residentsByFlat.putIfAbsent(flatId, () => []).add(resident);
        }
      }

      // 3) Build ResidenceUnit list for UI
      final List<ResidenceUnit> units = [];
      for (final flat in flats) {
        final block = blocks.firstWhere(
          (b) => b.id == flat.blockId,
          orElse: () => BlockInfo(id: flat.blockId, societyId: societyId, name: 'Block ?'),
        );
        String tower = block.name.trim();
        if (tower.toLowerCase().startsWith('block')) {
          tower = tower.replaceFirst(RegExp(r'block\s*', caseSensitive: false), '').trim();
        }
        if (tower.isEmpty) {
          final parts = flat.flatNumber.split('-');
          tower = parts.isNotEmpty ? parts[0] : '—';
        }
        if (tower.length > 1) tower = tower[0];
        if (tower == '?' || tower.isEmpty) tower = '—';

        int bhk = 2;
        final bhkMatch = RegExp(r'(\d+)').firstMatch(flat.type);
        if (bhkMatch != null) bhk = int.tryParse(bhkMatch.group(1)!) ?? 2;
        int sqft = 1100 + flat.floorNumber * 40;

        final residents = residentsByFlat[flat.id] ?? [];
        units.add(ResidenceUnit(
          number: flat.flatNumber,
          tower: tower,
          floor: flat.floorNumber,
          bhk: bhk,
          sqft: sqft,
          parking: null,
          residents: residents,
        ));
      }

      // Keep flats even if no residents, to show vacant
      units.sort((a, b) => a.number.compareTo(b.number));

      if (!mounted) return;
      setState(() {
        _blocks = blocks;
        _flats = flats;
        _units = units;
        _towers = units.map((u) => u.tower).toSet().toList()..sort();
        _isLoading = false;
        _isMockMode = false;
        _error = null;
      });
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      final looksLikeInitError = msg.contains('Supabase') ||
          msg.contains('not initialized') ||
          msg.contains('NoSuchMethod') ||
          msg.contains('has not been initialized');
      // Fallback to sampleUnits in test env where supabase not ready
      if (looksLikeInitError && mounted) {
        setState(() {
          _units = List.of(sampleUnits);
          _towers = _units.map((u) => u.tower).toSet().toList()..sort();
          _blocks = [];
          _flats = [];
          _isLoading = false;
          _isMockMode = true;
          _error = null;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = msg;
        // keep previous units if any, else empty
        if (_units.isEmpty && _towers.isEmpty) {
          // try fallback to sample for demo if society missing? No, show error empty
        }
      });
    }
  }

  List<ResidenceUnit> get _filtered {
    final q = _query.trim().toLowerCase();
    return _units.where((unit) {
      if (_tower != null && unit.tower != _tower) return false;
      final vacants = !unit.isOccupied;
      final hasOwner = unit.residents.any((r) => r.role == ResidentRole.owner);
      final hasTenant = unit.residents.any((r) => r.role == ResidentRole.tenant);
      final hasFamily = unit.residents.any((r) => r.role == ResidentRole.family);
      final matchesStatus = switch (_status) {
        _StatusFilter.all => true,
        _StatusFilter.vacant => vacants,
        _StatusFilter.owner => hasOwner,
        _StatusFilter.tenant => hasTenant,
        _StatusFilter.family => hasFamily,
      };
      if (!matchesStatus) return false;
      if (q.isEmpty) return true;
      if (unit.number.toLowerCase().contains(q)) return true;
      return unit.residents.any((r) => r.fullName.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSession.instance,
      builder: (context, _) {
        try {
          final filtered = _filtered;
          final occupied = _units.where((u) => u.isOccupied).length;
          final residents = _units.expand((u) => u.residents).length;
          final owners = _units
              .expand((u) => u.residents)
              .where((r) => r.role == ResidentRole.owner)
              .length;
          final tenants = _units
              .expand((u) => u.residents)
              .where((r) => r.role == ResidentRole.tenant)
              .length;
          final isAdmin = _effectiveIsAdmin;
          bool isLoadingSession = false;
          try {
            isLoadingSession = AppSession.instance.isLoading;
          } catch (_) {}

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: _loadData,
              edgeOffset: 90,
              child: _isLoading || isLoadingSession
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      children: [
                        _buildHeader(context, isAdmin: isAdmin),
                        const SizedBox(height: 80),
                        const Center(child: CircularProgressIndicator()),
                      ],
                    )
                  : _error != null && _units.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          children: [
                            _buildHeader(context, isAdmin: isAdmin),
                            const SizedBox(height: 24),
                            _buildError(context, _error!),
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          children: [
                            _buildHeader(context, isAdmin: isAdmin),
                            const SizedBox(height: 18),
                            _OccupancyCard(
                              totalUnits: _units.length,
                              occupied: occupied,
                              residents: residents,
                              owners: owners,
                              tenants: tenants,
                            ),
                            const SizedBox(height: 16),
                            _buildSearch(context),
                            const SizedBox(height: 12),
                            _buildTowerFilter(context),
                            const SizedBox(height: 8),
                            _buildStatusFilter(context),
                            const SizedBox(height: 12),
                            Text(
                              'Showing ${filtered.length} of ${_units.length} flats',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            if (_hasFilters) ...[
                              const SizedBox(height: 8),
                              _buildClearFilters(context),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              _buildInlineError(context, _error!),
                            ],
                            if (filtered.isEmpty)
                              _buildNoResults(context)
                            else
                              for (final tower in _towers)
                                ..._buildTowerSection(context, tower, filtered, isAdmin: isAdmin),
                            const SizedBox(height: 26),
                            SectionHeader(title: 'Help contacts', actionLabel: null),
                            const SizedBox(height: 12),
                            _buildQuickContacts(context),
                            if (!isAdmin) ...[
                              const SizedBox(height: 16),
                              _buildLimitedNotice(context),
                            ],
                          ],
                        ),
            ),
          ),
        );
        } catch (e, st) {
          // ignore: avoid_print
          print('Directory build error: $e\n$st');
          return Scaffold(
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  _buildHeader(context, isAdmin: _effectiveIsAdmin),
                  const SizedBox(height: 24),
                  _buildError(context, e.toString()),
                ],
              ),
            ),
          );
        }
      },
    );
  }

  Widget _buildInlineError(BuildContext context, String msg) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.danger.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: p.danger),
          const SizedBox(width: 10),
          Expanded(child: Text(msg, style: Theme.of(context).textTheme.bodySmall)),
          IconButton(
            icon: Icon(Icons.refresh_rounded, size: 18, color: p.primary),
            onPressed: _loadData,
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, String msg) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: p.danger.withValues(alpha: 0.10), shape: BoxShape.circle),
            child: Icon(Icons.error_outline_rounded, size: 28, color: p.danger),
          ),
          const SizedBox(height: 16),
          Text('Unable to load directory', style: textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(msg, textAlign: TextAlign.center, style: textTheme.bodySmall),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildLimitedNotice(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, size: 16, color: p.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Limited view — only name & flat are shown. Phone, email & Aadhaar are visible to admins only.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Header -----------------------------------------------------------

  Widget _buildHeader(BuildContext context, {required bool isAdmin}) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showBack) ...[
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded),
            style: IconButton.styleFrom(backgroundColor: p.card, side: BorderSide(color: p.hairline)),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppSession.instance.societyName.toUpperCase(),
                style: textTheme.labelSmall?.copyWith(color: p.primary, letterSpacing: 1.6, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text('Residents & Flats', style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                isAdmin ? 'Complete register of units and their occupants' : 'Directory — name & flat only (limited view)',
                style: textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (isAdmin) ...[
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/flats-management'),
            icon: const Icon(Icons.domain_outlined, size: 20),
            tooltip: 'Manage Flats & Blocks',
            style: IconButton.styleFrom(
              backgroundColor: p.card,
              side: BorderSide(color: p.hairline),
            ),
          ),
          const SizedBox(width: 8),
          _AddMemberButton(onPressed: () => _openAddMember(context)),
        ],
        if (!isAdmin)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: p.cardMuted,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.visibility_outlined, size: 14, color: p.textTertiary),
                const SizedBox(width: 4),
                Text('View only', style: textTheme.labelSmall?.copyWith(fontSize: 10)),
              ],
            ),
          ),
      ],
    );
  }

  // ---- Search & filters --------------------------------------------------

  Widget _buildSearch(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return TextField(
      onChanged: (value) => setState(() => _query = value),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search residents or flats',
        prefixIcon: Icon(Icons.search_rounded, size: 20, color: p.textTertiary),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                onPressed: () => setState(() => _query = ''),
                icon: Icon(Icons.close_rounded, size: 18, color: p.textTertiary),
              ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }

  Widget _buildTowerFilter(BuildContext context) {
    return _buildFilterRow(
      context,
      label: 'Tower',
      chips: [
        _FilterChip(label: 'All', selected: _tower == null, onTap: () => setState(() => _tower = null)),
        for (final tower in _towers)
          _FilterChip(label: 'Tower $tower', selected: _tower == tower, onTap: () => setState(() => _tower = tower)),
      ],
    );
  }

  Widget _buildStatusFilter(BuildContext context) {
    return _buildFilterRow(
      context,
      label: 'Residents',
      chips: [
        for (final status in _StatusFilter.values)
          _FilterChip(label: status.label, selected: _status == status, onTap: () => setState(() => _status = status)),
      ],
    );
  }

  Widget _buildFilterRow(BuildContext context, {required String label, required List<Widget> chips}) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Text(label, style: textTheme.labelSmall),
        const SizedBox(width: 12),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                for (var i = 0; i < chips.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  chips[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildClearFilters(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => setState(() {
          _query = '';
          _tower = null;
          _status = _StatusFilter.all;
        }),
        icon: Icon(Icons.filter_alt_off_rounded, size: 16, color: p.primary),
        label: const Text('Clear filters'),
      ),
    );
  }

  // ---- Directory body ----------------------------------------------------

  List<Widget> _buildTowerSection(BuildContext context, String tower, List<ResidenceUnit> filtered, {required bool isAdmin}) {
    final textTheme = Theme.of(context).textTheme;
    final units = filtered.where((u) => u.tower == tower).toList();
    if (units.isEmpty) return const [];

    final residentCount = units.expand((u) => u.residents).length;
    final occupied = units.where((u) => u.isOccupied).length;

    final header = Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 12),
      child: Row(
        children: [
          Text('Tower $tower', style: textTheme.titleMedium),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              '${units.length} flats · $occupied occupied${residentCount > 0 ? ' · $residentCount residents' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(fontSize: 11),
            ),
          ),
        ],
      ),
    );

    return [
      header,
      for (final unit in units)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _FlatCard(unit: unit, onTap: () => _openFlatDetails(context, unit, isAdmin: isAdmin), onCall: _callResident, isAdmin: isAdmin),
        ),
    ];
  }

  Widget _buildNoResults(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: p.hairline)),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: p.primary.withValues(alpha: 0.10), shape: BoxShape.circle),
            child: Icon(Icons.search_off_rounded, size: 28, color: p.primary),
          ),
          const SizedBox(height: 16),
          Text('Nothing matches this search', style: textTheme.titleSmall),
          const SizedBox(height: 6),
          Text('Try a different name or flat number, or widen your filters.', textAlign: TextAlign.center, style: textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _buildQuickContacts(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _QuickContact(icon: Icons.support_agent_rounded, title: 'Security desk', subtitle: 'Ground floor lobby')),
        const SizedBox(width: 12),
        Expanded(child: _QuickContact(icon: Icons.local_hospital_rounded, title: 'EMI / Fire', subtitle: '102 · 108')),
      ],
    );
  }

  // ---- Actions -----------------------------------------------------------

  void _callResident(Resident resident) {
    if (!_effectiveIsAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contact details are visible to admins only.')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Calling ${resident.fullName}…')));
  }

  void _openFlatDetails(BuildContext context, ResidenceUnit unit, {required bool isAdmin}) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      builder: (sheetContext) => _FlatDetailSheet(unit: unit, onCall: _callResident, isAdmin: isAdmin, onEdit: () {
        Navigator.pop(sheetContext);
        _openEditDetails(context, unit);
      }),
    );
  }

  void _openEditDetails(BuildContext context, ResidenceUnit unit) {
    if (_isMockMode) {
      final p = AppTheme.paletteFor(Theme.of(context).brightness);
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: p.card,
        builder: (sheetContext) => _MockEditDetailsSheet(
          unit: unit,
          onSave: (updated) {
            setState(() {
              final idx = _units.indexWhere((u) => u.number == unit.number);
              if (idx != -1) _units[idx] = updated;
              _towers = _units.map((u) => u.tower).toSet().toList()..sort();
            });
            Navigator.pop(sheetContext);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${updated.number} updated')));
          },
        ),
      );
      return;
    }
    if (!_effectiveIsAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Only admins can edit details.')));
      return;
    }
    // Find FlatInfo for this unit (match by flat_number)
    FlatInfo? flat;
    try {
      flat = _flats.firstWhere((f) => f.flatNumber == unit.number);
    } catch (_) {
      flat = null;
    }
    if (flat == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Flat ${unit.number} not found in database.')));
      return;
    }
    BlockInfo? block;
    try {
      block = _blocks.firstWhere((b) => b.id == flat!.blockId);
    } catch (_) {
      block = null;
    }
    final societyId = AppSession.instance.societyId;
    if (societyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No society linked.')));
      return;
    }
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      builder: (sheetContext) => _EditDetailsSheet(
        flat: flat!,
        block: block,
        societyId: societyId,
        onSuccess: () {
          Navigator.pop(sheetContext);
          _loadData();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${unit.number} details updated')));
        },
      ),
    );
  }

  void _openAddMember(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

    // Mock mode for widget tests — use in-memory add without supabase
    if (_isMockMode) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: p.card,
        builder: (sheetContext) => _MockAddMemberSheet(
          units: _units,
          onAdd: (unit, resident) {
            setState(() {
              final flat = _units.firstWhere((u) => u.number == unit.number);
              flat.residents.add(resident);
            });
            Navigator.pop(sheetContext);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${resident.fullName} added to ${unit.number} · ${resident.memberSince}')));
          },
        ),
      );
      return;
    }

    AppSession session;
    try {
      session = AppSession.instance;
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Only society admins can add members.')));
      return;
    }
    if (!_effectiveIsAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Only society admins can add members.')));
      return;
    }
    final societyId = session.societyId;
    if (societyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No society linked.')));
      return;
    }
    if (_blocks.isEmpty || _flats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No flats available. Create blocks/flats first.')));
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      builder: (sheetContext) => _AddMemberSheet(
        blocks: _blocks,
        flats: _flats,
        societyId: societyId,
        flatResidentsCount: {for (var u in _units) u.number: u.residents.length},
        onSuccess: () {
          Navigator.pop(sheetContext);
          _loadData();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Member added — will auto-link when they sign up with the same email.')));
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _AddMemberButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _AddMemberButton({required this.onPressed});
  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: p.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: p.primary.withValues(alpha: 0.18))),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_add_rounded, size: 18, color: p.primary),
              const SizedBox(width: 6),
              Text('Add member', style: textTheme.labelMedium?.copyWith(color: p.primary, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: selected ? p.primary.withValues(alpha: 0.16) : p.cardMuted,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: selected ? p.primary : p.hairline)),
          child: Text(label, style: textTheme.labelMedium?.copyWith(color: selected ? p.primary : p.textSecondary, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        ),
      ),
    );
  }
}

class _OccupancyCard extends StatelessWidget {
  final int totalUnits;
  final int occupied;
  final int residents;
  final int owners;
  final int tenants;
  const _OccupancyCard({required this.totalUnits, required this.occupied, required this.residents, required this.owners, required this.tenants});
  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    final fraction = totalUnits == 0 ? 0.0 : occupied / totalUnits;
    final percent = (fraction * 100).round();
    return Surface(
      padding: const EdgeInsets.all(16),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Overall occupancy', style: textTheme.titleSmall), const SizedBox(height: 3), Text('$occupied of $totalUnits flats occupied', style: textTheme.bodySmall)])),
              Text('$percent%', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: p.primary, fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
          const SizedBox(height: 14),
          OccupancyBar(fraction: fraction),
          const SizedBox(height: 16),
          Divider(color: p.hairline),
          const SizedBox(height: 14),
          Row(children: [_Metric(value: '$totalUnits', label: 'Units'), _divider(p), _Metric(value: '$occupied', label: 'Occupied'), _divider(p), _Metric(value: '$residents', label: 'Residents'), _divider(p), _Metric(value: '$owners', label: 'Owners'), _divider(p), _Metric(value: '$tenants', label: 'Tenants')]),
        ],
      ),
    );
  }

  Widget _divider(AppPaletteData p) => Container(width: 1, height: 26, color: p.hairline);
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;
  const _Metric({required this.value, required this.label});
  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    return Expanded(child: Column(children: [Text(value, style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])), const SizedBox(height: 2), Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.labelSmall?.copyWith(fontSize: 9.5, letterSpacing: 0.1, color: p.textTertiary))]));
  }
}

class _FlatCard extends StatelessWidget {
  final ResidenceUnit unit;
  final VoidCallback onTap;
  final void Function(Resident resident) onCall;
  final bool isAdmin;
  const _FlatCard({required this.unit, required this.onTap, required this.onCall, required this.isAdmin});
  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    return Surface(
      padding: EdgeInsets.zero,
      radius: 18,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Column(
          children: [
            _header(context, p, textTheme),
            if (unit.isOccupied) ...[
              const SizedBox(height: 10),
              Divider(color: p.hairline),
              for (final resident in unit.residents) _ResidentRow(resident: resident, onCall: () => onCall(resident), dense: true, isAdmin: isAdmin),
            ] else
              _vacantRow(context, p, textTheme),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, AppPaletteData p, TextTheme textTheme) {
    return Row(
      children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: p.accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.villa_outlined, size: 20, color: p.accent)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(unit.number, style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)), const SizedBox(height: 2), Text('Floor ${unit.floor} · ${unit.bhk} BHK · ${unit.sqft} sq ft', style: textTheme.bodySmall?.copyWith(fontSize: 11.5))])),
        if (unit.isOccupied)
          Text('${unit.residents.length} ${unit.residents.length == 1 ? 'resident' : 'residents'}', style: textTheme.labelMedium?.copyWith(color: p.textSecondary, fontSize: 11))
        else
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: p.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)), child: Text('Vacant', style: textTheme.labelSmall?.copyWith(color: p.warning, fontSize: 10, fontWeight: FontWeight.w700))),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right_rounded, size: 20, color: p.textTertiary),
      ],
    );
  }

  Widget _vacantRow(BuildContext context, AppPaletteData p, TextTheme textTheme) {
    return Padding(padding: const EdgeInsets.only(top: 10), child: Row(children: [Icon(Icons.hourglass_empty_rounded, size: 18, color: p.textTertiary), const SizedBox(width: 10), Expanded(child: Text('Open for allotment — no occupants on record', style: textTheme.bodySmall?.copyWith(fontSize: 12)))]));
  }
}

class _ResidentRow extends StatelessWidget {
  final Resident resident;
  final VoidCallback onCall;
  final bool dense;
  final bool isAdmin;
  const _ResidentRow({required this.resident, required this.onCall, this.dense = false, this.isAdmin = true});
  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    final subtitle = [
      if (resident.relation != null) resident.relation!,
      if (resident.isPrimary) 'Primary contact',
      if (!isAdmin) 'Limited view',
    ].join(' · ');
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 6 : 10),
      child: Row(
        children: [
          ResidentAvatar(initials: resident.initials, size: dense ? 34 : 44),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Flexible(child: Text(resident.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.titleSmall)), const SizedBox(width: 8), RolePill(role: resident.role)]), if (subtitle.isNotEmpty) ...[const SizedBox(height: 2), Text(subtitle, style: textTheme.bodySmall?.copyWith(fontSize: 11.5))]])),
          if (resident.vehicle != null && isAdmin) ...[Icon(Icons.directions_car_filled_rounded, size: 16, color: p.textTertiary), const SizedBox(width: 10)],
          if (resident.phone != null && isAdmin)
            Container(
              width: dense ? 32 : 36,
              height: dense ? 32 : 36,
              decoration: BoxDecoration(color: p.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(dense ? 10 : 12)),
              child: IconButton(onPressed: onCall, padding: EdgeInsets.zero, iconSize: 16, color: p.primary, icon: const Icon(Icons.call_rounded)),
            ),
        ],
      ),
    );
  }
}

class _QuickContact extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _QuickContact({required this.icon, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.hairline)),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: p.secondary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 20, color: p.secondary)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall), const SizedBox(height: 2), Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11.5))]))
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom sheets
// ---------------------------------------------------------------------------

class _FlatDetailSheet extends StatelessWidget {
  final ResidenceUnit unit;
  final void Function(Resident resident) onCall;
  final VoidCallback onEdit;
  final bool isAdmin;
  const _FlatDetailSheet({required this.unit, required this.onCall, required this.onEdit, required this.isAdmin});
  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    final vehicles = unit.residents.where((r) => r.vehicle != null).toList();
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: p.hairline, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 18),
            _sheetHeader(context, p, textTheme),
            const SizedBox(height: 6),
            _kicker(context, 'OCCUPANTS'),
            const SizedBox(height: 4),
            if (unit.isOccupied)
              for (final resident in unit.residents) ...[
                _ResidentRow(resident: resident, onCall: () => onCall(resident), isAdmin: isAdmin),
                Divider(color: p.hairline),
              ]
            else
              _sheetVacant(context, p, textTheme),
            if (!isAdmin && unit.isOccupied) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: p.warning.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: p.warning.withValues(alpha: 0.15))),
                child: Row(children: [Icon(Icons.lock_outline_rounded, size: 16, color: p.warning), const SizedBox(width: 8), Expanded(child: Text('Phone, email and Aadhaar are hidden in limited view.', style: textTheme.bodySmall?.copyWith(fontSize: 11)))]),
              ),
            ],
            const SizedBox(height: 14),
            _kicker(context, 'FLAT DETAILS'),
            const SizedBox(height: 10),
            _infoGrid(context, p, textTheme),
            if (vehicles.isNotEmpty && isAdmin) ...[
              const SizedBox(height: 22),
              _kicker(context, 'REGISTERED VEHICLES'),
              const SizedBox(height: 10),
              Surface(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                radius: 16,
                child: Column(children: [for (final resident in vehicles) _vehicleRow(context, p, textTheme, resident)]),
              ),
            ],
            const SizedBox(height: 24),
            Row(children: [
              if (isAdmin) ...[
                Expanded(child: OutlinedButton(onPressed: onEdit, child: const Text('Edit details'))),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: unit.primaryContact == null || !isAdmin ? null : () => onCall(unit.primaryContact!),
                  icon: const Icon(Icons.call_rounded, size: 18),
                  label: Text(unit.primaryContact == null ? 'No contact' : (isAdmin ? 'Call ${unit.primaryContact!.firstName}' : 'Admin only')),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _sheetHeader(BuildContext context, AppPaletteData p, TextTheme textTheme) {
    return Row(children: [
      ResidentAvatar(initials: unit.number.replaceAll('-', ''), size: 52),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Text(unit.number, style: textTheme.titleLarge), const SizedBox(width: 10), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: (unit.isOccupied ? p.success : p.warning).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)), child: Text(unit.isOccupied ? 'Occupied' : 'Vacant', style: textTheme.labelSmall?.copyWith(color: unit.isOccupied ? p.success : p.warning, fontSize: 10, fontWeight: FontWeight.w700)))]), const SizedBox(height: 4), Text('Tower ${unit.tower} · Floor ${unit.floor} · ${unit.bhk} BHK · ${unit.sqft} sq ft', style: textTheme.bodySmall)]))
    ]);
  }

  Widget _kicker(BuildContext context, String text) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: p.primary, letterSpacing: 1.2, fontWeight: FontWeight.w800));
  }

  Widget _infoGrid(BuildContext context, AppPaletteData p, TextTheme textTheme) {
    final parking = unit.parking ?? 'Not allocated';
    return Row(children: [
      Expanded(child: _InfoTile(icon: Icons.stairs_rounded, iconColor: p.secondary, label: 'Floor', value: '${unit.floor}')),
      const SizedBox(width: 10),
      Expanded(child: _InfoTile(icon: Icons.king_bed_outlined, iconColor: p.accent, label: 'Type', value: '${unit.bhk} BHK')),
      const SizedBox(width: 10),
      Expanded(child: _InfoTile(icon: Icons.straighten_rounded, iconColor: p.primary, label: 'Area', value: '${unit.sqft} sq ft')),
      const SizedBox(width: 10),
      Expanded(child: _InfoTile(icon: Icons.local_parking_rounded, iconColor: p.warning, label: 'Parking', value: parking)),
    ]);
  }

  Widget _sheetVacant(BuildContext context, AppPaletteData p, TextTheme textTheme) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: p.warning.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: p.warning.withValues(alpha: 0.18))),
        child: Row(children: [Icon(Icons.hourglass_empty_rounded, size: 20, color: p.warning), const SizedBox(width: 12), Expanded(child: Text('No residents on record for this unit. It is available for allotment by the committee.', style: textTheme.bodySmall?.copyWith(color: p.textSecondary)))]),
      );

  Widget _vehicleRow(BuildContext context, AppPaletteData p, TextTheme textTheme, Resident resident) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [Container(width: 36, height: 36, decoration: BoxDecoration(color: p.secondary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)), child: Icon(Icons.directions_car_filled_rounded, size: 18, color: p.secondary)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(resident.vehicle!, style: textTheme.titleSmall), const SizedBox(height: 2), Text('${resident.fullName} · ${resident.role.label}', style: textTheme.bodySmall?.copyWith(fontSize: 11.5))]))]),
      );
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  const _InfoTile({required this.icon, required this.iconColor, required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12), decoration: BoxDecoration(color: p.cardMuted, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.hairline)), child: Column(children: [Icon(icon, size: 18, color: iconColor), const SizedBox(height: 8), Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.labelMedium?.copyWith(color: p.textPrimary, fontWeight: FontWeight.w700)), const SizedBox(height: 2), Text(label, style: textTheme.labelSmall?.copyWith(fontSize: 9.5, letterSpacing: 0.2, color: p.textTertiary))]));
  }
}

class _AddMemberSheet extends StatefulWidget {
  final List<BlockInfo> blocks;
  final List<FlatInfo> flats;
  final String societyId;
  final Map<String, int> flatResidentsCount;
  final VoidCallback onSuccess;
  const _AddMemberSheet({required this.blocks, required this.flats, required this.societyId, required this.flatResidentsCount, required this.onSuccess});
  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _agreementHolder = TextEditingController();
  final _aadhar = TextEditingController();

  ResidentRole _role = ResidentRole.owner;
  String? _selectedBlockId;
  String? _selectedFlatId;
  bool _isPrimary = false;
  DateTime? _agreementDate;
  bool _triedSubmit = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.blocks.isNotEmpty) _selectedBlockId = widget.blocks.first.id;
    _updateFlatForBlock();
  }

  void _updateFlatForBlock() {
    final filtered = _filteredFlats;
    if (filtered.isNotEmpty) {
      _selectedFlatId = filtered.first.id;
      // auto primary if flat currently empty
      final flatNumber = filtered.first.flatNumber;
      _isPrimary = (widget.flatResidentsCount[flatNumber] ?? 0) == 0;
    } else {
      _selectedFlatId = null;
    }
  }

  List<FlatInfo> get _filteredFlats {
    if (_selectedBlockId == null) return widget.flats;
    return widget.flats.where((f) => f.blockId == _selectedBlockId).toList();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _agreementHolder.dispose();
    _aadhar.dispose();
    super.dispose();
  }

  bool _isEmailValid(String v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _agreementDate ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _agreementDate = picked);
  }

  Future<void> _submit() async {
    setState(() => _triedSubmit = true);
    final name = _name.text.trim();
    final email = _email.text.trim();
    final phone = _phone.text.trim();
    final holder = _agreementHolder.text.trim();
    final aadhar = _aadhar.text.trim();

    // validation
    if (name.isEmpty) return;
    if (email.isEmpty || !_isEmailValid(email)) return;
    if (phone.isEmpty) return;
    if (holder.isEmpty) return;
    if (_agreementDate == null) return;
    if (aadhar.isEmpty || !RegExp(r'^[0-9]{4}$').hasMatch(aadhar)) return;
    if (_selectedBlockId == null || _selectedFlatId == null) return;

    setState(() => _submitting = true);
    try {
      final client = Supabase.instance.client;
      final payload = {
        'society_id': widget.societyId,
        'flat_id': _selectedFlatId,
        'full_name': name,
        'email': email,
        'phone': phone,
        'resident_type': _role.name,
        'is_primary': _isPrimary,
        'agreement_holder_name': holder,
        'agreement_date': _agreementDate!.toIso8601String().split('T')[0],
        'aadhar_last4': aadhar,
        'status': 'active',
      };
      await client.from('residents').insert(payload);
      if (!mounted) return;
      widget.onSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_friendlyError(msg))));
    }
  }

  String _friendlyError(String raw) {
    if (raw.contains('residents_mandatory_fields_check')) return 'All mandatory fields must be filled (phone, agreement holder/date, Aadhaar).';
    if (raw.contains('residents_resident_type_check')) return 'Invalid resident type.';
    if (raw.contains('duplicate') || raw.contains('unique')) return 'A resident with this email already exists for the selected flat.';
    if (raw.contains('violates row-level security')) return 'Permission denied — only society admins can add members.';
    if (raw.contains('aadhar_last4')) return 'Aadhaar must be exactly 4 digits.';
    return raw.length > 200 ? '${raw.substring(0, 200)}…' : raw;
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    final filteredFlats = _filteredFlats;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 8, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: p.hairline, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Text('Add member', style: textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Member will be linked automatically when they sign up with the same email. All fields are mandatory.', style: textTheme.bodySmall),
              const SizedBox(height: 20),
              Text('Full name *', style: textTheme.labelMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(hintText: 'e.g. Aman Gupta', errorText: _triedSubmit && _name.text.trim().isEmpty ? 'Name is required' : null),
              ),
              const SizedBox(height: 16),
              Text('Email *', style: textTheme.labelMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'owner or tenant email (required)',
                  errorText: _triedSubmit && (_email.text.trim().isEmpty || !_isEmailValid(_email.text.trim())) ? 'Valid email is required (for linking)' : null,
                ),
              ),
              const SizedBox(height: 16),
              Text('Phone *', style: textTheme.labelMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(hintText: 'e.g. +91 98100 12345', errorText: _triedSubmit && _phone.text.trim().isEmpty ? 'Phone is required' : null),
              ),
              const SizedBox(height: 16),
              Text('Role *', style: textTheme.labelMedium),
              const SizedBox(height: 8),
              SegmentedButton<ResidentRole>(
                segments: const [
                  ButtonSegment(value: ResidentRole.owner, label: Text('Owner'), icon: Icon(Icons.home_rounded, size: 16)),
                  ButtonSegment(value: ResidentRole.tenant, label: Text('Tenant'), icon: Icon(Icons.key_rounded, size: 16)),
                  ButtonSegment(value: ResidentRole.family, label: Text('Family'), icon: Icon(Icons.family_restroom_rounded, size: 16)),
                ],
                selected: {_role},
                onSelectionChanged: (s) => setState(() => _role = s.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Block *', style: textTheme.labelMedium),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedBlockId,
                        isExpanded: true,
                        decoration: const InputDecoration(hintText: 'Choose block'),
                        items: [for (final b in widget.blocks) DropdownMenuItem(value: b.id, child: Text(b.name, overflow: TextOverflow.ellipsis))],
                        onChanged: (v) => setState(() {
                          _selectedBlockId = v;
                          _updateFlatForBlock();
                        }),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Flat *', style: textTheme.labelMedium),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedFlatId,
                        isExpanded: true,
                        decoration: InputDecoration(hintText: filteredFlats.isEmpty ? 'No flats' : 'Choose flat'),
                        items: [for (final f in filteredFlats) DropdownMenuItem(value: f.id, child: Text('${f.flatNumber} · ${f.type}${f.isOccupied ? '' : ' (vacant)'}', overflow: TextOverflow.ellipsis))],
                        onChanged: (v) => setState(() {
                          _selectedFlatId = v;
                          if (v != null) {
                            final flat = filteredFlats.firstWhere((x) => x.id == v);
                            _isPrimary = (widget.flatResidentsCount[flat.flatNumber] ?? 0) == 0;
                          }
                        }),
                      ),
                    ]),
                  ),
                ],
              ),
              if (_triedSubmit && (_selectedBlockId == null || _selectedFlatId == null))
                Padding(padding: const EdgeInsets.only(top: 6), child: Text('Block and flat are required', style: textTheme.bodySmall?.copyWith(color: p.danger))),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _isPrimary,
                onChanged: (v) => setState(() => _isPrimary = v ?? false),
                title: Text('Primary contact', style: textTheme.labelMedium),
                subtitle: Text('Primary residents are shown first and receive notices.', style: textTheme.bodySmall?.copyWith(fontSize: 11)),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 8),
              Text('Agreement holder name *', style: textTheme.labelMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _agreementHolder,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(hintText: 'e.g. Aman Gupta', errorText: _triedSubmit && _agreementHolder.text.trim().isEmpty ? 'Required' : null),
              ),
              const SizedBox(height: 16),
              Text('Agreement date *', style: textTheme.labelMedium),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _triedSubmit && _agreementDate == null ? p.danger : p.hairline)),
                  child: Row(children: [Icon(Icons.event_outlined, size: 18, color: p.textTertiary), const SizedBox(width: 10), Expanded(child: Text(_agreementDate == null ? 'Select date' : '${_agreementDate!.day}/${_agreementDate!.month}/${_agreementDate!.year}', style: textTheme.bodyMedium)), Icon(Icons.calendar_today_rounded, size: 16, color: p.textTertiary)]),
                ),
              ),
              if (_triedSubmit && _agreementDate == null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Agreement date is required', style: textTheme.bodySmall?.copyWith(color: p.danger))),
              const SizedBox(height: 16),
              Text('Aadhaar last 4 digits *', style: textTheme.labelMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _aadhar,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: InputDecoration(
                  hintText: 'e.g. 1234',
                  counterText: '',
                  errorText: _triedSubmit && !RegExp(r'^[0-9]{4}$').hasMatch(_aadhar.text.trim()) ? 'Exactly 4 digits required' : null,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Add to directory'),
                ),
              ),
              const SizedBox(height: 8),
              Center(child: Text('Admin can manage all flats (occupied or vacant).', style: textTheme.bodySmall?.copyWith(fontSize: 11))),
            ],
          ),
        ),
      ),
    );
  }
}

// Mock sheet used only in widget tests (Supabase not initialized)
// Mirrors original simple form so directory_test.dart keeps passing
class _MockAddMemberSheet extends StatefulWidget {
  final List<ResidenceUnit> units;
  final void Function(ResidenceUnit unit, Resident resident) onAdd;
  const _MockAddMemberSheet({required this.units, required this.onAdd});
  @override
  State<_MockAddMemberSheet> createState() => _MockAddMemberSheetState();
}

class _MockAddMemberSheetState extends State<_MockAddMemberSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  ResidentRole _role = ResidentRole.owner;
  late ResidenceUnit _unit;
  bool _triedSubmit = false;
  @override
  void initState() {
    super.initState();
    _unit = widget.units.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _triedSubmit = true);
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final now = DateTime.now();
    final resident = Resident(
      fullName: name,
      role: _role,
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      memberSince: '${months[now.month - 1]} ${now.year}',
      isPrimary: _unit.residents.isEmpty || _role == ResidentRole.owner,
    );
    widget.onAdd(_unit, resident);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 8, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: p.hairline, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Text('Add member', style: textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('New entries appear in the register immediately.', style: textTheme.bodySmall),
            const SizedBox(height: 20),
            Text('Full name *', style: textTheme.labelMedium),
            const SizedBox(height: 8),
            TextField(controller: _name, autofocus: true, textCapitalization: TextCapitalization.words, decoration: InputDecoration(hintText: 'e.g. Aman Gupta', errorText: _triedSubmit && _name.text.trim().isEmpty ? 'Name is required' : null)),
            const SizedBox(height: 16),
            Text('Role', style: textTheme.labelMedium),
            const SizedBox(height: 8),
            SegmentedButton<ResidentRole>(
              segments: const [
                ButtonSegment(value: ResidentRole.owner, label: Text('Owner'), icon: Icon(Icons.home_rounded, size: 16)),
                ButtonSegment(value: ResidentRole.tenant, label: Text('Tenant'), icon: Icon(Icons.key_rounded, size: 16)),
                ButtonSegment(value: ResidentRole.family, label: Text('Family'), icon: Icon(Icons.family_restroom_rounded, size: 16)),
              ],
              selected: {_role},
              onSelectionChanged: (s) => setState(() => _role = s.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 16),
            Text('Flat', style: textTheme.labelMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<ResidenceUnit>(
              initialValue: _unit,
              isExpanded: true,
              decoration: const InputDecoration(hintText: 'Choose a flat'),
              items: [for (final unit in widget.units) DropdownMenuItem(value: unit, child: Text('${unit.number} · ${unit.bhk} BHK${unit.isOccupied ? '' : ' (vacant)'}', overflow: TextOverflow.ellipsis))],
              onChanged: (u) { if (u != null) setState(() => _unit = u); },
            ),
            const SizedBox(height: 16),
            Text('Phone', style: textTheme.labelMedium),
            const SizedBox(height: 8),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(hintText: 'Optional')),
            const SizedBox(height: 16),
            Text('Email', style: textTheme.labelMedium),
            const SizedBox(height: 8),
            TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(hintText: 'Optional')),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _submit, child: const Text('Add to directory'))),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit Details — admin can edit owner/tenant/family resident records
// ---------------------------------------------------------------------------

class _EditDetailsSheet extends StatefulWidget {
  final FlatInfo flat;
  final BlockInfo? block;
  final String societyId;
  final VoidCallback onSuccess;

  const _EditDetailsSheet({required this.flat, required this.block, required this.societyId, required this.onSuccess});

  @override
  State<_EditDetailsSheet> createState() => _EditDetailsSheetState();
}

class _EditDetailsSheetState extends State<_EditDetailsSheet> {
  bool _loading = true;
  String? _error;
  List<ResidentRecord> _residents = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('residents')
          .select()
          .eq('flat_id', widget.flat.id)
          .order('is_primary', ascending: false)
          .order('full_name', ascending: true);
      final list = ((rows as List?) ?? []).cast<Map<String, dynamic>>().map(ResidentRecord.fromMap).where((r) => r.id.isNotEmpty).toList();
      if (!mounted) return;
      setState(() {
        _residents = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 8, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: p.hairline, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: p.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.edit_note_rounded, color: p.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Edit details', style: textTheme.titleLarge),
                        const SizedBox(height: 2),
                        Text('${widget.block?.name ?? 'Block ?'} · ${widget.flat.flatNumber} · Floor ${widget.flat.floorNumber} · ${widget.flat.type}',
                            style: textTheme.bodySmall),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                ],
              ),
              const SizedBox(height: 8),
              Text('Admin only — update owner, tenant and family records for this flat.',
                  style: textTheme.bodySmall?.copyWith(fontSize: 11.5)),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: p.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: p.danger.withValues(alpha: 0.18))),
                  child: Row(children: [
                    Icon(Icons.error_outline_rounded, size: 18, color: p.danger),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: textTheme.bodySmall)),
                    IconButton(icon: Icon(Icons.refresh_rounded, size: 18, color: p.primary), onPressed: _fetch),
                  ]),
                )
              else if (_residents.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: p.cardMuted, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.hairline)),
                  child: Row(children: [
                    Icon(Icons.hourglass_empty_rounded, size: 18, color: p.textTertiary),
                    const SizedBox(width: 8),
                    Expanded(child: Text('No residents on record. Use Add member to create one.', style: textTheme.bodySmall)),
                  ]),
                )
              else
                for (int i = 0; i < _residents.length; i++) ...[
                  _ResidentEditCard(
                    record: _residents[i],
                    flat: widget.flat,
                    societyId: widget.societyId,
                    onSaved: () {
                      _fetch();
                      widget.onSuccess();
                    },
                    onDeleted: () {
                      _fetch();
                      widget.onSuccess();
                    },
                  ),
                  if (i != _residents.length - 1) const SizedBox(height: 12),
                ],
              const SizedBox(height: 16),
              Text('All fields are mandatory for active residents — email, phone, agreement holder, agreement date and Aadhaar last 4 must be filled.',
                  style: textTheme.bodySmall?.copyWith(fontSize: 11, color: p.textTertiary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResidentEditCard extends StatefulWidget {
  final ResidentRecord record;
  final FlatInfo flat;
  final String societyId;
  final VoidCallback onSaved;
  final VoidCallback onDeleted;

  const _ResidentEditCard({required this.record, required this.flat, required this.societyId, required this.onSaved, required this.onDeleted});

  @override
  State<_ResidentEditCard> createState() => _ResidentEditCardState();
}

class _ResidentEditCardState extends State<_ResidentEditCard> {
  late TextEditingController _name;
  late TextEditingController _email;
  late TextEditingController _phone;
  late TextEditingController _holder;
  late TextEditingController _aadhar;
  late ResidentRole _role;
  late bool _isPrimary;
  late String _status;
  DateTime? _agreementDate;
  bool _expanded = false;
  bool _tried = false;
  bool _saving = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.record.fullName);
    _email = TextEditingController(text: widget.record.email);
    _phone = TextEditingController(text: widget.record.phone ?? '');
    _holder = TextEditingController(text: widget.record.agreementHolderName ?? '');
    _aadhar = TextEditingController(text: widget.record.aadharLast4 ?? '');
    _role = switch (widget.record.residentType) {
      'tenant' => ResidentRole.tenant,
      'family' => ResidentRole.family,
      _ => ResidentRole.owner,
    };
    _isPrimary = widget.record.isPrimary;
    _status = widget.record.status;
    _agreementDate = widget.record.agreementDate;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _holder.dispose();
    _aadhar.dispose();
    super.dispose();
  }

  bool _isEmailValid(String v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: _agreementDate ?? now, firstDate: DateTime(2000), lastDate: DateTime(now.year + 5));
    if (picked != null) setState(() => _agreementDate = picked);
  }

  Future<void> _save() async {
    setState(() => _tried = true);
    final name = _name.text.trim();
    final email = _email.text.trim();
    final phone = _phone.text.trim();
    final holder = _holder.text.trim();
    final aadhar = _aadhar.text.trim();
    if (name.isEmpty) return;
    if (email.isEmpty || !_isEmailValid(email)) return;
    if (phone.isEmpty) return;
    if (holder.isEmpty) return;
    if (_agreementDate == null) return;
    if (!RegExp(r'^[0-9]{4}$').hasMatch(aadhar)) return;

    setState(() => _saving = true);
    try {
      final client = Supabase.instance.client;
      final payload = {
        'full_name': name,
        'email': email,
        'phone': phone,
        'resident_type': _role.name,
        'is_primary': _isPrimary,
        'agreement_holder_name': holder,
        'agreement_date': _agreementDate!.toIso8601String().split('T')[0],
        'aadhar_last4': aadhar,
        'status': _status,
      };
      await client.from('residents').update(payload).eq('id', widget.record.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name updated')));
      widget.onSaved();
      setState(() => _expanded = false);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      String friendly = msg;
      if (msg.contains('residents_mandatory_fields_check')) friendly = 'Fill all mandatory fields (phone, agreement, Aadhaar).';
      if (msg.contains('violates row-level security')) friendly = 'Permission denied — admin only.';
      if (msg.contains('aadhar_last4')) friendly = 'Aadhaar must be 4 digits.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly.length > 200 ? '${friendly.substring(0, 200)}…' : friendly)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove resident?'),
        content: Text('Remove ${widget.record.fullName} from ${widget.flat.flatNumber}? This can be undone by re-adding.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove'))],
      ),
    );
    if (confirm != true) return;
    setState(() => _deleting = true);
    try {
      final client = Supabase.instance.client;
      // Soft delete by marking moved_out, or hard delete — we do soft to keep history
      await client.from('residents').update({'status': 'moved_out'}).eq('id', widget.record.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${widget.record.fullName} marked as moved out')));
      widget.onDeleted();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  String _friendlyRole(ResidentRole r) => switch (r) { ResidentRole.owner => 'Owner', ResidentRole.tenant => 'Tenant', ResidentRole.family => 'Family' };

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.hairline)),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: p.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
                    child: Text(widget.record.fullName.isEmpty ? '?' : widget.record.fullName[0].toUpperCase(), style: textTheme.titleSmall?.copyWith(color: p.primary, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.record.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Row(children: [
                          RolePill(role: _role),
                          const SizedBox(width: 6),
                          Text(_friendlyRole(_role), style: textTheme.bodySmall?.copyWith(fontSize: 11)),
                          if (_isPrimary) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: p.mint, borderRadius: BorderRadius.circular(8)), child: Text('Primary', style: textTheme.labelSmall?.copyWith(fontSize: 9, color: p.mintOn)))],
                          const SizedBox(width: 6),
                          Text('· $_status', style: textTheme.bodySmall?.copyWith(fontSize: 11)),
                        ]),
                      ],
                    ),
                  ),
                  Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: p.textTertiary),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: p.hairline),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Full name *', style: textTheme.labelMedium),
                  const SizedBox(height: 6),
                  TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(hintText: 'e.g. Aman Gupta', errorText: _tried && _name.text.trim().isEmpty ? 'Required' : null, isDense: true)),
                  const SizedBox(height: 12),
                  Text('Email *', style: textTheme.labelMedium),
                  const SizedBox(height: 6),
                  TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(hintText: 'owner/tenant email', isDense: true, errorText: _tried && (_email.text.trim().isEmpty || !_isEmailValid(_email.text.trim())) ? 'Valid email required' : null)),
                  const SizedBox(height: 12),
                  Text('Phone *', style: textTheme.labelMedium),
                  const SizedBox(height: 6),
                  TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(hintText: '+91 98100…', isDense: true, errorText: _tried && _phone.text.trim().isEmpty ? 'Required' : null)),
                  const SizedBox(height: 12),
                  Text('Role *', style: textTheme.labelMedium),
                  const SizedBox(height: 6),
                  SegmentedButton<ResidentRole>(
                    segments: const [
                      ButtonSegment(value: ResidentRole.owner, label: Text('Owner'), icon: Icon(Icons.home_rounded, size: 14)),
                      ButtonSegment(value: ResidentRole.tenant, label: Text('Tenant'), icon: Icon(Icons.key_rounded, size: 14)),
                      ButtonSegment(value: ResidentRole.family, label: Text('Family'), icon: Icon(Icons.family_restroom_rounded, size: 14)),
                    ],
                    selected: {_role},
                    onSelectionChanged: (s) => setState(() => _role = s.first),
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Status', style: textTheme.labelMedium),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: _status,
                            isDense: true,
                            decoration: const InputDecoration(isDense: true),
                            items: const [DropdownMenuItem(value: 'active', child: Text('Active')), DropdownMenuItem(value: 'moved_out', child: Text('Moved out'))],
                            onChanged: (v) => setState(() => _status = v ?? 'active'),
                          ),
                        ]),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Aadhaar last 4 *', style: textTheme.labelMedium),
                          const SizedBox(height: 6),
                          TextField(controller: _aadhar, keyboardType: TextInputType.number, maxLength: 4, decoration: InputDecoration(hintText: '1234', counterText: '', isDense: true, errorText: _tried && !RegExp(r'^[0-9]{4}$').hasMatch(_aadhar.text.trim()) ? '4 digits' : null)),
                        ]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Agreement holder *', style: textTheme.labelMedium),
                  const SizedBox(height: 6),
                  TextField(controller: _holder, decoration: InputDecoration(hintText: 'e.g. Aman Gupta', isDense: true, errorText: _tried && _holder.text.trim().isEmpty ? 'Required' : null)),
                  const SizedBox(height: 12),
                  Text('Agreement date *', style: textTheme.labelMedium),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(color: p.cardMuted, borderRadius: BorderRadius.circular(12), border: Border.all(color: _tried && _agreementDate == null ? p.danger : p.hairline)),
                      child: Row(children: [Icon(Icons.event_outlined, size: 16, color: p.textTertiary), const SizedBox(width: 8), Expanded(child: Text(_agreementDate == null ? 'Select date' : '${_agreementDate!.day}/${_agreementDate!.month}/${_agreementDate!.year}', style: textTheme.bodySmall)), Icon(Icons.calendar_today_rounded, size: 14, color: p.textTertiary)]),
                    ),
                  ),
                  if (_tried && _agreementDate == null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Required', style: textTheme.bodySmall?.copyWith(color: p.danger, fontSize: 11))),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    value: _isPrimary,
                    onChanged: (v) => setState(() => _isPrimary = v ?? false),
                    title: Text('Primary contact', style: textTheme.labelMedium?.copyWith(fontSize: 12)),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _deleting ? null : _delete,
                          icon: _deleting ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.person_remove_outlined, size: 16),
                          label: const Text('Remove'),
                          style: OutlinedButton.styleFrom(foregroundColor: p.danger, side: BorderSide(color: p.danger.withValues(alpha: 0.3))),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _saving ? null : _save,
                          child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Mock edit details for widget tests — edits in-memory ResidenceUnit
class _MockEditDetailsSheet extends StatefulWidget {
  final ResidenceUnit unit;
  final void Function(ResidenceUnit updated) onSave;
  const _MockEditDetailsSheet({required this.unit, required this.onSave});
  @override
  State<_MockEditDetailsSheet> createState() => _MockEditDetailsSheetState();
}

class _MockEditDetailsSheetState extends State<_MockEditDetailsSheet> {
  late List<Resident> _residents;

  @override
  void initState() {
    super.initState();
    _residents = List.of(widget.unit.residents);
  }

  void _editResident(int index) {
    final r = _residents[index];
    final nameCtrl = TextEditingController(text: r.fullName);
    final phoneCtrl = TextEditingController(text: r.phone ?? '');
    final emailCtrl = TextEditingController(text: r.email ?? '');
    ResidentRole role = r.role;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('Edit ${r.fullName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full name')),
                const SizedBox(height: 8),
                TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email')),
                const SizedBox(height: 8),
                TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone')),
                const SizedBox(height: 12),
                SegmentedButton<ResidentRole>(
                  segments: const [
                    ButtonSegment(value: ResidentRole.owner, label: Text('Owner')),
                    ButtonSegment(value: ResidentRole.tenant, label: Text('Tenant')),
                    ButtonSegment(value: ResidentRole.family, label: Text('Family')),
                  ],
                  selected: {role},
                  onSelectionChanged: (s) => setDlg(() => role = s.first),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                setState(() {
                  _residents[index] = Resident(fullName: nameCtrl.text.trim().isEmpty ? r.fullName : nameCtrl.text.trim(), role: role, phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(), email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(), memberSince: r.memberSince, isPrimary: r.isPrimary);
                });
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 8, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: p.hairline, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('Edit details', style: textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Update owner, tenant and family records for ${widget.unit.number}. Changes stay in memory for this demo.',
                style: textTheme.bodySmall),
            const SizedBox(height: 16),
            if (_residents.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text('No residents to edit — use Add member first.', style: textTheme.bodySmall),
              )
            else
              for (int i = 0; i < _residents.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Surface(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    radius: 12,
                    child: Row(
                      children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_residents[i].fullName, style: textTheme.titleSmall), Text('${_residents[i].role.label} · ${_residents[i].email ?? 'no email'}', style: textTheme.bodySmall?.copyWith(fontSize: 11))])),
                        IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _editResident(i)),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final updated = ResidenceUnit(number: widget.unit.number, tower: widget.unit.tower, floor: widget.unit.floor, bhk: widget.unit.bhk, sqft: widget.unit.sqft, parking: widget.unit.parking, residents: _residents);
                  widget.onSave(updated);
                },
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


