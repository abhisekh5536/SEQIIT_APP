import 'package:flutter/material.dart';

/// Slides a newly arrived visitor card in from the top and grows its slot,
/// so the cards below are pushed down smoothly instead of jumping.
///
/// Give it a stable key per visitor: the animation runs once, when the
/// element is first mounted with [animate] true, and never replays on
/// later rebuilds of the same row.
class VisitorEntrance extends StatefulWidget {
  final bool animate;
  final Widget child;

  const VisitorEntrance({
    super.key,
    required this.animate,
    required this.child,
  });

  @override
  State<VisitorEntrance> createState() => _VisitorEntranceState();
}

class _VisitorEntranceState extends State<VisitorEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: widget.animate ? 0 : 1,
  );

  late final Animation<double> _size = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.6, curve: Curves.easeOutCubic),
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.2, 1, curve: Curves.easeOut),
  );

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -0.25),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.2, 1, curve: Curves.easeOutBack),
  ));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _size,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(position: _slide, child: widget.child),
      ),
    );
  }
}
