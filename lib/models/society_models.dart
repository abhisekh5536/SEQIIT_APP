import 'package:flutter/material.dart';

class SocietyService {
  final String title;
  final String subtitle;
  final IconData icon;
  final String route;

  const SocietyService({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
  });
}

class QuickAction {
  final String label;
  final IconData icon;
  final String route;

  const QuickAction({
    required this.label,
    required this.icon,
    required this.route,
  });
}

class Announcement {
  final String title;
  final String description;
  final DateTime date;
  final String tag;

  const Announcement({
    required this.title,
    required this.description,
    required this.date,
    required this.tag,
  });

  String get tagId => tag.toLowerCase().trim();
}

/// Role of a person attached to a residence.
enum ResidentRole { owner, tenant, family }

extension ResidentRoleLabel on ResidentRole {
  String get label => switch (this) {
        ResidentRole.owner => 'Owner',
        ResidentRole.tenant => 'Tenant',
        ResidentRole.family => 'Family',
      };
}

/// A single individual living in a residence.
class Resident {
  final String fullName;
  final ResidentRole role;
  final String? phone;
  final String? email;
  final String? relation;
  final String? vehicle;
  final String memberSince;
  final bool isPrimary;

  const Resident({
    required this.fullName,
    required this.role,
    this.phone,
    this.email,
    this.relation,
    this.vehicle,
    required this.memberSince,
    this.isPrimary = false,
  });

  String get firstName => fullName.split(' ').first;

  String get initials {
    final parts = fullName.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

/// A flat / unit in the society, with the people currently living in it.
class ResidenceUnit {
  final String number;
  final String tower;
  final int floor;
  final int bhk;
  final int sqft;
  final String? parking;
  final List<Resident> residents;

  const ResidenceUnit({
    required this.number,
    required this.tower,
    required this.floor,
    required this.bhk,
    required this.sqft,
    this.parking,
    this.residents = const [],
  });

  bool get isOccupied => residents.isNotEmpty;

  /// Owner who heads the flat, or the primary tenant when no owner lives here.
  Resident? get primaryContact {
    for (final resident in residents) {
      if (resident.isPrimary) return resident;
    }
    if (residents.isNotEmpty) return residents.first;
    return null;
  }
}