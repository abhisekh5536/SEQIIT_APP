import 'package:flutter/material.dart';

/// Supported types of resident vehicles.
enum VehicleType {
  twoWheeler,
  fourWheeler,
  other;

  static VehicleType fromString(String? val) {
    return switch (val?.toLowerCase().trim()) {
      'two_wheeler' || '2w' || 'bike' || 'scooter' => VehicleType.twoWheeler,
      'four_wheeler' || '4w' || 'car' || 'suv' || 'sedan' => VehicleType.fourWheeler,
      _ => VehicleType.other,
    };
  }

  String toDbValue() {
    return switch (this) {
      VehicleType.twoWheeler => 'two_wheeler',
      VehicleType.fourWheeler => 'four_wheeler',
      VehicleType.other => 'other',
    };
  }

  String get label => switch (this) {
    VehicleType.twoWheeler => '2-Wheeler (Bike/Scooter)',
    VehicleType.fourWheeler => '4-Wheeler (Car/SUV)',
    VehicleType.other => 'Other Vehicle',
  };

  String get shortLabel => switch (this) {
    VehicleType.twoWheeler => '2 Wheeler',
    VehicleType.fourWheeler => '4 Wheeler',
    VehicleType.other => 'Other',
  };

  IconData get icon => switch (this) {
    VehicleType.twoWheeler => Icons.two_wheeler_rounded,
    VehicleType.fourWheeler => Icons.directions_car_rounded,
    VehicleType.other => Icons.electric_rickshaw_rounded,
  };
}

/// Physical parking slot category.
enum SlotCategory {
  covered,
  open;

  static SlotCategory fromString(String? val) {
    return switch (val?.toLowerCase().trim()) {
      'open' => SlotCategory.open,
      _ => SlotCategory.covered,
    };
  }

  String toDbValue() {
    return switch (this) {
      SlotCategory.covered => 'covered',
      SlotCategory.open => 'open',
    };
  }

  String get label => switch (this) {
    SlotCategory.covered => 'Covered',
    SlotCategory.open => 'Open-air',
  };

  IconData get icon => switch (this) {
    SlotCategory.covered => Icons.roofing_rounded,
    SlotCategory.open => Icons.wb_sunny_outlined,
  };
}

/// Current status of a physical parking slot.
enum SlotStatus {
  vacant,
  allocated,
  reserved,
  maintenance;

  static SlotStatus fromString(String? val) {
    return switch (val?.toLowerCase().trim()) {
      'allocated' => SlotStatus.allocated,
      'reserved' => SlotStatus.reserved,
      'maintenance' => SlotStatus.maintenance,
      _ => SlotStatus.vacant,
    };
  }

  String toDbValue() {
    return switch (this) {
      SlotStatus.vacant => 'vacant',
      SlotStatus.allocated => 'allocated',
      SlotStatus.reserved => 'reserved',
      SlotStatus.maintenance => 'maintenance',
    };
  }

  String get label => switch (this) {
    SlotStatus.vacant => 'Vacant',
    SlotStatus.allocated => 'Allocated',
    SlotStatus.reserved => 'Reserved',
    SlotStatus.maintenance => 'Maintenance',
  };

  IconData get icon => switch (this) {
    SlotStatus.vacant => Icons.check_circle_outline_rounded,
    SlotStatus.allocated => Icons.local_parking_rounded,
    SlotStatus.reserved => Icons.bookmark_border_rounded,
    SlotStatus.maintenance => Icons.build_circle_outlined,
  };
}

/// Status of an active or past allocation.
enum AllocationStatus {
  active,
  ended;

  static AllocationStatus fromString(String? val) {
    return switch (val?.toLowerCase().trim()) {
      'ended' => AllocationStatus.ended,
      _ => AllocationStatus.active,
    };
  }

  String toDbValue() => this == AllocationStatus.ended ? 'ended' : 'active';
  String get label => this == AllocationStatus.ended ? 'Ended' : 'Active';
}

/// Plate match result at the society gate.
enum MatchStatus {
  registered,
  unregistered;

  static MatchStatus fromString(String? val) {
    return switch (val?.toLowerCase().trim()) {
      'registered' => MatchStatus.registered,
      _ => MatchStatus.unregistered,
    };
  }

  String toDbValue() => this == MatchStatus.registered ? 'registered' : 'unregistered';
  String get label => this == MatchStatus.registered ? 'Registered Resident' : 'Unregistered Vehicle';
}

/// Model representing an individual resident vehicle.
class VehicleItem {
  final String id;
  final String societyId;
  final String flatId;
  final String? residentId;
  final VehicleType type;
  final String vehicleNumber;
  final String makeModel;
  final String? color;
  final String? rcPhotoUrl;
  final String status; // 'active' | 'inactive'
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Joined presentation data
  final String flatNumber;
  final String blockName;
  final String residentName;
  final String? residentPhone;
  final String residentType;
  final String? allocatedSlotNumber;
  final SlotCategory? allocatedSlotCategory;
  final String? allocationId;

  const VehicleItem({
    required this.id,
    required this.societyId,
    required this.flatId,
    this.residentId,
    required this.type,
    required this.vehicleNumber,
    required this.makeModel,
    this.color,
    this.rcPhotoUrl,
    this.status = 'active',
    this.createdAt,
    this.updatedAt,
    this.flatNumber = '—',
    this.blockName = '',
    this.residentName = 'Resident',
    this.residentPhone,
    this.residentType = 'resident',
    this.allocatedSlotNumber,
    this.allocatedSlotCategory,
    this.allocationId,
  });

  bool get isActive => status == 'active';
  bool get hasAllocatedSlot => allocatedSlotNumber != null && allocatedSlotNumber!.trim().isNotEmpty;

  String get flatDisplay =>
      blockName.isNotEmpty ? '$blockName · Flat $flatNumber' : 'Flat $flatNumber';

  /// Standard formatted Indian plate string (e.g. "MH 12 AB 1234")
  String get formattedPlate {
    final clean = vehicleNumber.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (clean.length == 10) {
      return '${clean.substring(0, 2)} ${clean.substring(2, 4)} ${clean.substring(4, 6)} ${clean.substring(6)}';
    }
    return vehicleNumber.toUpperCase();
  }

  factory VehicleItem.fromMap(Map<String, dynamic> m) {
    String flatNum = '—';
    String blkName = '';
    final flatMap = m['flats'];
    if (flatMap is Map<String, dynamic>) {
      flatNum = flatMap['flat_number']?.toString() ?? '—';
      final blockMap = flatMap['blocks'];
      if (blockMap is Map<String, dynamic>) {
        blkName = blockMap['name']?.toString() ?? '';
      }
    }

    String resName = 'Resident';
    String? resPhone;
    String resType = 'resident';
    final resMap = m['residents'];
    if (resMap is Map<String, dynamic>) {
      resName = resMap['full_name']?.toString() ?? 'Resident';
      resPhone = resMap['phone']?.toString();
      resType = resMap['resident_type']?.toString() ?? 'resident';
    }

    String? slotNum = m['allocated_slot_number']?.toString() ?? m['parking_slot']?.toString();
    SlotCategory? slotCat;
    String? allocId;

    final allocList = m['parking_allocations'];
    if (allocList is List && allocList.isNotEmpty) {
      Map<String, dynamic>? activeAlloc;
      for (final a in allocList) {
        if (a is Map) {
          final map = a.cast<String, dynamic>();
          if (map['status'] == 'active') {
            activeAlloc = map;
            break;
          }
          activeAlloc ??= map;
        }
      }
      if (activeAlloc != null) {
        allocId = activeAlloc['id']?.toString();
        final slotMap = activeAlloc['parking_slots'];
        if (slotMap is Map) {
          slotNum = slotMap['slot_number']?.toString();
          slotCat = SlotCategory.fromString(slotMap['category']?.toString());
        }
      }
    }

    final vNum = m['vehicle_number']?.toString() ?? m['registration_no']?.toString() ?? '';

    return VehicleItem(
      id: m['id']?.toString() ?? '',
      societyId: m['society_id']?.toString() ?? '',
      flatId: m['flat_id']?.toString() ?? '',
      residentId: m['resident_id']?.toString(),
      type: VehicleType.fromString(m['type']?.toString() ?? m['vehicle_type']?.toString()),
      vehicleNumber: vNum,
      makeModel: m['make_model']?.toString() ?? 'Vehicle',
      color: m['color']?.toString(),
      rcPhotoUrl: m['rc_photo_url']?.toString(),
      status: m['status']?.toString() ?? 'active',
      createdAt: m['created_at'] != null ? DateTime.tryParse(m['created_at'].toString()) : null,
      updatedAt: m['updated_at'] != null ? DateTime.tryParse(m['updated_at'].toString()) : null,
      flatNumber: flatNum,
      blockName: blkName,
      residentName: resName,
      residentPhone: resPhone,
      residentType: resType,
      allocatedSlotNumber: slotNum,
      allocatedSlotCategory: slotCat,
      allocationId: allocId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'society_id': societyId,
      'flat_id': flatId,
      'resident_id': residentId,
      'type': type.toDbValue(),
      'vehicle_number': vehicleNumber.replaceAll(RegExp(r'\s+'), '').toUpperCase(),
      'make_model': makeModel,
      'color': color,
      'rc_photo_url': rcPhotoUrl,
      'status': status,
    };
  }

  VehicleItem copyWith({
    String? id,
    String? societyId,
    String? flatId,
    String? residentId,
    VehicleType? type,
    String? vehicleNumber,
    String? makeModel,
    String? color,
    String? rcPhotoUrl,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? flatNumber,
    String? blockName,
    String? residentName,
    String? residentPhone,
    String? residentType,
    String? allocatedSlotNumber,
    SlotCategory? allocatedSlotCategory,
    String? allocationId,
  }) {
    return VehicleItem(
      id: id ?? this.id,
      societyId: societyId ?? this.societyId,
      flatId: flatId ?? this.flatId,
      residentId: residentId ?? this.residentId,
      type: type ?? this.type,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      makeModel: makeModel ?? this.makeModel,
      color: color ?? this.color,
      rcPhotoUrl: rcPhotoUrl ?? this.rcPhotoUrl,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      flatNumber: flatNumber ?? this.flatNumber,
      blockName: blockName ?? this.blockName,
      residentName: residentName ?? this.residentName,
      residentPhone: residentPhone ?? this.residentPhone,
      residentType: residentType ?? this.residentType,
      allocatedSlotNumber: allocatedSlotNumber ?? this.allocatedSlotNumber,
      allocatedSlotCategory: allocatedSlotCategory ?? this.allocatedSlotCategory,
      allocationId: allocationId ?? this.allocationId,
    );
  }
}

/// Active allocation summary inside a slot.
class ActiveSlotAllocation {
  final String allocationId;
  final String flatId;
  final String flatNumber;
  final String blockName;
  final String? residentName;
  final String? vehicleId;
  final String? vehicleNumber;
  final String? vehicleMakeModel;
  final DateTime? allocatedFrom;

  const ActiveSlotAllocation({
    required this.allocationId,
    required this.flatId,
    required this.flatNumber,
    required this.blockName,
    this.residentName,
    this.vehicleId,
    this.vehicleNumber,
    this.vehicleMakeModel,
    this.allocatedFrom,
  });

  String get flatDisplay =>
      blockName.isNotEmpty ? '$blockName · Flat $flatNumber' : 'Flat $flatNumber';
}

/// Model representing a physical parking bay in the society.
class ParkingSlotItem {
  final String id;
  final String societyId;
  final String? blockId;
  final String slotNumber;
  final VehicleType vehicleType;
  final SlotCategory category;
  final SlotStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Joined presentation data
  final String blockName;
  final ActiveSlotAllocation? activeAllocation;

  const ParkingSlotItem({
    required this.id,
    required this.societyId,
    this.blockId,
    required this.slotNumber,
    required this.vehicleType,
    required this.category,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.blockName = '',
    this.activeAllocation,
  });

  bool get isVacant => status == SlotStatus.vacant;
  bool get isAllocated => status == SlotStatus.allocated;
  bool get isUnderMaintenance => status == SlotStatus.maintenance;
  bool get isReserved => status == SlotStatus.reserved;

  factory ParkingSlotItem.fromMap(Map<String, dynamic> m) {
    String blkName = '';
    final blockMap = m['blocks'];
    if (blockMap is Map<String, dynamic>) {
      blkName = blockMap['name']?.toString() ?? '';
    }

    ActiveSlotAllocation? alloc;
    final allocList = m['parking_allocations'];
    if (allocList is List && allocList.isNotEmpty) {
      Map<String, dynamic>? active;
      for (final a in allocList) {
        if (a is Map) {
          final map = a.cast<String, dynamic>();
          if (map['status'] == 'active') {
            active = map;
            break;
          }
        }
      }
      if (active != null) {
        String fNum = '—';
        String fBlk = '';
        final fMap = active['flats'];
        if (fMap is Map<String, dynamic>) {
          fNum = fMap['flat_number']?.toString() ?? '—';
          final bMap = fMap['blocks'];
          if (bMap is Map<String, dynamic>) {
            fBlk = bMap['name']?.toString() ?? '';
          }
        }

        String? rName;
        final rMap = active['residents'];
        if (rMap is Map<String, dynamic>) {
          rName = rMap['full_name']?.toString();
        }

        String? vNum;
        String? vModel;
        final vMap = active['vehicles'];
        if (vMap is Map<String, dynamic>) {
          vNum = vMap['vehicle_number']?.toString();
          vModel = vMap['make_model']?.toString();
        }

        alloc = ActiveSlotAllocation(
          allocationId: active['id']?.toString() ?? '',
          flatId: active['flat_id']?.toString() ?? '',
          flatNumber: fNum,
          blockName: fBlk,
          residentName: rName,
          vehicleId: active['vehicle_id']?.toString(),
          vehicleNumber: vNum,
          vehicleMakeModel: vModel,
          allocatedFrom: active['allocated_from'] != null
              ? DateTime.tryParse(active['allocated_from'].toString())
              : null,
        );
      }
    }

    return ParkingSlotItem(
      id: m['id']?.toString() ?? '',
      societyId: m['society_id']?.toString() ?? '',
      blockId: m['block_id']?.toString(),
      slotNumber: m['slot_number']?.toString() ?? '',
      vehicleType: VehicleType.fromString(m['vehicle_type']?.toString()),
      category: SlotCategory.fromString(m['category']?.toString()),
      status: SlotStatus.fromString(m['status']?.toString()),
      createdAt: m['created_at'] != null ? DateTime.tryParse(m['created_at'].toString()) : null,
      updatedAt: m['updated_at'] != null ? DateTime.tryParse(m['updated_at'].toString()) : null,
      blockName: blkName,
      activeAllocation: alloc,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'society_id': societyId,
      'block_id': blockId,
      'slot_number': slotNumber,
      'vehicle_type': vehicleType.toDbValue(),
      'category': category.toDbValue(),
      'status': status.toDbValue(),
    };
  }

  ParkingSlotItem copyWith({
    String? id,
    String? societyId,
    String? blockId,
    String? slotNumber,
    VehicleType? vehicleType,
    SlotCategory? category,
    SlotStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? blockName,
    ActiveSlotAllocation? activeAllocation,
  }) {
    return ParkingSlotItem(
      id: id ?? this.id,
      societyId: societyId ?? this.societyId,
      blockId: blockId ?? this.blockId,
      slotNumber: slotNumber ?? this.slotNumber,
      vehicleType: vehicleType ?? this.vehicleType,
      category: category ?? this.category,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      blockName: blockName ?? this.blockName,
      activeAllocation: activeAllocation ?? this.activeAllocation,
    );
  }
}

/// Model representing an allocation of a slot to a flat/resident/vehicle.
class ParkingAllocationItem {
  final String id;
  final String societyId;
  final String slotId;
  final String flatId;
  final String? residentId;
  final String? vehicleId;
  final DateTime allocatedFrom;
  final DateTime? allocatedUntil;
  final AllocationStatus status;
  final String? allocatedBy;
  final String? notes;
  final DateTime? createdAt;

  // Presentation metadata
  final String slotNumber;
  final SlotCategory slotCategory;
  final VehicleType slotVehicleType;
  final String flatNumber;
  final String blockName;
  final String residentName;
  final String? vehicleNumber;
  final String? vehicleMakeModel;

  const ParkingAllocationItem({
    required this.id,
    required this.societyId,
    required this.slotId,
    required this.flatId,
    this.residentId,
    this.vehicleId,
    required this.allocatedFrom,
    this.allocatedUntil,
    required this.status,
    this.allocatedBy,
    this.notes,
    this.createdAt,
    this.slotNumber = '—',
    this.slotCategory = SlotCategory.covered,
    this.slotVehicleType = VehicleType.fourWheeler,
    this.flatNumber = '—',
    this.blockName = '',
    this.residentName = 'Resident',
    this.vehicleNumber,
    this.vehicleMakeModel,
  });

  bool get isActive => status == AllocationStatus.active;
  String get flatDisplay =>
      blockName.isNotEmpty ? '$blockName · Flat $flatNumber' : 'Flat $flatNumber';

  factory ParkingAllocationItem.fromMap(Map<String, dynamic> m) {
    String slotNum = '—';
    SlotCategory slotCat = SlotCategory.covered;
    VehicleType slotVType = VehicleType.fourWheeler;
    final slotMap = m['parking_slots'];
    if (slotMap is Map<String, dynamic>) {
      slotNum = slotMap['slot_number']?.toString() ?? '—';
      slotCat = SlotCategory.fromString(slotMap['category']?.toString());
      slotVType = VehicleType.fromString(slotMap['vehicle_type']?.toString());
    }

    String flatNum = '—';
    String blkName = '';
    final flatMap = m['flats'];
    if (flatMap is Map<String, dynamic>) {
      flatNum = flatMap['flat_number']?.toString() ?? '—';
      final bMap = flatMap['blocks'];
      if (bMap is Map<String, dynamic>) {
        blkName = bMap['name']?.toString() ?? '';
      }
    }

    String resName = 'Resident';
    final resMap = m['residents'];
    if (resMap is Map<String, dynamic>) {
      resName = resMap['full_name']?.toString() ?? 'Resident';
    }

    String? vNum;
    String? vModel;
    final vehMap = m['vehicles'];
    if (vehMap is Map<String, dynamic>) {
      vNum = vehMap['vehicle_number']?.toString();
      vModel = vehMap['make_model']?.toString();
    }

    return ParkingAllocationItem(
      id: m['id']?.toString() ?? '',
      societyId: m['society_id']?.toString() ?? '',
      slotId: m['slot_id']?.toString() ?? '',
      flatId: m['flat_id']?.toString() ?? '',
      residentId: m['resident_id']?.toString(),
      vehicleId: m['vehicle_id']?.toString(),
      allocatedFrom: m['allocated_from'] != null
          ? DateTime.tryParse(m['allocated_from'].toString()) ?? DateTime.now()
          : DateTime.now(),
      allocatedUntil: m['allocated_until'] != null
          ? DateTime.tryParse(m['allocated_until'].toString())
          : null,
      status: AllocationStatus.fromString(m['status']?.toString()),
      allocatedBy: m['allocated_by']?.toString(),
      notes: m['notes']?.toString(),
      createdAt: m['created_at'] != null ? DateTime.tryParse(m['created_at'].toString()) : null,
      slotNumber: slotNum,
      slotCategory: slotCat,
      slotVehicleType: slotVType,
      flatNumber: flatNum,
      blockName: blkName,
      residentName: resName,
      vehicleNumber: vNum,
      vehicleMakeModel: vModel,
    );
  }
}

/// Model representing a gate entry / exit log record.
class VehicleEntryLogItem {
  final String id;
  final String societyId;
  final String? vehicleId;
  final String vehicleNumberEntered;
  final MatchStatus matchStatus;
  final DateTime entryAt;
  final DateTime? exitAt;
  final String? loggedBy;
  final String? notes;
  final DateTime? createdAt;

  // Optional joined information
  final String? flatNumber;
  final String? blockName;
  final String? residentName;
  final String? makeModel;

  const VehicleEntryLogItem({
    required this.id,
    required this.societyId,
    this.vehicleId,
    required this.vehicleNumberEntered,
    required this.matchStatus,
    required this.entryAt,
    this.exitAt,
    this.loggedBy,
    this.notes,
    this.createdAt,
    this.flatNumber,
    this.blockName,
    this.residentName,
    this.makeModel,
  });

  bool get isExited => exitAt != null;

  String get flatDisplay {
    if (flatNumber == null) return '—';
    if (blockName != null && blockName!.isNotEmpty) {
      return '$blockName · Flat $flatNumber';
    }
    return 'Flat $flatNumber';
  }

  factory VehicleEntryLogItem.fromMap(Map<String, dynamic> m) {
    String? fNum;
    String? bName;
    String? rName;
    String? vModel;

    final vMap = m['vehicles'];
    if (vMap is Map<String, dynamic>) {
      vModel = vMap['make_model']?.toString();
      final fMap = vMap['flats'];
      if (fMap is Map<String, dynamic>) {
        fNum = fMap['flat_number']?.toString();
        final bMap = fMap['blocks'];
        if (bMap is Map<String, dynamic>) {
          bName = bMap['name']?.toString();
        }
      }
      final rMap = vMap['residents'];
      if (rMap is Map<String, dynamic>) {
        rName = rMap['full_name']?.toString();
      }
    }

    return VehicleEntryLogItem(
      id: m['id']?.toString() ?? '',
      societyId: m['society_id']?.toString() ?? '',
      vehicleId: m['vehicle_id']?.toString(),
      vehicleNumberEntered: m['vehicle_number_entered']?.toString() ?? '',
      matchStatus: MatchStatus.fromString(m['match_status']?.toString()),
      entryAt: m['entry_at'] != null
          ? DateTime.tryParse(m['entry_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      exitAt: m['exit_at'] != null ? DateTime.tryParse(m['exit_at'].toString()) : null,
      loggedBy: m['logged_by']?.toString(),
      notes: m['notes']?.toString(),
      createdAt: m['created_at'] != null ? DateTime.tryParse(m['created_at'].toString()) : null,
      flatNumber: fNum,
      blockName: bName,
      residentName: rName,
      makeModel: vModel,
    );
  }
}

/// Society-level parking configuration.
class ParkingPolicyConfig {
  final String societyId;
  final int maxSlotsPerFlat;
  final bool requireVehicleBinding;

  const ParkingPolicyConfig({
    required this.societyId,
    this.maxSlotsPerFlat = 2,
    this.requireVehicleBinding = false,
  });

  factory ParkingPolicyConfig.fromMap(Map<String, dynamic> m) {
    return ParkingPolicyConfig(
      societyId: m['society_id']?.toString() ?? '',
      maxSlotsPerFlat: (m['max_slots_per_flat'] is int)
          ? m['max_slots_per_flat'] as int
          : int.tryParse(m['max_slots_per_flat']?.toString() ?? '2') ?? 2,
      requireVehicleBinding: m['require_vehicle_binding'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'society_id': societyId,
      'max_slots_per_flat': maxSlotsPerFlat,
      'require_vehicle_binding': requireVehicleBinding,
    };
  }
}

/// Result returned from rapid plate lookup at the security gate.
class PlateLookupResult {
  final bool found;
  final MatchStatus matchStatus;
  final String normalizedQuery;
  final String? vehicleId;
  final String? vehicleNumber;
  final String? makeModel;
  final String? color;
  final VehicleType? type;
  final String? flatId;
  final String? flatNumber;
  final String? blockName;
  final String? residentId;
  final String? residentName;
  final String? residentPhone;
  final String? slotId;
  final String? slotNumber;
  final SlotCategory? slotCategory;

  const PlateLookupResult({
    required this.found,
    required this.matchStatus,
    required this.normalizedQuery,
    this.vehicleId,
    this.vehicleNumber,
    this.makeModel,
    this.color,
    this.type,
    this.flatId,
    this.flatNumber,
    this.blockName,
    this.residentId,
    this.residentName,
    this.residentPhone,
    this.slotId,
    this.slotNumber,
    this.slotCategory,
  });

  bool get isRegistered => matchStatus == MatchStatus.registered;

  String get flatDisplay {
    if (flatNumber == null) return '—';
    if (blockName != null && blockName!.isNotEmpty) {
      return '$blockName · Flat $flatNumber';
    }
    return 'Flat $flatNumber';
  }

  factory PlateLookupResult.fromMap(Map<String, dynamic> m, String rawQuery) {
    final isFound = m['found'] == true;
    final match = MatchStatus.fromString(m['match_status']?.toString());
    return PlateLookupResult(
      found: isFound,
      matchStatus: match,
      normalizedQuery: m['normalized_query']?.toString() ?? rawQuery,
      vehicleId: m['vehicle_id']?.toString(),
      vehicleNumber: m['vehicle_number']?.toString(),
      makeModel: m['make_model']?.toString(),
      color: m['color']?.toString(),
      type: m['type'] != null ? VehicleType.fromString(m['type']?.toString()) : null,
      flatId: m['flat_id']?.toString(),
      flatNumber: m['flat_number']?.toString(),
      blockName: m['block_name']?.toString(),
      residentId: m['resident_id']?.toString(),
      residentName: m['resident_name']?.toString(),
      residentPhone: m['resident_phone']?.toString(),
      slotId: m['slot_id']?.toString(),
      slotNumber: m['slot_number']?.toString(),
      slotCategory: m['slot_category'] != null
          ? SlotCategory.fromString(m['slot_category']?.toString())
          : null,
    );
  }
}
