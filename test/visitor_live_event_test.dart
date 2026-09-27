import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/models/visitor_models.dart';
import 'package:society_management/services/visitors_service.dart';

VisitorRecord _visitor({
  String id = 'v-1',
  String status = 'pending_approval',
  String flatId = 'f-101',
}) {
  return VisitorRecord.fromMap({
    'id': id,
    'society_id': 'soc-1',
    'flat_id': flatId,
    'visitor_name': 'Ramesh Kumar',
    'category': 'guest',
    'entry_type': 'gate_request',
    'status': status,
    'created_at': '2026-09-22T09:00:00Z',
    'flats': {
      'flat_number': '101',
      'blocks': {'name': 'Tower A'},
    },
  });
}

void main() {
  group('VisitorLiveEvent', () {
    test('a fresh gate request is what the resident must be shown', () {
      final e = VisitorLiveEvent(visitor: _visitor(), isNew: true);
      expect(e.isNewGateRequest, isTrue);
      expect(e.isApprovalDecision, isFalse);
    });

    test('pending -> approved is the decision the guard is waiting on', () {
      final e = VisitorLiveEvent(
        visitor: _visitor(status: 'approved'),
        previousStatus: VisitorStatus.pendingApproval,
      );
      expect(e.isApprovalDecision, isTrue);
      expect(e.isNewGateRequest, isFalse);
    });

    test('pending -> denied is equally a decision', () {
      final e = VisitorLiveEvent(
        visitor: _visitor(status: 'denied'),
        previousStatus: VisitorStatus.pendingApproval,
      );
      expect(e.isApprovalDecision, isTrue);
    });

    test('approved -> checked_in is not an approval decision', () {
      final e = VisitorLiveEvent(
        visitor: _visitor(status: 'checked_in'),
        previousStatus: VisitorStatus.approved,
      );
      expect(e.isApprovalDecision, isFalse);
      expect(e.isNewGateRequest, isFalse);
    });

    test('a row inserted already approved does not fire the guard alert', () {
      // Pre-approvals are created straight into 'approved'; nobody is being
      // held at the barrier, so this must not announce a decision.
      final e = VisitorLiveEvent(
        visitor: _visitor(status: 'approved'),
        isNew: true,
      );
      expect(e.isApprovalDecision, isFalse);
      expect(e.isNewGateRequest, isFalse);
    });

    test('an update with no known previous status stays quiet', () {
      // Without REPLICA IDENTITY FULL the old row is unavailable; better to
      // refresh silently than to shout a decision that may not have happened.
      final e = VisitorLiveEvent(visitor: _visitor(status: 'approved'));
      expect(e.isApprovalDecision, isFalse);
    });

    test('carries the flat id so a resident can filter to their own flats', () {
      final e = VisitorLiveEvent(
        visitor: _visitor(flatId: 'f-202'),
        isNew: true,
      );
      expect(e.visitor.flatId, 'f-202');
    });
  });

  group('LiveStatus', () {
    test('only the subscribed state counts as live', () {
      expect(LiveStatus.values, contains(LiveStatus.live));
      expect(
        LiveStatus.values.where((s) => s != LiveStatus.live).toList(),
        [LiveStatus.idle, LiveStatus.connecting, LiveStatus.degraded],
      );
    });
  });
}
