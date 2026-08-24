import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/resident_data.dart';
import '../models/society_models.dart';
import '../theme/app_theme.dart';
import '../widgets/flat_edit_bottom_sheet.dart';

/// Screen for managing society architecture: Blocks/Towers -> Floors -> Flats.
/// Allows viewing, filtering, editing flat parameters, and adding new units.
class FlatsManagementScreen extends StatefulWidget {
  const FlatsManagementScreen({super.key});

  @override
  State<FlatsManagementScreen> createState() => _FlatsManagementScreenState();
}

class _FlatsManagementScreenState extends State<FlatsManagementScreen> {
  List<ResidenceUnit> _allFlats = [];
  List<String> _blocks = [];

  String _selectedBlock = 'All';
  int? _selectedFloor;
  String _statusFilter = 'All'; // 'All', 'Occupied', 'Vacant'
  String _searchQuery = '';

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUnits();
  }

  void _loadUnits() {
    // Load from sampleUnits or database
    _allFlats = List.of(sampleUnits);
    final blockSet = _allFlats.map((u) => u.tower).toSet().toList()..sort();
    if (!blockSet.contains('A')) blockSet.insert(0, 'A');
    if (!blockSet.contains('B')) blockSet.add('B');
    if (!blockSet.contains('C')) blockSet.add('C');
    _blocks = blockSet;
    setState(() => _isLoading = false);
  }

  List<ResidenceUnit> get _filteredFlats {
    return _allFlats.where((flat) {
      // Block filter
      if (_selectedBlock != 'All' && flat.tower != _selectedBlock) {
        return false;
      }
      // Floor filter
      if (_selectedFloor != null && flat.floor != _selectedFloor) {
        return false;
      }
      // Status filter
      if (_statusFilter == 'Occupied' && !flat.isOccupied) return false;
      if (_statusFilter == 'Vacant' && flat.isOccupied) return false;

      // Search query
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchNumber = flat.number.toLowerCase().contains(q);
        final matchTower = flat.tower.toLowerCase().contains(q);
        final matchBhk = '${flat.bhk}bhk'.contains(q);
        final matchResident = flat.residents.any((r) => r.fullName.toLowerCase().contains(q));
        return matchNumber || matchTower || matchBhk || matchResident;
      }
      return true;
    }).toList();
  }

  Map<int, List<ResidenceUnit>> get _flatsByFloor {
    final map = <int, List<ResidenceUnit>>{};
    for (final flat in _filteredFlats) {
      map.putIfAbsent(flat.floor, () => []).add(flat);
    }
    // Sort flats within floor by number
    for (final floor in map.keys) {
      map[floor]!.sort((a, b) => a.number.compareTo(b.number));
    }
    return map;
  }

  List<int> get _availableFloors {
    final list = _allFlats
        .where((f) => _selectedBlock == 'All' || f.tower == _selectedBlock)
        .map((f) => f.floor)
        .toSet()
        .toList()
      ..sort();
    return list;
  }

  // ── Metrics ─────────────────────────────────────────────────────────────

  int get _totalCount => _filteredFlats.length;
  int get _occupiedCount => _filteredFlats.where((f) => f.isOccupied).length;
  int get _vacantCount => _totalCount - _occupiedCount;
  double get _occupancyRate => _totalCount == 0 ? 0 : (_occupiedCount / _totalCount) * 100;

  // ── Actions ─────────────────────────────────────────────────────────────

  void _onEditFlat(ResidenceUnit unit) {
    FlatEditBottomSheet.show(
      context,
      unit: unit,
      availableBlocks: _blocks,
      onSave: (updated) {
        setState(() {
          final index = _allFlats.indexWhere((u) => u.number == unit.number);
          if (index != -1) {
            _allFlats[index] = updated;
          }
        });
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Flat ${updated.number} details updated'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      onDelete: (toDelete) {
        setState(() {
          _allFlats.removeWhere((u) => u.number == toDelete.number);
        });
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Flat ${toDelete.number} removed'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }

  void _onAddNewFlat() {
    FlatEditBottomSheet.show(
      context,
      availableBlocks: _blocks,
      initialBlock: _selectedBlock == 'All' ? _blocks.first : _selectedBlock,
      onSave: (newUnit) {
        setState(() {
          _allFlats.add(newUnit);
          if (!_blocks.contains(newUnit.tower)) {
            _blocks.add(newUnit.tower);
            _blocks.sort();
          }
        });
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Flat ${newUnit.number} registered successfully'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }

  void _onAddNewBlock() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Building / Tower Block'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. Tower C or Wing 3',
            labelText: 'Block Name',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                setState(() {
                  if (!_blocks.contains(name)) {
                    _blocks.add(name);
                    _blocks.sort();
                  }
                  _selectedBlock = name;
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add Block'),
          ),
        ],
      ),
    );
  }

  // ── Layout ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        bottom: false,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: [
                  // App Bar / Header
                  SliverToBoxAdapter(child: _buildHeader(context, p, textTheme)),

                  // Blocks Horizontal Rail
                  SliverToBoxAdapter(child: _buildBlockRail(p, textTheme)),

                  // Summary Statistics
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    sliver: SliverToBoxAdapter(child: _buildStatsCard(p, textTheme)),
                  ),

                  // Search & Filter Rail
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    sliver: SliverToBoxAdapter(child: _buildFilterRail(p, textTheme)),
                  ),

                  // Flat List by Floor
                  if (_flatsByFloor.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.domain_disabled_rounded, size: 48, color: p.textTertiary),
                            const SizedBox(height: 12),
                            Text('No flats found', style: textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text(
                              'Try adjusting your search or floor filters',
                              style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._buildFloorSections(p, textTheme),

                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _onAddNewFlat,
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Flat', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppPaletteData p, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded),
            style: IconButton.styleFrom(
              backgroundColor: p.card,
              side: BorderSide(color: p.hairline),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Blocks & Flats',
                  style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  'Society structure and unit register',
                  style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockRail(AppPaletteData p, TextTheme textTheme) {
    final blocksList = ['All', ..._blocks];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: blocksList.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8), // ignore: unnecessary_underscores
        itemBuilder: (context, idx) {
          if (idx == blocksList.length) {
            return OutlinedButton.icon(
              onPressed: _onAddNewBlock,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add Block'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                side: BorderSide(color: p.hairline),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
            );
          }

          final blockName = blocksList[idx];
          final isSelected = _selectedBlock == blockName;
          final label = blockName == 'All'
              ? 'All Blocks'
              : (blockName.startsWith('Tower') || blockName.startsWith('Block')
                  ? blockName
                  : 'Block $blockName');

          return ChoiceChip(
            label: Text(label),
            selected: isSelected,
            selectedColor: p.primary,
            backgroundColor: p.card,
            side: BorderSide(color: isSelected ? p.primary : p.hairline),
            labelStyle: TextStyle(
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? p.onPrimary : p.textPrimary,
            ),
            onSelected: (val) {
              if (val) {
                setState(() {
                  _selectedBlock = blockName;
                  _selectedFloor = null;
                });
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildStatsCard(AppPaletteData p, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.hairline),
        boxShadow: [
          BoxShadow(
            color: p.shadow.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatColumn(
            label: 'Total Flats',
            value: '$_totalCount',
            color: p.textPrimary,
          ),
          Container(width: 1, height: 36, color: p.hairline),
          _StatColumn(
            label: 'Occupied',
            value: '$_occupiedCount',
            color: p.success,
            subtitle: '${_occupancyRate.toStringAsFixed(0)}%',
          ),
          Container(width: 1, height: 36, color: p.hairline),
          _StatColumn(
            label: 'Vacant',
            value: '$_vacantCount',
            color: p.warning,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRail(AppPaletteData p, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search bar
        TextField(
          onChanged: (val) => setState(() => _searchQuery = val.trim()),
          decoration: InputDecoration(
            hintText: 'Search by flat (e.g. A-101, 3BHK, resident)...',
            prefixIcon: Icon(Icons.search_rounded, size: 18, color: p.textSecondary),
            filled: true,
            fillColor: p.card,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: p.hairline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: p.hairline),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Floor and status filters
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // Status segment
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'All', label: Text('All')),
                  ButtonSegment(value: 'Occupied', label: Text('Occupied')),
                  ButtonSegment(value: 'Vacant', label: Text('Vacant')),
                ],
                selected: {_statusFilter},
                onSelectionChanged: (val) => setState(() => _statusFilter = val.first),
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 12),

              // Floor Filter Dropdown / chips
              if (_availableFloors.isNotEmpty)
                DropdownButtonHideUnderline(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: p.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: p.hairline),
                    ),
                    child: DropdownButton<int?>(
                      value: _selectedFloor,
                      hint: Text('All Floors', style: TextStyle(fontSize: 13, color: p.textPrimary)),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                      isDense: true,
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('All Floors', style: TextStyle(fontSize: 13)),
                        ),
                        ..._availableFloors.map(
                          (floor) => DropdownMenuItem<int?>(
                            value: floor,
                            child: Text('Floor $floor', style: const TextStyle(fontSize: 13)),
                          ),
                        ),
                      ],
                      onChanged: (val) => setState(() => _selectedFloor = val),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildFloorSections(AppPaletteData p, TextTheme textTheme) {
    final sortedFloors = _flatsByFloor.keys.toList()..sort();
    final widgets = <Widget>[];

    for (final floor in sortedFloors) {
      final flats = _flatsByFloor[floor]!;
      widgets.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Icon(Icons.layers_outlined, size: 18, color: p.textSecondary),
                const SizedBox(width: 8),
                Text(
                  'Floor $floor',
                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: p.cardMuted,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: p.hairline),
                  ),
                  child: Text(
                    '${flats.length} units',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      widgets.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 400,
              mainAxisExtent: 140,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final flat = flats[index];
                return _FlatCard(
                  flat: flat,
                  onTap: () => _onEditFlat(flat),
                );
              },
              childCount: flats.length,
            ),
          ),
        ),
      );
    }

    return widgets;
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String? subtitle;

  const _StatColumn({
    required this.label,
    required this.value,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(width: 4),
              Text(
                subtitle!,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(color: p.textSecondary),
        ),
      ],
    );
  }
}

class _FlatCard extends StatelessWidget {
  final ResidenceUnit flat;
  final VoidCallback onTap;

  const _FlatCard({required this.flat, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    final primaryContact = flat.primaryContact;
    final isOccupied = flat.isOccupied;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.hairline),
            boxShadow: [
              BoxShadow(
                color: p.shadow.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Header: Flat Number + Status Badge + Edit Icon
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: p.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.apartment_rounded, size: 16, color: p.primary),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        flat.number,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isOccupied
                              ? p.success.withValues(alpha: 0.12)
                              : p.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isOccupied ? 'Occupied' : 'Vacant',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isOccupied ? p.success : p.warning,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.edit_outlined, size: 16, color: p.textTertiary),
                    ],
                  ),
                ],
              ),

              // Specs row: BHK, Sqft, Parking
              Row(
                children: [
                  _Badge(label: flat.typeLabel, icon: Icons.bed_outlined),
                  const SizedBox(width: 6),
                  _Badge(label: '${flat.sqft} sqft', icon: Icons.straighten_outlined),
                  if (flat.parking != null) ...[
                    const SizedBox(width: 6),
                    _Badge(label: flat.parking!, icon: Icons.local_parking_rounded),
                  ],
                ],
              ),

              // Resident info or vacant prompt
              if (isOccupied && primaryContact != null)
                Row(
                  children: [
                    CircleAvatar(
                      radius: 9,
                      backgroundColor: p.primary.withValues(alpha: 0.15),
                      child: Text(
                        primaryContact.initials,
                        style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: p.primary),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${primaryContact.fullName} (${primaryContact.role.name.toUpperCase()})',
                        style: textTheme.bodySmall?.copyWith(fontSize: 11.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  'No occupants registered',
                  style: textTheme.labelSmall?.copyWith(color: p.textTertiary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final IconData icon;

  const _Badge({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: p.cardMuted,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: p.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: p.textSecondary),
          ),
        ],
      ),
    );
  }
}
