import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/marketplace_models.dart';
import 'marketplace_service.dart';

/// Counts behind the home carousel's always-on cards (migration 21).
///
/// Society-wide fields are null for residents: the server only fills them
/// for admins and guards.
class HomeSummary {
  final int gatesActive;
  final int guardsActive;
  final int emergencyContacts;
  final int openSos;
  final int? totalFlats;
  final int? occupiedFlats;
  final int? activeResidents;
  final int? blocks;
  final String? myBlock;
  final List<String> myParkingSlots;

  const HomeSummary({
    this.gatesActive = 0,
    this.guardsActive = 0,
    this.emergencyContacts = 0,
    this.openSos = 0,
    this.totalFlats,
    this.occupiedFlats,
    this.activeResidents,
    this.blocks,
    this.myBlock,
    this.myParkingSlots = const [],
  });

  static int? _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v');

  factory HomeSummary.fromMap(Map<String, dynamic> m) {
    final block = m['my_block']?.toString().trim();
    return HomeSummary(
        gatesActive: _int(m['gates_active']) ?? 0,
        guardsActive: _int(m['guards_active']) ?? 0,
        emergencyContacts: _int(m['emergency_contacts']) ?? 0,
        openSos: _int(m['open_sos']) ?? 0,
        totalFlats: m['total_flats'] == null ? null : _int(m['total_flats']),
        occupiedFlats:
            m['occupied_flats'] == null ? null : _int(m['occupied_flats']),
        activeResidents:
            m['active_residents'] == null ? null : _int(m['active_residents']),
        blocks: m['blocks'] == null ? null : _int(m['blocks']),
        myBlock: (block == null || block.isEmpty) ? null : block,
        myParkingSlots: (m['my_parking_slots'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
  }
}

/// What the marketplace card should show.
class MarketplaceTeaser {
  /// The society has the marketplace switched on for this user.
  final bool enabled;

  /// Newest live listing in the society, if any.
  final MarketplaceListing? latest;

  const MarketplaceTeaser({required this.enabled, this.latest});

  static const disabled = MarketplaceTeaser(enabled: false);
}

class HomeSummaryService {
  HomeSummaryService._();
  static final HomeSummaryService instance = HomeSummaryService._();

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  Future<HomeSummary> fetchSummary(String? societyId) async {
    final client = _client;
    if (client == null || societyId == null) return const HomeSummary();
    try {
      final res = await client
          .rpc('get_home_summary', params: {'p_society_id': societyId});
      if (res is Map) return HomeSummary.fromMap(res.cast<String, dynamic>());
    } catch (e) {
      // Pre-migration-21 databases: the cards fall back to zero counts.
      debugPrint('HomeSummaryService.fetchSummary error: $e');
    }
    return const HomeSummary();
  }

  Future<MarketplaceTeaser> fetchMarketplaceTeaser() async {
    if (_client == null) return MarketplaceTeaser.disabled;
    try {
      final ctx = await MarketplaceService.instance.fetchContext();
      if (!ctx.enabled) return MarketplaceTeaser.disabled;
      final feed = await MarketplaceService.instance.fetchFeed(limit: 1);
      return MarketplaceTeaser(
        enabled: true,
        latest: feed.isEmpty ? null : feed.first,
      );
    } catch (e) {
      debugPrint('HomeSummaryService.fetchMarketplaceTeaser error: $e');
      return MarketplaceTeaser.disabled;
    }
  }
}
