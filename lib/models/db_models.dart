/// Rows mapped directly from the Supabase database.
library;

class BlockInfo {
  final String id;
  final String societyId;
  final String name;

  const BlockInfo({required this.id, required this.societyId, required this.name});

  factory BlockInfo.fromMap(Map<String, dynamic> m) => BlockInfo(
        id: m['id']?.toString() ?? '',
        societyId: m['society_id']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
      );
}

class FlatInfo {
  final String id;
  final String blockId;
  final int floorNumber;
  final String flatNumber;
  final String type;
  final String status;

  const FlatInfo({
    required this.id,
    required this.blockId,
    required this.floorNumber,
    required this.flatNumber,
    required this.type,
    required this.status,
  });

  bool get isOccupied => status == 'occupied';

  factory FlatInfo.fromMap(Map<String, dynamic> m) => FlatInfo(
        id: m['id']?.toString() ?? '',
        blockId: m['block_id']?.toString() ?? '',
        floorNumber: (m['floor_number'] is int ? m['floor_number'] as int : int.tryParse(m['floor_number']?.toString() ?? '0') ?? 0),
        flatNumber: m['flat_number']?.toString() ?? '',
        type: m['type']?.toString() ?? '',
        status: m['status']?.toString() ?? 'vacant',
      );
}

class ResidentRecord {
  final String id;
  final String societyId;
  final String flatId;
  final String? userId;
  final String fullName;
  final String email;
  final String? phone;
  final String? relation;
  final String residentType;
  final bool isPrimary;
  final String? agreementHolderName;
  final DateTime? agreementDate;
  final String? aadharLast4;
  final String status;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ResidentRecord({
    required this.id,
    required this.societyId,
    required this.flatId,
    this.userId,
    required this.fullName,
    required this.email,
    this.phone,
    this.relation,
    required this.residentType,
    required this.isPrimary,
    this.agreementHolderName,
    this.agreementDate,
    this.aadharLast4,
    required this.status,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  bool get isActive => status == 'active';
  bool get isOwner => residentType == 'owner';
  bool get isTenant => residentType == 'tenant';
  bool get isFamily => residentType == 'family';

  String get roleLabel {
    if (isOwner) return 'Owner';
    if (isTenant) return 'Tenant';
    if (isFamily) return 'Family';
    return residentType;
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  factory ResidentRecord.fromMap(Map<String, dynamic> m) => ResidentRecord(
        id: m['id']?.toString() ?? '',
        societyId: m['society_id']?.toString() ?? '',
        flatId: m['flat_id']?.toString() ?? '',
        userId: m['user_id']?.toString(),
        fullName: m['full_name']?.toString() ?? '',
        email: m['email']?.toString() ?? '',
        phone: m['phone']?.toString(),
        relation: m['relation']?.toString(),
        residentType: m['resident_type']?.toString() ?? 'owner',
        isPrimary: (m['is_primary'] == true || m['is_primary'] == 1 || m['is_primary']?.toString() == 'true'),
        agreementHolderName: m['agreement_holder_name']?.toString(),
        agreementDate: _parseDate(m['agreement_date']),
        aadharLast4: m['aadhar_last4']?.toString(),
        status: m['status']?.toString() ?? 'active',
        createdBy: m['created_by']?.toString(),
        createdAt: _parseDate(m['created_at']),
        updatedAt: _parseDate(m['updated_at']),
      );
}

class VehicleRecord {
  final String id;
  final String flatId;
  final String? residentId;
  final String vehicleNumber;
  final String? vehicleType;
  final String makeModel;
  final String registrationNo;
  final String? parkingSlot;
  final DateTime? createdAt;

  const VehicleRecord({
    required this.id,
    required this.flatId,
    this.residentId,
    required this.vehicleNumber,
    this.vehicleType,
    String? makeModel,
    String? registrationNo,
    this.parkingSlot,
    this.createdAt,
  })  : makeModel = makeModel ?? vehicleType ?? 'Vehicle',
        registrationNo = registrationNo ?? vehicleNumber;

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  factory VehicleRecord.fromMap(Map<String, dynamic> m) {
    final vNum = m['vehicle_number']?.toString() ?? m['number']?.toString() ?? m['registration_no']?.toString() ?? '';
    final vType = m['vehicle_type']?.toString();
    return VehicleRecord(
      id: m['id']?.toString() ?? '',
      flatId: m['flat_id']?.toString() ?? '',
      residentId: m['resident_id']?.toString(),
      vehicleNumber: vNum,
      vehicleType: vType,
      makeModel: m['make_model']?.toString() ?? vType ?? 'Vehicle',
      registrationNo: m['registration_no']?.toString() ?? vNum,
      parkingSlot: m['parking_slot']?.toString(),
      createdAt: _parseDate(m['created_at']),
    );
  }
}

class SocietyInfo {
  final String id;
  final String name;
  final String? address;
  final String? city;
  final String? state;
  final String? registrationNumber;

  const SocietyInfo({
    required this.id,
    required this.name,
    this.address,
    this.city,
    this.state,
    this.registrationNumber,
  });

  String get locationSubtitle {
    final parts = [city, state].where((e) => e != null && e.trim().isNotEmpty).toList();
    if (parts.isNotEmpty) return parts.join(', ');
    return address ?? '';
  }

  factory SocietyInfo.fromMap(Map<String, dynamic> m) => SocietyInfo(
        id: m['id']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        address: m['address']?.toString(),
        city: m['city']?.toString(),
        state: m['state']?.toString(),
        registrationNumber: m['registration_number']?.toString(),
      );
}

class VacantFlatOption {
  final String flatId;
  final String blockId;
  final String blockName;
  final String flatNumber;
  final int floorNumber;
  final String type;

  const VacantFlatOption({
    required this.flatId,
    required this.blockId,
    required this.blockName,
    required this.flatNumber,
    required this.floorNumber,
    required this.type,
  });

  String get displayTitle => '$flatNumber ($type)';
  String get displaySubtitle => 'Floor $floorNumber · $blockName';

  factory VacantFlatOption.fromFlatAndBlock(Map<String, dynamic> flatMap, String blockName) {
    return VacantFlatOption(
      flatId: flatMap['id']?.toString() ?? '',
      blockId: flatMap['block_id']?.toString() ?? '',
      blockName: blockName,
      flatNumber: flatMap['flat_number']?.toString() ?? '',
      floorNumber: (flatMap['floor_number'] is int ? flatMap['floor_number'] as int : int.tryParse(flatMap['floor_number']?.toString() ?? '0') ?? 0),
      type: flatMap['type']?.toString() ?? 'Apartment',
    );
  }
}

class ResidentJoinRequest {
  final String id;
  final String societyId;
  final String flatId;
  final String userId;
  final String fullName;
  final String email;
  final String phone;
  final String residentType;
  final bool isPrimary;
  final String? agreementHolderName;
  final DateTime? agreementDate;
  final String? aadharLast4;
  final String status;
  final String? rejectionReason;
  final DateTime? createdAt;
  final DateTime? reviewedAt;

  // Joined metadata for UI display
  final String? societyName;
  final String? flatNumber;
  final String? blockName;

  const ResidentJoinRequest({
    required this.id,
    required this.societyId,
    required this.flatId,
    required this.userId,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.residentType,
    required this.isPrimary,
    this.agreementHolderName,
    this.agreementDate,
    this.aadharLast4,
    required this.status,
    this.rejectionReason,
    this.createdAt,
    this.reviewedAt,
    this.societyName,
    this.flatNumber,
    this.blockName,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isCancelled => status == 'cancelled';

  String get roleLabel {
    if (residentType == 'owner') return 'Owner';
    if (residentType == 'tenant') return 'Tenant';
    if (residentType == 'family') return 'Family Member';
    return residentType;
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  factory ResidentJoinRequest.fromMap(Map<String, dynamic> m) {
    String? socName;
    String? flatNum;
    String? blkName;

    if (m['societies'] is Map<String, dynamic>) {
      socName = m['societies']['name']?.toString();
    }
    if (m['flats'] is Map<String, dynamic>) {
      flatNum = m['flats']['flat_number']?.toString();
      if (m['flats']['blocks'] is Map<String, dynamic>) {
        blkName = m['flats']['blocks']['name']?.toString();
      }
    }

    return ResidentJoinRequest(
      id: m['id']?.toString() ?? '',
      societyId: m['society_id']?.toString() ?? '',
      flatId: m['flat_id']?.toString() ?? '',
      userId: m['user_id']?.toString() ?? '',
      fullName: m['full_name']?.toString() ?? '',
      email: m['email']?.toString() ?? '',
      phone: m['phone']?.toString() ?? '',
      residentType: m['resident_type']?.toString() ?? 'owner',
      isPrimary: (m['is_primary'] == true || m['is_primary'] == 1 || m['is_primary']?.toString() == 'true'),
      agreementHolderName: m['agreement_holder_name']?.toString(),
      agreementDate: _parseDate(m['agreement_date']),
      aadharLast4: m['aadhar_last4']?.toString(),
      status: m['status']?.toString() ?? 'pending',
      rejectionReason: m['rejection_reason']?.toString(),
      createdAt: _parseDate(m['created_at']),
      reviewedAt: _parseDate(m['reviewed_at']),
      societyName: socName,
      flatNumber: flatNum,
      blockName: blkName,
    );
  }
}

