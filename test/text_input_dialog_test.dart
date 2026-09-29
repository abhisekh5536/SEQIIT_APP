import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:society_management/screens/admin/security_staff_screen.dart';
import 'package:society_management/theme/app_theme.dart';
import 'package:society_management/widgets/text_input_dialog.dart';

/// Opens [showTextInputDialog] from a button and records what it returned.
Future<List<String?>> _pumpOpener(
  WidgetTester tester, {
  String? requiredMessage,
}) async {
  final results = <String?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => results.add(
            await showTextInputDialog(
              context,
              title: 'Add gate',
              requiredMessage: requiredMessage,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Regression: the controller used to be disposed as soon as the dialog
  // was popped, while its TextField was still animating out — "A
  // TextEditingController was used after being disposed", then
  // "'_dependents.isEmpty': is not true" and a red screen.
  testWidgets('saving closes the dialog cleanly and returns the text',
      (tester) async {
    final results = await _pumpOpener(tester);

    await tester.enterText(find.byType(TextFormField), '  Main Gate  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(results, ['Main Gate']);
  });

  testWidgets('cancel returns null', (tester) async {
    final results = await _pumpOpener(tester);

    await tester.enterText(find.byType(TextFormField), 'x');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(results, [null]);
  });

  testWidgets('a required answer cannot be left empty', (tester) async {
    final results = await _pumpOpener(tester, requiredMessage: 'Enter a gate name');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a gate name'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('Guards & Gates: adding a gate does not crash', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const SecurityStaffScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Gates ('));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add gate'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Main Gate');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
