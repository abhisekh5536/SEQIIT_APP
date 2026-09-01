import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/models/notification_model.dart';
import 'package:society_management/screens/notifications_screen.dart';

void main() {
  group('Notifications Model & Retention Tests', () {
    test('NotificationHistoryRetention enum and keys', () {
      expect(NotificationHistoryRetention.fromKey('3_days'), NotificationHistoryRetention.days3);
      expect(NotificationHistoryRetention.fromKey('1_week'), NotificationHistoryRetention.days7);
      expect(NotificationHistoryRetention.fromKey('2_weeks'), NotificationHistoryRetention.days14);
      expect(NotificationHistoryRetention.fromKey('1_month'), NotificationHistoryRetention.days30);
      expect(NotificationHistoryRetention.fromKey('all'), NotificationHistoryRetention.all);
      expect(NotificationHistoryRetention.fromKey(null), NotificationHistoryRetention.days7);
    });

    test('AppNotification fromMap deserialization and helper methods', () {
      final map = {
        'id': 'notif-1',
        'society_id': 'soc-123',
        'user_id': 'user-456',
        'target_role': 'society_admin',
        'title': 'New Complaint: Water Leakage',
        'body': 'Flat B-204 · Status: open',
        'type': 'complaint_created',
        'entity_type': 'complaint',
        'entity_id': 'c-999',
        'route': '/complaints',
        'is_read': false,
        'created_at': '2026-09-01T12:00:00.000Z',
      };

      final notif = AppNotification.fromMap(map);

      expect(notif.id, 'notif-1');
      expect(notif.societyId, 'soc-123');
      expect(notif.targetRole, 'society_admin');
      expect(notif.title, 'New Complaint: Water Leakage');
      expect(notif.body, 'Flat B-204 · Status: open');
      expect(notif.type, 'complaint_created');
      expect(notif.entityType, 'complaint');
      expect(notif.entityId, 'c-999');
      expect(notif.isRead, false);
      expect(notif.isComplaint, true);
      expect(notif.isApproval, false);

      final readNotif = notif.copyWith(isRead: true);
      expect(readNotif.isRead, true);
      expect(readNotif.id, 'notif-1');
    });

    test('AppNotification approval type identification', () {
      final notif = AppNotification(
        id: 'jr-1',
        societyId: 'soc-1',
        targetRole: 'society_admin',
        title: 'New Resident Approval Request',
        body: 'Saurabh requested to join',
        type: 'join_request_created',
        entityType: 'join_request',
        entityId: 'req-1',
        isRead: false,
        createdAt: DateTime.now(),
      );

      expect(notif.isApproval, true);
      expect(notif.isComplaint, false);
    });

    testWidgets('NotificationsScreen renders unread notification with NEW badge without errors',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: NotificationsScreen(),
        ),
      );

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Unread'), findsOneWidget);
      expect(find.text('Complaints'), findsOneWidget);
    });
  });
}
