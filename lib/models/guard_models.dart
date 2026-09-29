import 'package:intl/intl.dart';

import 'visitor_models.dart';

/// A gate guard, as recorded by the society admin in `society_guards`.
///
/// This row — not anything the user can set on their own account — is what
/// makes an account a guard (migration 17).
class GuardProfile {
  final String id;
  final String societyId;

  /// Null until the guard first signs in with [email].
  final String? userId;
  final String fullName;
  final String email;
  final String phone;
  final String? photoUrl;
  final String? employeeCode;
  final String? agencyName;
  final String? defaultGateId;
  final String? defaultGateName;
  final bool isActive;
  final DateTime createdAt;

  const GuardProfile({
    required this.id,
    required this.societyId,
    this.userId,
    required this.fullName,
    required this.email,
    required this.phone,
    this.photoUrl,
    this.employeeCode,
    this.agencyName,
    this.defaultGateId,
    this.defaultGateName,
    this.isActive = true,
    required this.createdAt,
  });

  /// True once the guard has signed in and the account is attached.
  bool get isLinked => userId != null && userId!.isNotEmpty;

  String get firstName {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? fullName : parts.first;
  }

  String get initials {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'G';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory GuardProfile.fromMap(Map<String, dynamic> m) {
    String? gateName;
    final gate = m['default_gate'] ?? m['society_gates'];
    if (gate is Map) {
      gateName = gate['name']?.toString();
    }

    return GuardProfile(
      id: m['id']?.toString() ?? '',
      societyId: m['society_id']?.toString() ?? '',
      userId: m['user_id']?.toString(),
      fullName: m['full_name']?.toString() ?? '',
      email: m['email']?.toString() ?? '',
      phone: m['phone']?.toString() ?? '',
      photoUrl: m['photo_url']?.toString(),
      employeeCode: _blankToNull(m['employee_code']),
      agencyName: _blankToNull(m['agency_name']),
      defaultGateId: m['default_gate_id']?.toString(),
      defaultGateName: gateName,
      isActive: (m['status']?.toString() ?? 'active') == 'active',
      createdAt:
          DateTime.tryParse(m['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

/// A physical entry point — "Main Gate", "Gate 2 (Service)".
class SocietyGate {
  final String id;
  final String societyId;
  final String name;
  final bool isActive;
  final int sortOrder;

  const SocietyGate({
    required this.id,
    required this.societyId,
    required this.name,
    this.isActive = true,
    this.sortOrder = 0,
  });

  factory SocietyGate.fromMap(Map<String, dynamic> m) => SocietyGate(
    id: m['id']?.toString() ?? '',
    societyId: m['society_id']?.toString() ?? '',
    name: m['name']?.toString() ?? '',
    isActive: m['is_active'] != false,
    sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
  );
}

/// A pre-approval that is active now or starts soon, as the gate sees it.
///
/// Carries no approval code on purpose: the visitor has to show it.
class ExpectedVisitor {
  final String id;
  final String visitorName;
  final VisitorCategory category;
  final String? companyOrContext;
  final String? vehicleNumber;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final String flatId;
  final String? flatNumber;
  final String? blockName;
  final int groupSize;

  const ExpectedVisitor({
    required this.id,
    required this.visitorName,
    required this.category,
    this.companyOrContext,
    this.vehicleNumber,
    this.validFrom,
    this.validUntil,
    required this.flatId,
    this.flatNumber,
    this.blockName,
    this.groupSize = 0,
  });

  String get flatDisplay {
    if (flatNumber == null) return 'Flat';
    if (blockName != null && blockName!.isNotEmpty) {
      return '$blockName · Flat $flatNumber';
    }
    return 'Flat $flatNumber';
  }

  /// Whether the pass can be used right now rather than later today.
  bool isActiveAt(DateTime now) =>
      (validFrom == null || !validFrom!.isAfter(now)) &&
      (validUntil == null || validUntil!.isAfter(now));

  /// "From 6:30 PM" for a pass that starts later, "Until 11:59 PM" once
  /// it is live.
  String windowLabel(DateTime now) {
    final fmt = DateFormat('h:mm a');
    if (validFrom != null && validFrom!.isAfter(now)) {
      return 'From ${fmt.format(validFrom!.toLocal())}';
    }
    if (validUntil != null) {
      final until = validUntil!.toLocal();
      final sameDay =
          until.year == now.year &&
          until.month == now.month &&
          until.day == now.day;
      return sameDay
          ? 'Until ${fmt.format(until)}'
          : 'Until ${DateFormat('d MMM').format(until)}';
    }
    return 'Any time';
  }

  factory ExpectedVisitor.fromMap(Map<String, dynamic> m) => ExpectedVisitor(
    id: m['id']?.toString() ?? '',
    visitorName: m['visitor_name']?.toString() ?? '',
    category: VisitorCategory.fromDb(m['category']?.toString()),
    companyOrContext: _blankToNull(m['company_or_context']),
    vehicleNumber: _blankToNull(m['vehicle_number']),
    validFrom: DateTime.tryParse(m['valid_from']?.toString() ?? ''),
    validUntil: DateTime.tryParse(m['valid_until']?.toString() ?? ''),
    flatId: m['flat_id']?.toString() ?? '',
    flatNumber: m['flat_number']?.toString(),
    blockName: _blankToNull(m['block_name']),
    groupSize: (m['group_size'] as num?)?.toInt() ?? 0,
  );
}

/// What `guard_call_flat` hands back: one number, already logged.
class GuardCallResult {
  final String phone;
  final String? residentFirstName;
  final String? callLogId;

  /// False when the number was issued but the phone had no dialer to open.
  final bool dialerOpened;

  const GuardCallResult({
    required this.phone,
    this.residentFirstName,
    this.callLogId,
    this.dialerOpened = true,
  });
}

/// How a pending gate request is closed from the gate.
enum GateDecision {
  /// The resident said yes on the phone.
  approved('approved'),

  /// The resident said no on the phone.
  denied('denied'),

  /// Nobody answered; the visitor was turned away.
  expired('expired');

  final String dbValue;
  const GateDecision(this.dbValue);
}

/// How long a checked-in visitor may stay before the gate flags them.
///
/// A pre-approval's own window wins when it has one. Otherwise the limit
/// depends on the kind of visit — a delivery rider inside for an hour is
/// worth a look, a dinner guest is not.
Duration overstayLimitFor(VisitorCategory category) => switch (category) {
  VisitorCategory.delivery => const Duration(minutes: 20),
  VisitorCategory.cab => const Duration(minutes: 15),
  VisitorCategory.guest => const Duration(hours: 6),
  VisitorCategory.groupInvite => const Duration(hours: 6),
  VisitorCategory.others => const Duration(hours: 2),
};

/// Whether [v] has been inside longer than it should have.
bool isOverstaying(VisitorRecord v, DateTime now) {
  if (!v.isCheckedIn) return false;
  if (v.validUntil != null) return now.isAfter(v.validUntil!);
  final inAt = v.checkedInAt;
  if (inAt == null) return false;
  return now.difference(inAt) > overstayLimitFor(v.category);
}

String? _blankToNull(dynamic value) {
  final s = value?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}
