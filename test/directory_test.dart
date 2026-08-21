import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:society_management/screens/directory_screen.dart';
import 'package:society_management/theme/app_theme.dart';

/// The register's vertical scroll view (chip rows are horizontal).
final verticalScroll = find.byWidgetPredicate(
  (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
);

Future<void> scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    300,
    scrollable: verticalScroll,
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Widget _screen({bool dark = false}) {
  return MaterialApp(
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    home: const DirectoryScreen(),
  );
}

void main() {
  testWidgets('register renders title, occupancy and all towers',
      (tester) async {
    await tester.pumpWidget(_screen());

    expect(find.text('Residents & Flats'), findsOneWidget);
    expect(find.text('Overall occupancy'), findsOneWidget);
    expect(find.text('Showing 24 of 24 flats'), findsOneWidget);
    expect(find.text('Tower A'), findsWidgets); // chip + section header
    expect(find.text('Tower B'), findsWidgets);
    expect(find.text('Tower C'), findsWidgets);

    await scrollTo(tester, find.text('B-204'));
    expect(find.text('B-204'), findsOneWidget);
    expect(find.text('Saurabh Roy'), findsOneWidget);

    await scrollTo(tester, find.text('Help contacts'));
    expect(find.text('Help contacts'), findsOneWidget);
    expect(find.text('Security desk'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark mode renders the register without errors',
      (tester) async {
    await tester.pumpWidget(_screen(dark: true));

    final context = tester.element(find.byType(DirectoryScreen));
    expect(Theme.of(context).scaffoldBackgroundColor, AppPalette.dark.canvas);
    expect(find.text('Residents & Flats'), findsOneWidget);
    expect(find.text('Showing 24 of 24 flats'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search narrows the register to matching flats',
      (tester) async {
    await tester.pumpWidget(_screen());

    await tester.enterText(
      find.byType(TextField),
      'mehta',
    );
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 24 flats'), findsOneWidget);
    expect(find.text('Rajesh Mehta'), findsOneWidget);
    expect(find.text('Clear filters'), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('Showing 24 of 24 flats'), findsOneWidget);
  });

  testWidgets('vacant + tower filters combine correctly', (tester) async {
    await tester.pumpWidget(_screen());

    await tester.tap(find.text('Vacant').first);
    await tester.pumpAndSettle();
    expect(find.text('Showing 4 of 24 flats'), findsOneWidget);

    await tester.tap(find.widgetWithText(InkWell, 'Tower A'));
    await tester.pumpAndSettle();
    expect(find.text('Showing 1 of 24 flats'), findsOneWidget);
    expect(find.text('A-106'), findsOneWidget);
  });

  testWidgets('flat card opens the detail sheet with flat info',
      (tester) async {
    await tester.pumpWidget(_screen());

    await tester.tap(find.text('A-101'));
    await tester.pumpAndSettle();

    expect(find.text('OCCUPANTS'), findsOneWidget);
    expect(find.text('FLAT DETAILS'), findsOneWidget);
    expect(find.text('REGISTERED VEHICLES'), findsOneWidget);
    expect(find.text('Call Rajesh'), findsOneWidget);
    expect(find.text('Rajesh Mehta'), findsWidgets); // card + sheet
    expect(find.text('A-01'), findsOneWidget); // parking
    expect(tester.takeException(), isNull);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.text('FLAT DETAILS'), findsNothing);
  });

  testWidgets('vacant flat sheet shows the allotment note', (tester) async {
    await tester.pumpWidget(_screen());

    await scrollTo(tester, find.text('A-106'));
    await tester.tap(find.text('A-106'));
    await tester.pumpAndSettle();

    expect(find.text('No contact'), findsOneWidget);
    expect(
      find.textContaining('No residents on record'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('add member appends the person to the register',
      (tester) async {
    await tester.pumpWidget(_screen());

    await tester.tap(find.text('Add member'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'e.g. Aman Gupta',
      ),
      'Aman Gupta',
    );
    await tester.ensureVisible(find.text('Add to directory'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to directory'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Aman Gupta added to A-101'), findsOneWidget);
    expect(find.text('Aman Gupta'), findsOneWidget);
    expect(find.text('Showing 24 of 24 flats'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}