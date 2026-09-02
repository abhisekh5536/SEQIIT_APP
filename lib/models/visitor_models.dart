import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ── Visitor Category ────────────────────────────────────────────
enum VisitorCategory {
  delivery('delivery', 'Delivery', Icons.local_shipping_rounded, Color(0xFFE67E22), 'Package, food, courier'),
  guest('guest', 'Guest', Icons.person_rounded, Color(0xFF3498DB), 'Family, friends, relatives'),
  groupInvite('group_invite', 'Group Invite', Icons.groups_rounded, Color(0xFF9B59B6), 'Party, gathering, event'),
  cab('cab', 'Cab', Icons.local_taxi_rounded, Color(0xFF1ABC9C), 'Ride pickup · Secure'),
  others('others', 'Others', Icons.category_rounded, Color(0xFF95A5A6), 'Miscellaneous');

  final String dbValue;
  final String label;
  final IconData icon;
  final Color color;
  final String hint;

  const VisitorCategory(this.dbValue, this.label, this.icon, this.color, this.hint);

  static VisitorCategory fromDb(String? value) {
    if (value == null) return VisitorCategory.others;
    for (final c in VisitorCategory.values) {
      if (c.dbValue == value.toLowerCase().trim()) return c;
    }
    return VisitorCategory.others;
  }

  /// Whether the category shows a special badge in the UI.
  String? get badge => switch (this) {
    VisitorCategory.groupInvite => 'New',
    VisitorCategory.cab => 'Secure pickup',
    _ => null,
  };
}

// ── Visitor Status ──────────────────────────────────────────────
enum VisitorStatus {
  pendingApproval('pending_approval', 'Pending', Icons.hourglass_top_rounded, Color(0xFFD97706), Color(0xFFFEF3C7)),
  approved('approved', 'Approved', Icons.check_circle_outline_rounded, Color(0xFF2563EB), Color(0xFFDBEAFE)),
  denied('denied', 'Denied', Icons.cancel_outlined, Color(0xFFDC2626), Color(0xFFFEE2E2)),
  expired('expired', 'Expired', Icons.timer_off_rounded, Color(0xFF64748B), Color(0xFFF1F5F9)),
  checkedIn('checked_in', 'Checked In', Icons.login_rounded, Color(0xFF16A34A), Color(0xFFDCFCE7)),
  checkedOut('checked_out', 'Checked Out', Icons.logout_rounded, Color(0xFF059669), Color(0xFFD1FAE5)),
  cancelled('cancelled', 'Cancelled', Icons.block_rounded, Color(0xFF64748B), Color(0xFFF1F5F9));

  final String dbValue;
  final String label;
  final IconData icon;
  final Color foreground;
  final Color background;

  const VisitorStatus(this.dbValue, this.label, this.icon, this.foreground, this.background);

  static VisitorStatus fromDb(String? value) {
    if (value == null) return VisitorStatus.pendingApproval;
    for (final s in VisitorStatus.values) {
      if (s.dbValue == value.toLowerCase().trim()) return s;
    }
    return VisitorStatus.pendingApproval;
  }

  bool get isTerminal => this == denied || this == expired || this == checkedOut || this == cancelled;
  bool get isActive => !isTerminal;
}

// ── Entry Type ──────────────────────────────────────────────────
enum VisitorEntryType {
  gateRequest('gate_request', 'Gate Request'),
  preApproved('pre_approved', 'Pre-Approved');

  final String dbValue;
  final String label;

  const VisitorEntryType(this.dbValue, this.label);

  static VisitorEntryType fromDb(String? value) {
    if (value == 'pre_approved') return VisitorEntryType.preApproved;
    return VisitorEntryType.gateRequest;
  }
}

// ── Duration Type ───────────────────────────────────────────────
enum VisitorDurationType {
  oneDay('one_day', 'One Day'),
  longDuration('long_duration', 'Long Duration');

  final String dbValue;
  final String label;

  const VisitorDurationType(this.dbValue, this.label);

  static VisitorDurationType fromDb(String? value) {
    if (value == 'long_duration') return VisitorDurationType.longDuration;
    return VisitorDurationType.oneDay;
  }
}

// ── Visitor Record ──────────────────────────────────────────────
class VisitorRecord {
  final String id;
  final String societyId;
  final String flatId;
  final String? blockId;

  final String createdByType;
  final String createdBy;

  final String visitorName;
  final String? visitorPhone;
  final String? visitorPhotoUrl;
  final String? vehicleNumber;

  final VisitorCategory category;
  final String? companyOrContext;

  final VisitorEntryType entryType;
  final VisitorStatus status;

  final String? approvalCode;
  final String? qrPayload;
  final VisitorDurationType? durationType;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final bool isPrivate;

  final String? approvedBy;
  final DateTime? approvedAt;
  final String? deniedBy;
  final DateTime? deniedAt;
  final String? deniedReason;

  final String? entryGate;
  final DateTime? checkedInAt;
  final String? checkedInBy;
  final DateTime? checkedOutAt;
  final String? checkedOutBy;

  final DateTime createdAt;
  final DateTime updatedAt;

  // Joined fields
  final String? flatNumber;
  final String? blockName;
  final String? residentName;

  const VisitorRecord({
    required this.id,
    required this.societyId,
    required this.flatId,
    this.blockId,
    required this.createdByType,
    required this.createdBy,
    required this.visitorName,
    this.visitorPhone,
    this.visitorPhotoUrl,
    this.vehicleNumber,
    required this.category,
    this.companyOrContext,
    required this.entryType,
    required this.status,
    this.approvalCode,
    this.qrPayload,
    this.durationType,
    this.validFrom,
    this.validUntil,
    this.isPrivate = false,
    this.approvedBy,
    this.approvedAt,
    this.deniedBy,
    this.deniedAt,
    this.deniedReason,
    this.entryGate,
    this.checkedInAt,
    this.checkedInBy,
    this.checkedOutAt,
    this.checkedOutBy,
    required this.createdAt,
    required this.updatedAt,
    this.flatNumber,
    this.blockName,
    this.residentName,
  });

  bool get isGateRequest => entryType == VisitorEntryType.gateRequest;
  bool get isPreApproved => entryType == VisitorEntryType.preApproved;
  bool get isPending => status == VisitorStatus.pendingApproval;
  bool get isApproved => status == VisitorStatus.approved;
  bool get isDenied => status == VisitorStatus.denied;
  bool get isCheckedIn => status == VisitorStatus.checkedIn;
  bool get isCheckedOut => status == VisitorStatus.checkedOut;
  bool get isCancelled => status == VisitorStatus.cancelled;
  bool get isExpired => status == VisitorStatus.expired;

  bool get canCancel => isPreApproved && isApproved;
  bool get canCheckIn => isApproved;
  bool get canCheckOut => isCheckedIn;

  /// Whether the pre-approval is not expired.
  bool get isWithinValidity {
    if (validUntil == null) return true;
    return DateTime.now().isBefore(validUntil!);
  }

  String get flatDisplay {
    if (flatNumber != null && blockName != null && blockName!.isNotEmpty) {
      return '$blockName · Flat $flatNumber';
    }
    if (flatNumber != null) return 'Flat $flatNumber';
    return 'Flat';
  }

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('dd MMM yyyy').format(createdAt);
  }

  String get formattedCreatedAt =>
      DateFormat('dd MMM yyyy, hh:mm a').format(createdAt.toLocal());

  String? get formattedValidUntil => validUntil == null
      ? null
      : DateFormat('dd MMM yyyy, hh:mm a').format(validUntil!.toLocal());

  String? get validityDisplay {
    if (validFrom == null || validUntil == null) return null;
    final fromStr = DateFormat('dd MMM').format(validFrom!.toLocal());
    final untilStr = DateFormat('dd MMM yyyy').format(validUntil!.toLocal());
    if (durationType == VisitorDurationType.oneDay) {
      return DateFormat('dd MMM yyyy').format(validFrom!.toLocal());
    }
    return '$fromStr – $untilStr';
  }

  factory VisitorRecord.fromMap(Map<String, dynamic> m) {
    // Nested joins parsing
    String? fNum;
    String? bName;
    final flatObj = m['flats'];
    if (flatObj is Map<String, dynamic>) {
      fNum = flatObj['flat_number']?.toString();
      final blockObj = flatObj['blocks'];
      if (blockObj is Map<String, dynamic>) {
        bName = blockObj['name']?.toString();
      }
    }

    String? rName;
    final resObj = m['residents'];
    if (resObj is Map<String, dynamic>) {
      rName = resObj['full_name']?.toString();
    }

    DateTime parseDt(dynamic val, [DateTime? fallback]) {
      if (val == null) return fallback ?? DateTime.now();
      return DateTime.tryParse(val.toString()) ?? fallback ?? DateTime.now();
    }

    DateTime? parseDtNullable(dynamic val) {
      if (val == null) return null;
      return DateTime.tryParse(val.toString());
    }

    return VisitorRecord(
      id: m['id']?.toString() ?? '',
      societyId: m['society_id']?.toString() ?? '',
      flatId: m['flat_id']?.toString() ?? '',
      blockId: m['block_id']?.toString(),
      createdByType: m['created_by_type']?.toString() ?? 'resident',
      createdBy: m['created_by']?.toString() ?? '',
      visitorName: m['visitor_name']?.toString() ?? '',
      visitorPhone: m['visitor_phone']?.toString(),
      visitorPhotoUrl: m['visitor_photo_url']?.toString(),
      vehicleNumber: m['vehicle_number']?.toString(),
      category: VisitorCategory.fromDb(m['category']?.toString()),
      companyOrContext: m['company_or_context']?.toString(),
      entryType: VisitorEntryType.fromDb(m['entry_type']?.toString()),
      status: VisitorStatus.fromDb(m['status']?.toString()),
      approvalCode: m['approval_code']?.toString(),
      qrPayload: m['qr_payload']?.toString(),
      durationType: m['duration_type'] != null
          ? VisitorDurationType.fromDb(m['duration_type']?.toString())
          : null,
      validFrom: parseDtNullable(m['valid_from']),
      validUntil: parseDtNullable(m['valid_until']),
      isPrivate: m['is_private'] == true,
      approvedBy: m['approved_by']?.toString(),
      approvedAt: parseDtNullable(m['approved_at']),
      deniedBy: m['denied_by']?.toString(),
      deniedAt: parseDtNullable(m['denied_at']),
      deniedReason: m['denied_reason']?.toString(),
      entryGate: m['entry_gate']?.toString(),
      checkedInAt: parseDtNullable(m['checked_in_at']),
      checkedInBy: m['checked_in_by']?.toString(),
      checkedOutAt: parseDtNullable(m['checked_out_at']),
      checkedOutBy: m['checked_out_by']?.toString(),
      createdAt: parseDt(m['created_at']),
      updatedAt: parseDt(m['updated_at']),
      flatNumber: fNum,
      blockName: bName,
      residentName: rName,
    );
  }
}

// ── Group Member ────────────────────────────────────────────────
class VisitorGroupMember {
  final String id;
  final String visitorId;
  final String guestName;
  final String? guestPhone;
  final DateTime createdAt;

  const VisitorGroupMember({
    required this.id,
    required this.visitorId,
    required this.guestName,
    this.guestPhone,
    required this.createdAt,
  });

  factory VisitorGroupMember.fromMap(Map<String, dynamic> m) {
    return VisitorGroupMember(
      id: m['id']?.toString() ?? '',
      visitorId: m['visitor_id']?.toString() ?? '',
      guestName: m['guest_name']?.toString() ?? '',
      guestPhone: m['guest_phone']?.toString(),
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

// ── Status History Record ───────────────────────────────────────
class VisitorStatusHistoryRecord {
  final String id;
  final String visitorId;
  final VisitorStatus? fromStatus;
  final VisitorStatus toStatus;
  final String? note;
  final String? changedBy;
  final String changedByRole; // 'resident' | 'society_admin' | 'guard' | 'system'
  final DateTime createdAt;

  const VisitorStatusHistoryRecord({
    required this.id,
    required this.visitorId,
    this.fromStatus,
    required this.toStatus,
    this.note,
    this.changedBy,
    required this.changedByRole,
    required this.createdAt,
  });

  bool get isByAdmin => changedByRole == 'society_admin';
  bool get isByResident => changedByRole == 'resident';
  bool get isBySystem => changedByRole == 'system';

  String get roleLabel => switch (changedByRole) {
    'society_admin' => 'Society Admin',
    'guard' => 'Security Guard',
    'system' => 'System',
    _ => 'Resident',
  };

  String get formattedTime =>
      DateFormat('dd MMM yyyy, hh:mm a').format(createdAt.toLocal());

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('dd MMM yyyy').format(createdAt);
  }

  factory VisitorStatusHistoryRecord.fromMap(Map<String, dynamic> m) {
    return VisitorStatusHistoryRecord(
      id: m['id']?.toString() ?? '',
      visitorId: m['visitor_id']?.toString() ?? '',
      fromStatus: m['from_status'] != null
          ? VisitorStatus.fromDb(m['from_status']?.toString())
          : null,
      toStatus: VisitorStatus.fromDb(m['to_status']?.toString()),
      note: m['note']?.toString(),
      changedBy: m['changed_by']?.toString(),
      changedByRole: m['changed_by_role']?.toString() ?? 'resident',
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
