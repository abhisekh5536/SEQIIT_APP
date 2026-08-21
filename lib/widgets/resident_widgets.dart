import 'package:flutter/material.dart';

import '../models/society_models.dart';
import '../theme/app_theme.dart';

/// Initials avatar on the brand gradient, matching the app's avatar recipe
/// (primary → secondary, small card-colour border).
class ResidentAvatar extends StatelessWidget {
  final String initials;
  final double size;
  final bool circle;

  const ResidentAvatar({
    super.key,
    required this.initials,
    this.size = 40,
    this.circle = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.primary, p.secondary],
        ),
        borderRadius: BorderRadius.circular(circle ? size / 2 : size * 0.32),
        border: Border.all(color: p.card, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Colour mapping for a resident's role in the census.
Color roleColor(AppPaletteData p, ResidentRole role) {
  return switch (role) {
    ResidentRole.owner => p.primary,
    ResidentRole.tenant => p.secondary,
    ResidentRole.family => p.accent,
  };
}

/// Small pill showing Owner / Tenant / Family, tinted with the palette.
class RolePill extends StatelessWidget {
  final ResidentRole role;

  const RolePill({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final accent = roleColor(p, role);
    final onAccent = role == ResidentRole.family ? p.accentOn : accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        role.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: onAccent,
              fontSize: 10,
              letterSpacing: 0.3,
            ),
      ),
    );
  }
}

/// Thin gradient progress bar used for occupancy summaries.
class OccupancyBar extends StatelessWidget {
  final double fraction;
  final double height;

  const OccupancyBar({
    super.key,
    required this.fraction,
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final clamped = fraction.clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Container(
        height: height,
        color: p.cardMuted,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: clamped,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [p.heroStart, p.heroEnd],
              ),
            ),
          ),
        ),
      ),
    );
  }
}