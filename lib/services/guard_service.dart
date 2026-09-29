import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/guard_models.dart';
import '../models/visitor_models.dart';
import 'app_session.dart';

/// Everything the gate does that is not already a visitor or vehicle
/// operation: which gate this phone is on, the live queues, calling a flat,
/// recording a decision taken on the phone — plus the admin side that
/// creates guards and gates.
///
/// Every write here goes through a security-definer RPC or an admin-only
/// table (migrations 17 and 18). Nothing on this side decides who may do
/// what; the server does.
class GuardService extends ChangeNotifier {
  GuardService._();
  static final GuardService instance = GuardService._();

  SupabaseClient? get _safeClient {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static const _gatePrefKey = 'guard_current_gate_id';
  static const _visitorJoins = '*, flats(flat_number, blocks(name))';

  // ─────────────────────────────────────────────────────────────
  // 1. Gate on duty
  // ─────────────────────────────────────────────────────────────

  List<SocietyGate> _gates = const [];
  String? _currentGateId;

  /// Active gates of the guard's society.
  List<SocietyGate> get gates => _gates;

  /// The gate this phone is working. Remembered per device, because a gate
  /// phone usually stays at one gate while guards rotate through it.
  SocietyGate? get currentGate {
    for (final g in _gates) {
      if (g.id == _currentGateId) return g;
    }
    return null;
  }

  Future<void> loadGates() async {
    final client = _safeClient;
    final societyId = AppSession.instance.societyId;
    if (client == null || societyId == null) return;

    try {
      final res = await client
          .from('society_gates')
          .select()
          .eq('society_id', societyId)
          .eq('is_active', true)
          .order('sort_order')
          .order('name');
      _gates = (res as List)
          .cast<Map<String, dynamic>>()
          .map(SocietyGate.fromMap)
          .toList();
    } catch (e) {
      debugPrint('GuardService.loadGates error: $e');
      _gates = const [];
    }

    String? saved;
    try {
      final prefs = await SharedPreferences.getInstance();
      saved = prefs.getString(_gatePrefKey);
    } catch (_) {}

    final ids = _gates.map((g) => g.id).toSet();
    final fallback = AppSession.instance.guardProfile?.defaultGateId;
    _currentGateId = ids.contains(saved)
        ? saved
        : ids.contains(fallback)
        ? fallback
        : (_gates.isNotEmpty ? _gates.first.id : null);
    notifyListeners();
  }

  Future<void> selectGate(String gateId) async {
    if (_currentGateId == gateId) return;
    _currentGateId = gateId;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_gatePrefKey, gateId);
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────
  // 2. Gate queues
  // ─────────────────────────────────────────────────────────────

  /// Walk-ins still waiting for the flat to answer.
  Future<List<VisitorRecord>> fetchWaitingRequests() async {
    final client = _safeClient;
    final societyId = AppSession.instance.societyId;
    if (client == null || societyId == null) return [];

    final since = DateTime.now().subtract(const Duration(hours: 12));
    final res = await client
        .from('visitors')
        .select(_visitorJoins)
        .eq('society_id', societyId)
        .eq('entry_type', 'gate_request')
        .eq('status', 'pending_approval')
        .gte('created_at', since.toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .limit(50);
    return (res as List)
        .cast<Map<String, dynamic>>()
        .map(VisitorRecord.fromMap)
        .toList();
  }

  /// Everyone checked in and not yet out — oldest first, so the visitor
  /// most likely to be overstaying is at the top.
  Future<List<VisitorRecord>> fetchInside() async {
    final client = _safeClient;
    final societyId = AppSession.instance.societyId;
    if (client == null || societyId == null) return [];

    final res = await client
        .from('visitors')
        .select(_visitorJoins)
        .eq('society_id', societyId)
        .eq('status', 'checked_in')
        .order('checked_in_at', ascending: true)
        .limit(200);
    return (res as List)
        .cast<Map<String, dynamic>>()
        .map(VisitorRecord.fromMap)
        .toList();
  }

  /// Today's register: anyone logged today, plus pre-approved visitors
  /// created earlier who came through the gate today.
  Future<List<VisitorRecord>> fetchTodayLog() async {
    final client = _safeClient;
    final societyId = AppSession.instance.societyId;
    if (client == null || societyId == null) return [];

    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).toUtc().toIso8601String();
    final res = await client
        .from('visitors')
        .select(_visitorJoins)
        .eq('society_id', societyId)
        .or('created_at.gte."$start",checked_in_at.gte."$start"')
        .order('created_at', ascending: false)
        .limit(200);
    return (res as List)
        .cast<Map<String, dynamic>>()
        .map(VisitorRecord.fromMap)
        .toList();
  }

  /// Pre-approvals active now or starting within 12 hours. No codes.
  Future<List<ExpectedVisitor>> fetchExpectedVisitors() async {
    final client = _safeClient;
    final societyId = AppSession.instance.societyId;
    if (client == null || societyId == null) return [];

    final res = await client.rpc(
      'fetch_expected_visitors',
      params: {'p_society_id': societyId},
    );
    final map = _ok(res, 'Could not load expected visitors');
    final list = (map['visitors'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    return list.map(ExpectedVisitor.fromMap).toList();
  }

  // ─────────────────────────────────────────────────────────────
  // 3. Calling a flat
  // ─────────────────────────────────────────────────────────────

  /// Asks the server for the flat's number (logged against this guard) and
  /// opens the dialer. The number is never listed anywhere in the app.
  Future<GuardCallResult> callFlat({
    required String flatId,
    String reason = 'other',
    String? visitorId,
  }) async {
    final client = _safeClient;
    if (client == null) throw Exception('Not connected');

    final res = await client.rpc(
      'guard_call_flat',
      params: {
        'p_flat_id': flatId,
        'p_reason': reason,
        'p_visitor_id': ?visitorId,
      },
    );
    final map = _ok(res, 'Could not get the flat\'s number');
    final phone = map['phone']?.toString() ?? '';
    final opened = await _dial(phone);

    return GuardCallResult(
      phone: phone,
      residentFirstName: map['resident_first_name']?.toString(),
      callLogId: map['call_log_id']?.toString(),
      dialerOpened: opened,
    );
  }

  /// Whether this guard logged a call about [visitorId] recently enough for
  /// the server to accept a phone decision (the window is 15 minutes).
  Future<bool> hasRecentCall(String visitorId) async {
    final client = _safeClient;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return false;
    try {
      final since = DateTime.now().subtract(const Duration(minutes: 14));
      final res = await client
          .from('guard_call_logs')
          .select('id')
          .eq('visitor_id', visitorId)
          .eq('caller_id', userId)
          .gte('called_at', since.toUtc().toIso8601String())
          .limit(1);
      return (res as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _dial(String phone) async {
    final uri = Uri(
      scheme: 'tel',
      path: phone.replaceAll(RegExp(r'[^\d+]'), ''),
    );
    try {
      // canLaunchUrl can say no while a dialer exists (package visibility),
      // so it is only a hint.
      if (await canLaunchUrl(uri) && await launchUrl(uri)) return true;
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('GuardService._dial error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 4. Closing a gate request from the gate
  // ─────────────────────────────────────────────────────────────

  /// Records what the resident said on the phone, or that nobody answered.
  ///
  /// The server only accepts approved / denied after a call this guard
  /// logged to the flat in the last 15 minutes, and tells the flat what was
  /// recorded. Returns the approval code for an approval.
  Future<String?> resolveGateRequest({
    required String visitorId,
    required GateDecision decision,
    String? note,
  }) async {
    final client = _safeClient;
    if (client == null) throw Exception('Not connected');

    final res = await client.rpc(
      'guard_resolve_gate_request',
      params: {
        'p_visitor_id': visitorId,
        'p_action': decision.dbValue,
        'p_note': (note != null && note.trim().isNotEmpty) ? note.trim() : null,
      },
    );
    final map = _ok(res, 'Could not record the decision');
    notifyListeners();
    return map['approval_code']?.toString();
  }

  // ─────────────────────────────────────────────────────────────
  // 5. Admin: guards
  // ─────────────────────────────────────────────────────────────

  static const _guardSelect = '*, default_gate:society_gates(id, name)';

  Future<List<GuardProfile>> fetchGuards() async {
    final client = _safeClient;
    final societyId = AppSession.instance.societyId;
    if (client == null || societyId == null) return [];

    final res = await client
        .from('society_guards')
        .select(_guardSelect)
        .eq('society_id', societyId)
        .order('status')
        .order('full_name');
    return (res as List)
        .cast<Map<String, dynamic>>()
        .map(GuardProfile.fromMap)
        .toList();
  }

  /// Adds a guard. They are linked to an account when they sign in with
  /// [email]; until then [GuardProfile.isLinked] is false.
  Future<GuardProfile> createGuard({
    required String fullName,
    required String email,
    required String phone,
    String? agencyName,
    String? employeeCode,
    String? defaultGateId,
  }) async {
    final client = _safeClient;
    final societyId = AppSession.instance.societyId;
    if (client == null || societyId == null) {
      throw Exception('This account is not linked to a society');
    }

    final res = await client
        .from('society_guards')
        .insert({
          'society_id': societyId,
          'full_name': fullName.trim(),
          'email': email.trim().toLowerCase(),
          'phone': phone.trim(),
          'agency_name': _nullIfBlank(agencyName),
          'employee_code': _nullIfBlank(employeeCode),
          'default_gate_id': defaultGateId,
        })
        .select(_guardSelect)
        .single();
    notifyListeners();
    return GuardProfile.fromMap(res);
  }

  Future<void> updateGuard(
    String guardId, {
    required String fullName,
    required String email,
    required String phone,
    String? agencyName,
    String? employeeCode,
    String? defaultGateId,
  }) async {
    final client = _safeClient;
    if (client == null) return;

    await client
        .from('society_guards')
        .update({
          'full_name': fullName.trim(),
          'email': email.trim().toLowerCase(),
          'phone': phone.trim(),
          'agency_name': _nullIfBlank(agencyName),
          'employee_code': _nullIfBlank(employeeCode),
          'default_gate_id': defaultGateId,
        })
        .eq('id', guardId);
    notifyListeners();
  }

  /// Switching a guard off takes effect on their next request: every policy
  /// checks `status = 'active'`.
  Future<void> setGuardActive(String guardId, bool active) async {
    final client = _safeClient;
    if (client == null) return;

    await client
        .from('society_guards')
        .update({'status': active ? 'active' : 'inactive'})
        .eq('id', guardId);
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────
  // 6. Admin: gates
  // ─────────────────────────────────────────────────────────────

  /// All gates including disabled ones, for the admin screen.
  Future<List<SocietyGate>> fetchAllGates() async {
    final client = _safeClient;
    final societyId = AppSession.instance.societyId;
    if (client == null || societyId == null) return [];

    final res = await client
        .from('society_gates')
        .select()
        .eq('society_id', societyId)
        .order('sort_order')
        .order('name');
    return (res as List)
        .cast<Map<String, dynamic>>()
        .map(SocietyGate.fromMap)
        .toList();
  }

  Future<void> createGate(String name) async {
    final client = _safeClient;
    final societyId = AppSession.instance.societyId;
    if (client == null || societyId == null) return;

    await client.from('society_gates').insert({
      'society_id': societyId,
      'name': name.trim(),
    });
    notifyListeners();
  }

  Future<void> updateGate(String gateId, {String? name, bool? isActive}) async {
    final client = _safeClient;
    if (client == null) return;

    await client
        .from('society_gates')
        .update({if (name != null) 'name': name.trim(), 'is_active': ?isActive})
        .eq('id', gateId);
    notifyListeners();
  }

  /// Clears per-session state on sign-out. The saved gate stays: it belongs
  /// to the device, not the guard.
  void reset() {
    _gates = const [];
    _currentGateId = null;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────

  /// Unwraps the `{success, error, ...}` envelope the gate RPCs return.
  /// A refusal becomes an exception with the server's own words.
  static Map<String, dynamic> _ok(dynamic res, String fallbackError) {
    if (res is Map) {
      final map = Map<String, dynamic>.from(res);
      if (map['success'] == true) return map;
      throw Exception(map['error']?.toString() ?? fallbackError);
    }
    throw Exception(fallbackError);
  }

  static String? _nullIfBlank(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
