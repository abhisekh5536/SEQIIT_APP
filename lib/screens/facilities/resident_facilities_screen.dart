import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/facility_models.dart';
import '../../services/facilities_service.dart';
import '../../services/notifications_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/skeleton_loader.dart';
import 'facility_detail_screen.dart';
import 'widgets/facility_widgets.dart';

/// Resident: the society's facilities as a photo grid.
///
/// Facilities under maintenance or closed stay in the grid with a badge —
/// a facility that silently vanishes reads as "removed", not "back soon".
class ResidentFacilitiesScreen extends StatefulWidget {
  final bool showBack;

  const ResidentFacilitiesScreen({super.key, this.showBack = true});

  @override
  State<ResidentFacilitiesScreen> createState() =>
      _ResidentFacilitiesScreenState();
}

class _ResidentFacilitiesScreenState extends State<ResidentFacilitiesScreen> {
  List<FacilityRecord> _facilities = [];
  List<FacilityCategory> _categories = [];
  String? _categoryId;
  bool _loading = true;
  bool _moduleEnabled = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    NotificationsService.instance.markModuleAsRead('facility');
    FacilitiesService.instance.startLive();
    FacilitiesService.instance.addListener(_onLive);
    _load();
  }

  @override
  void dispose() {
    FacilitiesService.instance.removeListener(_onLive);
    FacilitiesService.instance.stopLive();
    super.dispose();
  }

  void _onLive() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = _facilities.isEmpty;
        _error = null;
      });
    }
    final service = FacilitiesService.instance;
    try {
      final results = await Future.wait([
        service.isModuleEnabled(),
        service.fetchFacilities(),
        service.fetchCategories(),
      ]);
      if (!mounted) return;
      setState(() {
        _moduleEnabled = results[0] as bool;
        _facilities = results[1] as List<FacilityRecord>;
        _categories = results[2] as List<FacilityCategory>;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = 'Could not load facilities.';
      });
    }
  }

  /// Only categories that have something in them are worth a chip.
  List<FacilityCategory> get _usedCategories {
    final used = _facilities.map((f) => f.categoryId).toSet();
    return _categories.where((c) => used.contains(c.id)).toList();
  }

  List<FacilityRecord> get _visible => _categoryId == null
      ? _facilities
      : _facilities.where((f) => f.categoryId == _categoryId).toList();

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    final openCount =
        _facilities.where((f) => f.status.isAvailable).length;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
                  child: Row(
                    children: [
                      if (widget.showBack)
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_rounded),
                        )
                      else
                        const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Facilities',
                                style: textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                            if (!_loading && _moduleEnabled && _facilities.isNotEmpty)
                              Text(
                                '$openCount of ${_facilities.length} open now',
                                style: textTheme.bodySmall
                                    ?.copyWith(color: p.textSecondary),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_loading)
                const SliverToBoxAdapter(child: _GridSkeleton())
              else if (!_moduleEnabled)
                _message(
                  p,
                  icon: Icons.toggle_off_outlined,
                  title: 'Facilities are turned off',
                  body: 'Your society has not enabled this section yet.',
                )
              else if (_error != null)
                _message(
                  p,
                  icon: Icons.cloud_off_rounded,
                  title: _error!,
                  body: 'Pull down to try again.',
                )
              else if (_facilities.isEmpty)
                _message(
                  p,
                  icon: Icons.event_seat_outlined,
                  title: 'No facilities listed yet',
                  body: 'The society office will add the clubhouse, gym, pool '
                      'and more here.',
                )
              else ...[
                if (_usedCategories.length > 1)
                  SliverToBoxAdapter(
                    child: FacilityCategoryChips(
                      categories: _usedCategories,
                      selectedId: _categoryId,
                      onSelected: (id) {
                        HapticFeedback.selectionClick();
                        setState(() => _categoryId = id);
                      },
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.78,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => FacilityGridCard(
                        facility: _visible[i],
                        onTap: () => _open(_visible[i]),
                      ),
                      childCount: _visible.length,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _open(FacilityRecord f) {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FacilityDetailScreen(facilityId: f.id, initial: f),
      ),
    );
  }

  Widget _message(
    AppPaletteData p, {
    required IconData icon,
    required String title,
    required String body,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: p.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: p.textTertiary),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700, color: p.textSecondary)),
            const SizedBox(height: 4),
            Text(body,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(color: p.textTertiary)),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}

/// Photo card for the resident grid.
class FacilityGridCard extends StatelessWidget {
  final FacilityRecord facility;
  final VoidCallback onTap;

  const FacilityGridCard({
    super.key,
    required this.facility,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    final f = facility;

    return Surface(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'facility-cover-${f.id}',
                    child: FacilityImageView(
                      url: f.coverUrl,
                      fallbackIcon: f.fallbackIcon,
                      dimmed: !f.status.isAvailable,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: FacilityStatusBadge(
                      status: f.status,
                      compact: true,
                      onImage: true,
                    ),
                  ),
                  if (f.images.length > 1)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.photo_library_outlined,
                                size: 12, color: Colors.white),
                            const SizedBox(width: 3),
                            Text('${f.images.length}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  f.status.isAvailable
                      ? (f.operatingHours ?? f.categoryName ?? 'Open')
                      : (f.statusNote ?? f.status.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    fontSize: 11.5,
                    color: f.status.isAvailable
                        ? p.textSecondary
                        : f.status.color(p),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.78,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: List.generate(
            4,
            (_) => const SkeletonBox(borderRadius: 20),
          ),
        ),
      ),
    );
  }
}
