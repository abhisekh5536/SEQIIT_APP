import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/notice_models.dart';
import 'app_session.dart';

class NoticesService {
  NoticesService._();
  static final NoticesService instance = NoticesService._();

  SupabaseClient? get _safeClient {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  SupabaseClient get _client =>
      _safeClient ?? SupabaseClient('http://localhost', 'anon');

  /// Fetches published notices targeted to the current resident.
  Future<List<NoticeRecord>> fetchResidentNotices({
    NoticeCategory? categoryFilter,
    bool includeExpired = false,
  }) async {
    if (_safeClient == null) return [];

    final session = AppSession.instance;
    if (!session.isLoaded) {
      await session.load();
    }
    final societyId = session.societyId;
    final myResidences = session.myResidences;

    if (societyId == null) return [];

    // Collect block IDs for all flats the user is registered in
    final blockIds = <String>{};
    final residentIds = myResidences.map((r) => r.id).toList();

    for (final r in myResidences) {
      final flat = session.flatOf(r);
      if (flat != null && flat.blockId.isNotEmpty) {
        blockIds.add(flat.blockId);
      }
    }

    try {
      // 1. Fetch notices for society
      var query = _client
          .from('notices')
          .select('*, blocks(name)')
          .eq('society_id', societyId)
          .eq('status', 'published')
          .lte('publish_at', DateTime.now().toUtc().toIso8601String());

      if (categoryFilter != null) {
        query = query.eq('category', categoryFilter.dbValue);
      }

      final res = await query.order('is_pinned', ascending: false).order('publish_at', ascending: false);
      final rawList = (res as List).cast<Map<String, dynamic>>();

      // Filter by scope in Dart for resilience (all OR resident's blocks)
      var filtered = rawList.where((m) {
        final targetType = m['target_type']?.toString() ?? 'all';
        final targetBlockId = m['target_block_id']?.toString();

        if (targetType == 'block' && targetBlockId != null) {
          if (!blockIds.contains(targetBlockId)) return false;
        }

        if (!includeExpired && m['expires_at'] != null) {
          final expires = DateTime.tryParse(m['expires_at'].toString());
          if (expires != null && expires.isBefore(DateTime.now())) {
            return false;
          }
        }
        return true;
      }).toList();

      if (filtered.isEmpty) return [];

      final noticeIds = filtered.map((m) => m['id'].toString()).toList();

      // 2. Fetch read status for current resident
      final readNoticeIds = <String>{};
      if (residentIds.isNotEmpty) {
        try {
          final readsRes = await _client
              .from('notice_reads')
              .select('notice_id')
              .inFilter('notice_id', noticeIds)
              .inFilter('resident_id', residentIds);
          for (final row in (readsRes as List)) {
            readNoticeIds.add(row['notice_id'].toString());
          }
        } catch (e) {
          debugPrint('Error fetching notice_reads: $e');
        }
      }

      // 3. Fetch ack status for current resident
      final ackMap = <String, DateTime>{};
      if (residentIds.isNotEmpty) {
        try {
          final acksRes = await _client
              .from('notice_acknowledgments')
              .select('notice_id, acknowledged_at')
              .inFilter('notice_id', noticeIds)
              .inFilter('resident_id', residentIds);
          for (final row in (acksRes as List)) {
            final nid = row['notice_id'].toString();
            final at = DateTime.tryParse(row['acknowledged_at']?.toString() ?? '');
            if (at != null) ackMap[nid] = at;
          }
        } catch (e) {
          debugPrint('Error fetching notice_acknowledgments: $e');
        }
      }

      return filtered.map((m) {
        final id = m['id'].toString();
        return NoticeRecord.fromMap(
          m,
          isRead: readNoticeIds.contains(id),
          isAcknowledged: ackMap.containsKey(id),
          acknowledgedAt: ackMap[id],
        );
      }).toList();
    } catch (e) {
      debugPrint('NoticesService.fetchResidentNotices error: $e');
      rethrow;
    }
  }

  /// Fetches upcoming event notices specifically for the resident feed banner.
  Future<List<NoticeRecord>> fetchUpcomingEvents() async {
    final session = AppSession.instance;
    if (!session.isLoaded) {
      await session.load();
    }
    final societyId = session.societyId;
    if (societyId == null) return [];

    try {
      final nowStr = DateTime.now().toUtc().toIso8601String();
      final res = await _client
          .from('notices')
          .select('*, blocks(name)')
          .eq('society_id', societyId)
          .eq('status', 'published')
          .eq('is_event', true)
          .gte('event_starts_at', nowStr)
          .order('event_starts_at', ascending: true)
          .limit(10);

      final list = (res as List).cast<Map<String, dynamic>>();
      return list.map(NoticeRecord.fromMap).toList();
    } catch (e) {
      debugPrint('NoticesService.fetchUpcomingEvents error: $e');
      return [];
    }
  }

  /// Fetches all society notices for the Society Admin with filters and stats.
  Future<List<NoticeRecord>> fetchSocietyNotices({
    NoticeStatus? statusFilter,
    NoticeCategory? categoryFilter,
    String? blockIdFilter,
    String? searchQuery,
    String sortBy = 'newest', // 'newest' | 'oldest' | 'pinned'
  }) async {
    final session = AppSession.instance;
    if (!session.isLoaded) {
      await session.load();
    }
    final societyId = session.societyId;
    if (societyId == null) return [];

    try {
      dynamic query = _client
          .from('notices')
          .select('*, blocks(name)')
          .eq('society_id', societyId);

      if (statusFilter != null) {
        query = query.eq('status', statusFilter.dbValue);
      }

      if (categoryFilter != null) {
        query = query.eq('category', categoryFilter.dbValue);
      }

      if (blockIdFilter != null && blockIdFilter.isNotEmpty) {
        query = query.eq('target_block_id', blockIdFilter);
      }

      if (sortBy == 'oldest') {
        query = query.order('created_at', ascending: true);
      } else if (sortBy == 'pinned') {
        query = query.order('is_pinned', ascending: false).order('created_at', ascending: false);
      } else {
        query = query.order('created_at', ascending: false);
      }

      final res = await query;
      var rawList = (res as List).cast<Map<String, dynamic>>();

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.trim().toLowerCase();
        rawList = rawList.where((m) {
          final title = (m['title'] ?? '').toString().toLowerCase();
          final body = (m['body'] ?? '').toString().toLowerCase();
          return title.contains(q) || body.contains(q);
        }).toList();
      }

      if (rawList.isEmpty) return [];

      final noticeIds = rawList.map((m) => m['id'].toString()).toList();

      // Total residents count in society for percentage calculation
      int totalResidents = 0;
      try {
        final countRes = await _client
            .from('residents')
            .select('id')
            .eq('society_id', societyId)
            .eq('status', 'active');
        totalResidents = (countRes as List).length;
      } catch (_) {}

      // Fetch read counts per notice
      final readCounts = <String, int>{};
      try {
        final reads = await _client
            .from('notice_reads')
            .select('notice_id')
            .inFilter('notice_id', noticeIds);
        for (final row in (reads as List)) {
          final nid = row['notice_id'].toString();
          readCounts[nid] = (readCounts[nid] ?? 0) + 1;
        }
      } catch (_) {}

      // Fetch ack counts per notice
      final ackCounts = <String, int>{};
      try {
        final acks = await _client
            .from('notice_acknowledgments')
            .select('notice_id')
            .inFilter('notice_id', noticeIds);
        for (final row in (acks as List)) {
          final nid = row['notice_id'].toString();
          ackCounts[nid] = (ackCounts[nid] ?? 0) + 1;
        }
      } catch (_) {}

      return rawList.map((m) {
        final id = m['id'].toString();
        return NoticeRecord.fromMap(
          m,
          readCount: readCounts[id] ?? 0,
          ackCount: ackCounts[id] ?? 0,
          totalResidents: totalResidents,
        );
      }).toList();
    } catch (e) {
      debugPrint('NoticesService.fetchSocietyNotices error: $e');
      rethrow;
    }
  }

  /// Fetches a single notice by ID.
  Future<NoticeRecord?> fetchNoticeById(String noticeId) async {
    try {
      final res = await _client
          .from('notices')
          .select('*, blocks(name)')
          .eq('id', noticeId)
          .maybeSingle();

      if (res == null) return null;

      final session = AppSession.instance;
      final residentIds = session.myResidences.map((r) => r.id).toList();

      bool isRead = false;
      bool isAck = false;
      DateTime? ackAt;

      if (residentIds.isNotEmpty) {
        try {
          final rRes = await _client
              .from('notice_reads')
              .select('id')
              .eq('notice_id', noticeId)
              .inFilter('resident_id', residentIds)
              .maybeSingle();
          isRead = rRes != null;

          final aRes = await _client
              .from('notice_acknowledgments')
              .select('acknowledged_at')
              .eq('notice_id', noticeId)
              .inFilter('resident_id', residentIds)
              .maybeSingle();
          if (aRes != null) {
            isAck = true;
            ackAt = DateTime.tryParse(aRes['acknowledged_at']?.toString() ?? '');
          }
        } catch (_) {}
      }

      int readCount = 0;
      int ackCount = 0;
      int totalResidents = 0;

      if (session.isAdmin) {
        try {
          final societyId = res['society_id'].toString();
          final residentsRes = await _client
              .from('residents')
              .select('id')
              .eq('society_id', societyId)
              .eq('status', 'active');
          totalResidents = (residentsRes as List).length;

          final rList = await _client
              .from('notice_reads')
              .select('id')
              .eq('notice_id', noticeId);
          readCount = (rList as List).length;

          final aList = await _client
              .from('notice_acknowledgments')
              .select('id')
              .eq('notice_id', noticeId);
          ackCount = (aList as List).length;
        } catch (_) {}
      }

      return NoticeRecord.fromMap(
        res,
        isRead: isRead,
        isAcknowledged: isAck,
        acknowledgedAt: ackAt,
        readCount: readCount,
        ackCount: ackCount,
        totalResidents: totalResidents,
      );
    } catch (e) {
      debugPrint('NoticesService.fetchNoticeById error: $e');
      return null;
    }
  }

  /// Creates a new notice.
  Future<NoticeRecord> createNotice(
    NoticeRecord notice, {
    XFile? attachmentFile,
  }) async {
    final user = _client.auth.currentUser;
    String? uploadedUrl = notice.attachmentUrl;

    if (attachmentFile != null) {
      uploadedUrl = await uploadAttachment(attachmentFile);
    }

    final toInsert = notice.copyWith(
      createdBy: user?.id,
      attachmentUrl: uploadedUrl,
    ).toInsertMap();

    try {
      final res = await _client
          .from('notices')
          .insert(toInsert)
          .select('*, blocks(name)')
          .single();

      return NoticeRecord.fromMap(res);
    } catch (e) {
      debugPrint('NoticesService.createNotice error: $e');
      rethrow;
    }
  }

  /// Updates an existing notice.
  Future<NoticeRecord> updateNotice(
    NoticeRecord notice, {
    XFile? newAttachmentFile,
    bool removeAttachment = false,
  }) async {
    String? finalAttachmentUrl = notice.attachmentUrl;

    if (removeAttachment) {
      finalAttachmentUrl = null;
    } else if (newAttachmentFile != null) {
      finalAttachmentUrl = await uploadAttachment(newAttachmentFile);
    }

    final updateData = notice.copyWith(
      attachmentUrl: finalAttachmentUrl,
      updatedAt: DateTime.now(),
    ).toInsertMap();

    try {
      final res = await _client
          .from('notices')
          .update(updateData)
          .eq('id', notice.id)
          .select('*, blocks(name)')
          .single();

      return NoticeRecord.fromMap(res);
    } catch (e) {
      debugPrint('NoticesService.updateNotice error: $e');
      rethrow;
    }
  }

  /// Publishes a draft or scheduled notice immediately.
  Future<void> publishNoticeNow(String noticeId) async {
    try {
      await _client.from('notices').update({
        'status': 'published',
        'publish_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', noticeId);
    } catch (e) {
      debugPrint('NoticesService.publishNoticeNow error: $e');
      rethrow;
    }
  }

  /// Unpublishes an active notice (sets to draft).
  Future<void> unpublishNotice(String noticeId) async {
    try {
      await _client.from('notices').update({
        'status': 'draft',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', noticeId);
    } catch (e) {
      debugPrint('NoticesService.unpublishNotice error: $e');
      rethrow;
    }
  }

  /// Archives a notice.
  Future<void> archiveNotice(String noticeId) async {
    try {
      await _client.from('notices').update({
        'status': 'archived',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', noticeId);
    } catch (e) {
      debugPrint('NoticesService.archiveNotice error: $e');
      rethrow;
    }
  }

  /// Deletes a notice.
  Future<void> deleteNotice(String noticeId) async {
    try {
      await _client.from('notices').delete().eq('id', noticeId);
    } catch (e) {
      debugPrint('NoticesService.deleteNotice error: $e');
      rethrow;
    }
  }

  /// Records that the current resident opened/read the notice.
  Future<void> markAsRead(String noticeId) async {
    final session = AppSession.instance;
    final primary = session.primaryResidence ?? (session.myResidences.isNotEmpty ? session.myResidences.first : null);
    if (primary == null) return;

    final user = _client.auth.currentUser;

    try {
      await _client.from('notice_reads').upsert({
        'notice_id': noticeId,
        'resident_id': primary.id,
        if (user != null) 'user_id': user.id,
        'read_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'notice_id,resident_id');
    } catch (e) {
      // Fire-and-forget; do not block UI if already read
      debugPrint('NoticesService.markAsRead silent note: $e');
    }
  }

  /// Records that the resident explicitly acknowledged a mandatory notice.
  Future<void> acknowledgeNotice(String noticeId) async {
    final session = AppSession.instance;
    final primary = session.primaryResidence ?? (session.myResidences.isNotEmpty ? session.myResidences.first : null);
    if (primary == null) {
      throw Exception('No active resident profile found to acknowledge this notice.');
    }

    final user = _client.auth.currentUser;

    try {
      await _client.from('notice_acknowledgments').upsert({
        'notice_id': noticeId,
        'resident_id': primary.id,
        if (user != null) 'user_id': user.id,
        'acknowledged_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'notice_id,resident_id');

      // Also ensure it's marked as read
      await markAsRead(noticeId);
    } catch (e) {
      debugPrint('NoticesService.acknowledgeNotice error: $e');
      rethrow;
    }
  }

  /// Fetches reader and acknowledgment statistics with resident details for Admin view.
  Future<List<NoticeReaderInfo>> fetchNoticeReaderDetails(String noticeId) async {
    final societyId = AppSession.instance.societyId;
    if (societyId == null) return [];

    try {
      // Fetch all active residents in this society
      final resList = await _client
          .from('residents')
          .select('id, full_name, phone, email, flats(flat_number, blocks(name))')
          .eq('society_id', societyId)
          .eq('status', 'active');

      final readsList = await _client
          .from('notice_reads')
          .select('resident_id, read_at')
          .eq('notice_id', noticeId);

      final acksList = await _client
          .from('notice_acknowledgments')
          .select('resident_id, acknowledged_at')
          .eq('notice_id', noticeId);

      final readMap = <String, DateTime>{};
      for (final r in (readsList as List)) {
        final rid = r['resident_id'].toString();
        final dt = DateTime.tryParse(r['read_at']?.toString() ?? '');
        if (dt != null) readMap[rid] = dt;
      }

      final ackMap = <String, DateTime>{};
      for (final a in (acksList as List)) {
        final rid = a['resident_id'].toString();
        final dt = DateTime.tryParse(a['acknowledged_at']?.toString() ?? '');
        if (dt != null) ackMap[rid] = dt;
      }

      final readers = <NoticeReaderInfo>[];
      for (final r in (resList as List)) {
        final rid = r['id'].toString();
        final name = r['full_name']?.toString() ?? 'Resident';
        final phone = r['phone']?.toString();
        final email = r['email']?.toString();

        String flatNo = '-';
        String? blockName;
        if (r['flats'] != null && r['flats'] is Map) {
          final f = r['flats'] as Map;
          flatNo = f['flat_number']?.toString() ?? '-';
          if (f['blocks'] != null && f['blocks'] is Map) {
            blockName = (f['blocks'] as Map)['name']?.toString();
          }
        }

        readers.add(NoticeReaderInfo(
          residentId: rid,
          residentName: name,
          phone: phone,
          email: email,
          flatNumber: flatNo,
          blockName: blockName,
          readAt: readMap[rid],
          acknowledgedAt: ackMap[rid],
        ));
      }

      return readers;
    } catch (e) {
      debugPrint('NoticesService.fetchNoticeReaderDetails error: $e');
      return [];
    }
  }

  /// Fetches stats breakdown for society notices (counts by status).
  Future<NoticeStats> fetchNoticeStats() async {
    final societyId = AppSession.instance.societyId;
    if (societyId == null) return const NoticeStats();

    try {
      final res = await _client
          .from('notices')
          .select('status')
          .eq('society_id', societyId);

      final list = (res as List).cast<Map<String, dynamic>>();

      int draft = 0;
      int scheduled = 0;
      int published = 0;
      int expired = 0;
      int archived = 0;

      for (final row in list) {
        final s = row['status']?.toString();
        switch (s) {
          case 'draft':
            draft++;
            break;
          case 'scheduled':
            scheduled++;
            break;
          case 'published':
            published++;
            break;
          case 'expired':
            expired++;
            break;
          case 'archived':
            archived++;
            break;
        }
      }

      return NoticeStats(
        total: list.length,
        draft: draft,
        scheduled: scheduled,
        published: published,
        expired: expired,
        archived: archived,
      );
    } catch (e) {
      debugPrint('NoticesService.fetchNoticeStats error: $e');
      return const NoticeStats();
    }
  }

  /// Uploads an attachment to the `notice-attachments` bucket.
  Future<String> uploadAttachment(XFile file) async {
    final societyId = AppSession.instance.societyId ?? 'general';
    final ext = file.name.split('.').last;
    final fileName = '${societyId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final path = 'notices/$fileName';

    try {
      final bytes = await file.readAsBytes();
      await _client.storage.from('notice-attachments').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: _getContentType(ext),
              upsert: true,
            ),
          );

      return _client.storage.from('notice-attachments').getPublicUrl(path);
    } catch (e) {
      debugPrint('NoticesService.uploadAttachment error: $e');
      rethrow;
    }
  }

  /// Checks and syncs scheduled and expired notices in database.
  Future<void> syncDueNotices() async {
    try {
      await _client.rpc('publish_due_notices');
    } catch (e) {
      debugPrint('NoticesService.syncDueNotices silent note: $e');
    }
  }

  String _getContentType(String ext) {
    switch (ext.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }
}
