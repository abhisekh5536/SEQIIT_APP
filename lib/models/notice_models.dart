import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

/// Categories supported for society notices.
enum NoticeCategory {
  important('important', 'Important', Icons.warning_amber_rounded),
  event('event', 'Event', Icons.event_rounded),
  safety('safety', 'Safety', Icons.shield_outlined),
  maintenance('maintenance', 'Maintenance', Icons.build_outlined),
  billing('billing', 'Billing', Icons.receipt_long_outlined),
  general('general', 'General', Icons.campaign_outlined);

  final String dbValue;
  final String label;
  final IconData icon;

  const NoticeCategory(this.dbValue, this.label, this.icon);

  static NoticeCategory fromDb(String? value) {
    if (value == null) return NoticeCategory.general;
    return NoticeCategory.values.firstWhere(
      (c) => c.dbValue == value.toLowerCase().trim(),
      orElse: () => NoticeCategory.general,
    );
  }

  Color color(AppPaletteData p) {
    switch (this) {
      case NoticeCategory.important:
        return p.danger;
      case NoticeCategory.event:
        return p.secondary;
      case NoticeCategory.safety:
        return const Color(0xFFE68A00); // Amber warning
      case NoticeCategory.maintenance:
        return p.primary;
      case NoticeCategory.billing:
        return const Color(0xFF8E44AD); // Purple
      case NoticeCategory.general:
        return p.textSecondary;
    }
  }
}

/// Lifecycle status for a notice.
enum NoticeStatus {
  draft('draft', 'Draft', Icons.edit_note_rounded),
  scheduled('scheduled', 'Scheduled', Icons.schedule_rounded),
  published('published', 'Published', Icons.check_circle_outline_rounded),
  expired('expired', 'Expired', Icons.timer_off_outlined),
  archived('archived', 'Archived', Icons.archive_outlined);

  final String dbValue;
  final String label;
  final IconData icon;

  const NoticeStatus(this.dbValue, this.label, this.icon);

  static NoticeStatus fromDb(String? value) {
    if (value == null) return NoticeStatus.draft;
    return NoticeStatus.values.firstWhere(
      (s) => s.dbValue == value.toLowerCase().trim(),
      orElse: () => NoticeStatus.draft,
    );
  }

  Color color(AppPaletteData p) {
    switch (this) {
      case NoticeStatus.draft:
        return p.textTertiary;
      case NoticeStatus.scheduled:
        return const Color(0xFFE68A00);
      case NoticeStatus.published:
        return p.success;
      case NoticeStatus.expired:
        return p.danger;
      case NoticeStatus.archived:
        return p.textSecondary;
    }
  }
}

/// Target scope of a notice.
enum NoticeTargetType {
  all('all', 'All Residents'),
  block('block', 'Specific Block');

  final String dbValue;
  final String label;

  const NoticeTargetType(this.dbValue, this.label);

  static NoticeTargetType fromDb(String? value) {
    if (value == null) return NoticeTargetType.all;
    return NoticeTargetType.values.firstWhere(
      (t) => t.dbValue == value.toLowerCase().trim(),
      orElse: () => NoticeTargetType.all,
    );
  }
}

/// Complete representation of a notice row with relations and interaction stats.
class NoticeRecord {
  final String id;
  final String societyId;
  final String title;
  final String body;
  final NoticeCategory category;
  final String? attachmentUrl;

  final NoticeTargetType targetType;
  final String? targetBlockId;
  final String? targetBlockName;

  final bool isEvent;
  final DateTime? eventStartsAt;
  final DateTime? eventEndsAt;
  final String? eventVenue;

  final bool isPinned;
  final bool requiresAcknowledgment;

  final NoticeStatus status;
  final DateTime publishAt;
  final DateTime? expiresAt;

  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Interaction / aggregation stats
  final bool isReadByMe;
  final bool isAcknowledgedByMe;
  final DateTime? myAcknowledgedAt;

  final int readCount;
  final int ackCount;
  final int totalEligibleResidents;

  const NoticeRecord({
    required this.id,
    required this.societyId,
    required this.title,
    required this.body,
    required this.category,
    this.attachmentUrl,
    required this.targetType,
    this.targetBlockId,
    this.targetBlockName,
    this.isEvent = false,
    this.eventStartsAt,
    this.eventEndsAt,
    this.eventVenue,
    this.isPinned = false,
    this.requiresAcknowledgment = false,
    required this.status,
    required this.publishAt,
    this.expiresAt,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.isReadByMe = false,
    this.isAcknowledgedByMe = false,
    this.myAcknowledgedAt,
    this.readCount = 0,
    this.ackCount = 0,
    this.totalEligibleResidents = 0,
  });

  bool get isPublished => status == NoticeStatus.published;
  bool get isDraft => status == NoticeStatus.draft;
  bool get isScheduled => status == NoticeStatus.scheduled;
  bool get isExpired =>
      status == NoticeStatus.expired ||
      (expiresAt != null && expiresAt!.isBefore(DateTime.now()));

  bool get isEventUpcoming =>
      isEvent && eventStartsAt != null && eventStartsAt!.isAfter(DateTime.now());

  bool get isEventOngoing =>
      isEvent &&
      eventStartsAt != null &&
      eventEndsAt != null &&
      eventStartsAt!.isBefore(DateTime.now()) &&
      eventEndsAt!.isAfter(DateTime.now());

  /// Returns a clean relative time string (e.g. "2h ago", "Yesterday", "15 Aug").
  String get relativeTime {
    final now = DateTime.now();
    final diff = now.difference(createdAt);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return DateFormat('d MMM').format(createdAt);
  }

  /// Returns a formatted publish date string (e.g. "15 Aug 2026, 10:30 AM").
  String get formattedPublishDate {
    return DateFormat('d MMM yyyy, h:mm a').format(publishAt.toLocal());
  }

  /// Formatted event date/time range (e.g. "Sat, 15 Aug · 6:00 PM – 8:00 PM").
  String? get formattedEventSchedule {
    if (!isEvent || eventStartsAt == null) return null;
    final start = eventStartsAt!.toLocal();
    final dayStr = DateFormat('EEE, d MMM').format(start);
    final startTimeStr = DateFormat('h:mm a').format(start);

    if (eventEndsAt != null) {
      final end = eventEndsAt!.toLocal();
      final endTimeStr = DateFormat('h:mm a').format(end);
      return '$dayStr · $startTimeStr – $endTimeStr';
    }

    return '$dayStr · $startTimeStr';
  }

  /// Short event badge for preview cards (e.g. "6:00 PM · 15 Aug").
  String? get formattedEventBadge {
    if (!isEvent || eventStartsAt == null) return null;
    final start = eventStartsAt!.toLocal();
    return '${DateFormat('h:mm a').format(start)} · ${DateFormat('d MMM').format(start)}';
  }

  NoticeRecord copyWith({
    String? id,
    String? societyId,
    String? title,
    String? body,
    NoticeCategory? category,
    String? attachmentUrl,
    NoticeTargetType? targetType,
    String? targetBlockId,
    String? targetBlockName,
    bool? isEvent,
    DateTime? eventStartsAt,
    DateTime? eventEndsAt,
    String? eventVenue,
    bool? isPinned,
    bool? requiresAcknowledgment,
    NoticeStatus? status,
    DateTime? publishAt,
    DateTime? expiresAt,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isReadByMe,
    bool? isAcknowledgedByMe,
    DateTime? myAcknowledgedAt,
    int? readCount,
    int? ackCount,
    int? totalEligibleResidents,
  }) {
    return NoticeRecord(
      id: id ?? this.id,
      societyId: societyId ?? this.societyId,
      title: title ?? this.title,
      body: body ?? this.body,
      category: category ?? this.category,
      attachmentUrl: attachmentUrl ?? this.attachmentUrl,
      targetType: targetType ?? this.targetType,
      targetBlockId: targetBlockId ?? this.targetBlockId,
      targetBlockName: targetBlockName ?? this.targetBlockName,
      isEvent: isEvent ?? this.isEvent,
      eventStartsAt: eventStartsAt ?? this.eventStartsAt,
      eventEndsAt: eventEndsAt ?? this.eventEndsAt,
      eventVenue: eventVenue ?? this.eventVenue,
      isPinned: isPinned ?? this.isPinned,
      requiresAcknowledgment:
          requiresAcknowledgment ?? this.requiresAcknowledgment,
      status: status ?? this.status,
      publishAt: publishAt ?? this.publishAt,
      expiresAt: expiresAt ?? this.expiresAt,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isReadByMe: isReadByMe ?? this.isReadByMe,
      isAcknowledgedByMe: isAcknowledgedByMe ?? this.isAcknowledgedByMe,
      myAcknowledgedAt: myAcknowledgedAt ?? this.myAcknowledgedAt,
      readCount: readCount ?? this.readCount,
      ackCount: ackCount ?? this.ackCount,
      totalEligibleResidents:
          totalEligibleResidents ?? this.totalEligibleResidents,
    );
  }

  factory NoticeRecord.fromMap(
    Map<String, dynamic> map, {
    bool isRead = false,
    bool isAcknowledged = false,
    DateTime? acknowledgedAt,
    int readCount = 0,
    int ackCount = 0,
    int totalResidents = 0,
  }) {
    String? blockName;
    if (map['blocks'] != null && map['blocks'] is Map) {
      blockName = (map['blocks'] as Map)['name']?.toString();
    }

    return NoticeRecord(
      id: map['id']?.toString() ?? '',
      societyId: map['society_id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      body: map['body']?.toString() ?? '',
      category: NoticeCategory.fromDb(map['category']?.toString()),
      attachmentUrl: map['attachment_url']?.toString(),
      targetType: NoticeTargetType.fromDb(map['target_type']?.toString()),
      targetBlockId: map['target_block_id']?.toString(),
      targetBlockName: blockName,
      isEvent: map['is_event'] == true,
      eventStartsAt: map['event_starts_at'] != null
          ? DateTime.tryParse(map['event_starts_at'].toString())
          : null,
      eventEndsAt: map['event_ends_at'] != null
          ? DateTime.tryParse(map['event_ends_at'].toString())
          : null,
      eventVenue: map['event_venue']?.toString(),
      isPinned: map['is_pinned'] == true,
      requiresAcknowledgment: map['requires_acknowledgment'] == true,
      status: NoticeStatus.fromDb(map['status']?.toString()),
      publishAt: map['publish_at'] != null
          ? DateTime.parse(map['publish_at'].toString())
          : DateTime.now(),
      expiresAt: map['expires_at'] != null
          ? DateTime.tryParse(map['expires_at'].toString())
          : null,
      createdBy: map['created_by']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'].toString())
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'].toString())
          : DateTime.now(),
      isReadByMe: isRead,
      isAcknowledgedByMe: isAcknowledged,
      myAcknowledgedAt: acknowledgedAt,
      readCount: readCount,
      ackCount: ackCount,
      totalEligibleResidents: totalResidents,
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'society_id': societyId,
      'title': title.trim(),
      'body': body.trim(),
      'category': category.dbValue,
      'attachment_url': attachmentUrl,
      'target_type': targetType.dbValue,
      'target_block_id': targetType == NoticeTargetType.block ? targetBlockId : null,
      'is_event': isEvent,
      'event_starts_at': isEvent ? eventStartsAt?.toUtc().toIso8601String() : null,
      'event_ends_at': isEvent ? eventEndsAt?.toUtc().toIso8601String() : null,
      'event_venue': isEvent ? eventVenue?.trim() : null,
      'is_pinned': isPinned,
      'requires_acknowledgment': requiresAcknowledgment,
      'status': status.dbValue,
      'publish_at': publishAt.toUtc().toIso8601String(),
      'expires_at': expiresAt?.toUtc().toIso8601String(),
      if (createdBy != null) 'created_by': createdBy,
    };
  }
}

/// Resident acknowledgment / read detail item for admin inspection.
class NoticeReaderInfo {
  final String residentId;
  final String residentName;
  final String? phone;
  final String? email;
  final String flatNumber;
  final String? blockName;
  final DateTime? readAt;
  final DateTime? acknowledgedAt;

  const NoticeReaderInfo({
    required this.residentId,
    required this.residentName,
    this.phone,
    this.email,
    required this.flatNumber,
    this.blockName,
    this.readAt,
    this.acknowledgedAt,
  });

  bool get hasRead => readAt != null;
  bool get hasAcknowledged => acknowledgedAt != null;

  String get flatDisplay =>
      blockName != null ? '$blockName - $flatNumber' : 'Flat $flatNumber';
}

/// Summary counts of society notices for admin tab badges.
class NoticeStats {
  final int total;
  final int draft;
  final int scheduled;
  final int published;
  final int expired;
  final int archived;

  const NoticeStats({
    this.total = 0,
    this.draft = 0,
    this.scheduled = 0,
    this.published = 0,
    this.expired = 0,
    this.archived = 0,
  });
}
