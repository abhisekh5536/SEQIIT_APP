import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:society_management/main.dart';
import 'package:society_management/theme/theme_controller.dart';

void main() {
  testWidgets('home hero carousel fits on narrow screens', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(SocietyApp(themeController: ThemeController()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
