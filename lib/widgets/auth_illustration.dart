import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Minimalist vector neighbourhood: residential towers, a small park,
/// trees and a morning sky. Drawn entirely with CustomPainter so it stays
/// crisp at every size and follows the app palette in light & dark mode.
class AuthIllustration extends StatelessWidget {
  final double aspectRatio;
  final BorderRadius borderRadius;

  /// When true the scene fills its parent box instead of keeping [aspectRatio].
  final bool stretch;

  const AuthIllustration({
    super.key,
    this.aspectRatio = 1.7,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.stretch = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scene = CustomPaint(painter: _NeighbourhoodPainter(p, dark));

    return ClipRRect(
      borderRadius: borderRadius,
      child: stretch ? scene : AspectRatio(aspectRatio: aspectRatio, child: scene),
    );
  }
}

class _NeighbourhoodPainter extends CustomPainter {
  final AppPaletteData p;
  final bool dark;

  _NeighbourhoodPainter(this.p, this.dark);

  // Logical canvas is 400 x 235 units.
  static const double _w = 400;
  static const double _h = 235;

  late final Color skyTop = dark ? const Color(0xFF161C3E) : const Color(0xFFEEF0FA);
  late final Color skyBottom = dark ? const Color(0xFF10152E) : const Color(0xFFE0E4F6);
  late final Color sun = dark ? const Color(0xFFE8B25E) : const Color(0xFFF2C879);
  late final Color cloud = dark ? const Color(0x14FFFFFF) : const Color(0xD9FFFFFF);
  late final Color backBuilding = dark ? const Color(0xFF262C55) : const Color(0xFFC7CCE9);
  late final Color towerA = dark ? const Color(0xFF453F85) : const Color(0xFF8B82CC);
  late final Color towerB = dark ? const Color(0xFF38336E) : const Color(0xFF6A61B5);
  late final Color towerC = dark ? const Color(0xFF55509B) : const Color(0xFF94ADD7);
  late final Color roof = dark ? const Color(0xFF241F4D) : const Color(0xFF4A4494);
  late final Color window = dark ? const Color(0x59B9AFF0) : const Color(0xF2F1F0FB);
  late final Color groundBack = dark ? const Color(0xFF1E5A47) : const Color(0xFF4E9678);
  late final Color groundFront = dark ? const Color(0xFF194A3A) : const Color(0xFF3F8066);
  late final Color trunk = dark ? const Color(0xFF14332A) : const Color(0xFF2E5F4B);
  late final Color canopyLight = dark ? const Color(0xFF3A8F6D) : const Color(0xFF5CB48D);
  late final Color canopyDeep = dark ? const Color(0xFF2E7A5B) : const Color(0xFF46A37B);
  late final Color bush = dark ? const Color(0xFF2A6B50) : const Color(0xFF57A983);
  late final Color path = dark ? const Color(0x14FFFFFF) : const Color(0xE6EFF1FB);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _w);

    _sky(canvas);
    _sun(canvas);
    _clouds(canvas, const Offset(84, 38), 1.0);
    _clouds(canvas, const Offset(292, 64), 0.72);
    _birds(canvas);
    _backBuildings(canvas);
    _tower(
      canvas,
      x: 36,
      width: 58,
      top: 78,
      floors: 4,
      cols: 3,
      body: towerA,
    );
    _tower(
      canvas,
      x: 104,
      width: 74,
      top: 50,
      floors: 6,
      cols: 3,
      body: towerB,
      antenna: true,
      door: true,
    );
    _tower(
      canvas,
      x: 188,
      width: 56,
      top: 92,
      floors: 4,
      cols: 3,
      body: towerA,
    );
    _tower(
      canvas,
      x: 254,
      width: 70,
      top: 64,
      floors: 5,
      cols: 3,
      body: towerC,
      waterTank: true,
      door: true,
    );
    _park(canvas);
  }

  void _sky(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, _w, _h);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [skyTop, skyBottom],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  void _sun(Canvas canvas) {
    final center = const Offset(330, 46);
    canvas.drawCircle(
      center,
      34,
      Paint()..color = sun.withValues(alpha: dark ? 0.10 : 0.28),
    );
    canvas.drawCircle(center, 20, Paint()..color = sun);
  }

  void _clouds(Canvas canvas, Offset c, double scale) {
    final paint = Paint()..color = cloud;
    final y = c.dy;
    canvas.drawCircle(Offset(c.dx, y), 11 * scale, paint);
    canvas.drawCircle(Offset(c.dx + 14 * scale, y - 5 * scale), 13 * scale, paint);
    canvas.drawCircle(Offset(c.dx + 30 * scale, y), 10 * scale, paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(c.dx - 10 * scale, y, 52 * scale, 10 * scale),
        Radius.circular(5 * scale),
      ),
      paint,
    );
  }

  void _birds(Canvas canvas) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = dark ? const Color(0x55EAE0CF) : const Color(0xB32A3050);
    canvas.drawArc(Rect.fromCenter(center: const Offset(262, 40), width: 16, height: 12),
        3.5, 2.4, false, paint);
    canvas.drawArc(Rect.fromCenter(center: const Offset(284, 30), width: 13, height: 10),
        3.5, 2.4, false, paint);
  }

  void _backBuildings(Canvas canvas) {
    final paint = Paint()..color = backBuilding;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(0, 128, 44, 62),
        topLeft: const Radius.circular(6),
      ),
      paint,
    );
    canvas.drawRect(const Rect.fromLTWH(160, 118, 34, 72), paint);
    canvas.drawRect(const Rect.fromLTWH(332, 124, 68, 66), paint);
    canvas.drawRect(const Rect.fromLTWH(350, 108, 18, 18), paint);
  }

  void _tower(
    Canvas canvas, {
    required double x,
    required double width,
    required double top,
    required int floors,
    required int cols,
    required Color body,
    bool antenna = false,
    bool waterTank = false,
    bool door = false,
  }) {
    const baseY = 190.0;
    final rect = Rect.fromLTWH(x, top, width, baseY - top);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        rect,
        topLeft: const Radius.circular(8),
        topRight: const Radius.circular(8),
      ),
      Paint()..color = body,
    );

    // Roof cap.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 4, top - 5, width + 8, 8),
        const Radius.circular(4),
      ),
      Paint()..color = roof,
    );

    if (antenna) {
      final cx = x + width / 2;
      canvas.drawLine(
        Offset(cx, top - 5),
        Offset(cx, top - 24),
        Paint()
          ..color = roof
          ..strokeWidth = 2.4,
      );
      canvas.drawCircle(Offset(cx, top - 26), 2.6, Paint()..color = roof);
    }

    if (waterTank) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 10, top - 17, 18, 12),
          const Radius.circular(3),
        ),
        Paint()..color = roof,
      );
    }

    // Windows grid.
    const marginX = 9.0;
    const marginY = 12.0;
    final cellW = (width - marginX * 2) / cols;
    final cellH = (baseY - top - marginY * 2 - (door ? 14 : 0)) / floors;
    final winPaint = Paint()..color = window;
    for (var r = 0; r < floors; r++) {
      for (var c = 0; c < cols; c++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              x + marginX + c * cellW + 2,
              top + marginY + r * cellH + 2,
              cellW - 5,
              cellH - 5,
            ),
            const Radius.circular(2.5),
          ),
          winPaint,
        );
      }
    }

    if (door) {
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x + width / 2 - 7, baseY - 15, 14, 15),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        Paint()..color = roof,
      );
    }
  }

  void _park(Canvas canvas) {
    canvas.drawRect(
      Rect.fromLTWH(0, 190, _w, 45),
      Paint()..color = groundBack,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 216, _w, 19),
      Paint()..color = groundFront,
    );

    // Winding path through the park.
    final pathPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round
      ..color = path;
    final walkway = Path()
      ..moveTo(150, 235)
      ..quadraticBezierTo(196, 214, 236, 192);
    canvas.drawPath(walkway, pathPaint);

    _tree(canvas, Offset(26, 222), 1.0);
    _tree(canvas, Offset(96, 226), 0.78);
    _tree(canvas, Offset(320, 224), 0.92);
    _tree(canvas, Offset(374, 228), 0.7);

    final bushPaint = Paint()..color = bush;
    for (final bx in [64.0, 130.0, 276.0, 344.0]) {
      canvas.drawCircle(Offset(bx, 218), 6.5, bushPaint);
      canvas.drawCircle(Offset(bx + 9, 220), 5, bushPaint);
    }
  }

  void _tree(Canvas canvas, Offset base, double scale) {
    final trunkPaint = Paint()..color = trunk;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(base.dx - 2 * scale, base.dy - 16 * scale, 4 * scale, 16 * scale),
        const Radius.circular(2),
      ),
      trunkPaint,
    );
    canvas.drawCircle(
      Offset(base.dx, base.dy - 24 * scale),
      11 * scale,
      Paint()..color = canopyDeep,
    );
    canvas.drawCircle(
      Offset(base.dx - 8 * scale, base.dy - 18 * scale),
      8 * scale,
      Paint()..color = canopyLight,
    );
    canvas.drawCircle(
      Offset(base.dx + 8 * scale, base.dy - 19 * scale),
      8.4 * scale,
      Paint()..color = canopyLight,
    );
  }

  @override
  bool shouldRepaint(covariant _NeighbourhoodPainter oldDelegate) =>
      oldDelegate.p != p || oldDelegate.dark != dark;
}
