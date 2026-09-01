import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Gradient shell shared by every dark hero card in the home carousel.
///
/// Keeps the brand treatment (diagonal gradient, 24px radius, a soft glow in
/// one corner, a thin glass highlight along the top edge and a faint ring in
/// the opposite corner) in one place so all gradient slides feel like they
/// belong to the same family — while each card's own layout keeps it distinct.
class HeroCardShell extends StatelessWidget {
  final Widget child;
  final LinearGradient? gradient;
  final Color? accent;
  final EdgeInsetsGeometry padding;

  const HeroCardShell({
    super.key,
    required this.child,
    this.gradient,
    this.accent,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 18),
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

    final g =
        gradient ??
        LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.55, 1.0],
          colors: [p.heroStart, p.heroStart.withValues(alpha: 0.92), p.heroEnd],
        );
    final glow = accent ?? p.accent;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: g,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          // Deep neutral drop + a tinted ambient glow in the card's own hue —
          // the card reads as lit from within rather than pasted on.
          BoxShadow(
            color: p.shadow.withValues(alpha: 0.16),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: glow.withValues(alpha: 0.20),
            blurRadius: 36,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      // Glass edge: a hairline of white light tracing the rounded border.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -70,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    glow.withValues(alpha: 0.34),
                    glow.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -46,
            child: Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                  width: 16,
                ),
              ),
            ),
          ),
          // Small counter-ring, top-left — balances the big glow without
          // competing with the content.
          Positioned(
            top: -30,
            left: -34,
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 10,
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 1.4,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.55),
                    Colors.white.withValues(alpha: 0.04),
                  ],
                ),
              ),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// Light "paper" shell for the deck so the carousel alternates gradient cards
/// with clean white cards — the same radius and padding family, a different
/// material.
class HeroPaperShell extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const HeroPaperShell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 18),
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: p.hairline),
        boxShadow: [
          BoxShadow(
            color: p.shadow.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final TextStyle? style;

  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: (style ?? Theme.of(context).textTheme.labelMedium)?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Primary action on a dark/gradient card (white button, brand foreground).
class _GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const _GradientButton({required this.label, this.onPressed, this.icon});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

    final btn = ElevatedButton.icon(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: p.heroStart,
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        elevation: 4,
        shadowColor: p.shadow.withValues(alpha: 0.35),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
      icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 18),
      label: Text(label),
    );

    return SizedBox(height: 46, child: btn);
  }
}

/// Ghost (text) action, white on dark cards.
class _GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _GhostButton({required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      child: Text(label),
    );
  }
}

/// A crisp dashed divider, used as the perforation on ticket-style cards.
class _DashedDivider extends StatelessWidget {
  final Color color;

  const _DashedDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = (constraints.maxWidth / 9).floor();
        return Row(
          children: [
            for (var i = 0; i < count; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.5),
                  child: Container(
                    height: 1.6,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Small pseudo-QR glyph (three finder squares + deterministic modules) so a
/// gate-pass card reads like a real pass without shipping an asset.
class _QrGlyph extends StatelessWidget {
  final Color color;
  final int seed;

  const _QrGlyph({required this.color, required this.seed});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(44, 44),
      painter: _QrPainter(color: color, seed: seed),
    );
  }
}

class _QrPainter extends CustomPainter {
  final Color color;
  final int seed;

  _QrPainter({required this.color, required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    const n = 9;
    final cell = size.width / n;
    final paint = Paint()..color = color;

    void finder(int x, int y) {
      final outer = Rect.fromLTWH(x * cell, y * cell, cell * 3, cell * 3);
      final inner = Rect.fromLTWH(x * cell + cell, y * cell + cell, cell, cell);
      final path = Path()
        ..fillType = PathFillType.evenOdd
        ..addRRect(RRect.fromRectAndRadius(outer, Radius.circular(cell * 0.5)))
        ..addRRect(
          RRect.fromRectAndRadius(inner, Radius.circular(cell * 0.25)),
        );
      canvas.drawPath(path, paint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(inner, Radius.circular(cell * 0.25)),
        paint,
      );
    }

    final rnd = Random(seed);
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        final inFinder =
            (i < 3 && j < 3) || (i < 3 && j > n - 4) || (i > n - 4 && j < 3);
        if (inFinder) continue;
        if (rnd.nextDouble() < 0.42) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                j * cell + cell * 0.2,
                i * cell + cell * 0.2,
                cell * 0.6,
                cell * 0.6,
              ),
              Radius.circular(cell * 0.2),
            ),
            paint,
          );
        }
      }
    }

    finder(0, 0);
    finder(n - 3, 0);
    finder(0, n - 3);
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.seed != seed;
}

/// Gate-pass slide: a light ticket with a big arrival time, a perforated edge
/// and a QR-style block on the right. Reads as a physical pass, not a banner.
class HeroTicketCard extends StatelessWidget {
  final String guestName;
  final String time;
  final String period; // e.g. 'PM'
  final String dayLabel;
  final String location;
  final String passNumber;
  final VoidCallback onShow;
  final VoidCallback? onDetails;

  const HeroTicketCard({
    super.key,
    required this.guestName,
    required this.time,
    required this.period,
    required this.dayLabel,
    required this.location,
    required this.passNumber,
    required this.onShow,
    this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return HeroPaperShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'GATE PASS',
                style: textTheme.labelSmall?.copyWith(
                  color: p.textTertiary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
              const Spacer(),
              _Pill(
                label: dayLabel.toUpperCase(),
                background: p.secondary.withValues(alpha: 0.16),
                foreground: p.secondary,
                style: textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: time,
                        style: textTheme.headlineLarge?.copyWith(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      TextSpan(
                        text: ' $period',
                        style: textTheme.titleMedium?.copyWith(
                          color: p.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 12),
              // Soft tinted halo behind the QR so it reads as the scannable
              // heart of the pass, not a sticker.
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: p.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _QrGlyph(color: p.primary, seed: passNumber.hashCode),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            guestName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleMedium?.copyWith(
              color: p.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          // Perforation: dashed tear-line with punched side notches that bite
          // in from the card edges — the detail that sells "physical ticket".
          SizedBox(
            height: 22,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _DashedDivider(color: p.hairline),
                ),
                Positioned(
                  left: -31,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: p.canvas,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  right: -31,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: p.canvas,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: p.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Pass #$passNumber',
                      style: textTheme.labelSmall?.copyWith(
                        color: p.textTertiary,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onShow,
                style: TextButton.styleFrom(
                  foregroundColor: p.primary,
                  minimumSize: const Size(0, 44),
                  backgroundColor: p.primary.withValues(alpha: 0.10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: Text('Show pass'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Booking slide: a calendar-invite card with a big date block on the left
/// and event details on the right.
class HeroBookingCard extends StatelessWidget {
  final String dateDay;
  final String dateMonth;
  final String eyebrow;
  final String title;
  final String timeRange;
  final String detail;
  final VoidCallback onManage;
  final VoidCallback? onRules;

  const HeroBookingCard({
    super.key,
    required this.dateDay,
    required this.dateMonth,
    required this.eyebrow,
    required this.title,
    required this.timeRange,
    required this.detail,
    required this.onManage,
    this.onRules,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return HeroCardShell(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [p.heroStart, p.secondary],
      ),
      accent: p.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Calendar page: binder rings along the top, date below.
              Container(
                width: 58,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.17),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: 8,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (var i = 0; i < 3; i++)
                            Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.75),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            dateDay,
                            style: textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateMonth.toUpperCase(),
                            style: textTheme.labelSmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 13,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            timeRange,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Icon(
                Icons.celebration_rounded,
                size: 15,
                color: Colors.white.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _GradientButton(
                  label: 'Manage booking',
                  icon: Icons.event_available_rounded,
                  onPressed: onManage,
                ),
              ),
              if (onRules != null) ...[
                const SizedBox(width: 12),
                _GhostButton(label: 'Rules', onPressed: onRules),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Small horizontal status stepper (three nodes with connectors) used by the
/// request slide.
class _StatusStepper extends StatelessWidget {
  final List<String> steps;
  final int current;
  final Color activeColor;
  final Color idleColor;

  const _StatusStepper({
    required this.steps,
    required this.current,
    required this.activeColor,
    required this.idleColor,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 5, left: 3, right: 3),
                child: Container(
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: i <= current
                        ? activeColor.withValues(alpha: 0.65)
                        : idleColor.withValues(alpha: 0.30),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i <= current ? activeColor : Colors.transparent,
                  border: Border.all(
                    color: i <= current ? activeColor : idleColor,
                    width: 2,
                  ),
                  boxShadow: i == current
                      ? [
                          BoxShadow(
                            color: activeColor.withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                steps[i],
                style: textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: i <= current ? activeColor : idleColor,
                  fontWeight: i == current ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Request / approval slide: a light card with a status stepper, assignee and
/// ETA, and a primary action pinned to the bottom.
class HeroStatusCard extends StatelessWidget {
  final String pill;
  final String eyebrow;
  final String title;
  final String detail;
  final List<String> steps;
  final int current;
  final String actionLabel;
  final VoidCallback onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final Color? accent;

  const HeroStatusCard({
    super.key,
    required this.pill,
    required this.eyebrow,
    required this.title,
    required this.detail,
    required this.steps,
    required this.current,
    required this.actionLabel,
    required this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    final accent = this.accent ?? p.warning;

    return HeroPaperShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Pill(
                label: pill,
                background: accent.withValues(alpha: 0.13),
                foreground: accent,
                style: textTheme.labelSmall,
              ),
              const Spacer(),
              _Pill(
                label: steps[current],
                background: accent.withValues(alpha: 0.13),
                foreground: accent,
                style: textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            eyebrow,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: p.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleLarge?.copyWith(
              color: p.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          _StatusStepper(
            steps: steps,
            current: current,
            activeColor: accent,
            idleColor: p.textTertiary,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.person_outline_rounded,
                size: 14,
                color: p.textSecondary,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    onPressed: onAction,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 46),
                    ),
                    child: Text(actionLabel),
                  ),
                ),
              ),
              if (secondaryActionLabel != null) ...[
                const SizedBox(width: 12),
                TextButton(
                  onPressed: onSecondaryAction,
                  style: TextButton.styleFrom(
                    foregroundColor: p.textSecondary,
                    minimumSize: const Size(0, 46),
                  ),
                  child: Text(secondaryActionLabel!),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Society notice slide: a gradient news card — category tag, headline,
/// snippet and a read action.
class HeroNoticeCard extends StatelessWidget {
  final String category;
  final String eyebrow;
  final String title;
  final String snippet;
  final String meta;
  final VoidCallback onRead;

  /// Whether to show the pinned marker. Only set it for notices that are
  /// actually pinned — a permanent pin icon reads as decoration, not signal.
  final bool pinned;

  const HeroNoticeCard({
    super.key,
    required this.category,
    required this.eyebrow,
    required this.title,
    required this.snippet,
    required this.meta,
    required this.onRead,
    this.pinned = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return HeroCardShell(
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [p.secondary, p.heroStart],
      ),
      accent: p.mint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Pill(
                label: category,
                background: Colors.white.withValues(alpha: 0.18),
                foreground: Colors.white,
                style: textTheme.labelSmall,
              ),
              const Spacer(),
              if (pinned)
                Icon(
                  Icons.push_pin_rounded,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            eyebrow.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.75),
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            snippet,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.8),
              height: 1.4,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 13,
                color: Colors.white.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 5),
              Text(
                meta,
                style: textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onRead,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 40),
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('Read'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Horizontally swipeable stack of full-width hero cards with a dot
/// indicator. Pages recede slightly (scale + fade) while swiping so the
/// deck reads as one object rather than separate banners.
class HeroCarousel extends StatefulWidget {
  final List<Widget> slides;
  final double height;

  const HeroCarousel({super.key, required this.slides, this.height = 264});

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  late final PageController _controller;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

    return Column(
      children: [
        SizedBox(
          height: widget.height,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.slides.length,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (index) {
              setState(() => _page = index);
              HapticFeedback.lightImpact();
            },
            itemBuilder: (context, index) {
              return AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final page =
                      _controller.hasClients &&
                          _controller.position.haveDimensions
                      ? _controller.page ?? _page.toDouble()
                      : _page.toDouble();
                  final delta = (page - index).clamp(-1.0, 1.0);
                  return Transform.scale(
                    scale: 1 - 0.045 * delta.abs(),
                    child: Opacity(
                      opacity: 1 - 0.28 * delta.abs(),
                      child: child,
                    ),
                  );
                },
                child: widget.slides[index],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.slides.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _page ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _page
                      ? p.primary
                      : p.textTertiary.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: i == _page
                      ? [
                          BoxShadow(
                            color: p.primary.withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
