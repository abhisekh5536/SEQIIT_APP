import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:society_management/models/resident_document_models.dart';
import 'package:society_management/screens/documents/admin_documents_dashboard.dart';
import 'package:society_management/screens/documents/document_upload_sheet.dart';
import 'package:society_management/screens/documents/resident_documents_screen.dart';
import 'package:society_management/screens/documents/widgets/document_widgets.dart';
import 'package:society_management/theme/app_theme.dart';

DocumentSubject _tenant() => DocumentSubject.fromMap({
  'resident_id': 'r1',
  'society_id': 's1',
  'flat_id': 'f1',
  'flat_label': 'A-101',
  'full_name': 'Ravi Kumar',
  'resident_type': 'tenant',
  'status': 'active',
  'is_self': true,
  'can_upload_identity': true,
  'can_upload_tenancy': true,
  'can_open_tenancy': true,
});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Without Supabase (tests, previews) the screens must say so — never
  // invent documents.
  testWidgets('resident screen without a server says so', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const ResidentDocumentsScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Documents need a connection to the server.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('office dashboard without a server says so', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const AdminDocumentsDashboard(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Resident documents'), findsOneWidget);
    expect(
      find.text('Documents need a connection to the server.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => DocumentUploadSheet.show(
                context,
                subject: _tenant(),
                category: DocumentCategory.tenancy,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('upload sheet offers only tenancy papers and asks for dates', (
    tester,
  ) async {
    await openSheet(tester);

    expect(find.text('Add tenancy document'), findsOneWidget);
    expect(find.text('Ravi Kumar · A-101'), findsOneWidget);
    expect(find.text('Rent agreement'), findsOneWidget);
    expect(find.text('Agreement period *'), findsOneWidget);
    expect(find.text('Sale deed'), findsNothing);
    expect(
      find.text('I agree to share this with the society office'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('upload sheet refuses to send without pages', (tester) async {
    await openSheet(tester);

    await tester.scrollUntilVisible(
      find.text('Send for review'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Send for review'));
    await tester.pumpAndSettle();

    expect(find.text('Add at least one page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('upload sheet fits a 320 px phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await openSheet(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a rejected document shows why', (tester) async {
    final doc = ResidentDocument.fromMap({
      'id': 'd1',
      'society_id': 's1',
      'doc_type': 'masked_aadhaar',
      'status': 'rejected',
      'review_note': 'All 12 digits are visible',
      'created_at': '2026-09-01T00:00:00Z',
    })!;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: DocumentTile(document: doc)),
      ),
    );
    expect(find.text('Masked Aadhaar'), findsOneWidget);
    expect(find.text('Not accepted'), findsOneWidget);
    expect(find.text('Reason: All 12 digits are visible'), findsOneWidget);
  });
}
