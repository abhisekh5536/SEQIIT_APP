import 'package:flutter/material.dart';

enum SosAlertType {
  medical,
  fire,
  theftSecurity,
  other;

  static SosAlertType fromString(String? val) {
    return switch (val?.toLowerCase()) {
      'medical' => SosAlertType.medical,
      'fire' => SosAlertType.fire,
      'theft_security' || 'theft' || 'security' => SosAlertType.theftSecurity,
      _ => SosAlertType.other,
    };
  }

  String toDbValue() {
    return switch (this) {
      SosAlertType.medical => 'medical',
      SosAlertType.fire => 'fire',
      SosAlertType.theftSecurity => 'theft_security',
      SosAlertType.other => 'other',
    };
  }

  String get label => switch (this) {
    SosAlertType.medical => 'Medical Emergency',
    SosAlertType.fire => 'Fire / Gas Leak',
    SosAlertType.theftSecurity => 'Theft / Intrusion',
    SosAlertType.other => 'General Emergency',
  };

  String get shortLabel => switch (this) {
    SosAlertType.medical => 'Medical',
    SosAlertType.fire => 'Fire',
    SosAlertType.theftSecurity => 'Theft / Alert',
    SosAlertType.other => 'Emergency',
  };

  IconData get icon => switch (this) {
    SosAlertType.medical => Icons.medical_services_rounded,
    SosAlertType.fire => Icons.local_fire_department_rounded,
    SosAlertType.theftSecurity => Icons.shield_rounded,
    SosAlertType.other => Icons.warning_amber_rounded,
  };

  Color get color => switch (this) {
    SosAlertType.medical => const Color(0xFFE53935),
    SosAlertType.fire => const Color(0xFFFF5722),
    SosAlertType.theftSecurity => const Color(0xFF673AB7),
    SosAlertType.other => const Color(0xFFE65100),
  };
}

enum SosStatus {
  active,
  acknowledged,
  resolved,
  cancelled;

  static SosStatus fromString(String? val) {
    return switch (val?.toLowerCase()) {
      'acknowledged' => SosStatus.acknowledged,
      'resolved' => SosStatus.resolved,
      'cancelled' => SosStatus.cancelled,
      _ => SosStatus.active,
    };
  }

  String toDbValue() => name;

  String get label => switch (this) {
    SosStatus.active => 'Active Alert',
    SosStatus.acknowledged => 'Acknowledged',
    SosStatus.resolved => 'Resolved',
    SosStatus.cancelled => 'Cancelled',
  };

  IconData get icon => switch (this) {
    SosStatus.active => Icons.emergency_rounded,
    SosStatus.acknowledged => Icons.visibility_rounded,
    SosStatus.resolved => Icons.check_circle_rounded,
    SosStatus.cancelled => Icons.cancel_outlined,
  };

  Color get color => switch (this) {
    SosStatus.active => const Color(0xFFD32F2F),
    SosStatus.acknowledged => const Color(0xFF0288D1),
    SosStatus.resolved => const Color(0xFF2E7D32),
    SosStatus.cancelled => const Color(0xFF757575),
  };
}

class EmergencyCategory {
  final String id;
  final String? societyId;
  final String name;
  final String iconKey;
  final int sortOrder;
  final bool isGlobal;
  final DateTime createdAt;

  const EmergencyCategory({
    required this.id,
    this.societyId,
    required this.name,
    this.iconKey = 'shield',
    this.sortOrder = 0,
    this.isGlobal = false,
    required this.createdAt,
  });

  factory EmergencyCategory.fromMap(Map<String, dynamic> map) {
    return EmergencyCategory(
      id: map['id']?.toString() ?? '',
      societyId: map['society_id']?.toString(),
      name: map['name']?.toString() ?? '',
      iconKey: map['icon_key']?.toString() ?? 'shield',
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      isGlobal: map['is_global'] == true,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())?.toLocal() ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (societyId != null) 'society_id': societyId,
      'name': name,
      'icon_key': iconKey,
      'sort_order': sortOrder,
      'is_global': isGlobal,
    };
  }

  IconData get icon => SecurityIconHelper.getIconData(iconKey);
}

class EmergencyContact {
  final String id;
  final String? societyId;
  final String categoryId;
  final String name;
  final String? designation;
  final String phoneNumber;
  final String? alternatePhoneNumber;
  final String? photoUrl;
  final String availability;
  final bool isActive;
  final bool isGlobal;
  final int sortOrder;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Joined fields
  final String? categoryName;
  final String? categoryIconKey;

  const EmergencyContact({
    required this.id,
    this.societyId,
    required this.categoryId,
    required this.name,
    this.designation,
    required this.phoneNumber,
    this.alternatePhoneNumber,
    this.photoUrl,
    this.availability = '24/7',
    this.isActive = true,
    this.isGlobal = false,
    this.sortOrder = 0,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.categoryName,
    this.categoryIconKey,
  });

  factory EmergencyContact.fromMap(Map<String, dynamic> map) {
    String? catName;
    String? catIcon;
    final catObj = map['emergency_contact_categories'];
    if (catObj is Map<String, dynamic>) {
      catName = catObj['name']?.toString();
      catIcon = catObj['icon_key']?.toString();
    }

    return EmergencyContact(
      id: map['id']?.toString() ?? '',
      societyId: map['society_id']?.toString(),
      categoryId: map['category_id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      designation: map['designation']?.toString(),
      phoneNumber: map['phone_number']?.toString() ?? '',
      alternatePhoneNumber: map['alternate_phone_number']?.toString(),
      photoUrl: map['photo_url']?.toString(),
      availability: map['availability']?.toString() ?? '24/7',
      isActive: map['is_active'] != false,
      isGlobal: map['is_global'] == true,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      createdBy: map['created_by']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())?.toLocal() ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())?.toLocal() ?? DateTime.now()
          : DateTime.now(),
      categoryName: catName,
      categoryIconKey: catIcon,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (societyId != null) 'society_id': societyId,
      'category_id': categoryId,
      'name': name,
      if (designation != null) 'designation': designation,
      'phone_number': phoneNumber,
      if (alternatePhoneNumber != null && alternatePhoneNumber!.isNotEmpty)
        'alternate_phone_number': alternatePhoneNumber,
      if (photoUrl != null) 'photo_url': photoUrl,
      'availability': availability,
      'is_active': isActive,
      'is_global': isGlobal,
      'sort_order': sortOrder,
    };
  }

  EmergencyContact copyWith({
    String? id,
    String? societyId,
    String? categoryId,
    String? name,
    String? designation,
    String? phoneNumber,
    String? alternatePhoneNumber,
    String? photoUrl,
    String? availability,
    bool? isActive,
    bool? isGlobal,
    int? sortOrder,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? categoryName,
    String? categoryIconKey,
  }) {
    return EmergencyContact(
      id: id ?? this.id,
      societyId: societyId ?? this.societyId,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      designation: designation ?? this.designation,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      alternatePhoneNumber: alternatePhoneNumber ?? this.alternatePhoneNumber,
      photoUrl: photoUrl ?? this.photoUrl,
      availability: availability ?? this.availability,
      isActive: isActive ?? this.isActive,
      isGlobal: isGlobal ?? this.isGlobal,
      sortOrder: sortOrder ?? this.sortOrder,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      categoryName: categoryName ?? this.categoryName,
      categoryIconKey: categoryIconKey ?? this.categoryIconKey,
    );
  }
}

class EmergencyCallLog {
  final String id;
  final String societyId;
  final String contactId;
  final String flatId;
  final String callerType;
  final String callerId;
  final DateTime calledAt;

  // Joined fields
  final String? contactName;
  final String? contactDesignation;
  final String? contactPhone;
  final String? contactCategory;
  final String? flatNumber;
  final String? blockName;

  const EmergencyCallLog({
    required this.id,
    required this.societyId,
    required this.contactId,
    required this.flatId,
    required this.callerType,
    required this.callerId,
    required this.calledAt,
    this.contactName,
    this.contactDesignation,
    this.contactPhone,
    this.contactCategory,
    this.flatNumber,
    this.blockName,
  });

  factory EmergencyCallLog.fromMap(Map<String, dynamic> map) {
    String? cName;
    String? cDesig;
    String? cPhone;
    String? cCat;
    final contactObj = map['emergency_contacts'];
    if (contactObj is Map<String, dynamic>) {
      cName = contactObj['name']?.toString();
      cDesig = contactObj['designation']?.toString();
      cPhone = contactObj['phone_number']?.toString();
      final catObj = contactObj['emergency_contact_categories'];
      if (catObj is Map<String, dynamic>) {
        cCat = catObj['name']?.toString();
      }
    }

    String? fNum;
    String? bName;
    final flatObj = map['flats'];
    if (flatObj is Map<String, dynamic>) {
      fNum = flatObj['flat_number']?.toString();
      final blkObj = flatObj['blocks'];
      if (blkObj is Map<String, dynamic>) {
        bName = blkObj['name']?.toString();
      }
    }

    return EmergencyCallLog(
      id: map['id']?.toString() ?? '',
      societyId: map['society_id']?.toString() ?? '',
      contactId: map['contact_id']?.toString() ?? '',
      flatId: map['flat_id']?.toString() ?? '',
      callerType: map['caller_type']?.toString() ?? 'resident',
      callerId: map['caller_id']?.toString() ?? '',
      calledAt: map['called_at'] != null
          ? DateTime.tryParse(map['called_at'].toString())?.toLocal() ?? DateTime.now()
          : DateTime.now(),
      contactName: cName,
      contactDesignation: cDesig,
      contactPhone: cPhone,
      contactCategory: cCat,
      flatNumber: fNum,
      blockName: bName,
    );
  }
}

class SosAlert {
  final String id;
  final String societyId;
  final String flatId;
  final String raisedBy;
  final SosAlertType alertType;
  final String? note;
  final SosStatus status;
  final String? acknowledgedBy;
  final String? acknowledgedByRole;
  final DateTime? acknowledgedAt;
  final String? resolvedBy;
  final DateTime? resolvedAt;
  final DateTime createdAt;

  // Joined fields
  final String? flatNumber;
  final String? blockName;
  final String? residentName;
  final String? residentPhone;

  const SosAlert({
    required this.id,
    required this.societyId,
    required this.flatId,
    required this.raisedBy,
    required this.alertType,
    this.note,
    required this.status,
    this.acknowledgedBy,
    this.acknowledgedByRole,
    this.acknowledgedAt,
    this.resolvedBy,
    this.resolvedAt,
    required this.createdAt,
    this.flatNumber,
    this.blockName,
    this.residentName,
    this.residentPhone,
  });

  factory SosAlert.fromMap(Map<String, dynamic> map) {
    String? fNum;
    String? bName;
    final flatObj = map['flats'];
    if (flatObj is Map<String, dynamic>) {
      fNum = flatObj['flat_number']?.toString();
      final blkObj = flatObj['blocks'];
      if (blkObj is Map<String, dynamic>) {
        bName = blkObj['name']?.toString();
      }
    }

    String? rName;
    String? rPhone;
    final resObj = map['residents'];
    if (resObj is Map<String, dynamic>) {
      rName = resObj['full_name']?.toString();
      rPhone = resObj['phone']?.toString();
    }

    return SosAlert(
      id: map['id']?.toString() ?? '',
      societyId: map['society_id']?.toString() ?? '',
      flatId: map['flat_id']?.toString() ?? '',
      raisedBy: map['raised_by']?.toString() ?? '',
      alertType: SosAlertType.fromString(map['alert_type']?.toString()),
      note: map['note']?.toString(),
      status: SosStatus.fromString(map['status']?.toString()),
      acknowledgedBy: map['acknowledged_by']?.toString(),
      acknowledgedByRole: map['acknowledged_by_role']?.toString(),
      acknowledgedAt: map['acknowledged_at'] != null
          ? DateTime.tryParse(map['acknowledged_at'].toString())?.toLocal()
          : null,
      resolvedBy: map['resolved_by']?.toString(),
      resolvedAt: map['resolved_at'] != null
          ? DateTime.tryParse(map['resolved_at'].toString())?.toLocal()
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())?.toLocal() ?? DateTime.now()
          : DateTime.now(),
      flatNumber: fNum,
      blockName: bName,
      residentName: rName,
      residentPhone: rPhone,
    );
  }

  bool get isActive => status == SosStatus.active;
  bool get isAcknowledged => status == SosStatus.acknowledged;
  bool get isResolved => status == SosStatus.resolved;
  bool get isCancelled => status == SosStatus.cancelled;
  bool get isOpen => isActive || isAcknowledged;

  String get formattedFlat => blockName != null && blockName!.isNotEmpty
      ? '$blockName - $flatNumber'
      : (flatNumber ?? 'Flat');
}

class SosStatusHistory {
  final String id;
  final String sosAlertId;
  final String? fromStatus;
  final String toStatus;
  final String? changedBy;
  final String changedByRole;
  final String? note;
  final DateTime createdAt;

  const SosStatusHistory({
    required this.id,
    required this.sosAlertId,
    this.fromStatus,
    required this.toStatus,
    this.changedBy,
    required this.changedByRole,
    this.note,
    required this.createdAt,
  });

  factory SosStatusHistory.fromMap(Map<String, dynamic> map) {
    return SosStatusHistory(
      id: map['id']?.toString() ?? '',
      sosAlertId: map['sos_alert_id']?.toString() ?? '',
      fromStatus: map['from_status']?.toString(),
      toStatus: map['to_status']?.toString() ?? '',
      changedBy: map['changed_by']?.toString(),
      changedByRole: map['changed_by_role']?.toString() ?? 'system',
      note: map['note']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())?.toLocal() ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class SecurityIconHelper {
  static const Map<String, IconData> _iconMap = {
    'emergency': Icons.emergency_rounded,
    'local_police': Icons.local_police_rounded,
    'police': Icons.local_police_outlined,
    'medical_services': Icons.medical_services_rounded,
    'hospital': Icons.local_hospital_rounded,
    'local_fire_department': Icons.local_fire_department_rounded,
    'fire': Icons.local_fire_department_outlined,
    'shield': Icons.shield_outlined,
    'security': Icons.security_rounded,
    'plumbing': Icons.plumbing_rounded,
    'electrical_services': Icons.electrical_services_rounded,
    'electrician': Icons.bolt_rounded,
    'build': Icons.build_rounded,
    'handyman': Icons.handyman_rounded,
    'cleaning_services': Icons.cleaning_services_rounded,
    'phone': Icons.phone_in_talk_rounded,
    'support_agent': Icons.support_agent_rounded,
    'groups': Icons.groups_rounded,
    'car': Icons.directions_car_rounded,
    'lift': Icons.elevator_rounded,
  };

  static List<String> get availableKeys => _iconMap.keys.toList();

  static IconData getIconData(String? key) {
    if (key == null || key.isEmpty) return Icons.shield_outlined;
    return _iconMap[key.toLowerCase()] ?? Icons.shield_outlined;
  }
}
