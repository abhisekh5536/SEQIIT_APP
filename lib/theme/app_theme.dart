import 'package:flutter/material.dart';

import 'app_palette.dart';

export 'app_palette.dart';

class AppTheme {
  AppTheme._();

  /// Returns the palette matching the given [Brightness].
  static AppPaletteData paletteFor(Brightness brightness) =>
      brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;

  static ThemeData light() => _build(AppPalette.light);

  static ThemeData dark() => _build(AppPalette.dark);

  static ThemeData _build(AppPaletteData p) {
    final isDark = p == AppPalette.dark;

    final colorScheme = ColorScheme.light().copyWith(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: p.primary,
      onPrimary: p.onPrimary,
      primaryContainer: p.primary.withValues(alpha: 0.16),
      onPrimaryContainer: p.textPrimary,
      secondary: p.secondary,
      onSecondary: p.onSecondary,
      secondaryContainer: p.accent.withValues(alpha: 0.35),
      onSecondaryContainer: p.accentOn,
      surface: p.card,
      onSurface: p.textPrimary,
      surfaceContainerLowest: p.canvas,
      surfaceContainerLow: p.card,
      surfaceContainer: p.cardMuted,
      surfaceContainerHigh: p.cardMuted,
      surfaceContainerHighest: p.hairline,
      onSurfaceVariant: p.textSecondary,
      outline: p.hairline,
      outlineVariant: p.hairline,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: p.canvas,
    );

    final textTheme = base.textTheme
        .copyWith(
          headlineLarge: base.textTheme.headlineLarge?.copyWith(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1.15,
            color: p.textPrimary,
          ),
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            height: 1.2,
            color: p.textPrimary,
          ),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            height: 1.25,
            color: p.textPrimary,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            height: 1.3,
            color: p.textPrimary,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1.3,
            color: p.textPrimary,
          ),
          titleSmall: base.textTheme.titleSmall?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.35,
            color: p.textPrimary,
          ),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            height: 1.45,
            color: p.textPrimary,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height: 1.45,
            color: p.textPrimary,
          ),
          bodySmall: base.textTheme.bodySmall?.copyWith(
            fontSize: 12.5,
            fontWeight: FontWeight.w400,
            height: 1.4,
            color: p.textSecondary,
          ),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            color: p.textPrimary,
          ),
          labelMedium: base.textTheme.labelMedium?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: p.textSecondary,
          ),
          labelSmall: base.textTheme.labelSmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: p.textTertiary,
          ),
        )
        .apply(bodyColor: p.textPrimary, displayColor: p.textPrimary);

    return base.copyWith(
      textTheme: textTheme,
      iconTheme: IconThemeData(color: p.textSecondary),
      appBarTheme: AppBarTheme(
        backgroundColor: p.canvas,
        foregroundColor: p.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        color: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          elevation: 0,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: textTheme.labelLarge?.copyWith(color: p.onPrimary),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.primary,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          side: BorderSide(color: p.hairline),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.card,
        hintStyle: TextStyle(color: p.textTertiary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: TextStyle(color: p.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.danger),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: p.hairline,
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.card.withValues(alpha: 0.92),
        indicatorColor: p.primary.withValues(alpha: 0.16),
        elevation: 0,
        height: 68,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? p.primary
                : p.textTertiary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11.5,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? p.primary
                : p.textTertiary,
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? p.onPrimary
                : p.textSecondary,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? p.primary
                : Colors.transparent,
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(color: p.hairline),
          ),
          textStyle: WidgetStateProperty.resolveWith(
            (_) => textTheme.labelLarge,
          ),
          visualDensity: VisualDensity.compact,
          shape: WidgetStateProperty.resolveWith(
            (_) => RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: p.cardMuted,
        labelStyle: textTheme.labelMedium,
        side: BorderSide(color: p.hairline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textSecondary,
        textColor: p.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }
}

/// Convenience surface — a rounded card used app-wide.
///
/// Painted with the palette's card colour, a hairline border and a very soft
/// shadow for depth. Everything stays driven by the active palette.
class Surface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: p.hairline),
        boxShadow: [
          BoxShadow(
            color: p.shadow.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return box;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: box,
      ),
    );
  }
}