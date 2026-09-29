import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/facility_models.dart';
import '../../services/app_session.dart';
import '../../services/facilities_service.dart';
import '../../theme/app_theme.dart';
import 'facility_form_screen.dart';
import 'widgets/facility_widgets.dart';

/// Full view of one facility: gallery, status, hours, rules.
///
/// The "Book Now" bar is deliberately present but disabled — it is where
/// the future Facility Booking module attaches, so this page will not need
/// a redesign when booking arrives.
class FacilityDetailScreen extends StatefulWidget {
  final String facilityId;

  /// Shown immediately while the fresh copy loads.
  final FacilityRecord? initial;

  const FacilityDetailScreen({
    super.key,
    required this.facilityId,
    this.initial,
  });

  @override
  State<FacilityDetailScreen> createState() => _FacilityDetailScreenState();
}

class _FacilityDetailScreenState extends State<FacilityDetailScreen> {
  late FacilityRecord? _facility = widget.initial;
  bool _loading = true;
  bool _missing = false;
  int _page = 0;
  final _pageController = PageController();

  @override
  void initState() {
    super.initState();
    FacilitiesService.instance.startLive();
    FacilitiesService.instance.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    FacilitiesService.instance.removeListener(_load);
    FacilitiesService.instance.stopLive();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final f = await FacilitiesService.instance.fetchFacility(widget.facilityId);
      if (!mounted) return;
      setState(() {
        _facility = f;
        _missing = f == null;
        _loading = false;
        if (f != null && _page >= f.images.length) _page = 0;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final f = _facility;

    if (f == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : _missing
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'This facility is no longer available.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.textSecondary),
                      ),
                    )
                  : const Text('Could not load facility'),
        ),
      );
    }

    final isAdmin = AppSession.instance.isAdmin;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildGallery(context, p, f, isAdmin),
          SliverToBoxAdapter(child: _buildBody(context, p, f)),
        ],
      ),
      bottomNavigationBar: _buildBookBar(context, p, f),
    );
  }

  Widget _buildGallery(
    BuildContext context,
    AppPaletteData p,
    FacilityRecord f,
    bool isAdmin,
  ) {
    final urls = f.images.map((i) => i.imageUrl).toList();

    Widget circleButton(IconData icon, VoidCallback onTap, String tooltip) =>
        Padding(
          padding: const EdgeInsets.all(6),
          child: Material(
            color: Colors.black.withValues(alpha: 0.35),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: tooltip,
              onPressed: onTap,
              icon: Icon(icon, color: Colors.white, size: 20),
            ),
          ),
        );

    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      stretch: true,
      backgroundColor: p.canvas,
      automaticallyImplyLeading: false,
      leading: circleButton(
          Icons.arrow_back_rounded, () => Navigator.pop(context), 'Back'),
      actions: [
        if (isAdmin)
          circleButton(Icons.edit_rounded, () async {
            HapticFeedback.lightImpact();
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FacilityFormScreen(facility: f),
              ),
            );
            _load();
          }, 'Edit'),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (urls.isEmpty)
              FacilityImageView(
                url: null,
                fallbackIcon: f.fallbackIcon,
                iconSize: 72,
              )
            else
              PageView.builder(
                controller: _pageController,
                itemCount: urls.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => FacilityPhotoViewer.open(context, urls, i),
                  child: Hero(
                    tag: i == 0 ? 'facility-cover-${f.id}' : 'facility-$i-${f.id}',
                    child: FacilityImageView(
                      url: urls[i],
                      fallbackIcon: f.fallbackIcon,
                    ),
                  ),
                ),
              ),
            // Legibility for the buttons over bright photos.
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black38, Colors.transparent, Colors.black26],
                    stops: [0, 0.4, 1],
                  ),
                ),
              ),
            ),
            if (urls.length > 1)
              Positioned(
                bottom: 14,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < urls.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _page ? 18 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i == _page
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppPaletteData p, FacilityRecord f) {
    final textTheme = Theme.of(context).textTheme;
    final statusColor = f.status.color(p);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
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
                      f.name,
                      style: textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (f.categoryName != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        f.categoryName!,
                        style: textTheme.bodySmall
                            ?.copyWith(color: p.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FacilityStatusBadge(status: f.status),
            ],
          ),

          // Unavailable facilities say so up front, with the admin's reason.
          if (!f.status.isAvailable) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(f.status.icon, color: statusColor, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.status == FacilityStatus.maintenance
                              ? 'Temporarily under maintenance'
                              : 'Currently closed',
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          f.statusNote ??
                              'The society office will reopen it soon.',
                          style: textTheme.bodySmall
                              ?.copyWith(color: p.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (f.operatingHours != null || f.location != null) ...[
            const SizedBox(height: 20),
            Surface(
              child: Column(
                children: [
                  if (f.operatingHours != null)
                    FacilityInfoRow(
                      icon: Icons.schedule_rounded,
                      label: 'Operating hours',
                      value: f.operatingHours!,
                    ),
                  if (f.operatingHours != null && f.location != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1, color: p.hairline),
                    ),
                  if (f.location != null)
                    FacilityInfoRow(
                      icon: Icons.place_outlined,
                      label: 'Location',
                      value: f.location!,
                    ),
                ],
              ),
            ),
          ],

          if (f.description.isNotEmpty) ...[
            const SizedBox(height: 24),
            _sectionTitle(context, 'About'),
            const SizedBox(height: 8),
            Text(
              f.description,
              style: textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ],

          if (f.rulesText != null) ...[
            const SizedBox(height: 24),
            _sectionTitle(context, 'Rules & guidelines'),
            const SizedBox(height: 10),
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final rule in _splitRules(f.rulesText!))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 7),
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: p.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              rule,
                              style: textTheme.bodyMedium
                                  ?.copyWith(height: 1.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// One rule per line; leading bullets/numbers typed by the admin are
  /// dropped since the list draws its own.
  List<String> _splitRules(String text) => text
      .split('\n')
      .map((l) => l.replaceFirst(RegExp(r'^\s*([-•*]|\d+[.)])\s*'), '').trim())
      .where((l) => l.isNotEmpty)
      .toList();

  Widget _sectionTitle(BuildContext context, String title) => Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w800),
      );

  Widget _buildBookBar(BuildContext context, AppPaletteData p, FacilityRecord f) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: p.card,
          border: Border(top: BorderSide(color: p.hairline)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Online booking',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Coming soon · contact the society office',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: p.textTertiary, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            // Stubbed: the Facility Booking module wires this up later.
            const FilledButton(
              onPressed: null,
              child: Text('Book Now'),
            ),
          ],
        ),
      ),
    );
  }
}
