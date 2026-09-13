import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Gives a button something to say back.
///
/// A press that produces nothing until the next screen arrives leaves a
/// half-second where the only honest reading is "it did not register", and
/// people press again. This squashes, springs past its size and tips a couple
/// of degrees each way -- so the press is acknowledged by the button itself,
/// on the frame it happened.
///
/// The real button stays the thing being pressed. [builder] hands it a
/// callback to use as its own `onPressed`, rather than this widget swallowing
/// the gesture -- which keeps the button's ripple, its disabled colours and
/// its hit testing exactly as Material intends them.
///
/// [onPressed] runs when the wiggle finishes, not when the finger lands.
///
/// Firing immediately looks better on paper -- nothing is ever held back --
/// and is worthless in practice: the button that starts a duel replaces the
/// whole screen on the same frame, so the animation plays on a page nobody is
/// looking at any more. A quarter of a second is not a wait when the button
/// is visibly doing something for the whole of it, and the haptic still lands
/// on the frame the finger does.
class Wiggle extends StatefulWidget {
  const Wiggle({
    super.key,
    required this.onPressed,
    required this.builder,
    this.haptic = true,
  });

  /// Null disables the wiggle along with the press, and is passed straight
  /// through to the builder so a disabled button looks disabled.
  final VoidCallback? onPressed;

  final Widget Function(BuildContext context, VoidCallback? press) builder;

  final bool haptic;

  static const Duration duration = Duration(milliseconds: 260);

  @override
  State<Wiggle> createState() => _WiggleState();
}

class _WiggleState extends State<Wiggle> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Wiggle.duration,
  );

  /// Down, past, and back. The overshoot is what makes it read as springy
  /// rather than as a button that briefly got smaller.
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.94,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 30,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.94,
        end: 1.035,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 34,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.035,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 36,
    ),
  ]).animate(_controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _press() {
    final act = widget.onPressed;
    // Already wiggling: a second tap would otherwise open the next screen
    // twice, which is exactly what an impatient double-press does.
    if (act == null || _controller.isAnimating) return;
    if (widget.haptic) HapticFeedback.mediumImpact();

    _controller
      ..reset()
      ..forward().whenComplete(() {
        if (mounted) act();
      });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      // Two decaying cycles of a wobble, tipped a couple of degrees. Any
      // more and it reads as a mistake rather than a flourish.
      final t = _controller.value;
      final tilt = math.sin(t * math.pi * 4) * 0.035 * (1 - t) * (1 - t);
      return Transform.rotate(
        angle: tilt,
        child: Transform.scale(scale: _scale.value, child: child),
      );
    },
    child: widget.builder(context, widget.onPressed == null ? null : _press),
  );
}
