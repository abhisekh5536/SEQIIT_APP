import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/models/notice_models.dart';
import 'package:society_management/theme/app_theme.dart';

void main() {
  group('Notice Models & Enums Tests', () {
    test('NoticeCategory mapping and defaults', () {
      expect(NoticeCategory.fromDb('important'), NoticeCategory.important);
      expect(NoticeCategory.fromDb('EVENT'), NoticeCategory.event);
      expect(NoticeCategory.fromDb('safety'), NoticeCategory.safety);
      expect(NoticeCategory.fromDb('maintenance'), NoticeCategory.maintenance);
      expect(NoticeCategory.fromDb('billing'), NoticeCategory.billing);
      expect(NoticeCategory.fromDb('general'), NoticeCategory.general);
      expect(NoticeCategory.fromDb('invalid_category'), NoticeCategory.general);
      expect(NoticeCategory.fromDb(null), NoticeCategory.general);
    });

    test('NoticeStatus mapping and defaults', () {
      expect(NoticeStatus.fromDb('draft'), NoticeStatus.draft);
      expect(NoticeStatus.fromDb('scheduled'), NoticeStatus.scheduled);
      expect(NoticeStatus.fromDb('published'), NoticeStatus.published);
      expect(NoticeStatus.fromDb('expired'), NoticeStatus.expired);
      expect(NoticeStatus.fromDb('archived'), NoticeStatus.archived);
      expect(NoticeStatus.fromDb('unknown_status'), NoticeStatus.draft);
      expect(NoticeStatus.fromDb(null), NoticeStatus.draft);
    });

    test('NoticeTargetType mapping and defaults', () {
      expect(NoticeTargetType.fromDb('all'), NoticeTargetType.all);
      expect(NoticeTargetType.fromDb('block'), NoticeTargetType.block);
      expect(NoticeTargetType.fromDb('invalid'), NoticeTargetType.all);
      expect(NoticeTargetType.fromDb(null), NoticeTargetType.all);
    });

    test('NoticeRecord deserialization fromMap and helpers', () {
      final now = DateTime.now();
      final map = {
        'id': 'notice-101',
        'society_id': 'soc-01',
        'title': 'Janmashtami Cultural Evening',
        'body': 'Join us for celebration, games, and prasad distribution at the clubhouse.',
        'category': 'event',
        'attachment_url': 'https://storage.supabase.co/notices/event.jpg',
        'target_type': 'all',
        'target_block_id': null,
        'is_event': true,
        'event_starts_at': now.add(const Duration(days: 3, hours: 2)).toUtc().toIso8601String(),
        'event_ends_at': now.add(const Duration(days: 3, hours: 4)).toUtc().toIso8601String(),
        'event_venue': 'Clubhouse Lawn',
        'is_pinned': true,
        'requires_acknowledgment': true,
        'status': 'published',
        'publish_at': now.subtract(const Duration(hours: 1)).toUtc().toIso8601String(),
        'expires_at': now.add(const Duration(days: 4)).toUtc().toIso8601String(),
        'created_by': 'admin-uuid',
        'created_at': now.subtract(const Duration(hours: 1)).toUtc().toIso8601String(),
        'updated_at': now.subtract(const Duration(hours: 1)).toUtc().toIso8601String(),
        'blocks': null,
      };

      final record = NoticeRecord.fromMap(
        map,
        isRead: true,
        isAcknowledged: true,
        acknowledgedAt: now.subtract(const Duration(minutes: 30)),
        readCount: 42,
        ackCount: 35,
        totalResidents: 50,
      );

      expect(record.id, 'notice-101');
      expect(record.societyId, 'soc-01');
      expect(record.title, 'Janmashtami Cultural Evening');
      expect(record.category, NoticeCategory.event);
      expect(record.isEvent, true);
      expect(record.isPinned, true);
      expect(record.requiresAcknowledgment, true);
      expect(record.status, NoticeStatus.published);
      expect(record.isPublished, true);
      expect(record.isDraft, false);
      expect(record.isEventUpcoming, true);
      expect(record.eventVenue, 'Clubhouse Lawn');
      expect(record.isReadByMe, true);
      expect(record.isAcknowledgedByMe, true);
      expect(record.readCount, 42);
      expect(record.ackCount, 35);
      expect(record.totalEligibleResidents, 50);
      expect(record.formattedEventBadge, isNotNull);
      expect(record.formattedEventSchedule, isNot(contains('Clubhouse Lawn')));
      expect(record.formattedEventSchedule, isNotNull);
    });

    test('NoticeRecord targeted to specific block', () {
      final map = {
        'id': 'notice-102',
        'society_id': 'soc-01',
        'title': 'Block A Lift Maintenance',
        'body': 'Lift #2 will undergo routine service tomorrow between 10am and 1pm.',
        'category': 'maintenance',
        'target_type': 'block',
        'target_block_id': 'blk-1',
        'is_event': false,
        'is_pinned': false,
        'requires_acknowledgment': false,
        'status': 'published',
        'publish_at': DateTime.now().toUtc().toIso8601String(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'blocks': {
          'name': 'Tower A',
        },
      };

      final record = NoticeRecord.fromMap(map);

      expect(record.targetType, NoticeTargetType.block);
      expect(record.targetBlockId, 'blk-1');
      expect(record.targetBlockName, 'Tower A');
      expect(record.category, NoticeCategory.maintenance);
      expect(record.isEvent, false);
      expect(record.formattedEventBadge, isNull);
    });

    test('NoticeReaderInfo and NoticeStats models', () {
      const reader = NoticeReaderInfo(
        residentId: 'res-1',
        residentName: 'Anita Sharma',
        phone: '+91 9988776655',
        email: 'anita@example.com',
        flatNumber: '302',
        blockName: 'Tower C',
        readAt: null,
        acknowledgedAt: null,
      );

      expect(reader.hasRead, false);
      expect(reader.hasAcknowledged, false);
      expect(reader.flatDisplay, 'Tower C - 302');

      const stats = NoticeStats(
        total: 10,
        published: 6,
        draft: 2,
        scheduled: 1,
        expired: 1,
        archived: 0,
      );

      expect(stats.total, 10);
      expect(stats.published, 6);
      expect(stats.draft, 2);
      expect(stats.scheduled, 1);
      expect(stats.expired, 1);
    });

    test('NoticeCategory and NoticeStatus theme colors resolution', () {
      final palette = AppTheme.paletteFor(Brightness.light);

      for (final cat in NoticeCategory.values) {
        expect(cat.color(palette), isNotNull);
      }

      for (final status in NoticeStatus.values) {
        expect(status.color(palette), isNotNull);
      }
    });
  });
}
