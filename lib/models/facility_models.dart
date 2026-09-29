import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Whether residents can use a facility right now.
///
/// Maintenance and closed facilities stay listed with a badge rather than
/// disappearing, so residents don't assume a facility was removed.
enum FacilityStatus {
  active('active', 'Open', 'Open', Icons.check_circle_rounded),
  maintenance(
      'maintenance', 'Under maintenance', 'Maintenance', Icons.build_rounded),
  closed('closed', 'Closed', 'Closed', Icons.block_rounded);

  final String dbValue;
  final String label;
  final String shortLabel;
  final IconData icon;

  const FacilityStatus(this.dbValue, this.label, this.shortLabel, this.icon);

  static FacilityStatus fromDb(String? value) {
    return FacilityStatus.values.firstWhere(
      (s) => s.dbValue == value?.toLowerCase().trim(),
      orElse: () => FacilityStatus.active,
    );
  }

  bool get isAvailable => this == FacilityStatus.active;

  Color color(AppPaletteData p) {
    switch (this) {
      case FacilityStatus.active:
        return p.success;
      case FacilityStatus.maintenance:
        return p.warning;
      case FacilityStatus.closed:
        return p.danger;
    }
  }
}

class FacilityCategory {
  final String id;

  /// Null for the shared defaults every society sees; those are read-only.
  final String? societyId;
  final String name;
  final int sortOrder;

  const FacilityCategory({
    required this.id,
    required this.societyId,
    required this.name,
    required this.sortOrder,
  });

  bool get isDefault => societyId == null;

  factory FacilityCategory.fromMap(Map<String, dynamic> m) => FacilityCategory(
        id: m['id'].toString(),
        societyId: m['society_id']?.toString(),
        name: m['name']?.toString() ?? '',
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 100,
      );

  /// A best-guess icon from the name, since categories are free text.
  IconData get icon {
    final n = name.toLowerCase();
    if (n.contains('sport')) return Icons.sports_tennis_rounded;
    if (n.contains('fit') || n.contains('gym') || n.contains('well')) {
      return Icons.fitness_center_rounded;
    }
    if (n.contains('hall') || n.contains('community')) {
      return Icons.meeting_room_rounded;
    }
    if (n.contains('pool') || n.contains('swim')) return Icons.pool_rounded;
    if (n.contains('outdoor') || n.contains('garden') || n.contains('park')) {
      return Icons.park_rounded;
    }
    if (n.contains('kid') || n.contains('play')) return Icons.toys_rounded;
    return Icons.category_rounded;
  }
}

class FacilityImage {
  final String id;
  final String facilityId;
  final String imageUrl;
  final String? storagePath;
  final int sortOrder;

  const FacilityImage({
    required this.id,
    required this.facilityId,
    required this.imageUrl,
    required this.storagePath,
    required this.sortOrder,
  });

  factory FacilityImage.fromMap(Map<String, dynamic> m) => FacilityImage(
        id: m['id'].toString(),
        facilityId: m['facility_id'].toString(),
        imageUrl: m['image_url']?.toString() ?? '',
        storagePath: m['storage_path']?.toString(),
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
      );
}

class FacilityRecord {
  final String id;
  final String societyId;
  final String? categoryId;
  final String? categoryName;
  final String name;
  final String description;
  final FacilityStatus status;
  final String? statusNote;
  final String? operatingHours;
  final String? location;
  final String? rulesText;
  final List<FacilityImage> images;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FacilityRecord({
    required this.id,
    required this.societyId,
    required this.categoryId,
    required this.categoryName,
    required this.name,
    required this.description,
    required this.status,
    required this.statusNote,
    required this.operatingHours,
    required this.location,
    required this.rulesText,
    required this.images,
    required this.createdAt,
    required this.updatedAt,
  });

  String? get coverUrl => images.isEmpty ? null : images.first.imageUrl;

  /// Icon for image-less facilities, guessed from the name first (a
  /// "Swimming Pool" filed under "Sports" should still show a pool).
  IconData get fallbackIcon {
    final n = name.toLowerCase();
    if (n.contains('pool') || n.contains('swim')) return Icons.pool_rounded;
    if (n.contains('gym') || n.contains('fitness')) {
      return Icons.fitness_center_rounded;
    }
    if (n.contains('hall') || n.contains('club')) {
      return Icons.meeting_room_rounded;
    }
    if (n.contains('tennis') || n.contains('badminton') || n.contains('court')) {
      return Icons.sports_tennis_rounded;
    }
    if (n.contains('garden') || n.contains('park')) return Icons.park_rounded;
    if (n.contains('play') || n.contains('kid')) return Icons.toys_rounded;
    if (n.contains('yoga') || n.contains('spa')) return Icons.spa_rounded;
    return Icons.event_seat_rounded;
  }

  factory FacilityRecord.fromMap(Map<String, dynamic> m) {
    final category = m['facility_categories'];
    final images = (m['facility_images'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(FacilityImage.fromMap)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return FacilityRecord(
      id: m['id'].toString(),
      societyId: m['society_id'].toString(),
      categoryId: m['category_id']?.toString(),
      categoryName: category is Map ? category['name']?.toString() : null,
      name: m['name']?.toString() ?? '',
      description: m['description']?.toString() ?? '',
      status: FacilityStatus.fromDb(m['status']?.toString()),
      statusNote: _blankToNull(m['status_note']),
      operatingHours: _blankToNull(m['operating_hours']),
      location: _blankToNull(m['location']),
      rulesText: _blankToNull(m['rules_text']),
      images: images,
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(m['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  static String? _blankToNull(dynamic v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }
}
