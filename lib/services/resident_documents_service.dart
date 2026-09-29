import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/resident_document_models.dart';
import 'app_session.dart';

/// Tenant and owner documents (migration 20).
///
/// Files live in a private bucket. They are never turned into URLs: a page
/// is fetched with the signed-in user's token, and only after
/// `open_resident_document` has logged the view — the storage policy
/// refuses the download otherwise.
class ResidentDocumentsService extends ChangeNotifier {
  ResidentDocumentsService._();
  static final ResidentDocumentsService instance = ResidentDocumentsService._();

  static const bucket = 'resident-documents';

  SupabaseClient? get _safeClient {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  SupabaseClient get _client {
    final c = _safeClient;
    if (c == null) throw Exception('Not connected to the server');
    return c;
  }

  bool get isOffline => _safeClient == null;

  int _adminPendingCount = 0;
  int _attentionCount = 0;

  /// Admin: documents waiting for review.
  int get adminPendingCount => _adminPendingCount;

  /// Resident: rent agreement missing or ending soon, or an upload rejected.
  int get attentionCount => _attentionCount;

  /// Unwraps the `{success, error}` envelope the document RPCs return.
  static Map<String, dynamic> _rpcOk(dynamic res, String fallbackError) {
    if (res is Map) {
      final map = Map<String, dynamic>.from(res);
      if (map['success'] == true) return map;
      throw Exception(map['error']?.toString() ?? fallbackError);
    }
    throw Exception(fallbackError);
  }

  static String humanize(Object e) {
    if (e is PostgrestException) {
      if (e.code == 'PGRST202' || e.code == '42883' || e.code == '42P01') {
        return 'Documents are not set up on this database yet — run migration 20.';
      }
      if (e.code == '42501') {
        return 'You do not have access to these documents.';
      }
      return e.message;
    }
    if (e is StorageException) {
      if (e.statusCode == '413' || e.message.contains('exceeded')) {
        return 'That file is too large (10 MB at most).';
      }
      if (e.statusCode == '415' || e.message.toLowerCase().contains('mime')) {
        return 'Only JPG, PNG or PDF files.';
      }
      return e.message;
    }
    final s = e.toString();
    if (s.contains('SocketException') ||
        s.contains('Failed host lookup') ||
        s.contains('ClientException')) {
      return 'No connection to the server. Check the network and retry.';
    }
    return s.replaceFirst('Exception: ', '');
  }

  // ─────────────────────────────────────────────────────────────
  // Reading
  // ─────────────────────────────────────────────────────────────

  /// The people whose documents the caller may see. [flatId] set: one flat
  /// (the office, from the directory). Null: the caller's own flats.
  Future<List<DocumentSubject>> fetchSubjects({String? flatId}) async {
    final res = await _client.rpc(
      'get_document_subjects',
      params: {'p_flat_id': flatId},
    );
    return (res as List)
        .whereType<Map>()
        .map((m) => DocumentSubject.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Document rows for these residents. RLS drops any the caller may not
  /// list.
  Future<List<ResidentDocument>> fetchDocuments(
    List<String> residentIds,
  ) async {
    if (residentIds.isEmpty) return const [];
    final rows = await _client
        .from('resident_documents')
        .select()
        .inFilter('resident_id', residentIds)
        .order('created_at', ascending: false);
    return (rows as List)
        .whereType<Map>()
        .map((m) => ResidentDocument.fromMap(Map<String, dynamic>.from(m)))
        .whereType<ResidentDocument>()
        .toList();
  }

  Future<ResidentDocument?> fetchDocument(String documentId) async {
    final row = await _client
        .from('resident_documents')
        .select()
        .eq('id', documentId)
        .maybeSingle();
    return row == null ? null : ResidentDocument.fromMap(row);
  }

  Future<AdminDocumentsOverview> fetchOverview() async {
    final societyId = AppSession.instance.societyId;
    if (societyId == null) {
      throw Exception('This account is not linked to a society yet.');
    }
    final res = _rpcOk(
      await _client.rpc(
        'admin_documents_overview',
        params: {'p_society_id': societyId},
      ),
      'Could not load documents',
    );
    return AdminDocumentsOverview.fromMap(res);
  }

  /// Badge counts for the home screen. Failures leave the old counts: a
  /// missing badge is better than a wrong error on the home screen.
  Future<void> refreshCounts() async {
    final client = _safeClient;
    final session = AppSession.instance;
    if (client == null || client.auth.currentUser == null || session.isGuard) {
      return;
    }
    try {
      final res = _rpcOk(
        await client.rpc(
          'document_action_counts',
          params: {'p_society_id': session.societyId},
        ),
        'Could not load document counts',
      );
      final pending = (res['to_verify'] as num?)?.toInt() ?? 0;
      final attention = (res['attention'] as num?)?.toInt() ?? 0;
      if (pending != _adminPendingCount || attention != _attentionCount) {
        _adminPendingCount = pending;
        _attentionCount = attention;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('ResidentDocumentsService.refreshCounts: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Uploading
  // ─────────────────────────────────────────────────────────────

  /// Reserves the pages on the server, uploads them one at a time, then
  /// submits the document for review. Returns the document id.
  Future<String> upload({
    required DocumentSubject subject,
    required ResidentDocType type,
    required List<PickedDocumentPage> pages,
    DateTime? validFrom,
    DateTime? validUntil,
    String? referenceNumber,
    String? note,
    void Function(int done, int total)? onProgress,
  }) async {
    final pageError = DocumentFileCheck.checkPages(
      pages.map((p) => p.mimeType).toList(),
    );
    if (pageError != null) throw Exception(pageError);
    for (final p in pages) {
      final err = DocumentFileCheck.checkFile(p.bytes);
      if (err != null) throw Exception(err);
    }

    final created = _rpcOk(
      await _client.rpc(
        'create_resident_document',
        params: {
          'p_resident_id': subject.residentId,
          'p_doc_type': type.dbValue,
          'p_mime_types': pages.map((p) => p.mimeType).toList(),
          'p_sizes': pages.map((p) => p.bytes.length).toList(),
          'p_valid_from': _day(validFrom),
          'p_valid_until': _day(validUntil),
          'p_reference_number': referenceNumber,
          'p_note': note,
          'p_consent_version': kDocumentNoticeVersion,
        },
      ),
      'Could not start the upload',
    );

    final documentId = created['document_id'].toString();
    final paths = (created['paths'] as List).map((p) => p.toString()).toList();
    if (paths.length != pages.length) {
      await _cancel(documentId);
      throw Exception('Could not start the upload');
    }

    try {
      final storage = _client.storage.from(bucket);
      for (var i = 0; i < pages.length; i++) {
        onProgress?.call(i, pages.length);
        try {
          await storage.uploadBinary(
            paths[i],
            pages[i].bytes,
            fileOptions: FileOptions(
              contentType: pages[i].mimeType,
              upsert: false,
              cacheControl: '0',
            ),
          );
        } on StorageException catch (e) {
          // A retry after a dropped response: the page is already there.
          // submit re-checks every page exists with the right type.
          if (e.statusCode != '409' && !e.message.contains('already exists')) {
            rethrow;
          }
        }
      }
      onProgress?.call(pages.length, pages.length);

      _rpcOk(
        await _client.rpc(
          'submit_resident_document',
          params: {'p_document_id': documentId},
        ),
        'Could not submit the document',
      );
    } catch (_) {
      await _cancel(documentId);
      rethrow;
    }

    refreshCounts();
    return documentId;
  }

  Future<void> _cancel(String documentId) async {
    try {
      await _client.rpc(
        'cancel_resident_document',
        params: {'p_document_id': documentId},
      );
    } catch (e) {
      debugPrint('cancel_resident_document: $e');
    }
  }

  Future<void> withdraw(String documentId) async {
    _rpcOk(
      await _client.rpc(
        'withdraw_resident_document',
        params: {'p_document_id': documentId},
      ),
      'Could not withdraw the document',
    );
    refreshCounts();
  }

  static String? _day(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';

  // ─────────────────────────────────────────────────────────────
  // Viewing
  // ─────────────────────────────────────────────────────────────

  /// Logs the view and returns the pages. Downloads are allowed for the
  /// next 10 minutes; call again after that.
  Future<List<DocumentPage>> open(String documentId, {String? reason}) async {
    final res = _rpcOk(
      await _client.rpc(
        'open_resident_document',
        params: {'p_document_id': documentId, 'p_reason': reason},
      ),
      'Could not open the document',
    );
    return (res['pages'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => DocumentPage.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Fetches one page with the user's token. If the 10-minute window from
  /// [open] has passed, storage answers "not found"; the view is logged
  /// again once and the download retried.
  Future<Uint8List> downloadPage(String documentId, DocumentPage page) async {
    final storage = _client.storage.from(bucket);
    try {
      return await storage.download(page.path);
    } on StorageException catch (e) {
      final notFound =
          e.statusCode == '400' ||
          e.statusCode == '404' ||
          e.message.toLowerCase().contains('not found');
      if (!notFound) rethrow;
      await open(documentId);
      return storage.download(page.path);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Review (society office)
  // ─────────────────────────────────────────────────────────────

  Future<void> review(
    String documentId, {
    required bool verified,
    String? note,
  }) async {
    _rpcOk(
      await _client.rpc(
        'review_resident_document',
        params: {
          'p_document_id': documentId,
          'p_decision': verified ? 'verified' : 'rejected',
          'p_note': note,
        },
      ),
      'Could not save the decision',
    );
    refreshCounts();
  }

  // ─────────────────────────────────────────────────────────────
  // PAN
  // ─────────────────────────────────────────────────────────────

  /// Saves (encrypted on the server) and returns the last four characters.
  Future<String> setPan(String residentId, String pan) async {
    final res = _rpcOk(
      await _client.rpc(
        'set_resident_pan',
        params: {
          'p_resident_id': residentId,
          'p_pan': PanNumber.normalize(pan),
        },
      ),
      'Could not save the PAN',
    );
    return res['pan_last4']?.toString() ?? '';
  }

  /// The full PAN. Logged on the server; an admin must give a reason.
  Future<String> revealPan(String residentId, {String? reason}) async {
    final res = _rpcOk(
      await _client.rpc(
        'reveal_resident_pan',
        params: {'p_resident_id': residentId, 'p_reason': reason},
      ),
      'Could not show the PAN',
    );
    return res['pan']?.toString() ?? '';
  }

  /// Forget the counts on sign-out.
  void clear() {
    _adminPendingCount = 0;
    _attentionCount = 0;
    notifyListeners();
  }
}
