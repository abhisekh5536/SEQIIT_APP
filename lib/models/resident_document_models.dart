/// Tenant and owner documents (migration 20).
///
/// The full Aadhaar number is never stored anywhere — only the last four
/// digits (`residents.aadhar_last4`) and, optionally, the UIDAI "masked
/// Aadhaar" card. PAN is stored encrypted on the server; the app only ever
/// holds its last four characters unless the user asks to see it.
library;

import 'dart:typed_data';

/// Bumped whenever [kDocumentNoticeText] changes, so the server records
/// which wording each person agreed to.
const kDocumentNoticeVersion = '2026-09';

const kDocumentNoticeText =
    'The society office keeps these documents to know who lives in each '
    'flat and to support tenant police verification.\n\n'
    '• Seen only by the person, the society office and — for rent '
    'agreements and police verification — the flat\'s owner.\n'
    '• Every time someone opens a document it is logged.\n'
    '• Only the last 4 digits of Aadhaar are kept. Upload the masked '
    'Aadhaar (myaadhaar.uidai.gov.in), not the full card.\n'
    '• Everything is deleted 12 months after the person moves out.';

enum DocumentCategory {
  identity('ID proof'),
  tenancy('Tenancy'),
  ownership('Ownership');

  final String label;
  const DocumentCategory(this.label);

  static DocumentCategory? fromDb(String? v) => switch (v) {
    'identity' => identity,
    'tenancy' => tenancy,
    'ownership' => ownership,
    _ => null,
  };
}

enum ResidentDocType {
  maskedAadhaar('masked_aadhaar', 'Masked Aadhaar', DocumentCategory.identity),
  rentAgreement('rent_agreement', 'Rent agreement', DocumentCategory.tenancy),
  policeVerification(
    'police_verification',
    'Police verification',
    DocumentCategory.tenancy,
  ),
  ownerNoc('owner_noc', 'Owner NOC', DocumentCategory.tenancy),
  saleDeed('sale_deed', 'Sale deed', DocumentCategory.ownership),
  conveyanceDeed(
    'conveyance_deed',
    'Conveyance deed',
    DocumentCategory.ownership,
  ),
  allotmentLetter(
    'allotment_letter',
    'Allotment letter',
    DocumentCategory.ownership,
  ),
  possessionLetter(
    'possession_letter',
    'Possession letter',
    DocumentCategory.ownership,
  ),
  shareCertificate(
    'share_certificate',
    'Share certificate',
    DocumentCategory.ownership,
  ),
  indexII('index_ii', 'Index II', DocumentCategory.ownership),
  otherOwnership(
    'other_ownership',
    'Other ownership proof',
    DocumentCategory.ownership,
  );

  final String dbValue;
  final String label;
  final DocumentCategory category;

  const ResidentDocType(this.dbValue, this.label, this.category);

  static ResidentDocType? fromDb(String? v) {
    for (final t in values) {
      if (t.dbValue == v) return t;
    }
    return null;
  }

  /// Rent agreements are tracked by their end date.
  bool get requiresValidity => this == rentAgreement;

  /// Mirrors `document_type_fits()` in SQL: tenancy papers belong to
  /// tenants, title papers to owners, ID to anyone.
  bool allowedFor(String residentType) => switch (category) {
    DocumentCategory.identity => true,
    DocumentCategory.tenancy => residentType == 'tenant',
    DocumentCategory.ownership => residentType == 'owner',
  };

  static List<ResidentDocType> forCategory(
    DocumentCategory category,
    String residentType,
  ) => values
      .where((t) => t.category == category && t.allowedFor(residentType))
      .toList();

  /// Label for the optional reference-number field, or null to hide it.
  String? get referenceLabel => switch (this) {
    rentAgreement => 'Registration / e-stamp no. (optional)',
    policeVerification => 'Acknowledgement no. (optional)',
    saleDeed || conveyanceDeed || indexII => 'Registration no. (optional)',
    shareCertificate => 'Certificate no. (optional)',
    _ => null,
  };

  String? get help => switch (this) {
    maskedAadhaar =>
      'Download the masked Aadhaar from myaadhaar.uidai.gov.in. It shows '
          'only the last 4 digits. A card showing all 12 digits will be '
          'rejected.',
    rentAgreement => 'Photograph every page, or upload the signed PDF.',
    policeVerification =>
      'The acknowledgement from the police portal or station.',
    saleDeed => 'The registered sale deed, all pages.',
    _ => null,
  };
}

enum ResidentDocStatus {
  uploading('Uploading'),
  pending('Waiting for review'),
  verified('Verified'),
  rejected('Not accepted'),
  withdrawn('Withdrawn'),
  superseded('Replaced'),
  abandoned('Not uploaded'),
  purged('Deleted');

  final String label;
  const ResidentDocStatus(this.label);

  static ResidentDocStatus fromDb(String? v) {
    for (final s in values) {
      if (s.name == v) return s;
    }
    return abandoned;
  }
}

enum DocumentExpiry { none, valid, expiringSoon, expired }

class ResidentDocument {
  final String id;
  final String societyId;
  final String? flatId;
  final String? residentId;
  final ResidentDocType type;
  final ResidentDocStatus status;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final String? referenceNumber;
  final String? note;
  final String? reviewNote;
  final String? uploadedBy;
  final DateTime createdAt;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final DateTime? retentionUntil;
  final DateTime? filesPurgedAt;

  const ResidentDocument({
    required this.id,
    required this.societyId,
    this.flatId,
    this.residentId,
    required this.type,
    required this.status,
    this.validFrom,
    this.validUntil,
    this.referenceNumber,
    this.note,
    this.reviewNote,
    this.uploadedBy,
    required this.createdAt,
    this.submittedAt,
    this.reviewedAt,
    this.retentionUntil,
    this.filesPurgedAt,
  });

  static DateTime? _date(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  /// Null for a type this app version does not know.
  static ResidentDocument? fromMap(Map<String, dynamic> m) {
    final type = ResidentDocType.fromDb(m['doc_type']?.toString());
    final id = m['id']?.toString();
    if (type == null || id == null || id.isEmpty) return null;
    return ResidentDocument(
      id: id,
      societyId: m['society_id']?.toString() ?? '',
      flatId: m['flat_id']?.toString(),
      residentId: m['resident_id']?.toString(),
      type: type,
      status: ResidentDocStatus.fromDb(m['status']?.toString()),
      validFrom: _date(m['valid_from']),
      validUntil: _date(m['valid_until']),
      referenceNumber: m['reference_number']?.toString(),
      note: m['note']?.toString(),
      reviewNote: m['review_note']?.toString(),
      uploadedBy: m['uploaded_by']?.toString(),
      createdAt:
          _date(m['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      submittedAt: _date(m['submitted_at']),
      reviewedAt: _date(m['reviewed_at']),
      retentionUntil: _date(m['retention_until']),
      filesPurgedAt: _date(m['files_purged_at']),
    );
  }

  /// Pending or verified: the document that currently counts.
  bool get isCurrent =>
      status == ResidentDocStatus.pending ||
      status == ResidentDocStatus.verified;

  /// Worth showing in the main list (rather than history).
  bool get isVisible =>
      status != ResidentDocStatus.uploading &&
      status != ResidentDocStatus.abandoned &&
      status != ResidentDocStatus.withdrawn;

  bool get hasFiles =>
      filesPurgedAt == null &&
      status != ResidentDocStatus.purged &&
      status != ResidentDocStatus.abandoned &&
      status != ResidentDocStatus.uploading;

  /// Days from [now]'s date to [validUntil]; negative once it has ended.
  int? daysLeft([DateTime? now]) {
    final until = validUntil;
    if (until == null) return null;
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final end = DateTime(until.year, until.month, until.day);
    return end.difference(today).inDays;
  }

  /// Only meaningful for a document with an end date that still counts.
  DocumentExpiry expiryState([DateTime? now]) {
    final days = daysLeft(now);
    if (days == null || !isCurrent) return DocumentExpiry.none;
    if (days < 0) return DocumentExpiry.expired;
    if (days <= 30) return DocumentExpiry.expiringSoon;
    return DocumentExpiry.valid;
  }
}

/// A person whose documents the caller may see, and what they may do —
/// decided on the server by `get_document_subjects()`.
class DocumentSubject {
  final String residentId;
  final String societyId;
  final String flatId;
  final String flatLabel;
  final String fullName;
  final String residentType;
  final String? relation;
  final String status;
  final bool isSelf;
  final String? aadharLast4;
  final bool hasPan;
  final String? panLast4;
  final bool canUploadIdentity;
  final bool canOpenIdentity;
  final bool canUploadTenancy;
  final bool canOpenTenancy;
  final bool canUploadOwnership;
  final bool canOpenOwnership;
  final bool canRevealPan;

  const DocumentSubject({
    required this.residentId,
    required this.societyId,
    required this.flatId,
    required this.flatLabel,
    required this.fullName,
    required this.residentType,
    this.relation,
    required this.status,
    required this.isSelf,
    this.aadharLast4,
    required this.hasPan,
    this.panLast4,
    required this.canUploadIdentity,
    required this.canOpenIdentity,
    required this.canUploadTenancy,
    required this.canOpenTenancy,
    required this.canUploadOwnership,
    required this.canOpenOwnership,
    required this.canRevealPan,
  });

  static bool _b(dynamic v) => v == true || v?.toString() == 'true';

  factory DocumentSubject.fromMap(Map<String, dynamic> m) => DocumentSubject(
    residentId: m['resident_id']?.toString() ?? '',
    societyId: m['society_id']?.toString() ?? '',
    flatId: m['flat_id']?.toString() ?? '',
    flatLabel: m['flat_label']?.toString() ?? '',
    fullName: m['full_name']?.toString() ?? '',
    residentType: m['resident_type']?.toString() ?? 'owner',
    relation: m['relation']?.toString(),
    status: m['status']?.toString() ?? 'active',
    isSelf: _b(m['is_self']),
    aadharLast4: m['aadhar_last4']?.toString(),
    hasPan: _b(m['has_pan']),
    panLast4: m['pan_last4']?.toString(),
    canUploadIdentity: _b(m['can_upload_identity']),
    canOpenIdentity: _b(m['can_open_identity']),
    canUploadTenancy: _b(m['can_upload_tenancy']),
    canOpenTenancy: _b(m['can_open_tenancy']),
    canUploadOwnership: _b(m['can_upload_ownership']),
    canOpenOwnership: _b(m['can_open_ownership']),
    canRevealPan: _b(m['can_reveal_pan']),
  );

  bool get isActive => status == 'active';

  String get roleLabel => switch (residentType) {
    'owner' => 'Owner',
    'tenant' => 'Tenant',
    'family' =>
      relation?.trim().isNotEmpty == true ? relation!.trim() : 'Family',
    _ => residentType,
  };

  String get initials {
    final parts = fullName.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  bool canUpload(DocumentCategory c) => switch (c) {
    DocumentCategory.identity => canUploadIdentity,
    DocumentCategory.tenancy => canUploadTenancy,
    DocumentCategory.ownership => canUploadOwnership,
  };

  bool canOpen(DocumentCategory c) => switch (c) {
    DocumentCategory.identity => canOpenIdentity,
    DocumentCategory.tenancy => canOpenTenancy,
    DocumentCategory.ownership => canOpenOwnership,
  };

  /// Sections worth showing for this person.
  List<DocumentCategory> get categories => [
    DocumentCategory.identity,
    if (residentType == 'tenant') DocumentCategory.tenancy,
    if (residentType == 'owner') DocumentCategory.ownership,
  ];
}

/// One page of an opened document.
class DocumentPage {
  final String path;
  final String mimeType;
  final int pageNo;

  const DocumentPage({
    required this.path,
    required this.mimeType,
    required this.pageNo,
  });

  bool get isPdf => mimeType == 'application/pdf';

  factory DocumentPage.fromMap(Map<String, dynamic> m) => DocumentPage(
    path: m['path']?.toString() ?? '',
    mimeType: m['mime_type']?.toString() ?? '',
    pageNo: (m['page_no'] as num?)?.toInt() ?? 0,
  );
}

/// A page picked on the phone, waiting to be uploaded.
class PickedDocumentPage {
  final Uint8List bytes;
  final String mimeType;

  const PickedDocumentPage(this.bytes, this.mimeType);

  bool get isPdf => mimeType == 'application/pdf';
}

class PanNumber {
  PanNumber._();

  static final _pattern = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');

  static String normalize(String input) =>
      input.replaceAll(RegExp(r'\s'), '').toUpperCase();

  static bool isValid(String input) => _pattern.hasMatch(normalize(input));

  /// Form-field validator: null when valid.
  static String? validate(String input) {
    final v = normalize(input);
    if (v.isEmpty) return 'Enter the PAN';
    if (!_pattern.hasMatch(v)) return 'A PAN looks like ABCDE1234F';
    return null;
  }

  /// `••••••234F`. Only the last four characters are ever kept in the app.
  static String mask(String? last4) =>
      last4 == null || last4.isEmpty ? 'Not added' : '••••••$last4';
}

class DocumentFileCheck {
  DocumentFileCheck._();

  static const maxBytes = 10 * 1024 * 1024;
  static const maxImages = 10;

  /// The real type from the file's first bytes, whatever its name says.
  static String? sniffMime(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return 'application/pdf';
    }
    return null;
  }

  /// Checks one file; returns an error message or null.
  static String? checkFile(Uint8List bytes) {
    if (bytes.isEmpty) return 'That file is empty';
    if (bytes.length > maxBytes) return 'Each file must be under 10 MB';
    if (sniffMime(bytes) == null) return 'Only JPG, PNG or PDF files';
    return null;
  }

  /// A document is either one PDF or up to [maxImages] photos.
  static String? checkPages(List<String> mimeTypes) {
    if (mimeTypes.isEmpty) return 'Add at least one page';
    final pdfs = mimeTypes.where((m) => m == 'application/pdf').length;
    if (pdfs > 0 && mimeTypes.length > 1) {
      return 'Upload either one PDF or up to $maxImages photos';
    }
    if (mimeTypes.length > maxImages) {
      return 'Upload either one PDF or up to $maxImages photos';
    }
    return null;
  }
}

/// A row in one of the office's queues.
class AdminDocumentItem {
  final String? documentId;
  final ResidentDocType? type;
  final String? residentId;
  final String? flatId;
  final String fullName;
  final String flatLabel;
  final DateTime? submittedAt;
  final DateTime? validUntil;
  final bool renewalPending;

  const AdminDocumentItem({
    this.documentId,
    this.type,
    this.residentId,
    this.flatId,
    required this.fullName,
    required this.flatLabel,
    this.submittedAt,
    this.validUntil,
    this.renewalPending = false,
  });

  factory AdminDocumentItem.fromMap(Map<String, dynamic> m) =>
      AdminDocumentItem(
        documentId: m['document_id']?.toString(),
        type: ResidentDocType.fromDb(m['doc_type']?.toString()),
        residentId: m['resident_id']?.toString(),
        flatId: m['flat_id']?.toString(),
        fullName: m['full_name']?.toString() ?? 'Former resident',
        flatLabel: m['flat_label']?.toString() ?? '',
        submittedAt: ResidentDocument._date(m['submitted_at']),
        validUntil: ResidentDocument._date(m['valid_until']),
        renewalPending: m['renewal_pending'] == true,
      );
}

class AdminDocumentsOverview {
  final List<AdminDocumentItem> toVerify;
  final List<AdminDocumentItem> expiring;
  final List<AdminDocumentItem> expired;
  final List<AdminDocumentItem> missingRentAgreement;
  final List<AdminDocumentItem> missingOwnership;

  const AdminDocumentsOverview({
    this.toVerify = const [],
    this.expiring = const [],
    this.expired = const [],
    this.missingRentAgreement = const [],
    this.missingOwnership = const [],
  });

  static List<AdminDocumentItem> _list(dynamic v) => v is List
      ? v
            .whereType<Map>()
            .map((e) => AdminDocumentItem.fromMap(Map<String, dynamic>.from(e)))
            .toList()
      : const [];

  factory AdminDocumentsOverview.fromMap(Map<String, dynamic> m) =>
      AdminDocumentsOverview(
        toVerify: _list(m['to_verify']),
        expiring: _list(m['expiring']),
        expired: _list(m['expired']),
        missingRentAgreement: _list(m['missing_rent_agreement']),
        missingOwnership: _list(m['missing_ownership']),
      );

  int get missingCount => missingRentAgreement.length + missingOwnership.length;
  int get expiryCount => expiring.length + expired.length;
}
