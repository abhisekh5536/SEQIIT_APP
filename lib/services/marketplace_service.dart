import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/marketplace_models.dart';
import 'app_session.dart';

class MarketplaceException implements Exception {
  final String message;
  const MarketplaceException(this.message);

  @override
  String toString() => message;
}

/// Marketplace data access.
///
/// Society scoping and seller identity are enforced server-side: the feed,
/// detail, posting and reporting RPCs derive both from auth.uid(), so no
/// society id / flat / phone is ever sent from the client for those calls.
class MarketplaceService extends ChangeNotifier {
  MarketplaceService._();
  static final MarketplaceService instance = MarketplaceService._();

  static const bucket = 'marketplace-images';
  static const maxPhotos = 6;

  SupabaseClient? get _safeClient {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  SupabaseClient get _client {
    final c = _safeClient;
    if (c == null) {
      throw const MarketplaceException('Not connected to the server');
    }
    return c;
  }

  int _pendingReportsCount = 0;
  int get pendingReportsCount => _pendingReportsCount;

  DateTime? _lastExpirySweep;

  /// RPCs return {success, error, ...}; turn failures into exceptions.
  Map<String, dynamic> _unwrap(dynamic res) {
    if (res is! Map) {
      throw const MarketplaceException('Unexpected response from server');
    }
    final map = res.cast<String, dynamic>();
    if (map['success'] != true) {
      throw MarketplaceException(
        map['error']?.toString() ?? 'Something went wrong',
      );
    }
    return map;
  }

  Future<T> _guard<T>(String op, Future<T> Function() body) async {
    try {
      return await body();
    } on MarketplaceException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint('MarketplaceService.$op error: ${e.message}');
      throw MarketplaceException(e.message);
    } on StorageException catch (e) {
      debugPrint('MarketplaceService.$op storage error: ${e.message}');
      throw MarketplaceException('Photo upload failed: ${e.message}');
    } catch (e) {
      debugPrint('MarketplaceService.$op error: $e');
      throw MarketplaceException('$e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 1. CONTEXT & CATEGORIES
  // ─────────────────────────────────────────────────────────────

  Future<MarketplaceContext> fetchContext() async {
    if (_safeClient == null) return const MarketplaceContext();
    try {
      final res = await _client.rpc('get_marketplace_context');
      if (res is Map) {
        return MarketplaceContext.fromMap(res.cast<String, dynamic>());
      }
    } catch (e) {
      debugPrint('MarketplaceService.fetchContext error: $e');
    }
    return const MarketplaceContext(
      enabled: false,
      error: 'Could not load the marketplace. Pull down to retry.',
    );
  }

  /// Global defaults + this society's own categories (RLS-scoped).
  Future<List<MarketplaceCategory>> fetchCategories({
    bool includeInactive = false,
  }) async {
    if (_safeClient == null) return const [];
    try {
      var query = _client.from('marketplace_categories').select();
      if (!includeInactive) query = query.eq('is_active', true);
      final res = await query
          .order('sort_order', ascending: true)
          .order('name', ascending: true);
      return (res as List)
          .cast<Map<String, dynamic>>()
          .map(MarketplaceCategory.fromMap)
          .toList();
    } catch (e) {
      debugPrint('MarketplaceService.fetchCategories error: $e');
      return const [];
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 2. FEED & DETAIL
  // ─────────────────────────────────────────────────────────────

  Future<List<MarketplaceListing>> fetchFeed({
    String? categoryId,
    String? search,
    FeedSort sort = FeedSort.newest,
    int limit = 40,
    int offset = 0,
  }) async {
    if (_safeClient == null) return const [];
    _sweepExpired();
    return _guard('fetchFeed', () async {
      final res = await _client.rpc('get_marketplace_feed', params: {
        'p_category_id': categoryId,
        'p_search': (search ?? '').trim().isEmpty ? null : search!.trim(),
        'p_sort': sort.toDbValue(),
        'p_limit': limit,
        'p_offset': offset,
      });
      return (res as List)
          .cast<Map<String, dynamic>>()
          .map(MarketplaceListing.fromMap)
          .toList();
    });
  }

  Future<MarketplaceListing> fetchListing(String listingId) {
    return _guard('fetchListing', () async {
      final res = await _client.rpc(
        'get_marketplace_listing',
        params: {'p_listing_id': listingId},
      );
      final map = _unwrap(res);
      return MarketplaceListing.fromMap(
        (map['listing'] as Map).cast<String, dynamic>(),
      );
    });
  }

  /// Tap-to-reveal: the number is read live from residents.phone.
  Future<String> revealSellerPhone(String listingId) {
    return _guard('revealSellerPhone', () async {
      final res = await _client.rpc(
        'reveal_marketplace_seller_phone',
        params: {'p_listing_id': listingId},
      );
      return _unwrap(res)['phone'].toString();
    });
  }

  /// Opportunistic expiry so stale posts flip even without pg_cron.
  void _sweepExpired() {
    final now = DateTime.now();
    if (_lastExpirySweep != null &&
        now.difference(_lastExpirySweep!) < const Duration(minutes: 10)) {
      return;
    }
    _lastExpirySweep = now;
    _client.rpc('expire_marketplace_listings').catchError((Object e) {
      debugPrint('MarketplaceService.expire sweep skipped: $e');
      return null;
    });
  }

  // ─────────────────────────────────────────────────────────────
  // 3. POSTING (resident)
  // ─────────────────────────────────────────────────────────────

  /// Uploads into `<auth uid>/...` (enforced by the bucket policy) and
  /// returns the public URL stored in marketplace_images.
  Future<String> uploadImage({
    required Uint8List bytes,
    required String fileExtension,
  }) {
    return _guard('uploadImage', () async {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        throw const MarketplaceException('Please sign in again');
      }
      final ext = fileExtension.toLowerCase() == 'jpg'
          ? 'jpeg'
          : fileExtension.toLowerCase();
      final path =
          '$uid/${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 30)}.$ext';
      await _client.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: 'image/$ext'),
          );
      return _client.storage.from(bucket).getPublicUrl(path);
    });
  }

  Future<String> createListing({
    required String title,
    String? description,
    double? price,
    required PriceType priceType,
    required String categoryId,
    List<String> imageUrls = const [],
  }) {
    return _guard('createListing', () async {
      final res = await _client.rpc('create_marketplace_listing', params: {
        'p_title': title.trim(),
        'p_description': description?.trim(),
        'p_price': priceType.needsAmount ? price : null,
        'p_price_type': priceType.toDbValue(),
        'p_category_id': categoryId,
        'p_image_urls': imageUrls,
      });
      return _unwrap(res)['listing_id'].toString();
    });
  }

  Future<void> updateListing({
    required String listingId,
    required String title,
    String? description,
    double? price,
    required PriceType priceType,
    required String categoryId,
    List<String> imageUrls = const [],
  }) {
    return _guard('updateListing', () async {
      final res = await _client.rpc('update_marketplace_listing', params: {
        'p_listing_id': listingId,
        'p_title': title.trim(),
        'p_description': description?.trim(),
        'p_price': priceType.needsAmount ? price : null,
        'p_price_type': priceType.toDbValue(),
        'p_category_id': categoryId,
        'p_image_urls': imageUrls,
      });
      _unwrap(res);
    });
  }

  /// Owner: sold / active (relist). Admin: removed / active (restore).
  Future<void> setListingStatus(
    String listingId,
    ListingStatus status, {
    String? reason,
  }) {
    return _guard('setListingStatus', () async {
      final res = await _client.rpc('set_marketplace_listing_status', params: {
        'p_listing_id': listingId,
        'p_status': status.toDbValue(),
        'p_reason': reason,
      });
      _unwrap(res);
    });
  }

  Future<void> deleteListing(MarketplaceListing listing) {
    return _guard('deleteListing', () async {
      await _client.from('marketplace_listings').delete().eq('id', listing.id);
      // Best-effort storage cleanup; the policy only lets owners delete
      // their own files, so admin deletes simply leave the objects behind.
      final paths = listing.images
          .map((i) => _storagePathFromUrl(i.imageUrl))
          .whereType<String>()
          .toList();
      if (paths.isNotEmpty) {
        try {
          await _client.storage.from(bucket).remove(paths);
        } catch (e) {
          debugPrint('MarketplaceService.deleteListing storage cleanup: $e');
        }
      }
    });
  }

  /// Photos dropped while editing a listing.
  Future<void> removeUploadedImages(List<String> urls) async {
    final paths = urls.map(_storagePathFromUrl).whereType<String>().toList();
    if (paths.isEmpty || _safeClient == null) return;
    try {
      await _client.storage.from(bucket).remove(paths);
    } catch (e) {
      debugPrint('MarketplaceService.removeUploadedImages: $e');
    }
  }

  static String? _storagePathFromUrl(String url) {
    const marker = '/$bucket/';
    final i = url.indexOf(marker);
    if (i < 0) return null;
    return Uri.decodeComponent(url.substring(i + marker.length).split('?').first);
  }

  /// All of the signed-in user's own listings, across every status.
  Future<List<MarketplaceListing>> fetchMyListings() async {
    if (_safeClient == null) return const [];
    final residentIds =
        AppSession.instance.myResidences.map((r) => r.id).toList();
    if (residentIds.isEmpty) return const [];
    return _guard('fetchMyListings', () async {
      final res = await _client
          .from('marketplace_listings')
          .select(
            '*, marketplace_categories(name, icon_key), marketplace_images(id, image_url, sort_order)',
          )
          .inFilter('resident_id', residentIds)
          .order('created_at', ascending: false);
      return (res as List)
          .cast<Map<String, dynamic>>()
          .map((m) => MarketplaceListing.fromMap({...m, 'is_mine': true}))
          .toList();
    });
  }

  // ─────────────────────────────────────────────────────────────
  // 4. REPORTING (resident)
  // ─────────────────────────────────────────────────────────────

  /// Returns true when this report pushed the listing into auto-hide.
  Future<bool> reportListing({
    required String listingId,
    required ReportReason reason,
    String? details,
  }) {
    return _guard('reportListing', () async {
      final res = await _client.rpc('report_marketplace_listing', params: {
        'p_listing_id': listingId,
        'p_reason': reason.toDbValue(),
        'p_details': details?.trim(),
      });
      return _unwrap(res)['flagged'] == true;
    });
  }

  // ─────────────────────────────────────────────────────────────
  // 5. MODERATION & SETTINGS (society admin)
  // ─────────────────────────────────────────────────────────────

  static const _listingEmbed =
      '*, marketplace_categories(name, icon_key), marketplace_images(id, image_url, sort_order), residents(full_name, phone, flats(flat_number, blocks(name)))';

  Future<List<MarketplaceReport>> fetchReports({
    required String societyId,
    bool pendingOnly = true,
  }) {
    if (_safeClient == null) return Future.value(const []);
    return _guard('fetchReports', () async {
      var query = _client
          .from('marketplace_reports')
          .select(
            '*, residents(full_name, flats(flat_number, blocks(name))), marketplace_listings($_listingEmbed)',
          )
          .eq('society_id', societyId);
      query = pendingOnly
          ? query.eq('status', 'pending')
          : query.eq('status', 'reviewed');
      final res = await query
          .order('created_at', ascending: false)
          .limit(pendingOnly ? 200 : 50);
      final reports = (res as List)
          .cast<Map<String, dynamic>>()
          .map(MarketplaceReport.fromMap)
          .toList();
      if (pendingOnly) {
        _pendingReportsCount = reports.length;
        notifyListeners();
      }
      return reports;
    });
  }

  Future<void> refreshPendingReportsCount(String societyId) async {
    if (_safeClient == null) return;
    try {
      final res = await _client
          .from('marketplace_reports')
          .select('id')
          .eq('society_id', societyId)
          .eq('status', 'pending');
      _pendingReportsCount = (res as List).length;
      notifyListeners();
    } catch (e) {
      debugPrint('MarketplaceService.refreshPendingReportsCount error: $e');
    }
  }

  Future<List<MarketplaceListing>> fetchSocietyListings({
    required String societyId,
    ListingStatus? status,
  }) {
    if (_safeClient == null) return Future.value(const []);
    return _guard('fetchSocietyListings', () async {
      var query = _client
          .from('marketplace_listings')
          .select(_listingEmbed)
          .eq('society_id', societyId);
      if (status != null) query = query.eq('status', status.toDbValue());
      final res =
          await query.order('created_at', ascending: false).limit(200);
      return (res as List)
          .cast<Map<String, dynamic>>()
          .map(MarketplaceListing.fromMap)
          .toList();
    });
  }

  Future<void> resolveReport({
    required String reportId,
    required ReportAction action,
    String? note,
  }) {
    return _guard('resolveReport', () async {
      final res = await _client.rpc('resolve_marketplace_report', params: {
        'p_report_id': reportId,
        'p_action': action.toDbValue(),
        'p_note': note?.trim(),
      });
      _unwrap(res);
    });
  }

  /// Writes the society's module_flags row (module_key = 'marketplace').
  Future<void> setEnabled(bool enabled) {
    return _guard('setEnabled', () async {
      final res = await _client.rpc(
        'set_marketplace_enabled',
        params: {'p_enabled': enabled},
      );
      _unwrap(res);
    });
  }

  Future<void> updateSettings({
    required int listingExpiryDays,
    required int autoFlagThreshold,
  }) {
    return _guard('updateSettings', () async {
      final res = await _client.rpc('update_marketplace_settings', params: {
        'p_listing_expiry_days': listingExpiryDays,
        'p_auto_flag_threshold': autoFlagThreshold,
      });
      _unwrap(res);
    });
  }

  Future<void> addCategory({
    required String societyId,
    required String name,
  }) {
    return _guard('addCategory', () async {
      await _client.from('marketplace_categories').insert({
        'society_id': societyId,
        'name': name.trim(),
        'icon_key': 'other',
        'sort_order': 500,
      });
    });
  }

  Future<void> setCategoryActive(String categoryId, bool active) {
    return _guard('setCategoryActive', () async {
      await _client
          .from('marketplace_categories')
          .update({'is_active': active}).eq('id', categoryId);
    });
  }

  Future<List<BlockedSeller>> fetchBlockedSellers(String societyId) {
    if (_safeClient == null) return Future.value(const []);
    return _guard('fetchBlockedSellers', () async {
      final res = await _client
          .from('marketplace_blocked_residents')
          .select('*, residents(full_name, flats(flat_number, blocks(name)))')
          .eq('society_id', societyId)
          .order('created_at', ascending: false);
      return (res as List)
          .cast<Map<String, dynamic>>()
          .map(BlockedSeller.fromMap)
          .toList();
    });
  }

  Future<void> unblockSeller({
    required String societyId,
    required String residentId,
  }) {
    return _guard('unblockSeller', () async {
      await _client
          .from('marketplace_blocked_residents')
          .delete()
          .eq('society_id', societyId)
          .eq('resident_id', residentId);
    });
  }
}
