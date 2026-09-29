import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/visitor_models.dart';
import 'app_lifecycle_service.dart';
import 'app_session.dart';
import 'notifications_service.dart';

/// Health of the live connection, so screens can say so rather than
/// quietly going stale.
enum LiveStatus {
  /// No subscription attempted yet.
  idle,

  /// Socket is being established or re-established.
  connecting,

  /// Subscribed; changes arrive as they happen.
  live,

  /// Subscription failed or dropped — the service is polling instead.
  degraded,
}

/// What changed on a visitor row, as seen from the gate.
class VisitorLiveEvent {
  final VisitorRecord visitor;

  /// Status before the change; null for a newly created row.
  final VisitorStatus? previousStatus;

  final bool isNew;

  const VisitorLiveEvent({
    required this.visitor,
    this.previousStatus,
    this.isNew = false,
  });

  /// A resident just answered a gate request the guard is waiting on.
  bool get isApprovalDecision =>
      !isNew &&
      previousStatus == VisitorStatus.pendingApproval &&
      (visitor.status == VisitorStatus.approved ||
          visitor.status == VisitorStatus.denied);

  /// A fresh request landed on the resident's phone.
  bool get isNewGateRequest =>
      isNew && visitor.status == VisitorStatus.pendingApproval;
}

class VisitorsService extends ChangeNotifier {
  VisitorsService._() {
    AppLifecycleService.instance.onPaused.listen((_) => _onAppPaused());
    AppLifecycleService.instance.onResumed.listen((_) => _onAppResumed());
  }
  static final VisitorsService instance = VisitorsService._();

  SupabaseClient? get _safeClient {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  SupabaseClient get _client =>
      _safeClient ?? SupabaseClient('http://localhost', 'anon');


  // Fallback select without FK join on created_by (in case the FK isn't set up)
  static const _selectBasicJoins =
      '*, flats(flat_number, blocks(name))';

  /// True only when the RPC does not exist on this database (an older
  /// schema). A refusal from an RPC that does exist must reach the user: the
  /// direct-table fallbacks below would otherwise retry the same action
  /// under different rules, or hide the server's reason.
  static bool _isMissingRpc(Object e) =>
      e is PostgrestException && (e.code == 'PGRST202' || e.code == '42883');

  /// Unwraps the `{success, error}` envelope the visitor RPCs return.
  static Map<String, dynamic> _rpcOk(dynamic res, String fallbackError) {
    if (res is Map) {
      final map = Map<String, dynamic>.from(res);
      if (map['success'] == true) return map;
      throw Exception(map['error']?.toString() ?? fallbackError);
    }
    throw Exception(fallbackError);
  }

  /// Role written into the audit trail by the direct fallbacks. The RPCs
  /// derive it on the server; this only matters on pre-RPC schemas.
  static String get _gateRole =>
      AppSession.instance.isGuard ? 'guard' : 'society_admin';

  // ── Realtime ──────────────────────────────────────────────────
  //
  // The gate flow is a conversation between two phones: the guard logs a
  // visitor, the resident answers. Polling made the guard hammer refresh
  // while a decision sat unseen. This subscribes to the `visitors` table
  // over the socket supabase_flutter already holds, so both sides see the
  // change the moment it is written.

  RealtimeChannel? _visitorsChannel;
  String? _realtimeSocietyId;
  LiveStatus _liveStatus = LiveStatus.idle;
  Timer? _pollTimer;
  Timer? _retryTimer;
  int _retryAttempt = 0;

  final _eventController = StreamController<VisitorLiveEvent>.broadcast();

  /// Fires once per visitor row change visible to this user.
  Stream<VisitorLiveEvent> get onVisitorEvent => _eventController.stream;

  final _resyncController = StreamController<void>.broadcast();

  /// Fires when the app returns from the background. The socket was closed
  /// meanwhile, so any change made then never arrived as an event — open
  /// screens should re-fetch.
  Stream<void> get onResync => _resyncController.stream;

  LiveStatus get liveStatus => _liveStatus;
  bool get isLive => _liveStatus == LiveStatus.live;

  void _setLiveStatus(LiveStatus status) {
    if (_liveStatus == status) return;
    _liveStatus = status;
    notifyListeners();
  }

  /// Subscribes to visitor changes for [societyId]. Safe to call repeatedly —
  /// re-subscribes only when the society actually changes.
  void initRealtime(String societyId) {
    if (_safeClient == null || societyId.isEmpty) return;
    if (_visitorsChannel != null && _realtimeSocietyId == societyId) return;

    _teardownChannel();
    _realtimeSocietyId = societyId;
    _setLiveStatus(LiveStatus.connecting);

    try {
      _visitorsChannel = _client
          .channel('public:visitors:$societyId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'visitors',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'society_id',
              value: societyId,
            ),
            callback: _handleVisitorChange,
          )
          .subscribe((status, error) {
            switch (status) {
              case RealtimeSubscribeStatus.subscribed:
                _retryAttempt = 0;
                _stopPolling();
                _setLiveStatus(LiveStatus.live);
                break;
              case RealtimeSubscribeStatus.channelError:
              case RealtimeSubscribeStatus.timedOut:
              case RealtimeSubscribeStatus.closed:
                debugPrint('Visitors realtime status=$status error=$error');
                _degradeToPolling();
                break;
            }
          });
    } catch (e) {
      debugPrint('Error establishing visitors realtime channel: $e');
      _degradeToPolling();
    }
  }

  Future<void> _handleVisitorChange(PostgresChangePayload payload) async {
    try {
      final newRow = payload.newRecord;
      if (newRow.isEmpty) {
        notifyListeners();
        return;
      }

      final visitorId = newRow['id']?.toString();
      if (visitorId == null || visitorId.isEmpty) return;

      final oldRow = payload.oldRecord;
      final previousStatus = (oldRow.isNotEmpty && oldRow['status'] != null)
          ? VisitorStatus.fromDb(oldRow['status']?.toString())
          : null;

      // The change payload has no joined flat/block, so re-read the row for
      // a record the UI can render in full. Fall back to the raw payload if
      // that read is refused.
      VisitorRecord record;
      try {
        final full = await _client
            .from('visitors')
            .select(_selectBasicJoins)
            .eq('id', visitorId)
            .maybeSingle();
        record = VisitorRecord.fromMap(full ?? newRow);
      } catch (_) {
        record = VisitorRecord.fromMap(newRow);
      }

      if (!_eventController.isClosed) {
        _eventController.add(VisitorLiveEvent(
          visitor: record,
          previousStatus: previousStatus,
          isNew: payload.eventType == PostgresChangeEvent.insert,
        ));
      }

      notifyListeners();
    } catch (e) {
      debugPrint('VisitorsService._handleVisitorChange error: $e');
    }
  }

  /// When the socket will not hold, fall back to a slow poll rather than
  /// leaving the guard on a frozen screen, and keep trying to get back on
  /// the socket with a backoff.
  void _degradeToPolling() {
    _setLiveStatus(LiveStatus.degraded);
    // In the background the socket is closed on purpose; polling or a
    // retry here would reopen it. Resume picks this up again.
    if (!AppLifecycleService.instance.isForeground) return;
    _startPolling();

    _retryTimer?.cancel();
    _retryAttempt = (_retryAttempt + 1).clamp(1, 6);
    final delay = Duration(seconds: 5 * (1 << (_retryAttempt - 1)));
    _retryTimer = Timer(delay, () {
      final societyId = _realtimeSocietyId;
      if (societyId == null || _liveStatus == LiveStatus.live) return;
      if (!AppLifecycleService.instance.isForeground) return;
      _teardownChannel();
      initRealtime(societyId);
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      // Listeners re-run their own fetch; this is only a heartbeat.
      notifyListeners();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _teardownChannel() {
    final channel = _visitorsChannel;
    _visitorsChannel = null;
    if (channel != null) {
      try {
        _client.removeChannel(channel);
      } catch (_) {}
    }
  }

  void _onAppPaused() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _stopPolling();
  }

  void _onAppResumed() {
    final societyId = _realtimeSocietyId;
    if (societyId == null) return;

    // supabase_flutter rejoins healthy channels itself; one that was
    // already failing when the app went away needs a fresh start.
    if (_liveStatus != LiveStatus.live) {
      _retryAttempt = 0;
      _teardownChannel();
      initRealtime(societyId);
    }
    if (!_resyncController.isClosed) _resyncController.add(null);
    notifyListeners();
  }

  /// Drops the subscription — call on sign-out.
  void disposeRealtime() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _stopPolling();
    _teardownChannel();
    _realtimeSocietyId = null;
    _retryAttempt = 0;
    _setLiveStatus(LiveStatus.idle);
  }

  @override
  void dispose() {
    disposeRealtime();
    _eventController.close();
    _resyncController.close();
    super.dispose();
  }

  /// Default page size for list screens.
  ///
  /// These queries had no limit at all, so a two-year-old society meant
  /// pulling tens of thousands of rows onto a phone every time a filter chip
  /// was tapped.
  static const int defaultPageSize = 50;

  // ── Fetch: Resident's visitors (own flat) ─────────────────────
  Future<List<VisitorRecord>> fetchResidentVisitors({
    int limit = defaultPageSize,
    int offset = 0,
  }) async {
    if (_safeClient == null) return [];

    final session = AppSession.instance;
    final flatIds = session.myResidences.map((r) => r.flatId).toSet().toList();
    if (flatIds.isEmpty) return [];

    try {
      final res = await _client
          .from('visitors')
          .select(_selectBasicJoins)
          .inFilter('flat_id', flatIds)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      final list = (res as List).cast<Map<String, dynamic>>();
      return list.map(VisitorRecord.fromMap).toList();
    } catch (e) {
      debugPrint('VisitorsService.fetchResidentVisitors error: $e');
      rethrow;
    }
  }

  // ── Fetch: Society visitors (admin) ───────────────────────────
  Future<List<VisitorRecord>> fetchSocietyVisitors({
    String? statusFilter,
    String? categoryFilter,
    String? searchQuery,
    DateTime? dateFilter,
    int limit = defaultPageSize,
    int offset = 0,
  }) async {
    if (_safeClient == null) return [];
    final societyId = AppSession.instance.societyId;
    if (societyId == null) return [];

    try {
      var query = _client
          .from('visitors')
          .select(_selectBasicJoins)
          .eq('society_id', societyId);

      if (statusFilter != null && statusFilter != 'all') {
        query = query.eq('status', statusFilter);
      }

      if (categoryFilter != null && categoryFilter != 'all') {
        query = query.eq('category', categoryFilter);
      }

      if (dateFilter != null) {
        final start = DateTime(dateFilter.year, dateFilter.month, dateFilter.day);
        final end = start.add(const Duration(days: 1));
        query = query
            .gte('created_at', start.toIso8601String())
            .lt('created_at', end.toIso8601String());
      }

      final res = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      var list = (res as List)
          .cast<Map<String, dynamic>>()
          .map(VisitorRecord.fromMap)
          .toList();

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.toLowerCase().trim();
        list = list.where((v) {
          return v.visitorName.toLowerCase().contains(q) ||
              (v.visitorPhone?.toLowerCase().contains(q) ?? false) ||
              (v.flatNumber?.toLowerCase().contains(q) ?? false) ||
              (v.companyOrContext?.toLowerCase().contains(q) ?? false) ||
              (v.approvalCode?.toLowerCase().contains(q) ?? false);
        }).toList();
      }

      return list;
    } catch (e) {
      debugPrint('VisitorsService.fetchSocietyVisitors error: $e');
      rethrow;
    }
  }

  // ── Fetch: Single visitor detail ──────────────────────────────
  Future<VisitorRecord?> fetchVisitorDetail(String visitorId) async {
    try {
      final res = await _client
          .from('visitors')
          .select(_selectBasicJoins)
          .eq('id', visitorId)
          .maybeSingle();

      if (res == null) return null;
      return VisitorRecord.fromMap(res);
    } catch (e) {
      debugPrint('VisitorsService.fetchVisitorDetail error: $e');
      rethrow;
    }
  }

  // ── Fetch: Visitor status history ─────────────────────────────
  Future<List<VisitorStatusHistoryRecord>> fetchVisitorHistory(
      String visitorId) async {
    try {
      final res = await _client
          .from('visitor_status_history')
          .select()
          .eq('visitor_id', visitorId)
          .order('created_at', ascending: true);

      final list = (res as List).cast<Map<String, dynamic>>();
      return list.map(VisitorStatusHistoryRecord.fromMap).toList();
    } catch (e) {
      debugPrint('VisitorsService.fetchVisitorHistory error: $e');
      return [];
    }
  }

  // ── Fetch: Group members for a visitor ────────────────────────
  Future<List<VisitorGroupMember>> fetchGroupMembers(String visitorId) async {
    try {
      final res = await _client
          .from('visitor_group_members')
          .select()
          .eq('visitor_id', visitorId)
          .order('created_at', ascending: true);

      final list = (res as List).cast<Map<String, dynamic>>();
      return list.map(VisitorGroupMember.fromMap).toList();
    } catch (e) {
      debugPrint('VisitorsService.fetchGroupMembers error: $e');
      return [];
    }
  }

  // ── Create: Gate-initiated visitor (Flow A) ───────────────────
  Future<String> createVisitorEntry({
    required String societyId,
    required String flatId,
    String? blockId,
    required String visitorName,
    String? visitorPhone,
    String? visitorPhotoUrl,
    String? vehicleNumber,
    required VisitorCategory category,
    String? companyOrContext,
    String? gateId,
  }) async {
    try {
      try {
        final rpcRes = await _client.rpc('create_visitor_entry', params: {
          'p_society_id': societyId,
          'p_flat_id': flatId,
          'p_block_id': blockId,
          'p_visitor_name': visitorName,
          'p_visitor_phone': visitorPhone,
          'p_visitor_photo_url': visitorPhotoUrl,
          'p_vehicle_number': vehicleNumber,
          'p_category': category.dbValue,
          'p_company_or_context': companyOrContext,
          // Only sent when set, so databases before migration 17 (which
          // have no such parameter) still resolve the function.
          'p_gate_id': ?gateId,
        });

        final map = _rpcOk(rpcRes, 'Could not log the visitor');
        notifyListeners();
        return map['visitor_id']?.toString() ?? '';
      } on PostgrestException catch (rpcError) {
        if (!_isMissingRpc(rpcError)) rethrow;
        debugPrint('create_visitor_entry RPC missing, inserting directly: $rpcError');
      }

      // Direct fallback for schemas without the RPC.
      final user = _client.auth.currentUser;
      final insertRes = await _client.from('visitors').insert({
        'society_id': societyId,
        'flat_id': flatId,
        'block_id': blockId,
        'created_by_type': _gateRole,
        'created_by': user?.id,
        'visitor_name': visitorName.trim(),
        'visitor_phone': visitorPhone?.trim(),
        'visitor_photo_url': visitorPhotoUrl,
        'vehicle_number': vehicleNumber?.trim(),
        'category': category.dbValue,
        'company_or_context': companyOrContext?.trim(),
        'entry_type': 'gate_request',
        'status': 'pending_approval',
      }).select('id').single();

      final newId = insertRes['id']?.toString() ?? '';

      // Insert initial history
      await _client.from('visitor_status_history').insert({
        'visitor_id': newId,
        'from_status': null,
        'to_status': 'pending_approval',
        'note': 'Visitor logged at gate',
        'changed_by': user?.id,
        'changed_by_role': _gateRole,
      });

      notifyListeners();
      return newId;
    } catch (e) {
      debugPrint('VisitorsService.createVisitorEntry error: $e');
      rethrow;
    }
  }

  // ── Create: Pre-approval (Flow B) ─────────────────────────────
  Future<Map<String, String>> createPreApproval({
    required String societyId,
    required String flatId,
    String? blockId,
    required String visitorName,
    String? visitorPhone,
    String? vehicleNumber,
    required VisitorCategory category,
    String? companyOrContext,
    required VisitorDurationType durationType,
    required DateTime validFrom,
    DateTime? validUntil,
    bool isPrivate = false,
    List<Map<String, String>> groupMembers = const [],
  }) async {
    try {
      try {
        final rpcRes = await _client.rpc('create_pre_approval', params: {
          'p_society_id': societyId,
          'p_flat_id': flatId,
          'p_block_id': blockId,
          'p_visitor_name': visitorName,
          'p_visitor_phone': visitorPhone,
          'p_vehicle_number': vehicleNumber,
          'p_category': category.dbValue,
          'p_company_or_context': companyOrContext,
          'p_duration_type': durationType.dbValue,
          'p_valid_from': validFrom.toIso8601String(),
          'p_valid_until': validUntil?.toIso8601String(),
          'p_is_private': isPrivate,
          'p_group_members': groupMembers
              .map((m) => {'name': m['name'], 'phone': m['phone']})
              .toList(),
        });

        final map = _rpcOk(rpcRes, 'Could not create the pre-approval');
        notifyListeners();
        return {
          'visitor_id': map['visitor_id']?.toString() ?? '',
          'approval_code': map['approval_code']?.toString() ?? '',
        };
      } on PostgrestException catch (rpcError) {
        if (!_isMissingRpc(rpcError)) rethrow;
        debugPrint('create_pre_approval RPC missing, inserting directly: $rpcError');
      }

      // Direct fallback
      final user = _client.auth.currentUser;
      final session = AppSession.instance;
      final residentId = session.myResidences
          .where((r) => r.flatId == flatId)
          .firstOrNull
          ?.id;

      final code = _generateLocalCode();
      final computedValidUntil = validUntil ??
          (durationType == VisitorDurationType.oneDay
              ? DateTime(validFrom.year, validFrom.month, validFrom.day, 23, 59, 59)
              : validFrom.add(const Duration(days: 30)));

      final insertRes = await _client.from('visitors').insert({
        'society_id': societyId,
        'flat_id': flatId,
        'block_id': blockId,
        'created_by_type': 'resident',
        'created_by': residentId ?? user?.id,
        'visitor_name': visitorName.trim(),
        'visitor_phone': visitorPhone?.trim(),
        'vehicle_number': vehicleNumber?.trim(),
        'category': category.dbValue,
        'company_or_context': companyOrContext?.trim(),
        'entry_type': 'pre_approved',
        'status': 'approved',
        'approval_code': code,
        'qr_payload': 'SAQIIT:$code',
        'duration_type': durationType.dbValue,
        'valid_from': validFrom.toIso8601String(),
        'valid_until': computedValidUntil.toIso8601String(),
        'is_private': isPrivate,
        'approved_by': user?.id,
        'approved_at': DateTime.now().toIso8601String(),
      }).select('id').single();

      final newId = insertRes['id']?.toString() ?? '';

      // Insert history
      await _client.from('visitor_status_history').insert({
        'visitor_id': newId,
        'from_status': null,
        'to_status': 'approved',
        'note': 'Pre-approval created by resident',
        'changed_by': user?.id,
        'changed_by_role': 'resident',
      });

      // Insert group members
      if (category == VisitorCategory.groupInvite && groupMembers.isNotEmpty) {
        for (final member in groupMembers) {
          await _client.from('visitor_group_members').insert({
            'visitor_id': newId,
            'guest_name': member['name']?.trim() ?? '',
            'guest_phone': member['phone']?.trim(),
          });
        }
      }

      notifyListeners();
      return {'visitor_id': newId, 'approval_code': code};
    } catch (e) {
      debugPrint('VisitorsService.createPreApproval error: $e');
      rethrow;
    }
  }

  // ── Respond: Approve / Deny ───────────────────────────────────
  Future<String?> respondToVisitorRequest({
    required String visitorId,
    required String action, // 'approved' or 'denied'
    String? deniedReason,
  }) async {
    String? codeResult;
    try {
      bool rpcSucceeded = false;
      try {
        final rpcRes = await _client.rpc('respond_to_visitor_request', params: {
          'p_visitor_id': visitorId,
          'p_action': action,
          'p_denied_reason': deniedReason,
        });

        // A refusal ("You are not a resident of this flat") is final. It
        // used to fall through to a direct update, which an admin's RLS
        // allowed — approving on the resident's behalf by accident.
        final map = _rpcOk(rpcRes, 'Could not record your answer');
        codeResult = map['approval_code']?.toString();
        rpcSucceeded = true;
      } on PostgrestException catch (rpcError) {
        if (!_isMissingRpc(rpcError)) rethrow;
        debugPrint(
            'respond_to_visitor_request RPC missing, updating directly: $rpcError');
      }

      if (!rpcSucceeded) {
        // Direct fallback
        final user = _client.auth.currentUser;

        if (action == 'approved') {
          final code = _generateLocalCode();
          await _client.from('visitors').update({
            'status': 'approved',
            'approved_by': user?.id,
            'approved_at': DateTime.now().toIso8601String(),
            'approval_code': code,
            'qr_payload': 'SAQIIT:$code',
          }).eq('id', visitorId);

          await _client.from('visitor_status_history').insert({
            'visitor_id': visitorId,
            'from_status': 'pending_approval',
            'to_status': 'approved',
            'note': 'Approved by resident',
            'changed_by': user?.id,
            'changed_by_role': 'resident',
          });

          codeResult = code;
        } else {
          if (deniedReason == null || deniedReason.trim().isEmpty) {
            throw Exception('Denial reason is required');
          }

          await _client.from('visitors').update({
            'status': 'denied',
            'denied_by': user?.id,
            'denied_at': DateTime.now().toIso8601String(),
            'denied_reason': deniedReason.trim(),
          }).eq('id', visitorId);

          await _client.from('visitor_status_history').insert({
            'visitor_id': visitorId,
            'from_status': 'pending_approval',
            'to_status': 'denied',
            'note': 'Denied: ${deniedReason.trim()}',
            'changed_by': user?.id,
            'changed_by_role': 'resident',
          });

          codeResult = null;
        }
      }

      // Automatically mark any pending approval request notifications as read
      try {
        await NotificationsService.instance.markEntityAsRead('visitor', visitorId);
      } catch (notifErr) {
        debugPrint('Error marking visitor notifications as read: $notifErr');
      }

      notifyListeners();
      return codeResult;
    } catch (e) {
      debugPrint('VisitorsService.respondToVisitorRequest error: $e');
      rethrow;
    }
  }

  // ── Check in / Check out ──────────────────────────────────────
  Future<void> checkInVisitor(String visitorId, {String? entryGate}) async {
    try {
      try {
        final rpcRes = await _client.rpc('check_in_visitor', params: {
          'p_visitor_id': visitorId,
          'p_entry_gate': entryGate,
        });
        _rpcOk(rpcRes, 'Could not check the visitor in');
        notifyListeners();
        return;
      } on PostgrestException catch (rpcError) {
        if (!_isMissingRpc(rpcError)) rethrow;
        debugPrint('check_in_visitor RPC missing, updating directly: $rpcError');
      }

      final user = _client.auth.currentUser;
      await _client.from('visitors').update({
        'status': 'checked_in',
        'checked_in_at': DateTime.now().toIso8601String(),
        'checked_in_by': user?.id,
        'entry_gate': entryGate,
      }).eq('id', visitorId);

      await _client.from('visitor_status_history').insert({
        'visitor_id': visitorId,
        'from_status': 'approved',
        'to_status': 'checked_in',
        'note': entryGate != null ? 'Checked in at $entryGate' : 'Checked in',
        'changed_by': user?.id,
        'changed_by_role': _gateRole,
      });
      notifyListeners();
    } catch (e) {
      debugPrint('VisitorsService.checkInVisitor error: $e');
      rethrow;
    }
  }

  Future<void> checkOutVisitor(String visitorId) async {
    try {
      try {
        final rpcRes = await _client.rpc('check_out_visitor', params: {
          'p_visitor_id': visitorId,
        });
        _rpcOk(rpcRes, 'Could not check the visitor out');
        notifyListeners();
        return;
      } on PostgrestException catch (rpcError) {
        if (!_isMissingRpc(rpcError)) rethrow;
        debugPrint('check_out_visitor RPC missing, updating directly: $rpcError');
      }

      final user = _client.auth.currentUser;
      await _client.from('visitors').update({
        'status': 'checked_out',
        'checked_out_at': DateTime.now().toIso8601String(),
        'checked_out_by': user?.id,
      }).eq('id', visitorId);

      await _client.from('visitor_status_history').insert({
        'visitor_id': visitorId,
        'from_status': 'checked_in',
        'to_status': 'checked_out',
        'note': 'Checked out',
        'changed_by': user?.id,
        'changed_by_role': _gateRole,
      });
      notifyListeners();
    } catch (e) {
      debugPrint('VisitorsService.checkOutVisitor error: $e');
      rethrow;
    }
  }

  // ── Cancel pre-approval ───────────────────────────────────────
  Future<void> cancelPreApproval(String visitorId) async {
    try {
      try {
        final rpcRes = await _client.rpc('cancel_pre_approval', params: {
          'p_visitor_id': visitorId,
        });
        _rpcOk(rpcRes, 'Could not cancel the pre-approval');
        notifyListeners();
        return;
      } on PostgrestException catch (rpcError) {
        if (!_isMissingRpc(rpcError)) rethrow;
        debugPrint('cancel_pre_approval RPC missing, updating directly: $rpcError');
      }

      final user = _client.auth.currentUser;
      await _client.from('visitors').update({
        'status': 'cancelled',
      }).eq('id', visitorId);

      await _client.from('visitor_status_history').insert({
        'visitor_id': visitorId,
        'from_status': 'approved',
        'to_status': 'cancelled',
        'note': 'Cancelled by resident',
        'changed_by': user?.id,
        'changed_by_role': 'resident',
      });
      notifyListeners();
    } catch (e) {
      debugPrint('VisitorsService.cancelPreApproval error: $e');
      rethrow;
    }
  }

  // ── Verify pre-approval by code ───────────────────────────────
  Future<Map<String, dynamic>?> verifyPreApproval(String approvalCode) async {
    try {
      try {
        final rpcRes = await _client.rpc('verify_pre_approval', params: {
          'p_approval_code': approvalCode.trim().toUpperCase(),
          'p_society_id': AppSession.instance.societyId,
        });
        // "Too many attempts" and "expired" must reach the gate as said.
        // Falling back to a direct lookup here would also sidestep the
        // server's attempt throttle.
        return _rpcOk(rpcRes, 'No valid visitor found for this code');
      } on PostgrestException catch (rpcError) {
        if (!_isMissingRpc(rpcError)) rethrow;
        debugPrint('verify_pre_approval RPC missing, querying directly: $rpcError');
      }

      // Direct fallback for databases without the RPC. RLS scopes this to
      // the caller's own society, but the validity rules the RPC enforces
      // have to be repeated here or an expired pass would still verify.
      final res = await _client
          .from('visitors')
          .select(_selectBasicJoins)
          .eq('approval_code', approvalCode.trim().toUpperCase())
          .maybeSingle();

      if (res == null) return null;

      final visitor = VisitorRecord.fromMap(res);

      const deadStatuses = {
        VisitorStatus.denied,
        VisitorStatus.cancelled,
        VisitorStatus.expired,
        VisitorStatus.checkedOut,
      };
      if (deadStatuses.contains(visitor.status)) {
        throw Exception(
            'This pass is no longer valid (${visitor.status.label})');
      }
      if (!visitor.isWithinValidity) {
        throw Exception('This pass has expired');
      }

      final members = await fetchGroupMembers(visitor.id);

      return {
        'success': true,
        'visitor': res,
        'flat_number': visitor.flatNumber,
        'block_name': visitor.blockName,
        'group_members': members
            .map((m) => {
                  'id': m.id,
                  'guest_name': m.guestName,
                  'guest_phone': m.guestPhone,
                })
            .toList(),
      };
    } catch (e) {
      debugPrint('VisitorsService.verifyPreApproval error: $e');
      rethrow;
    }
  }

  // ── Upload visitor photo ──────────────────────────────────────
  Future<String?> uploadVisitorPhoto({
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    final user = _client.auth.currentUser;
    final userId = user?.id ?? 'anon';
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${(1000 + (DateTime.now().microsecond % 9000))}.$fileExtension';
    final filePath = '$userId/$fileName';

    // 1. Try 'visitor-photos' bucket
    try {
      await _client.storage.from('visitor-photos').uploadBinary(
            filePath,
            bytes,
            fileOptions: FileOptions(
              contentType: 'image/$fileExtension',
              upsert: true,
            ),
          );
      final publicUrl =
          _client.storage.from('visitor-photos').getPublicUrl(filePath);
      return publicUrl;
    } catch (e) {
      debugPrint('visitor-photos upload failed: $e. Trying fallback bucket...');
    }

    // 2. Try 'complaint-photos' fallback bucket
    try {
      await _client.storage.from('complaint-photos').uploadBinary(
            'visitors/$filePath',
            bytes,
            fileOptions: FileOptions(
              contentType: 'image/$fileExtension',
              upsert: true,
            ),
          );
      final publicUrl = _client.storage
          .from('complaint-photos')
          .getPublicUrl('visitors/$filePath');
      return publicUrl;
    } catch (e) {
      debugPrint('complaint-photos fallback upload failed: $e');
    }

    // No third fallback on purpose.
    //
    // This used to base64-encode the image into the returned string, which
    // then landed in visitors.visitor_photo_url — a Postgres text column
    // dragged into every list query. Because it was silent, a misconfigured
    // bucket could make that the normal path for months.
    //
    // Returning null lets the caller save the visitor without a photo and
    // say so, which is the honest outcome.
    debugPrint('All visitor photo uploads failed; saving without a photo.');
    return null;
  }

  // ── Stats ─────────────────────────────────────────────────────
  Future<int> getTodaysVisitorCount() async {
    final societyId = AppSession.instance.societyId;
    if (societyId == null) return 0;

    try {
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day);

      final res = await _client
          .from('visitors')
          .select('id')
          .eq('society_id', societyId)
          .gte('created_at', start.toIso8601String());

      return (res as List).length;
    } catch (e) {
      debugPrint('VisitorsService.getTodaysVisitorCount error: $e');
      return 0;
    }
  }

  Future<int> getPendingApprovalCount() async {
    final session = AppSession.instance;
    final flatIds = session.myResidences.map((r) => r.flatId).toSet().toList();
    if (flatIds.isEmpty) return 0;

    try {
      final res = await _client
          .from('visitors')
          .select('id')
          .inFilter('flat_id', flatIds)
          .eq('status', 'pending_approval')
          .eq('entry_type', 'gate_request');

      return (res as List).length;
    } catch (e) {
      debugPrint('VisitorsService.getPendingApprovalCount error: $e');
      return 0;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────
  String _generateLocalCode() {
    final rng = Random.secure();
    return List.generate(6, (_) => rng.nextInt(10)).join();
  }
}
