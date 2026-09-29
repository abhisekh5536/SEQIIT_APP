import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:society_management/models/resident_document_models.dart';

void main() {
  group('ResidentDocType', () {
    test('round-trips every database value', () {
      for (final t in ResidentDocType.values) {
        expect(ResidentDocType.fromDb(t.dbValue), t);
      }
      expect(ResidentDocType.fromDb('aadhaar_full'), isNull);
    });

    test('matches document_type_fits() on the server', () {
      expect(ResidentDocType.maskedAadhaar.allowedFor('family'), isTrue);
      expect(ResidentDocType.rentAgreement.allowedFor('tenant'), isTrue);
      expect(ResidentDocType.rentAgreement.allowedFor('owner'), isFalse);
      expect(ResidentDocType.saleDeed.allowedFor('owner'), isTrue);
      expect(ResidentDocType.saleDeed.allowedFor('tenant'), isFalse);
      expect(ResidentDocType.policeVerification.allowedFor('family'), isFalse);
    });

    test('forCategory lists only what fits the person', () {
      expect(
        ResidentDocType.forCategory(DocumentCategory.tenancy, 'owner'),
        isEmpty,
      );
      expect(ResidentDocType.forCategory(DocumentCategory.tenancy, 'tenant'), [
        ResidentDocType.rentAgreement,
        ResidentDocType.policeVerification,
        ResidentDocType.ownerNoc,
      ]);
      expect(
        ResidentDocType.forCategory(DocumentCategory.ownership, 'owner').first,
        ResidentDocType.saleDeed,
      );
    });

    test('only the rent agreement needs dates', () {
      expect(ResidentDocType.values.where((t) => t.requiresValidity), [
        ResidentDocType.rentAgreement,
      ]);
    });
  });

  group('ResidentDocument', () {
    Map<String, dynamic> row({
      String status = 'verified',
      String? validUntil,
      String type = 'rent_agreement',
    }) => {
      'id': 'd1',
      'society_id': 's1',
      'flat_id': 'f1',
      'resident_id': 'r1',
      'doc_type': type,
      'status': status,
      'valid_from': '2026-01-01',
      'valid_until': validUntil,
      'created_at': '2026-01-02T10:00:00Z',
    };

    test('fromMap reads the row', () {
      final d = ResidentDocument.fromMap(row(validUntil: '2026-11-30'))!;
      expect(d.type, ResidentDocType.rentAgreement);
      expect(d.status, ResidentDocStatus.verified);
      expect(d.validUntil, DateTime(2026, 11, 30));
      expect(d.isCurrent, isTrue);
      expect(d.hasFiles, isTrue);
    });

    test('an unknown type or a missing id is skipped, not guessed', () {
      expect(ResidentDocument.fromMap(row(type: 'something_new')), isNull);
      expect(ResidentDocument.fromMap({...row(), 'id': null}), isNull);
    });

    test('an unknown status falls back to a harmless one', () {
      final d = ResidentDocument.fromMap(row(status: 'weird'))!;
      expect(d.isCurrent, isFalse);
      expect(d.hasFiles, isFalse);
    });

    test('expiry boundaries', () {
      final now = DateTime(2026, 9, 30, 18, 0);
      DocumentExpiry at(String until, {String status = 'verified'}) =>
          ResidentDocument.fromMap(
            row(validUntil: until, status: status),
          )!.expiryState(now);

      expect(at('2026-09-29'), DocumentExpiry.expired);
      expect(
        at('2026-09-30'),
        DocumentExpiry.expiringSoon,
        reason: 'ends today',
      );
      expect(at('2026-10-30'), DocumentExpiry.expiringSoon, reason: '30 days');
      expect(at('2026-10-31'), DocumentExpiry.valid, reason: '31 days');
      expect(at('2026-09-01', status: 'superseded'), DocumentExpiry.none);
      expect(
        ResidentDocument.fromMap(row(validUntil: null))!.expiryState(now),
        DocumentExpiry.none,
      );
    });

    test('purged documents have no files to open', () {
      final d = ResidentDocument.fromMap({
        ...row(status: 'verified'),
        'files_purged_at': '2027-09-01T00:00:00Z',
      })!;
      expect(d.hasFiles, isFalse);
    });
  });

  group('DocumentSubject', () {
    test('sections follow the resident type', () {
      DocumentSubject s(String type) => DocumentSubject.fromMap({
        'resident_id': 'r',
        'resident_type': type,
        'can_upload_tenancy': 'true',
      });
      expect(s('tenant').categories, [
        DocumentCategory.identity,
        DocumentCategory.tenancy,
      ]);
      expect(s('owner').categories, [
        DocumentCategory.identity,
        DocumentCategory.ownership,
      ]);
      expect(s('family').categories, [DocumentCategory.identity]);
      expect(s('tenant').canUpload(DocumentCategory.tenancy), isTrue);
      expect(s('tenant').canOpen(DocumentCategory.identity), isFalse);
    });

    test('a family member shows their relation', () {
      final s = DocumentSubject.fromMap({
        'resident_id': 'r',
        'resident_type': 'family',
        'relation': 'Spouse',
        'full_name': 'Asha Rao',
      });
      expect(s.roleLabel, 'Spouse');
      expect(s.initials, 'AR');
    });
  });

  group('PanNumber', () {
    test('normalises spacing and case', () {
      expect(PanNumber.normalize(' abcde 1234f '), 'ABCDE1234F');
      expect(PanNumber.isValid('abcde1234f'), isTrue);
    });

    test('rejects malformed PANs', () {
      for (final bad in [
        '',
        'ABCD1234F',
        'ABCDE12345',
        '12345ABCDE',
        'ABCDE1234FF',
      ]) {
        expect(PanNumber.isValid(bad), isFalse, reason: bad);
        expect(PanNumber.validate(bad), isNotNull, reason: bad);
      }
      expect(PanNumber.validate('ABCDE1234F'), isNull);
    });

    test('masks to the last four characters', () {
      expect(PanNumber.mask('234F'), '••••••234F');
      expect(PanNumber.mask(null), 'Not added');
    });
  });

  group('DocumentFileCheck', () {
    Uint8List bytes(List<int> head, [int size = 16]) =>
        Uint8List.fromList([...head, ...List.filled(size - head.length, 0)]);

    test('sniffs the real type from the first bytes', () {
      expect(
        DocumentFileCheck.sniffMime(bytes([0xFF, 0xD8, 0xFF])),
        'image/jpeg',
      );
      expect(
        DocumentFileCheck.sniffMime(bytes([0x89, 0x50, 0x4E, 0x47])),
        'image/png',
      );
      expect(
        DocumentFileCheck.sniffMime(bytes([0x25, 0x50, 0x44, 0x46])),
        'application/pdf',
      );
      expect(
        DocumentFileCheck.sniffMime(bytes([0x4D, 0x5A])),
        isNull,
        reason: 'an .exe',
      );
      expect(DocumentFileCheck.sniffMime(Uint8List(0)), isNull);
    });

    test('rejects empty, oversized and unknown files', () {
      expect(DocumentFileCheck.checkFile(Uint8List(0)), isNotNull);
      expect(DocumentFileCheck.checkFile(bytes([0x4D, 0x5A])), isNotNull);
      expect(
        DocumentFileCheck.checkFile(
          bytes([0xFF, 0xD8, 0xFF], DocumentFileCheck.maxBytes + 1),
        ),
        'Each file must be under 10 MB',
      );
      expect(DocumentFileCheck.checkFile(bytes([0xFF, 0xD8, 0xFF])), isNull);
    });

    test('one PDF or up to ten photos, never mixed', () {
      const jpg = 'image/jpeg';
      const pdf = 'application/pdf';
      expect(DocumentFileCheck.checkPages([]), isNotNull);
      expect(DocumentFileCheck.checkPages([pdf]), isNull);
      expect(DocumentFileCheck.checkPages([pdf, pdf]), isNotNull);
      expect(DocumentFileCheck.checkPages([jpg, pdf]), isNotNull);
      expect(DocumentFileCheck.checkPages(List.filled(10, jpg)), isNull);
      expect(DocumentFileCheck.checkPages(List.filled(11, jpg)), isNotNull);
    });
  });

  test('admin overview parses every queue', () {
    final o = AdminDocumentsOverview.fromMap({
      'success': true,
      'to_verify': [
        {
          'document_id': 'd1',
          'doc_type': 'masked_aadhaar',
          'full_name': 'A',
          'flat_label': 'A-101',
        },
      ],
      'expiring': [
        {
          'document_id': 'd2',
          'doc_type': 'rent_agreement',
          'valid_until': '2026-10-10',
          'renewal_pending': true,
        },
      ],
      'expired': [],
      'missing_rent_agreement': [
        {'flat_id': 'f1', 'full_name': 'T', 'flat_label': 'B-202'},
      ],
      'missing_ownership': null,
    });
    expect(o.toVerify.single.type, ResidentDocType.maskedAadhaar);
    expect(o.expiring.single.renewalPending, isTrue);
    expect(o.expiryCount, 1);
    expect(o.missingCount, 1);
    expect(o.missingRentAgreement.single.documentId, isNull);
  });
}
