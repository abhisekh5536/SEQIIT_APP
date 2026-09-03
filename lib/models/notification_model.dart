import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum NotificationHistoryRetention {
  days3('3_days', 'Last 3 days', 3),
  days7('1_week', 'Last 1 week (Recommended)', 7),
  days14('2_weeks', 'Last 2 weeks', 14),
  days30('1_month', 'Last 1 month', 30),
  all('all', 'All time (No limit)', null);

  final String key;
  final String label;
  final int? days;

  const NotificationHistoryRetention(this.key, this.label, this.days);

  static NotificationHistoryRetention fromKey(String? key) {
    if (key == null) return NotificationHistoryRetention.days7;
    for (final r in NotificationHistoryRetention.values) {
      if (r.key == key) return r;
    }
    return NotificationHistoryRetention.days7;
  }
}

class AppNotification {
  final String id;
  final String societyId;
  final String? userId;
  final String targetRole; // 'resident' | 'society_admin' | 'all'
  final String title;
  final String body;
  final String type;
  final String? entityType; // 'complaint' | 'join_request' | 'notice'
  final String? entityId;
  final String? route;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.societyId,
    this.userId,
    required this.targetRole,
    required this.title,
    required this.body,
    required this.type,
    this.entityType,
    this.entityId,
    this.route,
    required this.isRead,
    required this.createdAt,
  });

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      societyId: societyId,
      userId: userId,
      targetRole: targetRole,
      title: title,
      body: body,
      type: type,
      entityType: entityType,
      entityId: entityId,
      route: route,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }

  bool get isComplaint => entityType == 'complaint' || type.startsWith('complaint');
  bool get isApproval => entityType == 'join_request' || type.startsWith('join_request');
  bool get isNotice => entityType == 'notice' || type == 'notice';
  bool get isVisitor => entityType == 'visitor' || type.startsWith('visitor');
  bool get isSos => entityType == 'sos_alert' || type.startsWith('sos_alert');

  IconData get icon {
    switch (type) {
      case 'complaint_created':
        return Icons.report_problem_rounded;
      case 'complaint_resolved':
        return Icons.task_alt_rounded;
      case 'complaint_updated':
        return Icons.timelapse_rounded;
      case 'complaint_reopened':
        return Icons.replay_rounded;
      case 'complaint_closed':
        return Icons.check_circle_rounded;
      case 'join_request_created':
        return Icons.how_to_reg_rounded;
      case 'join_request_approved':
        return Icons.celebration_rounded;
      case 'join_request_rejected':
        return Icons.cancel_outlined;
      case 'notice':
        return Icons.campaign_rounded;
      case 'visitor_approval_request':
        return Icons.door_front_door_rounded;
      case 'visitor_approved':
        return Icons.how_to_reg_rounded;
      case 'visitor_denied':
        return Icons.person_off_rounded;
      case 'visitor_preapproved_created':
        return Icons.verified_rounded;
      case 'visitor_checked_in':
        return Icons.login_rounded;
      case 'visitor_checked_out':
        return Icons.logout_rounded;
      case 'sos_alert_raised':
        return Icons.crisis_alert_rounded;
      case 'sos_alert_acknowledged':
        return Icons.visibility_rounded;
      case 'sos_alert_resolved':
        return Icons.task_alt_rounded;
      case 'sos_alert_cancelled':
        return Icons.cancel_outlined;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color get iconColor {
    switch (type) {
      case 'complaint_created':
      case 'join_request_created':
        return const Color(0xFFD97706);
      case 'complaint_resolved':
      case 'join_request_approved':
        return const Color(0xFF16A34A);
      case 'complaint_updated':
        return const Color(0xFF2563EB);
      case 'complaint_reopened':
      case 'join_request_rejected':
        return const Color(0xFFDC2626);
      case 'complaint_closed':
        return const Color(0xFF059669);
      case 'notice':
        return const Color(0xFF7C73C0);
      case 'visitor_approval_request':
        return const Color(0xFFD97706);
      case 'visitor_approved':
      case 'visitor_preapproved_created':
        return const Color(0xFF2563EB);
      case 'visitor_denied':
        return const Color(0xFFDC2626);
      case 'visitor_checked_in':
        return const Color(0xFF16A34A);
      case 'visitor_checked_out':
        return const Color(0xFF059669);
      case 'sos_alert_raised':
        return const Color(0xFFDC2626);
      case 'sos_alert_acknowledged':
        return const Color(0xFF0288D1);
      case 'sos_alert_resolved':
        return const Color(0xFF16A34A);
      case 'sos_alert_cancelled':
        return const Color(0xFF64748B);
      default:
        return const Color(0xFF64748B);
    }
  }

  Color get iconBgColor {
    return iconColor.withValues(alpha: 0.12);
  }

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('dd MMM yyyy').format(createdAt);
  }

  factory AppNotification.fromMap(Map<String, dynamic> m) {
    DateTime parseDt(dynamic val) {
      if (val == null) return DateTime.now();
      return DateTime.tryParse(val.toString()) ?? DateTime.now();
    }

    return AppNotification(
      id: m['id']?.toString() ?? '',
      societyId: m['society_id']?.toString() ?? '',
      userId: m['user_id']?.toString(),
      targetRole: m['target_role']?.toString() ?? 'all',
      title: m['title']?.toString() ?? 'Notification',
      body: m['body']?.toString() ?? '',
      type: m['type']?.toString() ?? 'general',
      entityType: m['entity_type']?.toString(),
      entityId: m['entity_id']?.toString(),
      route: m['route']?.toString(),
      isRead: m['is_read'] == true || m['is_read']?.toString() == 'true',
      createdAt: parseDt(m['created_at']),
    );
  }
}
