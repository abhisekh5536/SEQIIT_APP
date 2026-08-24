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
