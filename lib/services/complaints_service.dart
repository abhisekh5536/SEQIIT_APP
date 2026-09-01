import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/complaint_models.dart';
import 'app_session.dart';

class HelpdeskStats {
  final int total;
  final int open;
  final int inProgress;
  final int resolved;
  final int reopened;
  final int closed;
  final int securityCount;

  const HelpdeskStats({
    this.total = 0,
    this.open = 0,
    this.inProgress = 0,
    this.resolved = 0,
    this.reopened = 0,
    this.closed = 0,
    this.securityCount = 0,
  });

  int get pendingCount => open + inProgress + reopened;
}

class ComplaintsService {
  ComplaintsService._();
  static final ComplaintsService instance = ComplaintsService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Fetches complaints raised by the current resident across all their residences.
  Future<List<ComplaintRecord>> fetchResidentComplaints() async {
    final session = AppSession.instance;
    final residentIds = session.myResidences.map((r) => r.id).toList();

    if (residentIds.isEmpty) {
      return [];
    }

    try {
      final res = await _client
          .from('complaints')
          .select('*, flats(flat_number, blocks(name)), residents(full_name, phone, email)')
          .inFilter('raised_by', residentIds)
          .order('created_at', ascending: false);

      final list = (res as List).cast<Map<String, dynamic>>();
      return list.map(ComplaintRecord.fromMap).toList();
    } catch (e) {
      debugPrint('ComplaintsService.fetchResidentComplaints error: $e');
      rethrow;
    }
  }

  /// Fetches all complaints in the society for the Society Admin with optional filters.
  Future<List<ComplaintRecord>> fetchSocietyComplaints({
    String? statusFilter,
    String? categoryFilter,
    String? priorityFilter,
    String? searchQuery,
    String sortBy = 'newest', // 'newest' | 'oldest' | 'priority'
  }) async {
    final societyId = AppSession.instance.societyId;
    if (societyId == null) return [];

    try {
      var query = _client
          .from('complaints')
          .select('*, flats(flat_number, blocks(name)), residents(full_name, phone, email)')
          .eq('society_id', societyId);

      if (statusFilter != null && statusFilter != 'all') {
        query = query.eq('status', statusFilter);
      }

      if (categoryFilter != null && categoryFilter != 'all') {
        query = query.eq('category', categoryFilter);
      }

      if (priorityFilter != null && priorityFilter != 'all') {
        query = query.eq('priority', priorityFilter);
      }

      final res = await (sortBy == 'oldest'
          ? query.order('created_at', ascending: true)
          : query.order('created_at', ascending: false));
      var list = (res as List).cast<Map<String, dynamic>>().map(ComplaintRecord.fromMap).toList();

      if (sortBy == 'priority') {
        list.sort((a, b) {
          final priorityWeight = {
            ComplaintPriority.high: 3,
            ComplaintPriority.medium: 2,
            ComplaintPriority.low: 1,
          };
          final weightA = priorityWeight[a.priority] ?? 0;
          final weightB = priorityWeight[b.priority] ?? 0;
          if (weightA != weightB) {
            return weightB.compareTo(weightA);
          }
          return b.createdAt.compareTo(a.createdAt);
        });
      }

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.toLowerCase().trim();
        list = list.where((c) {
          final matchesTitle = c.title.toLowerCase().contains(q);
          final matchesDesc = c.description?.toLowerCase().contains(q) ?? false;
          final matchesFlat = c.flatNumber?.toLowerCase().contains(q) ?? false;
          final matchesResident = c.residentName?.toLowerCase().contains(q) ?? false;
          return matchesTitle || matchesDesc || matchesFlat || matchesResident;
        }).toList();
      }

      return list;
    } catch (e) {
      debugPrint('ComplaintsService.fetchSocietyComplaints error: $e');
      rethrow;
    }
  }

  /// Fetches single complaint details.
  Future<ComplaintRecord?> fetchComplaintDetail(String complaintId) async {
    try {
      final res = await _client
          .from('complaints')
          .select('*, flats(flat_number, blocks(name)), residents(full_name, phone, email)')
          .eq('id', complaintId)
          .maybeSingle();

      if (res == null) return null;
      return ComplaintRecord.fromMap(res);
    } catch (e) {
      debugPrint('ComplaintsService.fetchComplaintDetail error: $e');
      rethrow;
    }
  }

  /// Fetches the audit history timeline for a complaint.
  Future<List<ComplaintStatusHistoryRecord>> fetchComplaintHistory(String complaintId) async {
    try {
      final res = await _client
          .from('complaint_status_history')
          .select()
          .eq('complaint_id', complaintId)
          .order('created_at', ascending: true);

      final list = (res as List).cast<Map<String, dynamic>>();
      return list.map(ComplaintStatusHistoryRecord.fromMap).toList();
    } catch (e) {
      debugPrint('ComplaintsService.fetchComplaintHistory error: $e');
      return [];
    }
  }

  /// Uploads a photo to Supabase Storage bucket `complaint-photos` and returns the public URL.
  Future<String?> uploadComplaintPhoto({
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    try {
      final user = _client.auth.currentUser;
      final userId = user?.id ?? 'anon';
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${(1000 + (DateTime.now().microsecond % 9000))}.$fileExtension';
      final filePath = '$userId/$fileName';

      await _client.storage.from('complaint-photos').uploadBinary(
        filePath,
        bytes,
        fileOptions: FileOptions(
          contentType: 'image/$fileExtension',
          upsert: true,
        ),
      );

      final publicUrl = _client.storage.from('complaint-photos').getPublicUrl(filePath);
      return publicUrl;
    } catch (e) {
      debugPrint('ComplaintsService.uploadComplaintPhoto error: $e');
      return null;
    }
  }

  /// Submits a complaint. Uses RPC if available, falls back to direct insert.
  Future<String> submitComplaint({
    required String societyId,
    required String flatId,
    required String raisedBy,
    required ComplaintCategory category,
    required String title,
    String? description,
    String? photoUrl,
  }) async {
    try {
      // Try RPC first for atomic integrity
      try {
        final rpcRes = await _client.rpc('submit_complaint', params: {
          'p_society_id': societyId,
          'p_flat_id': flatId,
          'p_raised_by': raisedBy,
          'p_category': category.dbValue,
          'p_title': title,
          'p_description': description,
          'p_photo_url': photoUrl,
        });

        if (rpcRes is Map && rpcRes['success'] == true) {
          return rpcRes['complaint_id']?.toString() ?? '';
        } else if (rpcRes is Map && rpcRes['error'] != null) {
          throw Exception(rpcRes['error']);
        }
      } catch (rpcError) {
        debugPrint('submit_complaint RPC failed or not found, attempting direct insert fallback: $rpcError');
      }

      // Direct fallback
      final insertRes = await _client.from('complaints').insert({
        'society_id': societyId,
        'flat_id': flatId,
        'raised_by': raisedBy,
        'category': category.dbValue,
        'title': title.trim(),
        'description': description?.trim(),
        'photo_url': photoUrl,
        'status': 'open',
        'priority': 'medium',
      }).select('id').single();

      final newId = insertRes['id']?.toString() ?? '';

      // Insert initial history
      final user = _client.auth.currentUser;
      await _client.from('complaint_status_history').insert({
        'complaint_id': newId,
        'from_status': null,
        'to_status': 'open',
        'note': 'Complaint raised',
        'changed_by': user?.id,
        'changed_by_role': 'resident',
      });

      return newId;
    } catch (e) {
      debugPrint('ComplaintsService.submitComplaint error: $e');
      rethrow;
    }
  }

  /// Updates complaint status with validation and history logging.
  Future<void> updateStatus({
    required String complaintId,
    required ComplaintStatus newStatus,
    String? note,
    String? assignedTo,
    ComplaintPriority? priority,
  }) async {
    try {
      // Try RPC first
      try {
        final rpcRes = await _client.rpc('update_complaint_status_rpc', params: {
          'p_complaint_id': complaintId,
          'p_new_status': newStatus.dbValue,
          'p_note': note,
          'p_assigned_to': assignedTo,
          'p_priority': priority?.dbValue,
        });

        if (rpcRes is Map && rpcRes['success'] == true) {
          return;
        } else if (rpcRes is Map && rpcRes['error'] != null) {
          throw Exception(rpcRes['error']);
        }
      } catch (rpcError) {
        debugPrint('update_complaint_status_rpc failed or not found, falling back: $rpcError');
      }

      // Direct fallback
      final current = await _client
          .from('complaints')
          .select('status')
          .eq('id', complaintId)
          .single();

      final currentStatus = current['status']?.toString();
      final isAdmin = AppSession.instance.isAdmin;

      final updatePayload = <String, dynamic>{
        'status': newStatus.dbValue,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (newStatus == ComplaintStatus.resolved) {
        updatePayload['resolved_at'] = DateTime.now().toIso8601String();
      } else if (newStatus == ComplaintStatus.reopened) {
        updatePayload['resolved_at'] = null;
      }

      if (isAdmin) {
        if (note != null && note.trim().isNotEmpty) {
          updatePayload['admin_notes'] = note.trim();
        }
        if (assignedTo != null) {
          updatePayload['assigned_to'] = assignedTo.trim();
        }
        if (priority != null) {
          updatePayload['priority'] = priority.dbValue;
        }
      }

      await _client.from('complaints').update(updatePayload).eq('id', complaintId);

      final user = _client.auth.currentUser;
      await _client.from('complaint_status_history').insert({
        'complaint_id': complaintId,
        'from_status': currentStatus,
        'to_status': newStatus.dbValue,
        'note': note?.trim(),
        'changed_by': user?.id,
        'changed_by_role': isAdmin ? 'society_admin' : 'resident',
      });
    } catch (e) {
      debugPrint('ComplaintsService.updateStatus error: $e');
      rethrow;
    }
  }

  /// Admin note / assignment / priority update without changing status.
  Future<void> updateAdminDetails({
    required String complaintId,
    String? assignedTo,
    ComplaintPriority? priority,
    String? note,
  }) async {
    try {
      final current = await _client.from('complaints').select('status, admin_notes').eq('id', complaintId).single();
      final currentStatus = current['status']?.toString() ?? 'open';

      final payload = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (assignedTo != null) payload['assigned_to'] = assignedTo.trim();
      if (priority != null) payload['priority'] = priority.dbValue;
      if (note != null && note.trim().isNotEmpty) payload['admin_notes'] = note.trim();

      await _client.from('complaints').update(payload).eq('id', complaintId);

      if (note != null && note.trim().isNotEmpty) {
        final user = _client.auth.currentUser;
        await _client.from('complaint_status_history').insert({
          'complaint_id': complaintId,
          'from_status': currentStatus,
          'to_status': currentStatus,
          'note': note.trim(),
          'changed_by': user?.id,
          'changed_by_role': 'society_admin',
        });
      }
    } catch (e) {
      debugPrint('ComplaintsService.updateAdminDetails error: $e');
      rethrow;
    }
  }

  /// Computes stats for the Society Admin Helpdesk Queue.
  Future<HelpdeskStats> getSocietyHelpdeskStats() async {
    final societyId = AppSession.instance.societyId;
    if (societyId == null) return const HelpdeskStats();

    try {
      final res = await _client
          .from('complaints')
          .select('status, category')
          .eq('society_id', societyId);

      final list = (res as List).cast<Map<String, dynamic>>();
      int open = 0;
      int inProgress = 0;
      int resolved = 0;
      int reopened = 0;
      int closed = 0;
      int security = 0;

      for (final item in list) {
        final st = item['status']?.toString();
        final cat = item['category']?.toString();

        if (cat == 'security') security++;

        switch (st) {
          case 'open':
            open++;
            break;
          case 'in_progress':
            inProgress++;
            break;
          case 'resolved':
            resolved++;
            break;
          case 'reopened':
            reopened++;
            break;
          case 'closed':
            closed++;
            break;
        }
      }

      return HelpdeskStats(
        total: list.length,
        open: open,
        inProgress: inProgress,
        resolved: resolved,
        reopened: reopened,
        closed: closed,
        securityCount: security,
      );
    } catch (e) {
      debugPrint('ComplaintsService.getSocietyHelpdeskStats error: $e');
      return const HelpdeskStats();
    }
  }
}
