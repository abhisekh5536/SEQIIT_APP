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

      // 2. Synthesize/supplement notifications from complaints & join requests
      final fallbackList = await _synthesizeNotificationsFallback(client, session, cutoff);

      // Merge and deduplicate
      final Set<String> seenEntityKeys = {};
      final List<AppNotification> merged = [];

      for (final n in fetched) {
        final key = '${n.entityType ?? ''}_${n.entityId ?? ''}_${n.type}';
        if (key.length > 2) seenEntityKeys.add(key);
        merged.add(n);
      }

      for (final fn in fallbackList) {
        final key = '${fn.entityType ?? ''}_${fn.entityId ?? ''}_${fn.type}';
        if (!seenEntityKeys.contains(key)) {
          merged.add(fn);
          if (key.length > 2) seenEntityKeys.add(key);
        }
      }

      // Apply locally stored read states
      _notifications = merged.map((n) {
        if (_locallyReadIds.contains(n.id)) {
          return n.copyWith(isRead: true);
        }
        return n;
      }).toList();

      // Auto-reconcile visitor notifications: if a visitor is already resolved
      // (status != 'pending_approval'), its 'visitor_approval_request' notification
      // must be marked as read so it doesn't stay unread or show the NEW badge!
      final visitorReqNotifs = _notifications
          .where((n) =>
              (n.entityType == 'visitor' || n.type == 'visitor_approval_request') &&
              n.type == 'visitor_approval_request' &&
              !n.isRead &&
              n.entityId != null &&
              n.entityId!.isNotEmpty)
          .toList();

      if (visitorReqNotifs.isNotEmpty) {
        try {
          final vIds = visitorReqNotifs.map((n) => n.entityId!).toSet().toList();
          final vRes = await client
              .from('visitors')
              .select('id, status')
              .inFilter('id', vIds);

          final statusMap = {
            for (final row in (vRes as List))
              row['id']?.toString() ?? '': row['status']?.toString() ?? ''
          };

          bool changed = false;
          _notifications = _notifications.map((n) {
            if ((n.entityType == 'visitor' || n.type == 'visitor_approval_request') &&
                n.type == 'visitor_approval_request' &&
                !n.isRead) {
              final vStatus = statusMap[n.entityId];
              if (vStatus != null && vStatus != 'pending_approval') {
                changed = true;
                _locallyReadIds.add(n.id);
                // Also update DB table if it's a real DB record
                if (!n.id.contains('_')) {
                  client
                      .from('notifications')
                      .update({'is_read': true})
                      .eq('id', n.id)
                      .catchError((_) {});
                }
                return n.copyWith(isRead: true);
              }
            }
            return n;
          }).toList();

          if (changed) {
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(
                  _readIdsPrefKey, jsonEncode(_locallyReadIds.toList()));
            } catch (_) {}
          }
        } catch (e) {
          debugPrint('Error auto-reconciling visitor notifications: $e');
        }
      }

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

          String titleText;
          String bodyText;
          String notifType;

          if (status == 'resolved') {
            titleText = 'Complaint Resolved 🛠️: $title';
            bodyText = noteText != null && noteText.isNotEmpty
                ? 'Admin Note: $noteText'
                : 'The society office marked this as resolved.';
            notifType = 'complaint_resolved';
          } else if (status == 'closed') {
            titleText = 'Complaint Closed ✅: $title';
            bodyText = 'This complaint was closed. Tap to view history.';
            notifType = 'complaint_closed';
          } else if (status == 'in_progress') {
            titleText = 'Work In Progress ⏳: $title';
            bodyText = noteText != null && noteText.isNotEmpty
                ? 'Admin Note: $noteText'
                : 'Work has begun on your complaint.';
            notifType = 'complaint_updated';
          } else {
            titleText = 'Complaint: $title';
            bodyText = 'Status: ${status.replaceAll('_', ' ').toUpperCase()}';
            notifType = 'complaint_created';
          }

          list.add(AppNotification(
            id: 'c_res_${id}_${status}_$noteHash',
            societyId: societyId,
            targetRole: 'resident',
            title: titleText,
            body: bodyText,
            type: notifType,
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

      // Synthesize Visitor Notifications
      try {
        final flatIds = myResidences.map((r) => r.flatId).toSet().toList();
        if (isAdmin || flatIds.isNotEmpty) {
          var visitorQuery = client
              .from('visitors')
              .select('*, flats(flat_number)')
              .eq('society_id', societyId);

          if (!isAdmin) {
            visitorQuery = visitorQuery.inFilter('flat_id', flatIds);
          }

          final visitorsRes = await visitorQuery
              .order('created_at', ascending: false)
              .limit(25);

          for (final v in visitorsRes as List) {
            final createdAt = DateTime.tryParse(v['created_at']?.toString() ?? '') ?? DateTime.now();
            if (cutoff != null && createdAt.isBefore(cutoff)) continue;

            final id = v['id']?.toString() ?? '';
            final vName = v['visitor_name']?.toString() ?? 'Visitor';
            final status = v['status']?.toString() ?? 'pending_approval';
            final entryType = v['entry_type']?.toString() ?? 'gate_request';
            final category = v['category']?.toString() ?? 'guest';
            final code = v['approval_code']?.toString() ?? '';
            final flatMap = v['flats'] is Map ? v['flats'] as Map : {};
            final flatNum = flatMap['flat_number']?.toString() ?? '';

            if (isAdmin) {
              list.add(AppNotification(
                id: 'v_admin_${id}_$status',
                societyId: societyId,
                targetRole: 'society_admin',
                title: '🚪 Visitor: $vName',
                body: 'Flat $flatNum · Status: ${status.replaceAll('_', ' ').toUpperCase()}',
                type: status == 'pending_approval'
                    ? 'visitor_approval_request'
                    : status == 'approved'
                        ? 'visitor_approved'
                        : 'visitor_checked_in',
                entityType: 'visitor',
                entityId: id,
                route: '/visitors',
                isRead: status != 'pending_approval',
                createdAt: createdAt,
              ));
            } else {
              String notifTitle;
              String notifBody;
              String notifType;

              if (status == 'pending_approval') {
                notifTitle = '🚪 Visitor at Gate: $vName';
                notifBody = 'Category: $category · Tap to approve or deny';
                notifType = 'visitor_approval_request';
              } else if (status == 'approved' && entryType == 'pre_approved') {
                notifTitle = '✅ Pre-Approval Created: $vName';
                notifBody = 'Approval Code: #$code · $category';
                notifType = 'visitor_preapproved_created';
              } else if (status == 'approved') {
                notifTitle = '✅ Visitor Approved: $vName';
                notifBody = 'Entry approved · Code: #$code';
                notifType = 'visitor_approved';
              } else if (status == 'denied') {
                notifTitle = '❌ Visitor Denied: $vName';
                notifBody = v['denied_reason']?.toString() ?? 'Entry was denied';
                notifType = 'visitor_denied';
              } else {
                notifTitle = 'Visitor: $vName';
                notifBody = 'Status: ${status.replaceAll('_', ' ')}';
                notifType = 'general';
              }

              list.add(AppNotification(
                id: 'v_res_${id}_$status',
                societyId: societyId,
                targetRole: 'resident',
                title: notifTitle,
                body: notifBody,
                type: notifType,
                entityType: 'visitor',
                entityId: id,
                route: '/visitors',
                isRead: status != 'pending_approval',
                createdAt: createdAt,
              ));
            }
          }
        }
      } catch (visitorErr) {
        debugPrint('Visitor notifications synthesis error: $visitorErr');
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

  /// Marks all notifications corresponding to a specific entity (e.g. visitor, complaint) as read.
  Future<void> markEntityAsRead(String entityType, String entityId) async {
    final toMark = _notifications
        .where((n) =>
            (n.entityType == entityType || n.type.startsWith(entityType)) &&
            n.entityId == entityId)
        .map((n) => n.id)
        .toList();

    for (final id in toMark) {
      _locallyReadIds.add(id);
    }

    _notifications = _notifications.map((n) {
      if ((n.entityType == entityType || n.type.startsWith(entityType)) &&
          n.entityId == entityId) {
        return n.copyWith(isRead: true);
      }
      return n;
    }).toList();
    notifyListeners();

    // Persist locally
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _readIdsPrefKey, jsonEncode(_locallyReadIds.toList()));
    } catch (_) {}

    // Persist remotely
    try {
      final client = _client;
      if (client != null) {
        await client
            .from('notifications')
            .update({'is_read': true})
            .eq('entity_type', entityType)
            .eq('entity_id', entityId);
      }
    } catch (_) {}
  }

  /// Marks all notifications corresponding to a specific module (e.g. 'visitor', 'notice', 'complaint', 'join_request') as read.
  Future<void> markModuleAsRead(String entityType) async {
    final matchingNotifs = _notifications.where((n) {
      final isMatchingType = n.entityType == entityType ||
          n.type.startsWith(entityType) ||
          (entityType == 'visitor' && n.isVisitor) ||
          (entityType == 'notice' && n.isNotice) ||
          (entityType == 'complaint' && n.isComplaint) ||
          (entityType == 'join_request' && n.isApproval) ||
          ((entityType == 'sos_alert' || entityType == 'security') && n.isSos);
      return isMatchingType && !n.isRead;
    }).toList();

    if (matchingNotifs.isEmpty) return;

    for (final n in matchingNotifs) {
      _locallyReadIds.add(n.id);
    }

    _notifications = _notifications.map((n) {
      final isMatchingType = n.entityType == entityType ||
          n.type.startsWith(entityType) ||
          (entityType == 'visitor' && n.isVisitor) ||
          (entityType == 'notice' && n.isNotice) ||
          (entityType == 'complaint' && n.isComplaint) ||
          (entityType == 'join_request' && n.isApproval) ||
          ((entityType == 'sos_alert' || entityType == 'security') && n.isSos);
      if (isMatchingType) {
        return n.copyWith(isRead: true);
      }
      return n;
    }).toList();
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _readIdsPrefKey, jsonEncode(_locallyReadIds.toList()));
    } catch (_) {}

    try {
      final client = _client;
      if (client != null) {
        final idsToUpdate = matchingNotifs
            .where((n) => !n.id.contains('_'))
            .map((n) => n.id)
            .toList();
        if (idsToUpdate.isNotEmpty) {
          await client
              .from('notifications')
              .update({'is_read': true})
              .inFilter('id', idsToUpdate);
        }
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
