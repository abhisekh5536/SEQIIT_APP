import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum ComplaintCategory {
  plumbing('plumbing', 'Plumbing', Icons.plumbing_rounded, Color(0xFF0EA5E9)),
  electrical('electrical', 'Electrical', Icons.bolt_rounded, Color(0xFFF59E0B)),
  security('security', 'Security', Icons.shield_rounded, Color(0xFFEF4444)),
  cleanliness('cleanliness', 'Cleanliness', Icons.cleaning_services_rounded, Color(0xFF10B981)),
  billing('billing', 'Billing', Icons.receipt_long_rounded, Color(0xFF8B5CF6)),
  lift('lift', 'Lift / Elevator', Icons.elevator_rounded, Color(0xFF06B6D4)),
  other('other', 'Other', Icons.category_rounded, Color(0xFF64748B));

  final String dbValue;
  final String label;
  final IconData icon;
  final Color color;

  const ComplaintCategory(this.dbValue, this.label, this.icon, this.color);

  static ComplaintCategory fromDb(String? value) {
    if (value == null) return ComplaintCategory.other;
    for (final c in ComplaintCategory.values) {
      if (c.dbValue == value.toLowerCase().trim()) return c;
    }
    return ComplaintCategory.other;
  }
}

enum ComplaintStatus {
  open('open', 'Open', Icons.radio_button_unchecked_rounded, Color(0xFF64748B), Color(0xFFF1F5F9)),
  inProgress('in_progress', 'In Progress', Icons.timelapse_rounded, Color(0xFFD97706), Color(0xFFFEF3C7)),
  resolved('resolved', 'Resolved', Icons.task_alt_rounded, Color(0xFF2563EB), Color(0xFFDBEAFE)),
  closed('closed', 'Closed', Icons.check_circle_rounded, Color(0xFF16A34A), Color(0xFFDCFCE7)),
  reopened('reopened', 'Reopened', Icons.replay_rounded, Color(0xFFDC2626), Color(0xFFFEE2E2));

  final String dbValue;
  final String label;
  final IconData icon;
  final Color foreground;
  final Color background;

  const ComplaintStatus(this.dbValue, this.label, this.icon, this.foreground, this.background);

  static ComplaintStatus fromDb(String? value) {
    if (value == null) return ComplaintStatus.open;
    for (final s in ComplaintStatus.values) {
      if (s.dbValue == value.toLowerCase().trim()) return s;
    }
    return ComplaintStatus.open;
  }
}

enum ComplaintPriority {
  low('low', 'Low', Color(0xFF10B981)),
  medium('medium', 'Medium', Color(0xFFF59E0B)),
  high('high', 'High', Color(0xFFEF4444));

  final String dbValue;
  final String label;
  final Color color;

  const ComplaintPriority(this.dbValue, this.label, this.color);

  static ComplaintPriority fromDb(String? value) {
    if (value == null) return ComplaintPriority.medium;
    for (final p in ComplaintPriority.values) {
      if (p.dbValue == value.toLowerCase().trim()) return p;
    }
    return ComplaintPriority.medium;
  }
}

class ComplaintRecord {
  final String id;
  final String societyId;
  final String flatId;
  final String raisedBy;
  final ComplaintCategory category;
  final String title;
  final String? description;
  final String? photoUrl;
  final ComplaintStatus status;
  final ComplaintPriority priority;
  final String? assignedTo;
  final String? adminNotes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? resolvedAt;

  // Joined fields
  final String? flatNumber;
  final String? blockName;
  final String? residentName;
  final String? residentPhone;
  final String? residentEmail;

  const ComplaintRecord({
    required this.id,
    required this.societyId,
    required this.flatId,
    required this.raisedBy,
    required this.category,
    required this.title,
    this.description,
    this.photoUrl,
    required this.status,
    required this.priority,
    this.assignedTo,
    this.adminNotes,
    required this.createdAt,
    required this.updatedAt,
    this.resolvedAt,
    this.flatNumber,
    this.blockName,
    this.residentName,
    this.residentPhone,
    this.residentEmail,
  });

  bool get isSecurity => category == ComplaintCategory.security;
  bool get isOpen => status == ComplaintStatus.open;
  bool get isInProgress => status == ComplaintStatus.inProgress;
  bool get isResolved => status == ComplaintStatus.resolved;
  bool get isClosed => status == ComplaintStatus.closed;
  bool get isReopened => status == ComplaintStatus.reopened;
  bool get isActive => !isClosed;

  String get flatDisplay {
    if (flatNumber != null && blockName != null && blockName!.isNotEmpty) {
      return '$blockName · Flat $flatNumber';
    }
    if (flatNumber != null) {
      return 'Flat $flatNumber';
    }
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

  String get formattedCreatedAt => DateFormat('dd MMM yyyy, hh:mm a').format(createdAt.toLocal());
  String? get formattedResolvedAt => resolvedAt == null ? null : DateFormat('dd MMM yyyy, hh:mm a').format(resolvedAt!.toLocal());

  factory ComplaintRecord.fromMap(Map<String, dynamic> m) {
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
    String? rPhone;
    String? rEmail;
    final resObj = m['residents'];
    if (resObj is Map<String, dynamic>) {
      rName = resObj['full_name']?.toString();
      rPhone = resObj['phone']?.toString();
      rEmail = resObj['email']?.toString();
    }

    DateTime parseDt(dynamic val, [DateTime? fallback]) {
      if (val == null) return fallback ?? DateTime.now();
      return DateTime.tryParse(val.toString()) ?? fallback ?? DateTime.now();
    }

    return ComplaintRecord(
      id: m['id']?.toString() ?? '',
      societyId: m['society_id']?.toString() ?? '',
      flatId: m['flat_id']?.toString() ?? '',
      raisedBy: m['raised_by']?.toString() ?? '',
      category: ComplaintCategory.fromDb(m['category']?.toString()),
      title: m['title']?.toString() ?? '',
      description: m['description']?.toString(),
      photoUrl: m['photo_url']?.toString(),
      status: ComplaintStatus.fromDb(m['status']?.toString()),
      priority: ComplaintPriority.fromDb(m['priority']?.toString()),
      assignedTo: m['assigned_to']?.toString(),
      adminNotes: m['admin_notes']?.toString(),
      createdAt: parseDt(m['created_at']),
      updatedAt: parseDt(m['updated_at']),
      resolvedAt: m['resolved_at'] != null ? parseDt(m['resolved_at']) : null,
      flatNumber: fNum,
      blockName: bName,
      residentName: rName,
      residentPhone: rPhone,
      residentEmail: rEmail,
    );
  }
}

class ComplaintStatusHistoryRecord {
  final String id;
  final String complaintId;
  final ComplaintStatus? fromStatus;
  final ComplaintStatus toStatus;
  final String? note;
  final String? changedBy;
  final String changedByRole; // 'resident' | 'society_admin'
  final DateTime createdAt;

  const ComplaintStatusHistoryRecord({
    required this.id,
    required this.complaintId,
    this.fromStatus,
    required this.toStatus,
    this.note,
    this.changedBy,
    required this.changedByRole,
    required this.createdAt,
  });

  bool get isByAdmin => changedByRole == 'society_admin';
  bool get isByResident => changedByRole == 'resident';

  String get roleLabel => isByAdmin ? 'Society Admin' : 'Resident';

  String get formattedTime => DateFormat('dd MMM yyyy, hh:mm a').format(createdAt.toLocal());
  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('dd MMM yyyy').format(createdAt);
  }

  factory ComplaintStatusHistoryRecord.fromMap(Map<String, dynamic> m) {
    return ComplaintStatusHistoryRecord(
      id: m['id']?.toString() ?? '',
      complaintId: m['complaint_id']?.toString() ?? '',
      fromStatus: m['from_status'] != null ? ComplaintStatus.fromDb(m['from_status']?.toString()) : null,
      toStatus: ComplaintStatus.fromDb(m['to_status']?.toString()),
      note: m['note']?.toString(),
      changedBy: m['changed_by']?.toString(),
      changedByRole: m['changed_by_role']?.toString() ?? 'resident',
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
