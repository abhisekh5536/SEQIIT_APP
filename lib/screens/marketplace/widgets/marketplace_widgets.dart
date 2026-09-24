import 'package:flutter/material.dart';

import '../../../models/marketplace_models.dart';
import '../../../theme/app_theme.dart';
import '../../vehicles/widgets/vehicle_parking_widgets.dart';

export '../../vehicles/widgets/vehicle_parking_widgets.dart'
    show
        ModuleHeader,
        SegmentedTabs,
        ModuleEmptyState,
        ModuleSectionHeader,
        StatusDot,
        FieldLabel,
        SheetHeader,
        FormError;

IconData categoryIcon(String? key) => switch (key) {
      'furniture' => Icons.chair_outlined,
      'electronics' => Icons.devices_other_outlined,
      'kitchen' => Icons.blender_outlined,
      'kids' => Icons.child_friendly_outlined,
      'books' => Icons.menu_book_outlined,
      'vehicles' => Icons.pedal_bike_outlined,
      'clothing' => Icons.checkroom_outlined,
      'sports' => Icons.sports_tennis_outlined,
      _ => Icons.sell_outlined,
    };

Color listingStatusColor(ListingStatus s, AppPaletteData p) => switch (s) {
      ListingStatus.active => p.success,
      ListingStatus.sold => p.primary,
      ListingStatus.flagged => p.warning,
      ListingStatus.removed => p.danger,
      ListingStatus.expired => p.textTertiary,
    };

/// Network photo with a quiet placeholder while loading / on failure.
class ListingImage extends StatelessWidget {
  final String? url;
  final String? categoryIconKey;
  final double iconSize;
  final BoxFit fit;

  const ListingImage({
    super.key,
    required this.url,
    this.categoryIconKey,
    this.iconSize = 28,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final placeholder = Container(
      color: p.cardMuted,
      alignment: Alignment.center,
      child: Icon(
        categoryIcon(categoryIconKey),
        size: iconSize,
        color: p.textTertiary,
      ),
    );
    if (url == null || url!.isEmpty) return placeholder;
    return Image.network(
      url!,
      fit: fit,
      errorBuilder: (_, _, _) => placeholder,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : placeholder,
    );
  }
}

/// Feed tile: photo, price, title, flat + age.
class ListingGridCard extends StatelessWidget {
  final MarketplaceListing listing;
  final VoidCallback onTap;

  const ListingGridCard({
    super.key,
    required this.listing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: p.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(17),
                      ),
                      child: ListingImage(
                        url: listing.coverImageUrl,
                        categoryIconKey: listing.categoryIcon,
                      ),
                    ),
                    if (listing.imageCount > 1)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: _PhotoCountBadge(count: listing.imageCount),
                      ),
                    if (listing.isMine)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: _Tag(label: 'Yours', color: p.primary),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            listing.priceLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: listing.priceType == PriceType.free
                                  ? p.success
                                  : p.textPrimary,
                            ),
                          ),
                        ),
                        if (listing.isNegotiable) ...[
                          const SizedBox(width: 4),
                          Text(
                            'Neg.',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: p.textTertiary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      listing.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: p.textPrimary,
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (listing.flatNumber != null)
                          'Flat ${listing.flatNumber}',
                        listing.postedAgo,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: p.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact row for My Listings and admin lists.
class ListingRow extends StatelessWidget {
  final MarketplaceListing listing;
  final String? meta;
  final VoidCallback? onTap;
  final Widget? trailing;

  const ListingRow({
    super.key,
    required this.listing,
    this.meta,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    final status = listing.effectiveStatus;
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: p.hairline),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: ListingImage(
                    url: listing.coverImageUrl,
                    categoryIconKey: listing.categoryIcon,
                    iconSize: 22,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      listing.priceLabel,
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        StatusDot(
                          color: listingStatusColor(status, p),
                          label: status.label,
                          fontSize: 11,
                        ),
                        if (meta != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              meta!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: p.textTertiary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal category filter. `null` id = All.
class CategoryChips extends StatelessWidget {
  final List<MarketplaceCategory> categories;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  const CategoryChips({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    Widget chip(String? id, String label, IconData? icon) {
      final selected = selectedId == id;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          selected: selected,
          onSelected: (_) => onSelected(id),
          showCheckmark: false,
          avatar: icon == null
              ? null
              : Icon(
                  icon,
                  size: 16,
                  color: selected ? p.onPrimary : p.textSecondary,
                ),
          label: Text(label),
          labelStyle: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? p.onPrimary : p.textPrimary,
          ),
          selectedColor: p.primary,
          backgroundColor: p.card,
          side: BorderSide(color: selected ? p.primary : p.hairline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          chip(null, 'All', null),
          for (final c in categories)
            chip(c.id, c.name, categoryIcon(c.iconKey)),
        ],
      ),
    );
  }
}

class _PhotoCountBadge extends StatelessWidget {
  final int count;

  const _PhotoCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_library_outlined,
              size: 11, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;

  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Read-only "Posting as" strip — seller identity is never typed in.
class SellerIdentityStrip extends StatelessWidget {
  final String? name;
  final String? flat;
  final String caption;

  const SellerIdentityStrip({
    super.key,
    required this.name,
    required this.flat,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    final initial =
        (name ?? '').trim().isEmpty ? '?' : name!.trim()[0].toUpperCase();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.cardMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: p.primary.withValues(alpha: 0.16),
            child: Text(
              initial,
              style: TextStyle(
                color: p.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [name ?? 'You', ?flat].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  caption,
                  style: textTheme.bodySmall?.copyWith(
                    color: p.textTertiary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.lock_outline_rounded, size: 16, color: p.textTertiary),
        ],
      ),
    );
  }
}
