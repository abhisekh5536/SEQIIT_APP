import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/db_models.dart';

/// Holds the signed-in user's role and profile data.
///
/// Loaded once after login (and refreshed on demand):
/// - [isAdmin]   -> row exists in society_admin_users
/// - [societyId] -> the society this admin/resident belongs to
/// - [myResidences] -> resident records linked to this account
class AppSession extends ChangeNotifier {
  AppSession._();

  static final AppSession instance = AppSession._();

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  bool _loading = false;
  bool _loaded = false;
  bool _isAdmin = false;
  String? _adminName;
  String? _societyId;
  List<ResidentRecord> _myResidences = const [];
  Map<String, FlatInfo> _myFlats = const {};
  List<ResidentRecord> _householdMembers = const [];
  List<VehicleRecord> _myVehicles = const [];

  bool get isLoading => _loading;
  bool get isLoaded => _loaded;
  bool get isAdmin => _isAdmin;
  String? get adminName => _adminName;
  String? get societyId => _societyId;
  List<ResidentRecord> get myResidences => _myResidences;

  /// Other people registered in this user's flats (family members,
  /// co-owners, tenants). Requires the household-visibility policy.
  List<ResidentRecord> get householdMembers => _householdMembers;

  /// Vehicles registered against this user's flats.
  List<VehicleRecord> get myVehicles => _myVehicles;

  /// Display name for greeting / account card.
  /// Priority: adminName → primary resident fullName → first resident → auth email local part.
  String? get displayName {
    if (_isAdmin && _adminName != null && _adminName!.trim().isNotEmpty) {
      return _adminName!.trim();
    }
    final primary = primaryResidence;
    if (primary != null && primary.fullName.trim().isNotEmpty) {
      return primary.fullName.trim();
    }
    if (_myResidences.isNotEmpty && _myResidences.first.fullName.trim().isNotEmpty) {
      return _myResidences.first.fullName.trim();
    }
    try {
      final user = _client?.auth.currentUser;
      if (user != null) {
        final meta = user.userMetadata;
        if (meta != null) {
          final metaName = (meta['full_name'] ?? meta['name'] ?? meta['display_name']) as String?;
          if (metaName != null && metaName.trim().isNotEmpty) return metaName.trim();
        }
        final email = user.email;
        if (email != null && email.isNotEmpty) {
          // Use part before @ and capitalize
          final local = email.split('@').first;
          if (local.isNotEmpty) {
            // Insert spaces before capital? Just return local with first letter cap for nicer greeting
            return local[0].toUpperCase() + local.substring(1);
          }
          return email;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Flat subtitle for Home header, e.g. "Flat B-204 · Floor 2 · 3BHK"
  String? get flatSubtitle {
    final primary = primaryResidence;
    if (primary != null) {
      final flat = flatOf(primary);
      if (flat != null) {
        // We don't have block name here, so show flatNumber which already includes block prefix like B-204
        return 'Flat ${flat.flatNumber} · Floor ${flat.floorNumber} · ${flat.type}';
      }
    }
    return null;
  }

  /// Flat details for [record], resolved from the embedded join.
  FlatInfo? flatOf(ResidentRecord record) => _myFlats[record.flatId];

  ResidentRecord? get primaryResidence {
    for (final r in _myResidences) {
      if (r.isPrimary && r.isActive) return r;
    }
    for (final r in _myResidences) {
      if (r.isActive) return r;
    }
    return null;
  }

  Future<void> load() async {
    final client = _client;
    if (client == null) {
      // Supabase not initialized (e.g., in widget tests) — treat as logged out
      reset();
      return;
    }
    final user = client.auth.currentUser;
    if (user == null) {
      reset();
      return;
    }

    _loading = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        client.from('society_admin_users').select().eq('id', user.id),
        client.from('residents').select(
              '*, flats(id, block_id, floor_number, flat_number, type, status)',
            ).eq('user_id', user.id),
      ]);

      final adminRows = (results[0] as List).cast<Map<String, dynamic>>();
      final residentRows = (results[1] as List).cast<Map<String, dynamic>>();

      final flats = <String, FlatInfo>{};
      final records = <ResidentRecord>[];
      for (final row in residentRows) {
        records.add(ResidentRecord.fromMap(row));
        final flatMap = row['flats'];
        if (flatMap is Map<String, dynamic>) {
          final flat = FlatInfo.fromMap(flatMap);
          flats[flat.id] = flat;
        }
      }

      _isAdmin = adminRows.isNotEmpty;
      _adminName = _isAdmin ? adminRows.first['name'] as String? : null;
      _societyId = _isAdmin
          ? adminRows.first['society_id'] as String?
          : (records.isNotEmpty ? records.first.societyId : null);
      _myResidences = List.unmodifiable(records);
      _myFlats = Map.unmodifiable(flats);

      // Household members + vehicles for this user's flats.
      // Both are best-effort: they need the 04_profile_self_service
      // migration; on older schemas we silently fall back to empty.
      final flatIds = flats.keys.toList();
      if (flatIds.isNotEmpty) {
        try {
          final memberRows = await client
              .from('residents')
              .select()
              .inFilter('flat_id', flatIds)
              .eq('status', 'active');
          _householdMembers = List.unmodifiable(
            (memberRows as List)
                .cast<Map<String, dynamic>>()
                .map(ResidentRecord.fromMap),
          );
        } catch (_) {
          _householdMembers = const [];
        }
        try {
          final vehicleRows = await client
              .from('resident_vehicles')
              .select()
              .inFilter('flat_id', flatIds);
          _myVehicles = List.unmodifiable(
            (vehicleRows as List)
                .cast<Map<String, dynamic>>()
                .map(VehicleRecord.fromMap),
          );
        } catch (_) {
          _myVehicles = const [];
        }
      } else {
        _householdMembers = const [];
        _myVehicles = const [];
      }

      _loaded = true;
    } catch (e) {
      debugPrint('AppSession.load failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void reset() {
    _loaded = false;
    _isAdmin = false;
    _adminName = null;
    _societyId = null;
    _myResidences = const [];
    _myFlats = const {};
    _householdMembers = const [];
    _myVehicles = const [];
    notifyListeners();
  }
}
