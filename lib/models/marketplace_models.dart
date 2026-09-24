import 'package:intl/intl.dart';

/// Models for the Marketplace module (see supabase/12_marketplace_module.sql).
///
/// Seller name / flat / block are never stored on a listing — they arrive
/// joined from residents → flats → blocks, either via the feed/detail RPCs
/// or via embedded selects on the admin screens.

enum ListingStatus {
  active,
  sold,
  removed,
  flagged,
  expired;

  static ListingStatus fromDb(String? v) => switch (v) {
        'sold' => ListingStatus.sold,
        'removed' => ListingStatus.removed,
        'flagged' => ListingStatus.flagged,
        'expired' => ListingStatus.expired,
        _ => ListingStatus.active,
      };

  String toDbValue() => name;

  String get label => switch (this) {
        ListingStatus.active => 'Live',
        ListingStatus.sold => 'Sold',
        ListingStatus.removed => 'Removed',
        ListingStatus.flagged => 'Under review',
        ListingStatus.expired => 'Expired',
      };
}

enum PriceType {
  fixed,
  negotiable,
  free,
  onRequest;

  static PriceType fromDb(String? v) => switch (v) {
        'negotiable' => PriceType.negotiable,
        'free' => PriceType.free,
        'on_request' => PriceType.onRequest,
        _ => PriceType.fixed,
      };

  String toDbValue() => switch (this) {
        PriceType.fixed => 'fixed',
        PriceType.negotiable => 'negotiable',
        PriceType.free => 'free',
        PriceType.onRequest => 'on_request',
      };

  String get label => switch (this) {
        PriceType.fixed => 'Fixed',
        PriceType.negotiable => 'Negotiable',
        PriceType.free => 'Free',
        PriceType.onRequest => 'Ask price',
      };

  bool get needsAmount =>
      this == PriceType.fixed || this == PriceType.negotiable;
}

enum ReportReason {
  spam,
  inappropriate,
  prohibited,
  fraud,
  other;

  static ReportReason fromDb(String? v) => ReportReason.values.firstWhere(
        (r) => r.name == v,
        orElse: () => ReportReason.other,
      );

  String toDbValue() => name;

  String get label => switch (this) {
        ReportReason.spam => 'Spam or duplicate',
        ReportReason.inappropriate => 'Inappropriate content',
        ReportReason.prohibited => 'Prohibited item',
        ReportReason.fraud => 'Looks like a scam',
        ReportReason.other => 'Something else',
      };

  String get hint => switch (this) {
        ReportReason.spam => 'Posted repeatedly, or not a real item',
        ReportReason.inappropriate => 'Offensive photos or wording',
        ReportReason.prohibited => 'Medicines, weapons, alcohol and the like',
        ReportReason.fraud => 'Asking for advance payment, fake item',
        ReportReason.other => 'Tell the office in a line below',
      };
}

/// Admin decisions on a report (values match resolve_marketplace_report).
enum ReportAction {
  dismiss,
  warnSeller,
  removeListing,
  blockSeller;

  String toDbValue() => switch (this) {
        ReportAction.dismiss => 'dismiss',
        ReportAction.warnSeller => 'warn_seller',
        ReportAction.removeListing => 'remove_listing',
        ReportAction.blockSeller => 'block_seller',
      };

  String get label => switch (this) {
        ReportAction.dismiss => 'Dismiss',
        ReportAction.warnSeller => 'Warn seller',
        ReportAction.removeListing => 'Remove listing',
        ReportAction.blockSeller => 'Remove & block seller',
      };
}

enum FeedSort {
  newest,
  priceLow,
  priceHigh;

  String toDbValue() => switch (this) {
        FeedSort.newest => 'newest',
        FeedSort.priceLow => 'price_low',
        FeedSort.priceHigh => 'price_high',
      };

  String get label => switch (this) {
        FeedSort.newest => 'Newest first',
        FeedSort.priceLow => 'Price: low to high',
        FeedSort.priceHigh => 'Price: high to low',
      };
}

DateTime? _parseDate(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

double? _parseDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int _parseInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

String? _nonEmpty(dynamic v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

final _inr = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

/// "₹1,20,000" — Indian digit grouping, no paise.
String formatInr(double amount) => _inr.format(amount.round());

/// "Tower A · Flat 101", same shape as the vehicles module.
String? flatLabel(String? blockName, String? flatNumber) {
  if (flatNumber == null || flatNumber.isEmpty) return null;
  if (blockName == null || blockName.isEmpty) return 'Flat $flatNumber';
  return '$blockName · Flat $flatNumber';
}

String timeAgo(DateTime at, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(at);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('d MMM').format(at);
}

class MarketplaceCategory {
  final String id;
  final String? societyId;
  final String name;
  final String iconKey;
  final int sortOrder;
  final bool isActive;

  const MarketplaceCategory({
    required this.id,
    this.societyId,
    required this.name,
    this.iconKey = 'other',
    this.sortOrder = 100,
    this.isActive = true,
  });

  /// Global defaults are shared across societies and not editable here.
  bool get isGlobal => societyId == null;

  factory MarketplaceCategory.fromMap(Map<String, dynamic> m) =>
      MarketplaceCategory(
        id: m['id']?.toString() ?? '',
        societyId: _nonEmpty(m['society_id']),
        name: m['name']?.toString() ?? 'Other',
        iconKey: m['icon_key']?.toString() ?? 'other',
        sortOrder: _parseInt(m['sort_order']),
        isActive: m['is_active'] != false,
      );
}

class MarketplaceImage {
  final String id;
  final String imageUrl;
  final int sortOrder;

  const MarketplaceImage({
    required this.id,
    required this.imageUrl,
    this.sortOrder = 0,
  });

  factory MarketplaceImage.fromMap(Map<String, dynamic> m) => MarketplaceImage(
        id: m['id']?.toString() ?? '',
        imageUrl: m['image_url']?.toString() ?? '',
        sortOrder: _parseInt(m['sort_order']),
      );
}

class MarketplaceListing {
  final String id;
  final String? societyId;
  final String? residentId;
  final String? categoryId;
  final String? categoryName;
  final String? categoryIcon;
  final String title;
  final String? description;
  final double? price;
  final PriceType priceType;
  final ListingStatus status;
  final String? removedReason;
  final int reportCount;
  final DateTime? soldAt;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final List<MarketplaceImage> images;
  final String? _coverImageUrl;
  final int _imageCount;

  // Seller — joined live from residents / flats / blocks.
  final String? sellerName;
  final String? flatNumber;
  final String? blockName;
  final bool hasSellerPhone;

  /// Only present on admin reads (admins may read residents directly).
  final String? sellerPhone;

  // Viewer-relative flags from the detail RPC.
  final bool isMine;
  final bool viewerIsAdmin;
  final bool myReportPending;

  const MarketplaceListing({
    required this.id,
    this.societyId,
    this.residentId,
    this.categoryId,
    this.categoryName,
    this.categoryIcon,
    required this.title,
    this.description,
    this.price,
    this.priceType = PriceType.fixed,
    this.status = ListingStatus.active,
    this.removedReason,
    this.reportCount = 0,
    this.soldAt,
    this.expiresAt,
    required this.createdAt,
    this.images = const [],
    this._coverImageUrl,
    this._imageCount = 0,
    this.sellerName,
    this.flatNumber,
    this.blockName,
    this.hasSellerPhone = false,
    this.sellerPhone,
    this.isMine = false,
    this.viewerIsAdmin = false,
    this.myReportPending = false,
  });

  String? get coverImageUrl =>
      images.isNotEmpty ? images.first.imageUrl : _coverImageUrl;

  int get imageCount => images.isNotEmpty ? images.length : _imageCount;

  String get priceLabel => switch (priceType) {
        PriceType.free => 'Free',
        PriceType.onRequest => 'Price on ask',
        _ => price == null ? 'Price on ask' : formatInr(price!),
      };

  bool get isNegotiable => priceType == PriceType.negotiable;

  String? get sellerFlatLabel => flatLabel(blockName, flatNumber);

  bool get isLive =>
      status == ListingStatus.active &&
      (expiresAt == null || expiresAt!.isAfter(DateTime.now()));

  /// Active in the DB but past its expiry (cron hasn't flipped it yet).
  bool get isStale =>
      status == ListingStatus.active &&
      expiresAt != null &&
      !expiresAt!.isAfter(DateTime.now());

  ListingStatus get effectiveStatus =>
      isStale ? ListingStatus.expired : status;

  int? get daysLeft {
    if (expiresAt == null || !isLive) return null;
    return expiresAt!.difference(DateTime.now()).inDays;
  }

  String get postedAgo => timeAgo(createdAt);

  factory MarketplaceListing.fromMap(Map<String, dynamic> m) {
    // Direct-table reads embed related rows; RPC reads flatten them.
    final category = m['marketplace_categories'];
    final resident = m['residents'];
    final flat = resident is Map ? resident['flats'] : null;
    final block = flat is Map ? flat['blocks'] : null;

    final rawImages = m['images'] ?? m['marketplace_images'];
    final images = rawImages is List
        ? (rawImages
              .whereType<Map>()
              .map((e) => MarketplaceImage.fromMap(e.cast<String, dynamic>()))
              .where((i) => i.imageUrl.isNotEmpty)
              .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
        : const <MarketplaceImage>[];

    final phone = resident is Map ? _nonEmpty(resident['phone']) : null;

    return MarketplaceListing(
      id: m['id']?.toString() ?? '',
      societyId: _nonEmpty(m['society_id']),
      residentId: _nonEmpty(m['resident_id']),
      categoryId: _nonEmpty(m['category_id']),
      categoryName: _nonEmpty(m['category_name']) ??
          (category is Map ? _nonEmpty(category['name']) : null),
      categoryIcon: _nonEmpty(m['category_icon']) ??
          (category is Map ? _nonEmpty(category['icon_key']) : null),
      title: m['title']?.toString() ?? '',
      description: _nonEmpty(m['description']),
      price: _parseDouble(m['price']),
      priceType: PriceType.fromDb(m['price_type']?.toString()),
      status: ListingStatus.fromDb(m['status']?.toString()),
      removedReason: _nonEmpty(m['removed_reason']),
      reportCount: _parseInt(m['report_count']),
      soldAt: _parseDate(m['sold_at']),
      expiresAt: _parseDate(m['expires_at']),
      createdAt: _parseDate(m['created_at']) ?? DateTime.now(),
      images: images,
      coverImageUrl: _nonEmpty(m['cover_image_url']),
      imageCount: _parseInt(m['image_count']),
      sellerName: _nonEmpty(m['seller_name']) ??
          (resident is Map ? _nonEmpty(resident['full_name']) : null),
      flatNumber: _nonEmpty(m['flat_number']) ??
          (flat is Map ? _nonEmpty(flat['flat_number']) : null),
      blockName: _nonEmpty(m['block_name']) ??
          (block is Map ? _nonEmpty(block['name']) : null),
      hasSellerPhone: m['has_seller_phone'] == true || phone != null,
      sellerPhone: phone,
      isMine: m['is_mine'] == true,
      viewerIsAdmin: m['viewer_is_admin'] == true,
      myReportPending: m['my_report_pending'] == true,
    );
  }
}

class MarketplaceReport {
  final String id;
  final String listingId;
  final ReportReason reason;
  final String? details;
  final bool isPending;
  final String? actionTaken;
  final String? adminNote;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String? reporterName;
  final String? reporterFlat;
  final MarketplaceListing? listing;

  const MarketplaceReport({
    required this.id,
    required this.listingId,
    required this.reason,
    this.details,
    this.isPending = true,
    this.actionTaken,
    this.adminNote,
    required this.createdAt,
    this.reviewedAt,
    this.reporterName,
    this.reporterFlat,
    this.listing,
  });

  String get actionLabel => switch (actionTaken) {
        'dismissed' => 'Dismissed',
        'seller_warned' => 'Seller warned',
        'listing_removed' => 'Listing removed',
        'seller_blocked' => 'Seller blocked',
        _ => isPending ? 'Pending' : 'Reviewed',
      };

  factory MarketplaceReport.fromMap(Map<String, dynamic> m) {
    final reporter = m['residents'];
    final flat = reporter is Map ? reporter['flats'] : null;
    final block = flat is Map ? flat['blocks'] : null;
    final listing = m['marketplace_listings'];
    return MarketplaceReport(
      id: m['id']?.toString() ?? '',
      listingId: m['listing_id']?.toString() ?? '',
      reason: ReportReason.fromDb(m['reason']?.toString()),
      details: _nonEmpty(m['details']),
      isPending: (m['status']?.toString() ?? 'pending') == 'pending',
      actionTaken: _nonEmpty(m['action_taken']),
      adminNote: _nonEmpty(m['admin_note']),
      createdAt: _parseDate(m['created_at']) ?? DateTime.now(),
      reviewedAt: _parseDate(m['reviewed_at']),
      reporterName:
          reporter is Map ? _nonEmpty(reporter['full_name']) : null,
      reporterFlat: flatLabel(
        block is Map ? _nonEmpty(block['name']) : null,
        flat is Map ? _nonEmpty(flat['flat_number']) : null,
      ),
      listing: listing is Map
          ? MarketplaceListing.fromMap(listing.cast<String, dynamic>())
          : null,
    );
  }
}

/// Who the current user is, as far as the marketplace is concerned.
/// Comes from get_marketplace_context — the poster identity shown on the
/// "Sell an item" form is read-only and derived server-side.
class MarketplaceContext {
  final String? societyId;
  final bool enabled;
  final bool isAdmin;
  final String? residentId;
  final bool isBlocked;
  final String? sellerName;
  final String? flatNumber;
  final String? blockName;
  final bool hasPhone;
  final int listingExpiryDays;
  final int autoFlagThreshold;
  final String? error;

  const MarketplaceContext({
    this.societyId,
    this.enabled = true,
    this.isAdmin = false,
    this.residentId,
    this.isBlocked = false,
    this.sellerName,
    this.flatNumber,
    this.blockName,
    this.hasPhone = false,
    this.listingExpiryDays = 30,
    this.autoFlagThreshold = 3,
    this.error,
  });

  bool get canPost => enabled && residentId != null && !isBlocked;

  String? get sellerFlatLabel => flatLabel(blockName, flatNumber);

  factory MarketplaceContext.fromMap(Map<String, dynamic> m) {
    if (m['success'] == false) {
      return MarketplaceContext(
        enabled: false,
        error: m['error']?.toString(),
      );
    }
    return MarketplaceContext(
      societyId: _nonEmpty(m['society_id']),
      enabled: m['enabled'] != false,
      isAdmin: m['is_admin'] == true,
      residentId: _nonEmpty(m['resident_id']),
      isBlocked: m['is_blocked'] == true,
      sellerName: _nonEmpty(m['seller_name']),
      flatNumber: _nonEmpty(m['flat_number']),
      blockName: _nonEmpty(m['block_name']),
      hasPhone: m['has_phone'] == true,
      listingExpiryDays: _parseInt(m['listing_expiry_days']) == 0
          ? 30
          : _parseInt(m['listing_expiry_days']),
      autoFlagThreshold: _parseInt(m['auto_flag_threshold']) == 0
          ? 3
          : _parseInt(m['auto_flag_threshold']),
    );
  }
}

class BlockedSeller {
  final String residentId;
  final String name;
  final String? flat;
  final String? reason;
  final DateTime? blockedAt;

  const BlockedSeller({
    required this.residentId,
    required this.name,
    this.flat,
    this.reason,
    this.blockedAt,
  });

  factory BlockedSeller.fromMap(Map<String, dynamic> m) {
    final resident = m['residents'];
    final flat = resident is Map ? resident['flats'] : null;
    final block = flat is Map ? flat['blocks'] : null;
    return BlockedSeller(
      residentId: m['resident_id']?.toString() ?? '',
      name: (resident is Map ? _nonEmpty(resident['full_name']) : null) ??
          'Resident',
      flat: flatLabel(
        block is Map ? _nonEmpty(block['name']) : null,
        flat is Map ? _nonEmpty(flat['flat_number']) : null,
      ),
      reason: _nonEmpty(m['reason']),
      blockedAt: _parseDate(m['created_at']),
    );
  }
}
