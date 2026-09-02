import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/visitor_models.dart';
import 'app_session.dart';
import 'notifications_service.dart';

class VisitorsService extends ChangeNotifier {
  VisitorsService._();
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

  // ── Fetch: Resident's visitors (own flat) ─────────────────────
  Future<List<VisitorRecord>> fetchResidentVisitors() async {
    if (_safeClient == null) return [];

    final session = AppSession.instance;
    final flatIds = session.myResidences.map((r) => r.flatId).toSet().toList();
    if (flatIds.isEmpty) return [];

    try {
      final res = await _client
          .from('visitors')
          .select(_selectBasicJoins)
          .inFilter('flat_id', flatIds)
          .order('created_at', ascending: false);

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

      final res = await query.order('created_at', ascending: false);
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
  }) async {
    try {
      // Try RPC first
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
        });

        if (rpcRes is Map && rpcRes['success'] == true) {
          return rpcRes['visitor_id']?.toString() ?? '';
        } else if (rpcRes is Map && rpcRes['error'] != null) {
          throw Exception(rpcRes['error']);
        }
      } catch (rpcError) {
        debugPrint('create_visitor_entry RPC failed, falling back: $rpcError');
      }

      // Direct fallback
      final user = _client.auth.currentUser;
      final insertRes = await _client.from('visitors').insert({
        'society_id': societyId,
        'flat_id': flatId,
        'block_id': blockId,
        'created_by_type': 'society_admin',
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
        'changed_by_role': 'society_admin',
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
      // Try RPC first
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

        if (rpcRes is Map && rpcRes['success'] == true) {
          return {
            'visitor_id': rpcRes['visitor_id']?.toString() ?? '',
            'approval_code': rpcRes['approval_code']?.toString() ?? '',
          };
        } else if (rpcRes is Map && rpcRes['error'] != null) {
          throw Exception(rpcRes['error']);
        }
      } catch (rpcError) {
        debugPrint('create_pre_approval RPC failed, falling back: $rpcError');
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
      // Try RPC first
      bool rpcSucceeded = false;
      try {
        final rpcRes = await _client.rpc('respond_to_visitor_request', params: {
          'p_visitor_id': visitorId,
          'p_action': action,
          'p_denied_reason': deniedReason,
        });

        if (rpcRes is Map && rpcRes['success'] == true) {
          codeResult = rpcRes['approval_code']?.toString();
          rpcSucceeded = true;
        } else if (rpcRes is Map && rpcRes['error'] != null) {
          throw Exception(rpcRes['error']);
        }
      } catch (rpcError) {
        debugPrint(
            'respond_to_visitor_request RPC failed, falling back: $rpcError');
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
        if (rpcRes is Map && rpcRes['success'] == true) return;
        if (rpcRes is Map && rpcRes['error'] != null) {
          throw Exception(rpcRes['error']);
        }
      } catch (rpcError) {
        debugPrint('check_in_visitor RPC failed, falling back: $rpcError');
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
        'changed_by_role': 'society_admin',
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
        if (rpcRes is Map && rpcRes['success'] == true) return;
        if (rpcRes is Map && rpcRes['error'] != null) {
          throw Exception(rpcRes['error']);
        }
      } catch (rpcError) {
        debugPrint('check_out_visitor RPC failed, falling back: $rpcError');
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
        'changed_by_role': 'society_admin',
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
        if (rpcRes is Map && rpcRes['success'] == true) return;
        if (rpcRes is Map && rpcRes['error'] != null) {
          throw Exception(rpcRes['error']);
        }
      } catch (rpcError) {
        debugPrint('cancel_pre_approval RPC failed, falling back: $rpcError');
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
          'p_approval_code': approvalCode.trim(),
        });
        if (rpcRes is Map && rpcRes['success'] == true) {
          return Map<String, dynamic>.from(rpcRes);
        } else if (rpcRes is Map && rpcRes['error'] != null) {
          throw Exception(rpcRes['error']);
        }
      } catch (rpcError) {
        debugPrint('verify_pre_approval RPC failed, falling back: $rpcError');
      }

      // Direct fallback
      final res = await _client
          .from('visitors')
          .select(_selectBasicJoins)
          .eq('approval_code', approvalCode.trim())
          .maybeSingle();

      if (res == null) return null;

      final visitor = VisitorRecord.fromMap(res);
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

    // 3. Fallback: Base64 data URI
    try {
      final b64 = base64Encode(bytes);
      return 'data:image/$fileExtension;base64,$b64';
    } catch (e) {
      debugPrint('Base64 encoding fallback failed: $e');
      return null;
    }
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
