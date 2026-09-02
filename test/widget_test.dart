import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:society_management/main.dart';
import 'package:society_management/screens/admin_vehicles_screen.dart';
import 'package:society_management/screens/home_screen.dart';
import 'package:society_management/screens/main_shell.dart';
import 'package:society_management/screens/notices_screen.dart';
import 'package:society_management/theme/app_theme.dart';
import 'package:society_management/theme/theme_controller.dart';
import 'package:society_management/widgets/home_widgets.dart';

Widget _buildApp([ThemeMode mode = ThemeMode.light]) {
  return SocietyApp(themeController: ThemeController(mode));
}

Color _scaffoldBackground(WidgetTester tester) {
  return Theme.of(tester.element(find.byType(MainShell))).scaffoldBackgroundColor;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Home screen renders the society management hub',
      (WidgetTester tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(find.text('MY SOCIETY'), findsOneWidget);
    expect(find.textContaining('Resident'), findsOneWidget);
    expect(find.textContaining('₹4,850'), findsWidgets);
    expect(find.text('Visitors today'), findsOneWidget);
    expect(find.text('Notices'), findsWidgets);

    // The hero carousel nests its own PageView scrollable; .first keeps the
    // outer page scroll (tree order puts ancestors before descendants).
    final scrollable = find
        .descendant(
          of: find.byType(HomeScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Services'),
      300,
      scrollable: scrollable,
    );
    expect(find.text('Services'), findsOneWidget);
    expect(find.text('Notices'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Latest updates'),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('No active notices right now'), findsOneWidget);
  });

  testWidgets('Settings tab toggles between light and dark palette',
      (WidgetTester tester) async {
    await tester.pumpWidget(_buildApp(ThemeMode.light));

    expect(_scaffoldBackground(tester), AppPalette.light.canvas);

    await tester.tap(find.byIcon(Icons.tune_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Theme'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(_scaffoldBackground(tester), AppPalette.dark.canvas);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(_scaffoldBackground(tester), AppPalette.light.canvas);
  });

  testWidgets('Hero balance card renders the cleared state when dues are paid',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: HeroBalanceCard(
              societyName: 'Sunrise Heights',
              period: 'September 2026',
              amount: '₹0.00',
              dueCaption: '',
              onPay: _noop,
              duesCleared: true,
              paidSummary: '₹4,850 paid on 5 Aug · Receipt #SH-2408',
              nextInvoiceCaption: 'Next invoice · 1 Oct 2026',
            ),
          ),
        ),
      ),
    );

    expect(find.text('All clear!'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.textContaining('Receipt #SH-2408'), findsOneWidget);
    expect(find.textContaining('Next invoice'), findsOneWidget);
    expect(find.text('View receipts'), findsOneWidget);
    expect(find.text('Ledger'), findsOneWidget);
    expect(find.text('Maintenance due'), findsNothing);
  });

  testWidgets('AdminVehiclesScreen renders vehicle stats, search, and list',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: AdminVehiclesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vehicles & Parking'), findsOneWidget);
    expect(find.text('Registered'), findsOneWidget);
    expect(find.text('Allotted Slot'), findsOneWidget);
    expect(find.text('Unassigned'), findsOneWidget);
    expect(find.textContaining('Creta'), findsOneWidget);
    expect(find.textContaining('P-101'), findsOneWidget);
    expect(find.text('Add vehicle'), findsOneWidget);
  });
}

void _noop() {}