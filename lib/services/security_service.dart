import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/security_models.dart';
import 'app_session.dart';

class SecurityService extends ChangeNotifier {
  SecurityService._();
  static final SecurityService instance = SecurityService._();

  SupabaseClient? get _safeClient {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  SupabaseClient get _client =>
      _safeClient ?? SupabaseClient('http://localhost', 'anon');

  RealtimeChannel? _sosChannel;
  final StreamController<SosAlert> _sosEventController =
      StreamController<SosAlert>.broadcast();

  Stream<SosAlert> get onSosAlertReceived => _sosEventController.stream;

  List<SosAlert> _activeSosAlerts = [];
  List<SosAlert> get activeSosAlerts => List.unmodifiable(_activeSosAlerts);

  bool _initializedRealtime = false;

  // ─────────────────────────────────────────────────────────────
  // 1. Categories
  // ─────────────────────────────────────────────────────────────

  Future<List<EmergencyCategory>> fetchCategories(String societyId) async {
    if (_safeClient == null) return [];
    try {
      final res = await _client
          .from('emergency_contact_categories')
          .select()
          .or('is_global.eq.true,society_id.eq.$societyId')
          .order('sort_order', ascending: true);

      final list = (res as List).cast<Map<String, dynamic>>();
      return list.map(EmergencyCategory.fromMap).toList();
    } catch (e) {
      debugPrint('SecurityService.fetchCategories error: $e');
      return [];
    }
  }

  Future<EmergencyCategory?> createCategory({
    required String societyId,
    required String name,
    required String iconKey,
    int sortOrder = 0,
  }) async {
    if (_safeClient == null) return null;
    try {
      final res = await _client
          .from('emergency_contact_categories')
          .insert({
            'society_id': societyId,
            'name': name.trim(),
            'icon_key': iconKey,
            'sort_order': sortOrder,
            'is_global': false,
          })
          .select()
          .single();

      notifyListeners();
      return EmergencyCategory.fromMap(res);
    } catch (e) {
      debugPrint('SecurityService.createCategory error: $e');
      rethrow;
    }
  }

  Future<void> updateCategory({
    required String categoryId,
    required String name,
    required String iconKey,
    required int sortOrder,
  }) async {
    if (_safeClient == null) return;
    try {
      await _client.from('emergency_contact_categories').update({
        'name': name.trim(),
        'icon_key': iconKey,
        'sort_order': sortOrder,
      }).eq('id', categoryId);

      notifyListeners();
    } catch (e) {
      debugPrint('SecurityService.updateCategory error: $e');
      rethrow;
    }
  }

  Future<void> deleteCategory(String categoryId) async {
    if (_safeClient == null) return;
    try {
      await _client
          .from('emergency_contact_categories')
          .delete()
          .eq('id', categoryId)
          .eq('is_global', false);

      notifyListeners();
    } catch (e) {
      debugPrint('SecurityService.deleteCategory error: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 2. Contacts
  // ─────────────────────────────────────────────────────────────

  static const _selectContactWithCategory =
      '*, emergency_contact_categories(name, icon_key)';

  Future<List<EmergencyContact>> fetchContacts(
    String societyId, {
    bool activeOnly = false,
  }) async {
    if (_safeClient == null) return [];
    try {
      var query = _client
          .from('emergency_contacts')
          .select(_selectContactWithCategory)
          .or('is_global.eq.true,society_id.eq.$societyId');

      if (activeOnly) {
        query = query.eq('is_active', true);
      }

      final res = await query.order('sort_order', ascending: true);
      final list = (res as List).cast<Map<String, dynamic>>();
      return list.map(EmergencyContact.fromMap).toList();
    } catch (e) {
      debugPrint('SecurityService.fetchContacts error: $e');
      return [];
    }
  }

  Future<EmergencyContact?> createContact({
    required String societyId,
    required String categoryId,
    required String name,
    String? designation,
    required String phoneNumber,
    String? alternatePhoneNumber,
    String? photoUrl,
    String availability = '24/7',
    int sortOrder = 0,
  }) async {
    if (_safeClient == null) return null;
    try {
      final user = _client.auth.currentUser;
      final res = await _client
          .from('emergency_contacts')
          .insert({
            'society_id': societyId,
            'category_id': categoryId,
            'name': name.trim(),
            'designation': designation?.trim(),
            'phone_number': phoneNumber.trim(),
            'alternate_phone_number': alternatePhoneNumber?.trim().isNotEmpty == true
                ? alternatePhoneNumber!.trim()
                : null,
            'photo_url': photoUrl,
            'availability': availability.trim(),
            'is_active': true,
            'is_global': false,
            'sort_order': sortOrder,
            'created_by': user?.id,
          })
          .select(_selectContactWithCategory)
          .single();

      notifyListeners();
      return EmergencyContact.fromMap(res);
    } catch (e) {
      debugPrint('SecurityService.createContact error: $e');
      rethrow;
    }
  }

  Future<void> updateContact({
    required String contactId,
    required String categoryId,
    required String name,
    String? designation,
    required String phoneNumber,
    String? alternatePhoneNumber,
    String? photoUrl,
    String availability = '24/7',
    int sortOrder = 0,
    bool isActive = true,
  }) async {
    if (_safeClient == null) return;
    try {
      await _client.from('emergency_contacts').update({
        'category_id': categoryId,
        'name': name.trim(),
        'designation': designation?.trim(),
        'phone_number': phoneNumber.trim(),
        'alternate_phone_number': alternatePhoneNumber?.trim().isNotEmpty == true
            ? alternatePhoneNumber!.trim()
            : null,
        if (photoUrl != null) 'photo_url': photoUrl,
        'availability': availability.trim(),
        'sort_order': sortOrder,
        'is_active': isActive,
      }).eq('id', contactId);

      notifyListeners();
    } catch (e) {
      debugPrint('SecurityService.updateContact error: $e');
      rethrow;
    }
  }

  Future<void> toggleContactActive(String contactId, bool isActive) async {
    if (_safeClient == null) return;
    try {
      await _client
          .from('emergency_contacts')
          .update({'is_active': isActive})
          .eq('id', contactId);

      notifyListeners();
    } catch (e) {
      debugPrint('SecurityService.toggleContactActive error: $e');
      rethrow;
    }
  }

  Future<void> deleteContact(String contactId) async {
    if (_safeClient == null) return;
    try {
      await _client
          .from('emergency_contacts')
          .delete()
          .eq('id', contactId)
          .eq('is_global', false);

      notifyListeners();
    } catch (e) {
      debugPrint('SecurityService.deleteContact error: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 3. Dialing & Call Logs
  // ─────────────────────────────────────────────────────────────

  /// Launches the native phone dialer with `tel:` URI and asynchronously logs
  /// the call attempt without blocking or interrupting the call.
  Future<bool> launchCall({
    required String phoneNumber,
    String? societyId,
    String? contactId,
    String? flatId,
  }) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri(scheme: 'tel', path: cleanPhone);

    // 1. Asynchronously log attempt (fire-and-forget)
    if (societyId != null && contactId != null && flatId != null) {
      unawaited(_logCallAttempt(
        societyId: societyId,
        contactId: contactId,
        flatId: flatId,
      ));
    }

    // 2. Launch phone dialer
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri);
      } else {
        // Fallback for devices without standard dialer handler
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('SecurityService.launchCall error: $e');
      return false;
    }
  }

  Future<void> _logCallAttempt({
    required String societyId,
    required String contactId,
    required String flatId,
  }) async {
    if (_safeClient == null) return;
    try {
      await _client.rpc('log_emergency_call_attempt', params: {
        'p_society_id': societyId,
        'p_contact_id': contactId,
        'p_flat_id': flatId,
      });
    } catch (e) {
      debugPrint('SecurityService._logCallAttempt fallback direct insert: $e');
      try {
        final user = _client.auth.currentUser;
        if (user != null) {
          await _client.from('emergency_contact_call_logs').insert({
            'society_id': societyId,
            'contact_id': contactId,
            'flat_id': flatId,
            'caller_type': AppSession.instance.isAdmin ? 'society_admin' : 'resident',
            'caller_id': user.id,
          });
        }
      } catch (insertErr) {
        debugPrint('Direct call log insert error: $insertErr');
      }
    }
  }

  static const _selectCallLogsWithJoins =
      '*, emergency_contacts(name, designation, phone_number, emergency_contact_categories(name)), flats(flat_number, blocks(name))';

  Future<List<EmergencyCallLog>> fetchMyCallLogs(List<String> flatIds) async {
    if (_safeClient == null || flatIds.isEmpty) return [];
    try {
      final res = await _client
          .from('emergency_contact_call_logs')
          .select(_selectCallLogsWithJoins)
          .inFilter('flat_id', flatIds)
          .order('called_at', ascending: false)
          .limit(100);

      final list = (res as List).cast<Map<String, dynamic>>();
      return list.map(EmergencyCallLog.fromMap).toList();
    } catch (e) {
      debugPrint('SecurityService.fetchMyCallLogs error: $e');
      return [];
    }
  }

  Future<List<EmergencyCallLog>> fetchSocietyCallLogs(
    String societyId, {
    String? contactId,
    String? flatId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (_safeClient == null) return [];
    try {
      var query = _client
          .from('emergency_contact_call_logs')
          .select(_selectCallLogsWithJoins)
          .eq('society_id', societyId);

      if (contactId != null && contactId.isNotEmpty) {
        query = query.eq('contact_id', contactId);
      }
      if (flatId != null && flatId.isNotEmpty) {
        query = query.eq('flat_id', flatId);
      }
      if (startDate != null) {
        query = query.gte('called_at', startDate.toIso8601String());
      }
      if (endDate != null) {
        query = query.lte('called_at', endDate.toIso8601String());
      }

      final res = await query.order('called_at', ascending: false).limit(250);
      final list = (res as List).cast<Map<String, dynamic>>();
      return list.map(EmergencyCallLog.fromMap).toList();
    } catch (e) {
      debugPrint('SecurityService.fetchSocietyCallLogs error: $e');
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 4. SOS Alerts
  // ─────────────────────────────────────────────────────────────

  static const _selectSosWithJoins =
      '*, flats(flat_number, blocks(name)), residents(full_name, phone)';

  Future<Map<String, dynamic>> raiseSosAlert({
    required String societyId,
    required String flatId,
    required SosAlertType alertType,
    String? note,
  }) async {
    if (_safeClient == null) {
      return {'success': false, 'error': 'Database client unavailable'};
    }
    try {
      final res = await _client.rpc('raise_sos_alert', params: {
        'p_society_id': societyId,
        'p_flat_id': flatId,
        'p_alert_type': alertType.toDbValue(),
        'p_note': note?.trim().isNotEmpty == true ? note!.trim() : null,
      });

      final map = res is Map<String, dynamic>
          ? res
          : Map<String, dynamic>.from(res as Map);

      await refreshActiveAlerts(societyId);
      return map;
    } catch (e) {
      debugPrint('SecurityService.raiseSosAlert error: $e');
      rethrow;
    }
  }

  Future<void> acknowledgeSosAlert(String alertId, {String? note}) async {
    if (_safeClient == null) return;
    try {
      await _client.rpc('acknowledge_sos_alert', params: {
        'p_alert_id': alertId,
        'p_note': note?.trim(),
      });

      final societyId = AppSession.instance.societyId;
      if (societyId != null) {
        await refreshActiveAlerts(societyId);
      }
    } catch (e) {
      debugPrint('SecurityService.acknowledgeSosAlert error: $e');
      rethrow;
    }
  }

  Future<void> resolveSosAlert(String alertId, {String? note}) async {
    if (_safeClient == null) return;
    try {
      await _client.rpc('resolve_sos_alert', params: {
        'p_alert_id': alertId,
        'p_note': note?.trim(),
      });

      final societyId = AppSession.instance.societyId;
      if (societyId != null) {
        await refreshActiveAlerts(societyId);
      }
    } catch (e) {
      debugPrint('SecurityService.resolveSosAlert error: $e');
      rethrow;
    }
  }

  Future<void> cancelSosAlert(String alertId, {String? note}) async {
    if (_safeClient == null) return;
    try {
      await _client.rpc('cancel_sos_alert', params: {
        'p_alert_id': alertId,
        'p_note': note?.trim(),
      });

      final societyId = AppSession.instance.societyId;
      if (societyId != null) {
        await refreshActiveAlerts(societyId);
      }
    } catch (e) {
      debugPrint('SecurityService.cancelSosAlert error: $e');
      rethrow;
    }
  }

  Future<List<SosAlert>> fetchMyActiveSosAlerts(List<String> flatIds) async {
    if (_safeClient == null || flatIds.isEmpty) return [];
    try {
      final res = await _client
          .from('sos_alerts')
          .select(_selectSosWithJoins)
          .inFilter('flat_id', flatIds)
          .inFilter('status', ['active', 'acknowledged'])
          .order('created_at', ascending: false);

      final list = (res as List).cast<Map<String, dynamic>>();
      return list.map(SosAlert.fromMap).toList();
    } catch (e) {
      debugPrint('SecurityService.fetchMyActiveSosAlerts error: $e');
      return [];
    }
  }

  Future<List<SosAlert>> fetchMySosHistory(List<String> flatIds) async {
    if (_safeClient == null || flatIds.isEmpty) return [];
    try {
      final res = await _client
          .from('sos_alerts')
          .select(_selectSosWithJoins)
          .inFilter('flat_id', flatIds)
          .order('created_at', ascending: false)
          .limit(50);

      final list = (res as List).cast<Map<String, dynamic>>();
      return list.map(SosAlert.fromMap).toList();
    } catch (e) {
      debugPrint('SecurityService.fetchMySosHistory error: $e');
      return [];
    }
  }

  Future<List<SosAlert>> fetchSocietySosAlerts(
    String societyId, {
    String? statusFilter,
  }) async {
    if (_safeClient == null) return [];
    try {
      var query = _client
          .from('sos_alerts')
          .select(_selectSosWithJoins)
          .eq('society_id', societyId);

      if (statusFilter != null && statusFilter != 'all') {
        query = query.eq('status', statusFilter);
      }

      final res = await query.order('created_at', ascending: false).limit(100);
      final list = (res as List).cast<Map<String, dynamic>>();
      return list.map(SosAlert.fromMap).toList();
    } catch (e) {
      debugPrint('SecurityService.fetchSocietySosAlerts error: $e');
      return [];
    }
  }

  Future<List<SosStatusHistory>> fetchSosHistoryTrail(String sosAlertId) async {
    if (_safeClient == null) return [];
    try {
      final res = await _client
          .from('sos_alert_status_history')
          .select()
          .eq('sos_alert_id', sosAlertId)
          .order('created_at', ascending: true);

      final list = (res as List).cast<Map<String, dynamic>>();
      return list.map(SosStatusHistory.fromMap).toList();
    } catch (e) {
      debugPrint('SecurityService.fetchSosHistoryTrail error: $e');
      return [];
    }
  }

  Future<void> refreshActiveAlerts(String societyId) async {
    if (_safeClient == null) return;
    try {
      final res = await _client
          .from('sos_alerts')
          .select(_selectSosWithJoins)
          .eq('society_id', societyId)
          .inFilter('status', ['active', 'acknowledged'])
          .order('created_at', ascending: false);

      final list = (res as List).cast<Map<String, dynamic>>();
      _activeSosAlerts = list.map(SosAlert.fromMap).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('SecurityService.refreshActiveAlerts error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 5. Realtime Subscriptions
  // ─────────────────────────────────────────────────────────────

  void initRealtime(String societyId) {
    if (_initializedRealtime || _safeClient == null) return;
    _initializedRealtime = true;

    refreshActiveAlerts(societyId);

    try {
      _sosChannel = _client
          .channel('public:sos_alerts:$societyId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'sos_alerts',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'society_id',
              value: societyId,
            ),
            callback: (payload) async {
              debugPrint('SOS Realtime Event: ${payload.eventType}');
              await refreshActiveAlerts(societyId);

              // If an insert or change to 'active' occurred, dispatch event
              final record = payload.newRecord;
              if (record.isNotEmpty) {
                try {
                  final alertId = record['id']?.toString();
                  if (alertId != null) {
                    final fullRes = await _client
                        .from('sos_alerts')
                        .select(_selectSosWithJoins)
                        .eq('id', alertId)
                        .maybeSingle();

                    if (fullRes != null) {
                      final alert = SosAlert.fromMap(fullRes);
                      _sosEventController.add(alert);
                    }
                  }
                } catch (e) {
                  debugPrint('Error fetching full realtime alert: $e');
                }
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Error establishing SOS realtime channel: $e');
    }
  }

  @override
  void dispose() {
    _sosChannel?.unsubscribe();
    _sosEventController.close();
    super.dispose();
  }
}
