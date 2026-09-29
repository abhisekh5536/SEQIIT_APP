import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/facility_models.dart';
import 'app_lifecycle_service.dart';
import 'app_session.dart';

/// Data access for the Facilities catalog (migration 19).
///
/// Society scoping is enforced by RLS from the caller's own membership; the
/// society id sent here only narrows the query and cannot widen it.
class FacilitiesService extends ChangeNotifier {
  FacilitiesService._() {
    // Open screens re-fetch on any notify; after the background the socket
    // was closed, so status changes made meanwhile need that re-fetch.
    AppLifecycleService.instance.onResumed.listen((_) {
      if (_listeners > 0) notifyListeners();
    });
  }
  static final FacilitiesService instance = FacilitiesService._();

  static const _bucket = 'facility-images';
  static const _select =
      '*, facility_categories(name), facility_images(*)';

  SupabaseClient? get _safeClient {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  SupabaseClient get _client =>
      _safeClient ?? SupabaseClient('http://localhost', 'anon');

  String? get _societyId => AppSession.instance.societyId;

  // ── Realtime ──────────────────────────────────────────────────
  //
  // "Admin marks the pool under maintenance, residents see it at once":
  // open screens listen here and re-fetch on any change.

  RealtimeChannel? _channel;
  String? _channelSocietyId;
  int _listeners = 0;

  /// Call from a screen's initState; pair with [stopLive] in dispose.
  void startLive() {
    _listeners++;
    final societyId = _societyId;
    final client = _safeClient;
    if (client == null || societyId == null) return;
    if (_channel != null && _channelSocietyId == societyId) return;

    _teardown();
    _channelSocietyId = societyId;
    _channel = client
        .channel('public:facilities:$societyId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'facilities',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'society_id',
            value: societyId,
          ),
          callback: (_) => notifyListeners(),
        )
        // No society column to filter on; RLS limits events to images of
        // facilities this user can see.
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'facility_images',
          callback: (_) => notifyListeners(),
        )
        .subscribe();
  }

  void stopLive() {
    _listeners = (_listeners - 1).clamp(0, 1 << 30);
    if (_listeners == 0) _teardown();
  }

  void _teardown() {
    final ch = _channel;
    _channel = null;
    _channelSocietyId = null;
    if (ch != null) _safeClient?.removeChannel(ch);
  }

  // ── Module flag ───────────────────────────────────────────────

  /// Whether the society has the module switched on. No flag row means on.
  Future<bool> isModuleEnabled() async {
    final societyId = _societyId;
    if (_safeClient == null || societyId == null) return true;
    try {
      final res = await _client
          .rpc('facilities_enabled', params: {'p_society_id': societyId});
      return res != false;
    } catch (e) {
      debugPrint('FacilitiesService.isModuleEnabled error: $e');
      return true;
    }
  }

  Future<void> setModuleEnabled(bool enabled) async {
    final societyId = _societyId;
    if (societyId == null) throw Exception('No society selected');
    await _client.from('module_flags').upsert(
      {
        'society_id': societyId,
        'module_key': 'facilities',
        'enabled': enabled,
      },
      onConflict: 'society_id,module_key',
    );
  }

  // ── Categories ────────────────────────────────────────────────

  /// Shared defaults plus this society's own categories.
  Future<List<FacilityCategory>> fetchCategories() async {
    if (_safeClient == null) return [];
    final res = await _client
        .from('facility_categories')
        .select()
        .order('sort_order')
        .order('name');
    final societyId = _societyId;
    return (res as List)
        .cast<Map<String, dynamic>>()
        .map(FacilityCategory.fromMap)
        // RLS already hides other societies; this keeps a master admin's
        // view to the society they are acting for.
        .where((c) => c.societyId == null || c.societyId == societyId)
        .toList();
  }

  Future<void> addCategory(String name) async {
    final societyId = _societyId;
    if (societyId == null) throw Exception('No society selected');
    await _client.from('facility_categories').insert({
      'society_id': societyId,
      'name': name.trim(),
    });
  }

  Future<void> renameCategory(String id, String name) async {
    await _client
        .from('facility_categories')
        .update({'name': name.trim()})
        .eq('id', id);
  }

  /// Facilities in a deleted category become uncategorised (FK set null).
  Future<void> deleteCategory(String id) async {
    await _client.from('facility_categories').delete().eq('id', id);
  }

  // ── Facilities ────────────────────────────────────────────────

  Future<List<FacilityRecord>> fetchFacilities() async {
    final societyId = _societyId;
    if (_safeClient == null || societyId == null) return [];
    final res = await _client
        .from('facilities')
        .select(_select)
        .eq('society_id', societyId)
        .order('name');
    return (res as List)
        .cast<Map<String, dynamic>>()
        .map(FacilityRecord.fromMap)
        .toList();
  }

  /// Null means the facility is gone (or hidden from this user); no
  /// connection throws instead, so callers keep what they already show.
  Future<FacilityRecord?> fetchFacility(String id) async {
    if (_safeClient == null) throw StateError('Supabase is not initialised');
    final res = await _client
        .from('facilities')
        .select(_select)
        .eq('id', id)
        .maybeSingle();
    return res == null ? null : FacilityRecord.fromMap(res);
  }

  /// Creates or updates a facility and returns its id.
  Future<String> saveFacility({
    String? id,
    required String name,
    required String description,
    required String? categoryId,
    required FacilityStatus status,
    String? statusNote,
    String? operatingHours,
    String? location,
    String? rulesText,
  }) async {
    final societyId = _societyId;
    if (societyId == null) throw Exception('No society selected');

    String? clean(String? v) =>
        (v == null || v.trim().isEmpty) ? null : v.trim();

    final data = {
      'name': name.trim(),
      'description': description.trim(),
      'category_id': categoryId,
      'status': status.dbValue,
      'status_note': status.isAvailable ? null : clean(statusNote),
      'operating_hours': clean(operatingHours),
      'location': clean(location),
      'rules_text': clean(rulesText),
    };

    if (id == null) {
      final row = await _client
          .from('facilities')
          .insert({
            ...data,
            'society_id': societyId,
            'created_by': _client.auth.currentUser?.id,
          })
          .select('id')
          .single();
      return row['id'].toString();
    }

    await _client.from('facilities').update(data).eq('id', id);
    return id;
  }

  Future<void> setStatus(
    String id,
    FacilityStatus status, {
    String? note,
  }) async {
    await _client.from('facilities').update({
      'status': status.dbValue,
      'status_note': status.isAvailable || note == null || note.trim().isEmpty
          ? null
          : note.trim(),
    }).eq('id', id);
  }

  Future<void> deleteFacility(FacilityRecord facility) async {
    // Rows go with the facility (cascade); the stored files do not.
    await _removeObjects(facility.images);
    await _client.from('facilities').delete().eq('id', facility.id);
  }

  // ── Images ────────────────────────────────────────────────────

  Future<void> uploadImage(
    String facilityId,
    XFile file, {
    required int sortOrder,
  }) async {
    final societyId = _societyId;
    if (societyId == null) throw Exception('No society selected');

    final ext = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : 'jpg';
    // The first segment must be the society id: storage policies check the
    // caller is an admin of it.
    final path =
        '$societyId/$facilityId/${DateTime.now().microsecondsSinceEpoch}.$ext';

    final bytes = await file.readAsBytes();
    await _client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: _contentType(ext)),
        );
    final url = _client.storage.from(_bucket).getPublicUrl(path);

    await _client.from('facility_images').insert({
      'facility_id': facilityId,
      'image_url': url,
      'storage_path': path,
      'sort_order': sortOrder,
    });
  }

  Future<void> deleteImage(FacilityImage image) async {
    await _client.from('facility_images').delete().eq('id', image.id);
    await _removeObjects([image]);
  }

  /// Gallery position; the image at 0 is the cover.
  Future<void> setImageSortOrder(String imageId, int sortOrder) async {
    await _client
        .from('facility_images')
        .update({'sort_order': sortOrder})
        .eq('id', imageId);
  }

  Future<void> _removeObjects(List<FacilityImage> images) async {
    final paths = images
        .map((i) => i.storagePath)
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .toList();
    if (paths.isEmpty) return;
    try {
      await _client.storage.from(_bucket).remove(paths);
    } catch (e) {
      // An orphaned file is harmless; failing the delete over it is not.
      debugPrint('FacilitiesService._removeObjects error: $e');
    }
  }

  String _contentType(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }
}
