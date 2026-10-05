import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:society_management/main.dart';
import 'package:society_management/screens/vehicles/admin/admin_vehicles_parking_dashboard.dart';
import 'package:society_management/screens/home_screen.dart';
import 'package:society_management/screens/main_shell.dart';
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
    // Header greeting + the My Flat card's role pill.
    expect(find.textContaining('Resident'), findsWidgets);
    // No sample dues on the home carousel until the maintenance module
    // supplies real ones; the first card is the (live) My Flat card.
    expect(find.textContaining('₹4,850'), findsNothing);
    expect(find.text('My Flat'), findsWidgets);
    expect(find.text('Security desk'), findsNothing,
        reason: 'only the first slide is built; security desk is second');
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

  testWidgets('AdminVehiclesParkingDashboard renders bays, allotted, vehicles tabs',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: AdminVehiclesParkingDashboard(showBack: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Parking & Vehicles'), findsOneWidget);
    expect(find.text('Bays'), findsWidgets);
    expect(find.text('Requests'), findsWidgets);
    expect(find.text('Allotted'), findsWidgets);
    expect(find.text('Vehicles'), findsWidgets);
    expect(find.text('Gate'), findsWidgets);
  });

  testWidgets('Bay requests tab shows an empty queue rather than sample rows',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: AdminVehiclesParkingDashboard(showBack: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Requests'));
    await tester.pumpAndSettle();

    expect(find.text('No bay requests'), findsOneWidget);
  });
}

void _noop() {}