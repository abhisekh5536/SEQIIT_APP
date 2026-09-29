import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:society_management/screens/guard/guard_home_screen.dart';
import 'package:society_management/screens/guard/guard_shell.dart';
import 'package:society_management/theme/app_theme.dart';
import 'package:society_management/theme/theme_controller.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('gate home leads with the code box and one-tap entries', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: GuardHomeScreen(onOpenTab: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Visitor has a pass?'), findsOneWidget);
    expect(find.text('Verify'), findsOneWidget);
    for (final label in [
      'Guest',
      'Delivery',
      'Cab',
      'Service',
      'Vehicle',
      'Emergency',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.scrollUntilVisible(
      find.text('Nobody is waiting on a flat right now.'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('WAITING FOR RESIDENT (0)'), findsOneWidget);
    expect(find.text('Nobody is waiting on a flat right now.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the guard shell has its own four tabs, not the resident ones', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: GuardShell(themeController: ThemeController()),
      ),
    );
    await tester.pumpAndSettle();

    for (final tab in ['Gate', 'Inside', 'Alerts', 'Me']) {
      expect(find.text(tab), findsWidgets, reason: tab);
    }
    expect(find.text('My Flat'), findsNothing);

    await tester.tap(find.text('Me'));
    await tester.pumpAndSettle();
    expect(find.text('Security Guard'), findsOneWidget);

    await tester.tap(find.text('Alerts'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No active emergencies'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('guard screens fit a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: GuardShell(themeController: ThemeController()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    for (final tab in ['Inside', 'Alerts', 'Me']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }
  });
}
