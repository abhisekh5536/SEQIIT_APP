import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/notification_model.dart';
import 'app_session.dart';

class NotificationsService extends ChangeNotifier {
  NotificationsService._();
  static final NotificationsService instance = NotificationsService._();

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static const String _retentionPrefKey = 'seqiit_notification_retention_key';
  static const String _readIdsPrefKey = 'seqiit_notification_read_ids_key';

  List<AppNotification> _notifications = [];
  NotificationHistoryRetention _retention = NotificationHistoryRetention.days7;
  Set<String> _locallyReadIds = {};
  bool _loading = false;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  NotificationHistoryRetention get retention => _retention;
  bool get isLoading => _loading;
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedRetention = prefs.getString(_retentionPrefKey);
      _retention = NotificationHistoryRetention.fromKey(savedRetention);

      final savedReadJson = prefs.getString(_readIdsPrefKey);
      if (savedReadJson != null) {
        final list = (jsonDecode(savedReadJson) as List).cast<String>();
        _locallyReadIds = list.toSet();
      }
    } catch (e) {
      debugPrint('NotificationsService.init error: $e');
    }
    await fetchNotifications();
  }

  Future<void> setRetention(NotificationHistoryRetention newRetention) async {
    _retention = newRetention;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_retentionPrefKey, newRetention.key);
    } catch (e) {
      debugPrint('Error saving retention preference: $e');
    }
    await fetchNotifications();
  }

  DateTime? get _retentionCutoff {
    if (_retention.days == null) return null;
    return DateTime.now().subtract(Duration(days: _retention.days!));
  }

  Future<void> fetchNotifications() async {
    final client = _client;
    final session = AppSession.instance;
    final societyId = session.societyId;
    final user = client?.auth.currentUser;

    if (client == null || user == null || societyId == null) {
      _notifications = [];
      notifyListeners();
      return;
    }

    _loading = true;
    notifyListeners();

    try {
      final cutoff = _retentionCutoff;
      List<AppNotification> fetched = [];

      // 1. Try querying public.notifications table
      try {
        var query = client
            .from('notifications')
            .select()
            .eq('society_id', societyId);

        if (cutoff != null) {
          query = query.gte('created_at', cutoff.toIso8601String());
        }

        final res = await query.order('created_at', ascending: false).limit(100);
        final list = (res as List).cast<Map<String, dynamic>>();
        fetched = list.map(AppNotification.fromMap).toList();
      } catch (dbError) {
        debugPrint('notifications table not available or error: $dbError');
      }

      // 2. Synthesize fallback notifications from complaints & join requests if table is empty
      if (fetched.isEmpty) {
        fetched = await _synthesizeNotificationsFallback(client, session, cutoff);
      }

      // Apply locally stored read states
      _notifications = fetched.map((n) {
        if (_locallyReadIds.contains(n.id)) {
          return n.copyWith(isRead: true);
        }
        return n;
      }).toList();

      // Sort newest first
      _notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      debugPrint('NotificationsService.fetchNotifications error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Synthesizes live notifications from actual complaints and join requests
  /// to ensure instant functionality even before DB migration is triggered.
  Future<List<AppNotification>> _synthesizeNotificationsFallback(
    SupabaseClient client,
    AppSession session,
    DateTime? cutoff,
  ) async {
    final List<AppNotification> list = [];
    final societyId = session.societyId!;
    final isAdmin = session.isAdmin;
    final myResidences = session.myResidences;
    final residentIds = myResidences.map((r) => r.id).toList();

    try {
      // Fetch complaints
      var complaintQuery = client
          .from('complaints')
          .select('*, flats(flat_number), residents(full_name)')
          .eq('society_id', societyId);

      if (!isAdmin && residentIds.isNotEmpty) {
        complaintQuery = complaintQuery.inFilter('raised_by', residentIds);
      }

      final complaintsRes = await complaintQuery.order('created_at', ascending: false).limit(30);
      for (final c in complaintsRes as List) {
        final createdAt = DateTime.tryParse(c['created_at']?.toString() ?? '') ?? DateTime.now();
        if (cutoff != null && createdAt.isBefore(cutoff)) continue;

        final id = c['id']?.toString() ?? '';
        final title = c['title']?.toString() ?? 'Complaint';
        final status = c['status']?.toString() ?? 'open';
        final category = c['category']?.toString() ?? 'other';
        final flatMap = c['flats'] is Map ? c['flats'] as Map : {};
        final flatNum = flatMap['flat_number']?.toString() ?? '';
        final residentMap = c['residents'] is Map ? c['residents'] as Map : {};
        final residentName = residentMap['full_name']?.toString() ?? 'Resident';

        if (isAdmin) {
          list.add(AppNotification(
            id: 'c_admin_${id}_${status}_${category == 'security' ? 'sec' : 'gen'}',
            societyId: societyId,
            targetRole: 'society_admin',
            title: category == 'security' ? '🚨 Security Alert Raised' : 'Complaint: $title',
            body: '$residentName (Flat $flatNum) · Status: ${status.toUpperCase()}',
            type: category == 'security' ? 'complaint_created' : 'complaint_created',
            entityType: 'complaint',
            entityId: id,
            route: '/complaints',
            isRead: false,
            createdAt: createdAt,
          ));
        } else {
          final noteText = c['admin_notes']?.toString();
          final noteHash = (noteText != null && noteText.isNotEmpty) ? noteText.hashCode.abs() : 0;
          final updatedDt = DateTime.tryParse(c['updated_at']?.toString() ?? '') ?? createdAt;

          list.add(AppNotification(
            id: 'c_res_${id}_${status}_$noteHash',
            societyId: societyId,
            targetRole: 'resident',
            title: status == 'resolved'
                ? 'Complaint Resolved: $title'
                : (status == 'in_progress'
                    ? 'Work In Progress: $title'
                    : 'Complaint Status: ${status.replaceAll('_', ' ').toUpperCase()}'),
            body: noteText != null && noteText.isNotEmpty
                ? 'Admin Note: $noteText'
                : (status == 'resolved'
                    ? 'The society office marked this as resolved. Tap to verify.'
                    : 'Tap to view updates and resolution timeline.'),
            type: status == 'resolved' ? 'complaint_resolved' : 'complaint_updated',
            entityType: 'complaint',
            entityId: id,
            route: '/complaints',
            isRead: false,
            createdAt: updatedDt,
          ));
        }
      }

      // If admin, fetch join requests
      if (isAdmin) {
        final reqs = await client
            .from('resident_join_requests')
            .select('*, flats(flat_number)')
            .eq('society_id', societyId)
            .order('created_at', ascending: false)
            .limit(20);

        for (final r in reqs as List) {
          final createdAt = DateTime.tryParse(r['created_at']?.toString() ?? '') ?? DateTime.now();
          if (cutoff != null && createdAt.isBefore(cutoff)) continue;

          final id = r['id']?.toString() ?? '';
          final name = r['full_name']?.toString() ?? 'Applicant';
          final st = r['status']?.toString() ?? 'pending';
          final flatMap = r['flats'] is Map ? r['flats'] as Map : {};
          final flatNum = flatMap['flat_number']?.toString() ?? '';

          list.add(AppNotification(
            id: 'jr_$id',
            societyId: societyId,
            targetRole: 'society_admin',
            title: st == 'pending' ? 'Approval Request: $name' : 'Join Request ($st): $name',
            body: 'Flat $flatNum · ${r['resident_type']}',
            type: st == 'approved' ? 'join_request_approved' : 'join_request_created',
            entityType: 'join_request',
            entityId: id,
            route: '/admin-approvals',
            isRead: st != 'pending',
            createdAt: createdAt,
          ));
        }
      }
    } catch (e) {
      debugPrint('Error synthesizing fallback notifications: $e');
    }

    return list;
  }

  Future<void> markAsRead(String notificationId) async {
    _locallyReadIds.add(notificationId);
    _notifications = _notifications.map((n) {
      if (n.id == notificationId) {
        return n.copyWith(isRead: true);
      }
      return n;
    }).toList();
    notifyListeners();

    // Persist locally
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_readIdsPrefKey, jsonEncode(_locallyReadIds.toList()));
    } catch (_) {}

    // Persist remotely if it's a UUID record
    try {
      final client = _client;
      if (client != null && !notificationId.contains('_')) {
        await client.from('notifications').update({'is_read': true}).eq('id', notificationId);
      }
    } catch (_) {}
  }

  Future<void> markAllAsRead() async {
    for (final n in _notifications) {
      _locallyReadIds.add(n.id);
    }
    _notifications = _notifications.map((n) => n.copyWith(isRead: true)).toList();
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_readIdsPrefKey, jsonEncode(_locallyReadIds.toList()));
    } catch (_) {}

    final societyId = AppSession.instance.societyId;
    if (societyId != null) {
      try {
        final client = _client;
        if (client != null) {
          await client.rpc('mark_all_notifications_as_read', params: {'p_society_id': societyId});
        }
      } catch (_) {}
    }
  }
}
