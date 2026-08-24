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
  final String id;
  final String number;
  final String tower;
  final int floor;
  final int bhk;
  final int sqft;
  final String? parking;
  final String status;
  final List<Resident> residents;

  ResidenceUnit({
    String? id,
    required this.number,
    required this.tower,
    required this.floor,
    required this.bhk,
    required this.sqft,
    this.parking,
    String? status,
    this.residents = const [],
  })  : id = id ?? number,
        status = status ?? (residents.isNotEmpty ? 'occupied' : 'vacant');

  bool get isOccupied => status == 'occupied' || residents.isNotEmpty;

  String get typeLabel => '${bhk}BHK';

  /// Owner who heads the flat, or the primary tenant when no owner lives here.
  Resident? get primaryContact {
    for (final resident in residents) {
      if (resident.isPrimary) return resident;
    }
    if (residents.isNotEmpty) return residents.first;
    return null;
  }

  ResidenceUnit copyWith({
    String? id,
    String? number,
    String? tower,
    int? floor,
    int? bhk,
    int? sqft,
    String? parking,
    String? status,
    List<Resident>? residents,
  }) {
    return ResidenceUnit(
      id: id ?? this.id,
      number: number ?? this.number,
      tower: tower ?? this.tower,
      floor: floor ?? this.floor,
      bhk: bhk ?? this.bhk,
      sqft: sqft ?? this.sqft,
      parking: parking ?? this.parking,
      status: status ?? this.status,
      residents: residents ?? this.residents,
    );
  }
}

/// Represents a society block/building with aggregated metrics.
class BlockData {
  final String id;
  final String name;
  final List<ResidenceUnit> flats;

  const BlockData({
    required this.id,
    required this.name,
    this.flats = const [],
  });

  int get totalFlats => flats.length;
  int get occupiedFlats => flats.where((f) => f.isOccupied).length;
  int get vacantFlats => totalFlats - occupiedFlats;
  double get occupancyRate => totalFlats == 0 ? 0 : occupiedFlats / totalFlats;
  int get totalResidents => flats.fold(0, (sum, f) => sum + f.residents.length);
}