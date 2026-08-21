import 'package:flutter/material.dart';

/// Central color palette for the entire app.
///
/// CLIENT BRAND COLORS ARE CONFIGURED ONLY HERE.
/// Replace any hex value once and the whole application updates globally
/// for both light and dark mode.
///
/// The client palettes are mapped to semantic roles below. A calm, neutral
/// foundation (canvas / card / hairline) is layered under the brand hues so
/// the interface reads premium and professional instead of oversaturated.
class AppPalette {
  AppPalette._();

  // ---- LIGHT MODE ---------------------------------------------------------
  // Brand palette: #E8FFCE (mint) · #ACFADF (aqua) · #94ADD7 (periwinkle)
  //                #7C73C0 (violet) · text navy #111844
  static const light = AppPaletteData(
    // Foundations
    canvas: Color(0xFFF3F4F8),
    card: Color(0xFFFFFFFF),
    cardMuted: Color(0xFFF1F2F7),
    hairline: Color(0xFFE6E8F0),
    // Brand roles
    primary: Color(0xFF7C73C0),
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFF94ADD7),
    onSecondary: Color(0xFF1B2340),
    accent: Color(0xFFACFADF),
    accentOn: Color(0xFF0E3A2E),
    mint: Color(0xFFE8FFCE),
    mintOn: Color(0xFF2C4A1E),
    // Text
    textPrimary: Color(0xFF1E2240),
    textSecondary: Color(0xFF5E6480),
    textTertiary: Color(0xFF9AA1BC),
    // Semantics
    success: Color(0xFF2F9E6E),
    warning: Color(0xFFD99A2B),
    danger: Color(0xFFD9534F),
    // Depth
    shadow: Color(0xFF16224D),
    heroStart: Color(0xFF7C73C0),
    heroEnd: Color(0xFF94ADD7),
    // Muted, desaturated categorical colors for service tiles
    featureColors: [
      Color(0xFF7C73C0),
      Color(0xFF5C8AD8),
      Color(0xFF2E9A8E),
      Color(0xFF7B61C4),
      Color(0xFFC98A3D),
      Color(0xFFC25E5E),
      Color(0xFF3F7FBF),
      Color(0xFF9B7AC0),
    ],
  );

  // ---- DARK MODE ----------------------------------------------------------
  // Brand palette: #111844 (navy) · #4B5694 (indigo) · #7288AE (steel)
  //                #EAE0CF (cream)
  static const dark = AppPaletteData(
    // Foundations
    canvas: Color(0xFF111844),
    card: Color(0xFF1C2557),
    cardMuted: Color(0xFF242F6A),
    hairline: Color(0xFF2B3574),
    // Brand roles
    primary: Color(0xFF7288AE),
    onPrimary: Color(0xFF111844),
    secondary: Color(0xFF94ADD7),
    onSecondary: Color(0xFF111844),
    accent: Color(0xFF4B5694),
    accentOn: Color(0xFFEAE0CF),
    mint: Color(0xFFEAE0CF),
    mintOn: Color(0xFF1E2440),
    // Text
    textPrimary: Color(0xFFEAE0CF),
    textSecondary: Color(0xFFAEB7DA),
    textTertiary: Color(0xFF7E88B8),
    // Semantics
    success: Color(0xFF4FD0A0),
    warning: Color(0xFFF0BD5E),
    danger: Color(0xFFF27084),
    // Depth
    shadow: Color(0xFF000000),
    heroStart: Color(0xFF4B5694),
    heroEnd: Color(0xFF7288AE),
    // Lighter categorical colors tuned for dark surfaces
    featureColors: [
      Color(0xFF9A8CE8),
      Color(0xFF7BA4EC),
      Color(0xFF4CC3A6),
      Color(0xFFA58BE0),
      Color(0xFFE8B25E),
      Color(0xFFE77A7A),
      Color(0xFF6CA2FF),
      Color(0xFFBF9AE0),
    ],
  );
}

class AppPaletteData {
  // Foundations
  final Color canvas;
  final Color card;
  final Color cardMuted;
  final Color hairline;

  // Brand roles
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color onSecondary;
  final Color accent;
  final Color accentOn;
  final Color mint;
  final Color mintOn;

  // Text
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  // Semantics
  final Color success;
  final Color warning;
  final Color danger;

  // Depth
  final Color shadow;
  final Color heroStart;
  final Color heroEnd;

  // Categorical colors for service tiles
  final List<Color> featureColors;

  const AppPaletteData({
    required this.canvas,
    required this.card,
    required this.cardMuted,
    required this.hairline,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    required this.accent,
    required this.accentOn,
    required this.mint,
    required this.mintOn,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.success,
    required this.warning,
    required this.danger,
    required this.shadow,
    required this.heroStart,
    required this.heroEnd,
    required this.featureColors,
  });

  Color featureColor(int index) => featureColors[index % featureColors.length];

  /// A soft shadow tinted by the palette's shadow color.
  Color shadowAt(double opacity) => shadow.withValues(alpha: opacity);
}
