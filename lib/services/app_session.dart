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
  String? _societyName;
  String? _societyCity;
  String? _societyAddress;
  List<ResidentRecord> _myResidences = const [];
  Map<String, FlatInfo> _myFlats = const {};
  List<ResidentRecord> _householdMembers = const [];
  List<VehicleRecord> _myVehicles = const [];
  ResidentJoinRequest? _pendingJoinRequest;
  int _pendingApprovalsCount = 0;

  bool get isLoading => _loading;
  bool get isLoaded => _loaded;
  bool get isAdmin => _isAdmin;
  bool get isUnlinkedUser =>
      _loaded &&
      _client != null &&
      _client?.auth.currentUser != null &&
      !_isAdmin &&
      _myResidences.isEmpty;
  String? get adminName => _adminName;
  String? get societyId => _societyId;
  String get societyName => _societyName ?? _pendingJoinRequest?.societyName ?? (_loaded ? 'My Society' : '');
  String? get societyCity => _societyCity;
  String? get societyAddress => _societyAddress;
  List<ResidentRecord> get myResidences => _myResidences;
  ResidentJoinRequest? get pendingJoinRequest => _pendingJoinRequest;
  int get pendingApprovalsCount => _pendingApprovalsCount;

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
      // Supabase not initialized (e.g., in widget tests) — treat as loaded logged out
      _loading = false;
      _loaded = true;
      return;
    }
    final user = client.auth.currentUser;
    if (user == null) {
      _loading = false;
      _loaded = true;
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

      // Fetch society metadata (name, address, city, state) dynamically
      if (_societyId != null) {
        try {
          final socRow = await client
              .from('societies')
              .select('name, address, city, state')
              .eq('id', _societyId!)
              .maybeSingle();
          if (socRow != null) {
            _societyName = socRow['name'] as String?;
            _societyCity = socRow['city'] as String?;
            _societyAddress = socRow['address'] as String?;
          }
        } catch (e) {
          debugPrint('Error fetching society details: $e');
        }
      } else {
        _societyName = null;
        _societyCity = null;
        _societyAddress = null;
      }

      // If user is admin, count pending approvals
      if (_isAdmin && _societyId != null) {
        await refreshAdminApprovalsCount();
      }

      // If user is unlinked (neither admin nor linked resident), check for pending join request
      if (!_isAdmin && records.isEmpty) {
        await refreshJoinRequest();
      } else {
        _pendingJoinRequest = null;
      }

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

  Future<void> refreshAdminApprovalsCount() async {
    final client = _client;
    final socId = _societyId;
    if (client == null || socId == null || !_isAdmin) return;
    try {
      final res = await client
          .from('resident_join_requests')
          .select('id')
          .eq('society_id', socId)
          .eq('status', 'pending');
      _pendingApprovalsCount = (res as List).length;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading approvals count: $e');
    }
  }

  Future<void> refreshJoinRequest() async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    try {
      final res = await client
          .from('resident_join_requests')
          .select('*, societies(name), flats(flat_number, blocks(name))')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(1);

      final list = (res as List).cast<Map<String, dynamic>>();
      if (list.isNotEmpty) {
        _pendingJoinRequest = ResidentJoinRequest.fromMap(list.first);
      } else {
        _pendingJoinRequest = null;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading join request: $e');
    }
  }

  void reset() {
    _loaded = false;
    _isAdmin = false;
    _adminName = null;
    _societyId = null;
    _societyName = null;
    _societyCity = null;
    _societyAddress = null;
    _myResidences = const [];
    _myFlats = const {};
    _householdMembers = const [];
    _myVehicles = const [];
    _pendingJoinRequest = null;
    _pendingApprovalsCount = 0;
    notifyListeners();
  }
}
