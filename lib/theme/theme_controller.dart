import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the active [ThemeMode] and persists the user's choice locally.
///
/// Exposes the palette for the active brightness so screens can read brand
/// colors directly instead of hardcoding them.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController([super._mode = ThemeMode.system]);

  static const _prefsKey = 'theme_mode';

  static Future<ThemeController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = switch (prefs.getString(_prefsKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return ThemeController(mode);
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == value) return;
    value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }

  bool get isDark => value == ThemeMode.dark;
}