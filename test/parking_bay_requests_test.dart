import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/models/vehicle_parking_models.dart';

void main() {
  group('normalizePlate', () {
    test('strips every separator and upper-cases', () {
      expect(normalizePlate('mh 12 ab 1234'), 'MH12AB1234');
      expect(normalizePlate('MH-12-AB-1234'), 'MH12AB1234');
      expect(normalizePlate('  MH12ab1234 '), 'MH12AB1234');
      expect(normalizePlate('MH.12/AB_1234'), 'MH12AB1234');
    });

    test('every spelling of one plate collapses to the same key', () {
      const spellings = [
        'MH 12 AB 1234',
        'mh-12-ab-1234',
        'MH12AB1234',
        ' Mh12Ab1234 ',
      ];
      final normalized = spellings.map(normalizePlate).toSet();
      expect(
        normalized.length,
        1,
        reason: 'gate register and vehicle registry must agree on one form',
      );
    });

    test('leaves an empty string empty rather than throwing', () {
      expect(normalizePlate(''), '');
      expect(normalizePlate('---'), '');
    });
  });

  group('BayRequestStatus', () {
    test('maps database values, defaulting unknown to pending', () {
      expect(BayRequestStatus.fromString('approved'), BayRequestStatus.approved);
      expect(BayRequestStatus.fromString('rejected'), BayRequestStatus.rejected);
      expect(
          BayRequestStatus.fromString('cancelled'), BayRequestStatus.cancelled);
      expect(BayRequestStatus.fromString('pending'), BayRequestStatus.pending);
      expect(BayRequestStatus.fromString(null), BayRequestStatus.pending);
      expect(BayRequestStatus.fromString('nonsense'), BayRequestStatus.pending);
    });

    test('round-trips through toDbValue', () {
      for (final s in BayRequestStatus.values) {
        expect(BayRequestStatus.fromString(s.toDbValue()), s);
      }
    });
  });

  group('ParkingBayRequestItem.fromMap', () {
    Map<String, dynamic> baseMap({
      String status = 'pending',
      String? category = 'covered',
      Map<String, dynamic>? vehicle,
      String? reviewNotes,
    }) {
      return {
        'id': 'req-1',
        'society_id': 'soc-1',
        'flat_id': 'f-101',
        'resident_id': 'r-1',
        'vehicle_id': vehicle != null ? 'v-1' : null,
        'preferred_category': category,
        'notes': 'Prefer basement near lift',
        'status': status,
        'review_notes': reviewNotes,
        'created_at': '2026-09-20T10:30:00Z',
        'flats': {
          'flat_number': '101',
          'blocks': {'name': 'Tower A'},
        },
        'residents': {'full_name': 'Asha Rao', 'phone': '9876543210'},
        'vehicles': vehicle,
      };
    }

    test('resolves joined flat, resident and vehicle metadata', () {
      final r = ParkingBayRequestItem.fromMap(baseMap(
        vehicle: {
          'vehicle_number': 'MH12AB1234',
          'make_model': 'Hyundai Creta',
          'type': 'four_wheeler',
        },
      ));

      expect(r.id, 'req-1');
      expect(r.flatDisplay, 'Tower A · Flat 101');
      expect(r.residentName, 'Asha Rao');
      expect(r.residentPhone, '9876543210');
      expect(r.vehicleDisplay, 'MH12AB1234 · Hyundai Creta');
      expect(r.vehicleType, VehicleType.fourWheeler);
      expect(r.preferredCategory, SlotCategory.covered);
      expect(r.categoryLabel, 'Covered');
      expect(r.isPending, isTrue);
      expect(r.isResolved, isFalse);
    });

    test('a request with no vehicle tied reads as a flat-level request', () {
      final r = ParkingBayRequestItem.fromMap(baseMap());
      expect(r.vehicleId, isNull);
      expect(r.vehicleDisplay, 'No specific vehicle');
    });

    test('null preferred category means no preference, not covered', () {
      final r = ParkingBayRequestItem.fromMap(baseMap(category: null));
      expect(r.preferredCategory, isNull);
      expect(r.categoryLabel, 'Any category');
    });

    test('empty preferred category is treated as no preference', () {
      final r = ParkingBayRequestItem.fromMap(baseMap(category: ''));
      expect(r.preferredCategory, isNull);
      expect(r.categoryLabel, 'Any category');
    });

    test('a declined request carries the office reason back to the resident',
        () {
      final r = ParkingBayRequestItem.fromMap(baseMap(
        status: 'rejected',
        reviewNotes: 'No covered bays free; added to waitlist',
      ));

      expect(r.status, BayRequestStatus.rejected);
      expect(r.isPending, isFalse);
      expect(r.isResolved, isTrue);
      expect(r.reviewNotes, 'No covered bays free; added to waitlist');
      expect(r.status.label, 'Declined');
    });

    test('flat display omits the separator when there is no block', () {
      final map = baseMap();
      map['flats'] = {'flat_number': '101'};
      final r = ParkingBayRequestItem.fromMap(map);
      expect(r.flatDisplay, 'Flat 101');
    });

    test('a malformed row degrades to safe defaults instead of throwing', () {
      final r = ParkingBayRequestItem.fromMap({'id': 'req-2'});
      expect(r.id, 'req-2');
      expect(r.status, BayRequestStatus.pending);
      expect(r.residentName, 'Resident');
      expect(r.flatNumber, '—');
      expect(r.createdAt, isA<DateTime>());
    });
  });
}
