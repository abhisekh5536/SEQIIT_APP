import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/models/complaint_models.dart';

void main() {
  group('Complaint Models & Enums Tests', () {
    test('ComplaintCategory mapping and defaults', () {
      expect(ComplaintCategory.fromDb('plumbing'), ComplaintCategory.plumbing);
      expect(ComplaintCategory.fromDb('ELECTRICAL'), ComplaintCategory.electrical);
      expect(ComplaintCategory.fromDb('security'), ComplaintCategory.security);
      expect(ComplaintCategory.fromDb('cleanliness'), ComplaintCategory.cleanliness);
      expect(ComplaintCategory.fromDb('billing'), ComplaintCategory.billing);
      expect(ComplaintCategory.fromDb('lift'), ComplaintCategory.lift);
      expect(ComplaintCategory.fromDb('other'), ComplaintCategory.other);
      expect(ComplaintCategory.fromDb('unknown_cat'), ComplaintCategory.other);
      expect(ComplaintCategory.fromDb(null), ComplaintCategory.other);
    });

    test('ComplaintStatus mapping and defaults', () {
      expect(ComplaintStatus.fromDb('open'), ComplaintStatus.open);
      expect(ComplaintStatus.fromDb('in_progress'), ComplaintStatus.inProgress);
      expect(ComplaintStatus.fromDb('resolved'), ComplaintStatus.resolved);
      expect(ComplaintStatus.fromDb('closed'), ComplaintStatus.closed);
      expect(ComplaintStatus.fromDb('reopened'), ComplaintStatus.reopened);
      expect(ComplaintStatus.fromDb('unknown_status'), ComplaintStatus.open);
      expect(ComplaintStatus.fromDb(null), ComplaintStatus.open);
    });

    test('ComplaintPriority mapping and defaults', () {
      expect(ComplaintPriority.fromDb('low'), ComplaintPriority.low);
      expect(ComplaintPriority.fromDb('medium'), ComplaintPriority.medium);
      expect(ComplaintPriority.fromDb('high'), ComplaintPriority.high);
      expect(ComplaintPriority.fromDb('invalid'), ComplaintPriority.medium);
      expect(ComplaintPriority.fromDb(null), ComplaintPriority.medium);
    });

    test('ComplaintRecord fromMap deserialization and helper methods', () {
      final map = {
        'id': 'c-101',
        'society_id': 'soc-1',
        'flat_id': 'f-204',
        'raised_by': 'r-55',
        'category': 'security',
        'title': 'Main gate lock malfunctioning',
        'description': 'The magnetic latch on block B entrance fails to lock intermittently.',
        'photo_url': 'https://storage.supabase.co/complaint-photos/photo.jpg',
        'status': 'resolved',
        'priority': 'high',
        'assigned_to': 'Ramesh - Security Staff',
        'admin_notes': 'Repaired latch and replaced sensor battery.',
        'created_at': '2026-09-01T10:00:00.000Z',
        'updated_at': '2026-09-01T14:30:00.000Z',
        'resolved_at': '2026-09-01T14:30:00.000Z',
        'flats': {
          'flat_number': 'B-204',
          'blocks': {
            'name': 'Tower B',
          },
        },
        'residents': {
          'full_name': 'Saurabh Kumar',
          'phone': '+91 9876543210',
          'email': 'saurabh@example.com',
        },
      };

      final record = ComplaintRecord.fromMap(map);

      expect(record.id, 'c-101');
      expect(record.societyId, 'soc-1');
      expect(record.flatId, 'f-204');
      expect(record.raisedBy, 'r-55');
      expect(record.category, ComplaintCategory.security);
      expect(record.title, 'Main gate lock malfunctioning');
      expect(record.description, contains('magnetic latch'));
      expect(record.photoUrl, contains('photo.jpg'));
      expect(record.status, ComplaintStatus.resolved);
      expect(record.priority, ComplaintPriority.high);
      expect(record.assignedTo, 'Ramesh - Security Staff');
      expect(record.adminNotes, contains('Repaired latch'));
      expect(record.flatNumber, 'B-204');
      expect(record.blockName, 'Tower B');
      expect(record.flatDisplay, 'Tower B · Flat B-204');
      expect(record.residentName, 'Saurabh Kumar');
      expect(record.residentPhone, '+91 9876543210');
      expect(record.residentEmail, 'saurabh@example.com');
      expect(record.isSecurity, true);
      expect(record.isResolved, true);
      expect(record.isActive, true); // Active until closed
      expect(record.isClosed, false);
      expect(record.resolvedAt, isNotNull);
    });

    test('ComplaintStatusHistoryRecord fromMap deserialization', () {
      final historyMap = {
        'id': 'h-01',
        'complaint_id': 'c-101',
        'from_status': 'in_progress',
        'to_status': 'resolved',
        'note': 'Work completed by technician',
        'changed_by': 'admin-uuid',
        'changed_by_role': 'society_admin',
        'created_at': '2026-09-01T14:30:00.000Z',
      };

      final history = ComplaintStatusHistoryRecord.fromMap(historyMap);

      expect(history.id, 'h-01');
      expect(history.complaintId, 'c-101');
      expect(history.fromStatus, ComplaintStatus.inProgress);
      expect(history.toStatus, ComplaintStatus.resolved);
      expect(history.note, 'Work completed by technician');
      expect(history.changedByRole, 'society_admin');
      expect(history.isByAdmin, true);
      expect(history.isByResident, false);
      expect(history.roleLabel, 'Society Admin');
    });
  });
}
