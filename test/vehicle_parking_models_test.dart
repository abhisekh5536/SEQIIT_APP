import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/models/vehicle_parking_models.dart';

void main() {
  group('VehicleItem tests', () {
    test('parses from Map correctly and handles Indian plate formatting', () {
      final map = {
        'id': 'v-1',
        'society_id': 'soc-1',
        'flat_id': 'f-101',
        'resident_id': 'r-1',
        'type': 'four_wheeler',
        'vehicle_number': 'MH12AB1234',
        'make_model': 'Hyundai Creta',
        'color': 'Polar White',
        'status': 'active',
        'flats': {
          'flat_number': '101',
          'blocks': {'name': 'Tower A'},
        },
        'residents': {
          'full_name': 'Abhishek Sharma',
          'phone': '+91 9876543210',
          'resident_type': 'owner',
        },
        'parking_allocations': [
          {
            'id': 'alloc-1',
            'status': 'active',
            'parking_slots': {
              'slot_number': 'P-101',
              'category': 'covered',
            },
          },
        ],
      };

      final item = VehicleItem.fromMap(map);

      expect(item.id, 'v-1');
      expect(item.vehicleNumber, 'MH12AB1234');
      expect(item.formattedPlate, 'MH 12 AB 1234');
      expect(item.type, VehicleType.fourWheeler);
      expect(item.isActive, true);
      expect(item.hasAllocatedSlot, true);
      expect(item.allocatedSlotNumber, 'P-101');
      expect(item.allocatedSlotCategory, SlotCategory.covered);
      expect(item.flatDisplay, 'Tower A · Flat 101');
      expect(item.residentName, 'Abhishek Sharma');
    });

    test('handles unallocated / waitlisted vehicle', () {
      final map = {
        'id': 'v-2',
        'society_id': 'soc-1',
        'flat_id': 'f-202',
        'type': 'two_wheeler',
        'vehicle_number': 'DL01ZZ9999',
        'make_model': 'Honda Activa',
        'status': 'active',
        'flats': {
          'flat_number': '202',
        },
      };

      final item = VehicleItem.fromMap(map);

      expect(item.hasAllocatedSlot, false);
      expect(item.allocatedSlotNumber, null);
      expect(item.type, VehicleType.twoWheeler);
      expect(item.formattedPlate, 'DL 01 ZZ 9999');
    });
  });

  group('ParkingSlotItem tests', () {
    test('parses slot with active allocation', () {
      final map = {
        'id': 'slot-101',
        'society_id': 'soc-1',
        'slot_number': 'P-101',
        'vehicle_type': 'four_wheeler',
        'category': 'covered',
        'status': 'allocated',
        'blocks': {'name': 'Tower A'},
        'parking_allocations': [
          {
            'id': 'alloc-1',
            'flat_id': 'f-101',
            'status': 'active',
            'allocated_from': '2026-09-01T10:00:00Z',
            'flats': {
              'flat_number': '101',
              'blocks': {'name': 'Tower A'},
            },
            'residents': {'full_name': 'Abhishek Sharma'},
            'vehicles': {'vehicle_number': 'MH 12 AB 1234', 'make_model': 'Hyundai Creta'},
          },
        ],
      };

      final slot = ParkingSlotItem.fromMap(map);

      expect(slot.id, 'slot-101');
      expect(slot.slotNumber, 'P-101');
      expect(slot.isAllocated, true);
      expect(slot.isVacant, false);
      expect(slot.category, SlotCategory.covered);
      expect(slot.blockName, 'Tower A');
      expect(slot.activeAllocation, isNotNull);
      expect(slot.activeAllocation!.flatNumber, '101');
      expect(slot.activeAllocation!.residentName, 'Abhishek Sharma');
      expect(slot.activeAllocation!.vehicleNumber, 'MH 12 AB 1234');
    });

    test('parses vacant slot without allocations', () {
      final map = {
        'id': 'slot-102',
        'society_id': 'soc-1',
        'slot_number': 'P-102',
        'vehicle_type': 'four_wheeler',
        'category': 'open',
        'status': 'vacant',
      };

      final slot = ParkingSlotItem.fromMap(map);

      expect(slot.isVacant, true);
      expect(slot.isAllocated, false);
      expect(slot.category, SlotCategory.open);
      expect(slot.activeAllocation, isNull);
    });
  });

  group('PlateLookupResult tests', () {
    test('parses registered plate match', () {
      final map = {
        'found': true,
        'match_status': 'registered',
        'vehicle_id': 'v-1',
        'vehicle_number': 'MH12AB1234',
        'make_model': 'Hyundai Creta',
        'color': 'White',
        'type': 'four_wheeler',
        'flat_number': '101',
        'block_name': 'Tower A',
        'resident_name': 'Abhishek Sharma',
        'resident_phone': '+91 9876543210',
        'slot_number': 'P-101',
        'slot_category': 'covered',
      };

      final res = PlateLookupResult.fromMap(map, 'MH12AB1234');

      expect(res.found, true);
      expect(res.isRegistered, true);
      expect(res.flatDisplay, 'Tower A · Flat 101');
      expect(res.slotNumber, 'P-101');
      expect(res.slotCategory, SlotCategory.covered);
    });

    test('parses unregistered plate', () {
      final map = {
        'found': false,
        'match_status': 'unregistered',
        'normalized_query': 'KA01ZZ0000',
      };

      final res = PlateLookupResult.fromMap(map, 'KA01ZZ0000');

      expect(res.found, false);
      expect(res.isRegistered, false);
      expect(res.matchStatus, MatchStatus.unregistered);
      expect(res.flatDisplay, '—');
    });
  });

  group('ParkingPolicyConfig tests', () {
    test('parses policy config values', () {
      final map = {
        'society_id': 'soc-1',
        'max_slots_per_flat': 3,
        'require_vehicle_binding': true,
      };

      final cfg = ParkingPolicyConfig.fromMap(map);

      expect(cfg.societyId, 'soc-1');
      expect(cfg.maxSlotsPerFlat, 3);
      expect(cfg.requireVehicleBinding, true);
    });

    test('defaults to 2 max slots and false binding', () {
      final cfg = ParkingPolicyConfig.fromMap({'society_id': 'soc-2'});

      expect(cfg.maxSlotsPerFlat, 2);
      expect(cfg.requireVehicleBinding, false);
    });
  });
}
