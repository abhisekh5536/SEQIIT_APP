import 'package:flutter/material.dart';

import '../../../models/facility_models.dart';
import '../../../theme/app_theme.dart';

/// Coloured pill for a facility's status: Open / Maintenance / Closed.
class FacilityStatusBadge extends StatelessWidget {
  final FacilityStatus status;
  final bool compact;

  /// Solid background, for use on top of photos.
  final bool onImage;

  const FacilityStatusBadge({
    super.key,
    required this.status,
    this.compact = false,
    this.onImage = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final color = status.color(p);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: onImage ? color : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: onImage ? null : Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon,
              size: compact ? 11 : 13, color: onImage ? Colors.white : color),
          SizedBox(width: compact ? 3 : 5),
          Text(
            compact ? status.shortLabel : status.label,
            style: TextStyle(
              color: onImage ? Colors.white : color,
              fontSize: compact ? 10.5 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// A facility photo, or a tinted icon placeholder when there is none or it
/// fails to load. Unavailable facilities are greyed so the state reads at a
/// glance even before the badge.
class FacilityImageView extends StatelessWidget {
  final String? url;
  final IconData fallbackIcon;
  final bool dimmed;
  final double iconSize;

  const FacilityImageView({
    super.key,
    required this.url,
    required this.fallbackIcon,
    this.dimmed = false,
    this.iconSize = 40,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

    Widget placeholder() => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                p.primary.withValues(alpha: 0.22),
                p.secondary.withValues(alpha: 0.18),
              ],
            ),
          ),
          alignment: Alignment.center,
          child: Icon(fallbackIcon,
              size: iconSize, color: p.primary.withValues(alpha: 0.75)),
        );

    Widget child = url == null || url!.isEmpty
        ? placeholder()
        : Image.network(
            url!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : Container(color: p.cardMuted),
            errorBuilder: (_, _, _) => placeholder(),
          );

    if (dimmed) {
      child = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.45, 0.45, 0.10, 0, 0, //
          0.35, 0.55, 0.10, 0, 0, //
          0.35, 0.45, 0.20, 0, 0, //
          0, 0, 0, 1, 0,
        ]),
        child: child,
      );
    }
    return child;
  }
}

/// Horizontal "All + categories" filter row.
class FacilityCategoryChips extends StatelessWidget {
  final List<FacilityCategory> categories;
  final String? selectedId;
  final ValueChanged<String?> onSelected;
  final EdgeInsetsGeometry padding;

  const FacilityCategoryChips({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    this.padding = const EdgeInsets.fromLTRB(20, 4, 20, 8),
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

    Widget chip(String label, String? id, IconData? icon) {
      final selected = selectedId == id;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          avatar: icon == null
              ? null
              : Icon(icon,
                  size: 16, color: selected ? p.primary : p.textSecondary),
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => onSelected(id),
          selectedColor: p.primary.withValues(alpha: 0.18),
          backgroundColor: p.card,
          labelStyle: TextStyle(
            color: selected ? p.primary : p.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: selected ? p.primary : p.hairline),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          chip('All', null, null),
          for (final c in categories) chip(c.name, c.id, c.icon),
        ],
      ),
    );
  }
}

/// Full-screen, swipeable, pinch-to-zoom photo viewer.
class FacilityPhotoViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const FacilityPhotoViewer({
    super.key,
    required this.urls,
    this.initialIndex = 0,
  });

  static Future<void> open(BuildContext context, List<String> urls, int index) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) =>
            FacilityPhotoViewer(urls: urls, initialIndex: index),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  State<FacilityPhotoViewer> createState() => _FacilityPhotoViewerState();
}

class _FacilityPhotoViewerState extends State<FacilityPhotoViewer> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: Image.network(
                  widget.urls[i],
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 48),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  const Spacer(),
                  if (widget.urls.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        '${_index + 1} / ${widget.urls.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon + label + value row used on the detail page.
class FacilityInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const FacilityInfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: p.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: p.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: textTheme.bodySmall
                      ?.copyWith(color: p.textTertiary, fontSize: 11.5)),
              const SizedBox(height: 2),
              Text(value,
                  style: textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}
