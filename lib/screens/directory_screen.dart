import 'package:flutter/material.dart';

import '../data/resident_data.dart';
import '../models/society_models.dart';
import '../theme/app_theme.dart';
import '../widgets/home_widgets.dart';
import '../widgets/resident_widgets.dart';

enum _StatusFilter { all, owner, tenant, vacant }

extension _StatusLabel on _StatusFilter {
  String get label => switch (this) {
        _StatusFilter.all => 'All',
        _StatusFilter.owner => 'Owners',
        _StatusFilter.tenant => 'Tenants',
        _StatusFilter.vacant => 'Vacant',
      };
}

/// Resident & Flat Management — the society's unit register.
///
/// A complete, searchable record of residents, owners, tenants and flat
/// details, grouped by tower the way a physical register would be.
class DirectoryScreen extends StatefulWidget {
  final bool showBack;

  const DirectoryScreen({super.key, this.showBack = false});

  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  late final List<ResidenceUnit> _units;
  late final List<String> _towers;

  String _query = '';
  String? _tower;
  _StatusFilter _status = _StatusFilter.all;

  @override
  void initState() {
    super.initState();
    _units = List.of(sampleUnits);
    _towers = _units.map((u) => u.tower).toSet().toList();
  }

  bool get _hasFilters => _query.isNotEmpty || _tower != null || _status != _StatusFilter.all;

  List<ResidenceUnit> get _filtered {
    final q = _query.trim().toLowerCase();
    return _units.where((unit) {
      if (_tower != null && unit.tower != _tower) return false;
      final vacants = !unit.isOccupied;
      final hasOwner = unit.residents.any((r) => r.role == ResidentRole.owner);
      final hasTenant = unit.residents.any((r) => r.role == ResidentRole.tenant);
      final matchesStatus = switch (_status) {
        _StatusFilter.all => true,
        _StatusFilter.vacant => vacants,
        _StatusFilter.owner => hasOwner,
        _StatusFilter.tenant => hasTenant,
      };
      if (!matchesStatus) return false;
      if (q.isEmpty) return true;
      if (unit.number.toLowerCase().contains(q)) return true;
      return unit.residents.any(
        (r) => r.fullName.toLowerCase().contains(q),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final occupied = _units.where((u) => u.isOccupied).length;
    final residents = _units.expand((u) => u.residents).length;
    final owners = _units.expand((u) => u.residents)
        .where((r) => r.role == ResidentRole.owner)
        .length;
    final tenants = _units.expand((u) => u.residents)
        .where((r) => r.role == ResidentRole.tenant)
        .length;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          edgeOffset: 90,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              _buildHeader(context),
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
              if (filtered.isEmpty)
                _buildNoResults(context)
              else
                for (final tower in _towers)
                  ..._buildTowerSection(context, tower, filtered),
              const SizedBox(height: 26),
              SectionHeader(
                title: 'Help contacts',
                actionLabel: null,
              ),
              const SizedBox(height: 12),
              _buildQuickContacts(context),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Header -----------------------------------------------------------

  Widget _buildHeader(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showBack) ...[
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded),
            style: IconButton.styleFrom(
              backgroundColor: p.card,
              side: BorderSide(color: p.hairline),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SUNRISE HEIGHTS',
                style: textTheme.labelSmall?.copyWith(
                  color: p.primary,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Residents & Flats',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Complete register of units and their occupants',
                style: textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _AddMemberButton(onPressed: () => _openAddMember(context)),
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
        _FilterChip(
          label: 'All',
          selected: _tower == null,
          onTap: () => setState(() => _tower = null),
        ),
        for (final tower in _towers)
          _FilterChip(
            label: 'Tower $tower',
            selected: _tower == tower,
            onTap: () => setState(() => _tower = tower),
          ),
      ],
    );
  }

  Widget _buildStatusFilter(BuildContext context) {
    return _buildFilterRow(
      context,
      label: 'Residents',
      chips: [
        for (final status in _StatusFilter.values)
          _FilterChip(
            label: status.label,
            selected: _status == status,
            onTap: () => setState(() => _status = status),
          ),
      ],
    );
  }

  Widget _buildFilterRow(
    BuildContext context, {
    required String label,
    required List<Widget> chips,
  }) {
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

  List<Widget> _buildTowerSection(
    BuildContext context,
    String tower,
    List<ResidenceUnit> filtered,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final units = filtered.where((u) => u.tower == tower).toList();
    if (units.isEmpty) return const [];

    final residentCount =
        units.expand((u) => u.residents).length;
    final occupied = units.where((u) => u.isOccupied).length;

    final header = Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 12),
      child: Row(
        children: [
          Text('Tower $tower', style: textTheme.titleMedium),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              '$units.length flats · $occupied occupied'
              '${residentCount > 0 ? ' · $residentCount residents' : ''}',
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
          child: _FlatCard(
            unit: unit,
            onTap: () => _openFlatDetails(context, unit),
            onCall: _callResident,
          ),
        ),
    ];
  }

  Widget _buildNoResults(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
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
            decoration: BoxDecoration(
              color: p.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.search_off_rounded, size: 28, color: p.primary),
          ),
          const SizedBox(height: 16),
          Text('Nothing matches this search', style: textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            'Try a different name or flat number, or widen your filters.',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  // ---- Quick contacts (kept from the previous directory) -----------------

  Widget _buildQuickContacts(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickContact(
            icon: Icons.support_agent_rounded,
            title: 'Security desk',
            subtitle: 'Ground floor lobby',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickContact(
            icon: Icons.local_hospital_rounded,
            title: 'EMI / Fire',
            subtitle: '102 · 108',
          ),
        ),
      ],
    );
  }

  // ---- Actions -----------------------------------------------------------

  Future<void> _refresh() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Register is up to date · ${_units.length} flats, '
          '${_units.expand((u) => u.residents).length} residents',
        ),
      ),
    );
  }

  void _callResident(Resident resident) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Calling ${resident.fullName}…')),
    );
  }

  void _openFlatDetails(BuildContext context, ResidenceUnit unit) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      builder: (sheetContext) => _FlatDetailSheet(
        unit: unit,
        onCall: _callResident,
        onEdit: () {
          Navigator.pop(sheetContext);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Editing is coming with the register backend.'),
            ),
          );
        },
      ),
    );
  }

  void _openAddMember(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      builder: (sheetContext) => _AddMemberSheet(
        units: _units,
        onAdd: (unit, resident) {
          setState(() {
            final flat = _units.firstWhere((u) => u.number == unit.number);
            flat.residents.add(resident);
          });
          Navigator.pop(sheetContext);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${resident.fullName} added to ${unit.number} · '
                '${resident.memberSince}',
              ),
            ),
          );
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
          decoration: BoxDecoration(
            color: p.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.primary.withValues(alpha: 0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_add_rounded, size: 18, color: p.primary),
              const SizedBox(width: 6),
              Text(
                'Add member',
                style: textTheme.labelMedium?.copyWith(
                  color: p.primary,
                  fontSize: 13,
                ),
              ),
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

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: selected
          ? p.primary.withValues(alpha: 0.16)
          : p.cardMuted,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? p.primary : p.hairline,
            ),
          ),
          child: Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: selected ? p.primary : p.textSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
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

  const _OccupancyCard({
    required this.totalUnits,
    required this.occupied,
    required this.residents,
    required this.owners,
    required this.tenants,
  });

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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Overall occupancy', style: textTheme.titleSmall),
                    const SizedBox(height: 3),
                    Text(
                      '$occupied of $totalUnits flats occupied',
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                '$percent%',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: p.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          OccupancyBar(fraction: fraction),
          const SizedBox(height: 16),
          Divider(color: p.hairline),
          const SizedBox(height: 14),
          Row(
            children: [
              _Metric(value: '$totalUnits', label: 'Units'),
              _divider(p),
              _Metric(value: '$occupied', label: 'Occupied'),
              _divider(p),
              _Metric(value: '$residents', label: 'Residents'),
              _divider(p),
              _Metric(value: '$owners', label: 'Owners'),
              _divider(p),
              _Metric(value: '$tenants', label: 'Tenants'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _divider(AppPaletteData p) {
    return Container(width: 1, height: 26, color: p.hairline);
  }
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;

  const _Metric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              fontSize: 9.5,
              letterSpacing: 0.1,
              color: p.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FlatCard extends StatelessWidget {
  final ResidenceUnit unit;
  final VoidCallback onTap;
  final void Function(Resident resident) onCall;

  const _FlatCard({
    required this.unit,
    required this.onTap,
    required this.onCall,
  });

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
              for (final resident in unit.residents)
                _ResidentRow(
                  resident: resident,
                  onCall: () => onCall(resident),
                  dense: true,
                ),
            ] else
              _vacantRow(context, p, textTheme),
          ],
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    AppPaletteData p,
    TextTheme textTheme,
  ) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: p.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.villa_outlined, size: 20, color: p.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                unit.number,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Floor ${unit.floor} · ${unit.bhk} BHK · ${unit.sqft} sq ft',
                style: textTheme.bodySmall?.copyWith(fontSize: 11.5),
              ),
            ],
          ),
        ),
        if (unit.isOccupied)
          Text(
            '${unit.residents.length} '
            '${unit.residents.length == 1 ? 'resident' : 'residents'}',
            style: textTheme.labelMedium?.copyWith(
              color: p.textSecondary,
              fontSize: 11,
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: p.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Vacant',
              style: textTheme.labelSmall?.copyWith(
                color: p.warning,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right_rounded, size: 20, color: p.textTertiary),
      ],
    );
  }

  Widget _vacantRow(BuildContext context, AppPaletteData p, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(Icons.hourglass_empty_rounded,
              size: 18, color: p.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Open for allotment — no occupants on record',
              style: textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared occupant row used inside flat cards and the detail sheet.
class _ResidentRow extends StatelessWidget {
  final Resident resident;
  final VoidCallback onCall;
  final bool dense;

  const _ResidentRow({
    required this.resident,
    required this.onCall,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    final subtitle = [
      if (resident.relation != null) resident.relation!,
      if (resident.isPrimary) 'Primary contact',
    ].join(' · ');

    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 6 : 10),
      child: Row(
        children: [
          ResidentAvatar(initials: resident.initials, size: dense ? 34 : 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        resident.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    RolePill(role: resident.role),
                  ],
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: textTheme.bodySmall?.copyWith(fontSize: 11.5)),
                ],
              ],
            ),
          ),
          if (resident.vehicle != null) ...[
            Icon(Icons.directions_car_filled_rounded,
                size: 16, color: p.textTertiary),
            const SizedBox(width: 10),
          ],
          if (resident.phone != null)
            Container(
              width: dense ? 32 : 36,
              height: dense ? 32 : 36,
              decoration: BoxDecoration(
                color: p.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(dense ? 10 : 12),
              ),
              child: IconButton(
                onPressed: onCall,
                padding: EdgeInsets.zero,
                iconSize: 16,
                color: p.primary,
                icon: const Icon(Icons.call_rounded),
              ),
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

  const _QuickContact({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

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
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: p.secondary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: p.secondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
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

  const _FlatDetailSheet({
    required this.unit,
    required this.onCall,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    final vehicles = unit.residents
        .where((r) => r.vehicle != null)
        .toList();

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
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
            const SizedBox(height: 18),
            _sheetHeader(context, p, textTheme),
            const SizedBox(height: 6),
            _kicker(context, 'OCCUPANTS'),
            const SizedBox(height: 4),
            if (unit.isOccupied)
              for (final resident in unit.residents) ...[
                _ResidentRow(resident: resident, onCall: () => onCall(resident)),
                Divider(color: p.hairline),
              ]
            else
              _sheetVacant(context, p, textTheme),
            const SizedBox(height: 14),
            _kicker(context, 'FLAT DETAILS'),
            const SizedBox(height: 10),
            _infoGrid(context, p, textTheme),
            if (vehicles.isNotEmpty) ...[
              const SizedBox(height: 22),
              _kicker(context, 'REGISTERED VEHICLES'),
              const SizedBox(height: 10),
              Surface(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                radius: 16,
                child: Column(
                  children: [
                    for (final resident in vehicles)
                      _vehicleRow(context, p, textTheme, resident),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onEdit,
                    child: const Text('Edit flat'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: unit.primaryContact == null
                        ? null
                        : () => onCall(unit.primaryContact!),
                    icon: const Icon(Icons.call_rounded, size: 18),
                    label: Text(
                      unit.primaryContact == null
                          ? 'No contact'
                          : 'Call ${unit.primaryContact!.firstName}',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetHeader(
    BuildContext context,
    AppPaletteData p,
    TextTheme textTheme,
  ) {
    return Row(
      children: [
        ResidentAvatar(initials: unit.number.replaceAll('-', ''), size: 52),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(unit.number, style: textTheme.titleLarge),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (unit.isOccupied ? p.success : p.warning)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      unit.isOccupied ? 'Occupied' : 'Vacant',
                      style: textTheme.labelSmall?.copyWith(
                        color: unit.isOccupied ? p.success : p.warning,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Tower ${unit.tower} · Floor ${unit.floor} · '
                '${unit.bhk} BHK · ${unit.sqft} sq ft',
                style: textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kicker(BuildContext context, String text) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: p.primary,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w800,
          ),
    );
  }

  Widget _infoGrid(
    BuildContext context,
    AppPaletteData p,
    TextTheme textTheme,
  ) {
    final parking = unit.parking ?? 'Not allocated';

    return Row(
      children: [
        Expanded(
          child: _InfoTile(
            icon: Icons.stairs_rounded,
            iconColor: p.secondary,
            label: 'Floor',
            value: '${unit.floor}',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _InfoTile(
            icon: Icons.king_bed_outlined,
            iconColor: p.accent,
            label: 'Type',
            value: '${unit.bhk} BHK',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _InfoTile(
            icon: Icons.straighten_rounded,
            iconColor: p.primary,
            label: 'Area',
            value: '${unit.sqft} sq ft',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _InfoTile(
            icon: Icons.local_parking_rounded,
            iconColor: p.warning,
            label: 'Parking',
            value: parking,
          ),
        ),
      ],
    );
  }

  Widget _sheetVacant(
    BuildContext context,
    AppPaletteData p,
    TextTheme textTheme,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.warning.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.hourglass_empty_rounded, size: 20, color: p.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No residents on record for this unit. It is available for '
              'allotment by the committee.',
              style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vehicleRow(
    BuildContext context,
    AppPaletteData p,
    TextTheme textTheme,
    Resident resident,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: p.secondary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.directions_car_filled_rounded,
                size: 18, color: p.secondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(resident.vehicle!, style: textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  '${resident.fullName} · ${resident.role.label}',
                  style: textTheme.bodySmall?.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: p.cardMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelMedium?.copyWith(
              color: p.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              fontSize: 9.5,
              letterSpacing: 0.2,
              color: p.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddMemberSheet extends StatefulWidget {
  final List<ResidenceUnit> units;
  final void Function(ResidenceUnit unit, Resident resident) onAdd;

  const _AddMemberSheet({required this.units, required this.onAdd});

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
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

    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
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
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
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
              const SizedBox(height: 20),
              Text('Add member', style: textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'New entries appear in the register immediately.',
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              Text('Full name *', style: textTheme.labelMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'e.g. Aman Gupta',
                  errorText: _triedSubmit && _name.text.trim().isEmpty
                      ? 'Name is required'
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              Text('Role', style: textTheme.labelMedium),
              const SizedBox(height: 8),
              SegmentedButton<ResidentRole>(
                segments: const [
                  ButtonSegment(
                    value: ResidentRole.owner,
                    label: Text('Owner'),
                    icon: Icon(Icons.home_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: ResidentRole.tenant,
                    label: Text('Tenant'),
                    icon: Icon(Icons.key_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: ResidentRole.family,
                    label: Text('Family'),
                    icon: Icon(Icons.family_restroom_rounded, size: 16),
                  ),
                ],
                selected: {_role},
                onSelectionChanged: (selection) =>
                    setState(() => _role = selection.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 16),
              Text('Flat', style: textTheme.labelMedium),
              const SizedBox(height: 8),
              DropdownButtonFormField<ResidenceUnit>(
                initialValue: _unit,
                isExpanded: true,
                decoration: InputDecoration(hintText: 'Choose a flat'),
                items: [
                  for (final unit in widget.units)
                    DropdownMenuItem(
                      value: unit,
                      child: Text(
                        '${unit.number} · ${unit.bhk} BHK'
                        '${unit.isOccupied ? '' : ' (vacant)'}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (unit) {
                  if (unit != null) setState(() => _unit = unit);
                },
              ),
              const SizedBox(height: 16),
              Text('Phone', style: textTheme.labelMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(hintText: 'Optional'),
              ),
              const SizedBox(height: 16),
              Text('Email', style: textTheme.labelMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(hintText: 'Optional'),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submit,
                  child: const Text('Add to directory'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}