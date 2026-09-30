import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/screens/splash_screen.dart';

void main() {
  testWidgets('shows the loading screen until start-up finishes',
      (tester) async {
    final done = Completer<String>();
    await tester.pumpWidget(AppBootstrap<String>(
      initialize: () => done.future,
      builder: (v) => MaterialApp(home: Text('app: $v')),
    ));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(SplashView), findsOneWidget);
    expect(find.text('SAQIIT'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    done.complete('ready');
    await tester.pumpAndSettle();
    expect(find.byType(SplashView), findsNothing);
    expect(find.text('app: ready'), findsOneWidget);
  });

  testWidgets('a failed start-up offers a retry that re-runs it',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(AppBootstrap<String>(
      initialize: () async {
        attempts++;
        if (attempts == 1) throw Exception('offline');
        return 'ok';
      },
      builder: (v) => MaterialApp(home: Text('app: $v')),
    ));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't start the app"), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('app: ok'), findsOneWidget);
  });
}
