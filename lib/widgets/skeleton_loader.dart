import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Reusable shimmer container for smooth loading states.
class SkeletonShimmer extends StatefulWidget {
  final Widget child;

  const SkeletonShimmer({super.key, required this.child});

  @override
  State<SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    final isTesting =
        WidgetsBinding.instance.runtimeType.toString().toLowerCase().contains('test');

    if (!isTesting) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1400),
      )..repeat();
      _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
        CurvedAnimation(parent: _controller!, curve: Curves.easeInOutSine),
      );
    } else {
      _animation = const AlwaysStoppedAnimation<double>(0.5);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF1C2557) : const Color(0xFFE2E4EE);
    final highlightColor = isDark ? const Color(0xFF2E3B7D) : const Color(0xFFF3F4F9);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
              stops: const [0.0, 0.5, 1.0],
              transform: _SlidingGradientTransform(slidePercent: _animation.value),
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;

  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0.0, 0.0);
  }
}

/// A simple rectangular or rounded skeleton block.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double borderRadius;
  final ShapeBorder? shape;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 8.0,
    this.shape,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? const Color(0xFF1C2557) : const Color(0xFFE2E4EE);

    return Container(
      width: width,
      height: height,
      decoration: ShapeDecoration(
        color: color,
        shape: shape ??
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(borderRadius),
            ),
      ),
    );
  }
}

/// Full Home Screen skeleton matching exact layout to prevent any pop-in or layout shifts.
class HomeScreenSkeleton extends StatelessWidget {
  const HomeScreenSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

    return SkeletonShimmer(
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 140, height: 14, borderRadius: 6),
                        const SizedBox(height: 8),
                        SkeletonBox(width: 200, height: 24, borderRadius: 8),
                        const SizedBox(height: 6),
                        SkeletonBox(width: 160, height: 12, borderRadius: 6),
                      ],
                    ),
                  ),
                  const SkeletonBox(width: 44, height: 44, borderRadius: 14),
                  const SizedBox(width: 10),
                  const SkeletonBox(width: 46, height: 46, borderRadius: 15),
                ],
              ),
              const SizedBox(height: 20),

              // Hero Balance Card Placeholder
              const SkeletonBox(
                width: double.infinity,
                height: 190,
                borderRadius: 24,
              ),
              const SizedBox(height: 14),

              // Quick Actions Rail
              const SkeletonBox(
                width: double.infinity,
                height: 76,
                borderRadius: 20,
              ),
              const SizedBox(height: 16),

              // 3 Stat Cards
              Row(
                children: const [
                  Expanded(child: SkeletonBox(height: 106, borderRadius: 18)),
                  SizedBox(width: 12),
                  Expanded(child: SkeletonBox(height: 106, borderRadius: 18)),
                  SizedBox(width: 12),
                  Expanded(child: SkeletonBox(height: 106, borderRadius: 18)),
                ],
              ),
              const SizedBox(height: 26),

              // Services Title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  SkeletonBox(width: 100, height: 18, borderRadius: 6),
                  SkeletonBox(width: 60, height: 14, borderRadius: 6),
                ],
              ),
              const SizedBox(height: 12),

              // Services Grid (first 4)
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.25,
                children: const [
                  SkeletonBox(height: 138, borderRadius: 20),
                  SkeletonBox(height: 138, borderRadius: 20),
                  SkeletonBox(height: 138, borderRadius: 20),
                  SkeletonBox(height: 138, borderRadius: 20),
                ],
              ),
              const SizedBox(height: 26),

              // Latest updates
              const SkeletonBox(width: 120, height: 18, borderRadius: 6),
              const SizedBox(height: 12),
              const SkeletonBox(width: double.infinity, height: 96, borderRadius: 20),
              const SizedBox(height: 10),
              const SkeletonBox(width: double.infinity, height: 96, borderRadius: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton loader for the Notices Screen.
class NoticesScreenSkeleton extends StatelessWidget {
  const NoticesScreenSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              const SkeletonBox(width: 120, height: 26, borderRadius: 8),
              const SizedBox(height: 6),
              const SkeletonBox(width: 220, height: 14, borderRadius: 6),
              const SizedBox(height: 18),

              // Event strip skeleton
              const SkeletonBox(width: 140, height: 16, borderRadius: 6),
              const SizedBox(height: 8),
              const SkeletonBox(width: 260, height: 110, borderRadius: 18),
              const SizedBox(height: 20),

              // Category chips row
              Row(
                children: const [
                  SkeletonBox(width: 50, height: 34, borderRadius: 12),
                  SizedBox(width: 8),
                  SkeletonBox(width: 85, height: 34, borderRadius: 12),
                  SizedBox(width: 8),
                  SkeletonBox(width: 75, height: 34, borderRadius: 12),
                  SizedBox(width: 8),
                  SkeletonBox(width: 80, height: 34, borderRadius: 12),
                ],
              ),
              const SizedBox(height: 18),

              // Notice cards
              const SkeletonBox(width: double.infinity, height: 118, borderRadius: 20),
              const SizedBox(height: 12),
              const SkeletonBox(width: double.infinity, height: 118, borderRadius: 20),
              const SizedBox(height: 12),
              const SkeletonBox(width: double.infinity, height: 118, borderRadius: 20),
            ],
          ),
        ),
      ),
    );
  }
}
