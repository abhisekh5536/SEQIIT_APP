import 'package:flutter_test/flutter_test.dart';

import 'package:society_management/models/guard_models.dart';
import 'package:society_management/models/visitor_models.dart';
import 'package:society_management/screens/guard/widgets/guard_widgets.dart';

VisitorRecord _visitor({
  VisitorCategory category = VisitorCategory.guest,
  String status = 'checked_in',
  DateTime? checkedInAt,
  DateTime? validUntil,
}) {
  return VisitorRecord.fromMap({
    'id': 'v1',
    'society_id': 's1',
    'flat_id': 'f1',
    'visitor_name': 'Amit',
    'category': category.dbValue,
    'entry_type': validUntil != null ? 'pre_approved' : 'gate_request',
    'status': status,
    'checked_in_at': checkedInAt?.toIso8601String(),
    'valid_until': validUntil?.toIso8601String(),
    'created_at': DateTime.now().toIso8601String(),
    'updated_at': DateTime.now().toIso8601String(),
  });
}

void main() {
  group('GuardProfile', () {
    test('parses the embedded default gate and derives names', () {
      final g = GuardProfile.fromMap({
        'id': 'g1',
        'society_id': 's1',
        'user_id': null,
        'full_name': 'Ramesh Kumar Yadav',
        'email': 'ramesh@example.com',
        'phone': '9876500100',
        'agency_name': '  ',
        'employee_code': 'SIS-44',
        'default_gate_id': 'gate1',
        'default_gate': {'id': 'gate1', 'name': 'Main Gate'},
        'status': 'active',
        'created_at': '2026-09-01T10:00:00Z',
      });

      expect(g.firstName, 'Ramesh');
      expect(g.initials, 'RY');
      expect(g.defaultGateName, 'Main Gate');
      expect(g.agencyName, isNull, reason: 'blank strings are not agencies');
      expect(g.employeeCode, 'SIS-44');
      expect(g.isLinked, isFalse);
      expect(g.isActive, isTrue);
    });

    test('an inactive row is not active', () {
      final g = GuardProfile.fromMap({
        'id': 'g1',
        'full_name': 'Sita',
        'status': 'inactive',
        'user_id': 'u1',
      });
      expect(g.isActive, isFalse);
      expect(g.isLinked, isTrue);
      expect(g.initials, 'S');
    });
  });

  group('ExpectedVisitor', () {
    final now = DateTime(2026, 9, 28, 12);

    test('a pass that starts later says when', () {
      final e = ExpectedVisitor.fromMap({
        'id': 'v1',
        'visitor_name': 'Sharma family',
        'category': 'group_invite',
        'flat_id': 'f1',
        'flat_number': '204',
        'block_name': 'B',
        'valid_from': DateTime(2026, 9, 28, 18, 30).toIso8601String(),
        'valid_until': DateTime(2026, 9, 28, 23, 59).toIso8601String(),
        'group_size': 3,
      });
      expect(e.isActiveAt(now), isFalse);
      expect(e.windowLabel(now), 'From 6:30 PM');
      expect(e.flatDisplay, 'B · Flat 204');
      expect(e.groupSize, 3);
      expect(e.category, VisitorCategory.groupInvite);
    });

    test('a live pass says until when', () {
      final e = ExpectedVisitor.fromMap({
        'id': 'v1',
        'visitor_name': 'Amit',
        'category': 'guest',
        'flat_id': 'f1',
        'valid_from': DateTime(2026, 9, 28, 9).toIso8601String(),
        'valid_until': DateTime(2026, 9, 28, 23, 59).toIso8601String(),
      });
      expect(e.isActiveAt(now), isTrue);
      expect(e.windowLabel(now), 'Until 11:59 PM');
    });
  });

  group('overstay', () {
    final now = DateTime.now();

    test('a delivery inside for 25 minutes is overstaying', () {
      final v = _visitor(
        category: VisitorCategory.delivery,
        checkedInAt: now.subtract(const Duration(minutes: 25)),
      );
      expect(isOverstaying(v, now), isTrue);
    });

    test('a guest inside for an hour is not', () {
      final v = _visitor(checkedInAt: now.subtract(const Duration(hours: 1)));
      expect(isOverstaying(v, now), isFalse);
    });

    test('a pre-approval past its window is, whatever the category', () {
      final v = _visitor(
        checkedInAt: now.subtract(const Duration(minutes: 5)),
        validUntil: now.subtract(const Duration(minutes: 1)),
      );
      expect(isOverstaying(v, now), isTrue);
    });

    test('someone not inside cannot overstay', () {
      final v = _visitor(
        status: 'checked_out',
        checkedInAt: now.subtract(const Duration(days: 1)),
      );
      expect(isOverstaying(v, now), isFalse);
    });
  });

  test('approved_via marks approvals recorded from a phone call', () {
    final v = VisitorRecord.fromMap({
      'id': 'v1',
      'status': 'approved',
      'approved_via': 'guard_call',
    });
    expect(v.isApprovedOnCall, isTrue);
    expect(_visitor(status: 'approved').isApprovedOnCall, isFalse);
  });

  test('the gate timer reads m:ss, then hours', () {
    expect(ElapsedText.format(const Duration(seconds: 75)), '1:15');
    expect(ElapsedText.format(const Duration(minutes: 125)), '2h 05m');
    expect(ElapsedText.format(const Duration(seconds: -3)), '0:00');
  });

  test('server errors reach the guard without the Dart prefix', () {
    expect(
      gateErrorText(Exception('Call the flat first.')),
      'Call the flat first.',
    );
  });
}
