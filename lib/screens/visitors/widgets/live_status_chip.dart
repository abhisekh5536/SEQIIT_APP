import 'package:flutter/material.dart';

import '../../../services/visitors_service.dart';
import '../../../theme/app_theme.dart';

/// Small chip telling the guard whether the screen is actually receiving
/// updates.
///
/// Without it, "live" and "silently disconnected" look identical — which is
/// exactly the uncertainty that had guards refreshing on a loop. When the
/// socket drops this turns amber and offers a manual refresh.
class LiveStatusChip extends StatelessWidget {
  final LiveStatus status;
  final VoidCallback? onRefresh;

  const LiveStatusChip({
    super.key,
    required this.status,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

    final (Color color, String label, bool pulsing) = switch (status) {
      LiveStatus.live => (p.success, 'Live', true),
      LiveStatus.connecting => (p.textTertiary, 'Connecting', false),
      LiveStatus.degraded => (p.warning, 'Reconnecting', false),
      LiveStatus.idle => (p.textTertiary, 'Offline', false),
    };

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(color: color, pulsing: pulsing),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          if (status != LiveStatus.live && onRefresh != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.refresh_rounded, size: 13, color: color),
          ],
        ],
      ),
    );

    if (status == LiveStatus.live || onRefresh == null) return chip;
    return InkWell(
      onTap: onRefresh,
      borderRadius: BorderRadius.circular(20),
      child: chip,
    );
  }
}

class _Dot extends StatefulWidget {
  final Color color;
  final bool pulsing;

  const _Dot({required this.color, required this.pulsing});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Dot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.pulsing && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = widget.pulsing ? 0.45 + (_controller.value * 0.55) : 1.0;
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: t),
            shape: BoxShape.circle,
            boxShadow: widget.pulsing
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.4 * t),
                      blurRadius: 6,
                      spreadRadius: 1.5,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}
