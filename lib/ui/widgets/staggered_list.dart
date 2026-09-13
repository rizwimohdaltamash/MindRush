import 'package:flutter/material.dart';

/// A ListView whose children fade and rise into place one after another.
///
/// Used on the result screen, where the reveal is the point: seeing the score,
/// then the rating change, then how you were beaten, lands better in sequence
/// than all at once. Deliberately not used on tab screens -- an animation the
/// player triggers many times a session stops being a flourish and starts
/// being a wait.
class StaggeredList extends StatefulWidget {
  const StaggeredList({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.stagger = const Duration(milliseconds: 55),
    this.itemDuration = const Duration(milliseconds: 340),
  });

  final List<Widget> children;
  final EdgeInsets padding;

  /// Delay between consecutive children.
  final Duration stagger;

  /// How long one child takes to arrive.
  final Duration itemDuration;

  @override
  State<StaggeredList> createState() => _StaggeredListState();
}

class _StaggeredListState extends State<StaggeredList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Total run: the last child starts at (n-1) * stagger and takes
  /// itemDuration to finish.
  Duration get _total =>
      widget.stagger * (widget.children.length - 1) + widget.itemDuration;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _total)..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = _total.inMilliseconds;
    return ListView(
      padding: widget.padding,
      children: [
        for (final (index, child) in widget.children.indexed)
          _RevealSlot(
            controller: _controller,
            begin: (widget.stagger.inMilliseconds * index) / totalMs,
            end:
                (widget.stagger.inMilliseconds * index +
                    widget.itemDuration.inMilliseconds) /
                totalMs,
            child: child,
          ),
      ],
    );
  }
}

class _RevealSlot extends StatelessWidget {
  const _RevealSlot({
    required this.controller,
    required this.begin,
    required this.end,
    required this.child,
  });

  final AnimationController controller;
  final double begin;
  final double end;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(
        begin.clamp(0.0, 1.0),
        end.clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Opacity(
        opacity: animation.value,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - animation.value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
