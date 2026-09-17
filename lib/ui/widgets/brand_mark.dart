import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The MindRush mark: a bolt inside a ring split into the three category
/// colours.
///
/// One painter serves the launcher icon, the native splash and the animated
/// intro, so the thing on the home screen is literally the same drawing the
/// app opens with -- no separate asset to drift out of step.
///
/// Kept deliberately simple. A launcher icon is often seen at 48 logical
/// pixels, where detail turns to mud; a single bold silhouette survives that,
/// fine linework does not.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 96,
    this.sweep = 1.0,
    this.spread = 0.0,
    this.boltOpacity = 1.0,
    this.background = true,
  });

  final double size;

  /// How much of the tri-colour ring is drawn, 0 to 1.
  final double sweep;

  /// How far the three arcs sit out from the ring, as a fraction of the
  /// mark's side. 0 is the assembled ring.
  ///
  /// Each arc moves along the bearing of its own middle, so anything above 0
  /// has the three of them out in three directions -- which is how the intro
  /// brings them in. Kept in this painter rather than done with three
  /// stacked widgets so that the pieces flying in are the very same arcs the
  /// finished mark is made of, at the same radius and the same weight.
  final double spread;

  /// Fade for the bolt, so it can land after the ring.
  final double boltOpacity;

  /// The rounded tile behind the mark. Off for the in-app intro, which sits on
  /// the app background already.
  final bool background;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _BrandPainter(
      sweep: sweep.clamp(0.0, 1.0),
      spread: spread < 0 ? 0 : spread,
      boltOpacity: boltOpacity.clamp(0.0, 1.0),
      background: background,
    ),
  );
}

class _BrandPainter extends CustomPainter {
  const _BrandPainter({
    required this.sweep,
    required this.spread,
    required this.boltOpacity,
    required this.background,
  });

  final double sweep;
  final double spread;
  final double boltOpacity;
  final bool background;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);

    if (background) {
      // A deep indigo lift rather than flat black: a fully dark icon vanishes
      // against a dark wallpaper.
      final rect = Offset.zero & size;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(side * 0.22)),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1B1B33), Color(0xFF090910)],
          ).createShader(rect),
      );
    }

    // The ring: three arcs, one per category, in play order.
    final radius = side * 0.315;
    final stroke = side * 0.085;
    const gap = 0.16; // radians of space between arcs
    const arc = (2 * math.pi / 3) - gap;
    const start = -math.pi / 2 + gap / 2;

    const colours = [AppColors.math, AppColors.memory, AppColors.logic];
    final ring = Rect.fromCircle(center: center, radius: radius);
    for (var i = 0; i < colours.length; i++) {
      final from = start + i * (arc + gap);
      // Shifting the arc's bounding box is what moves the arc: it keeps its
      // radius and its angles, and only its centre travels.
      final mid = from + arc / 2;
      final away = spread == 0
          ? Offset.zero
          : Offset(math.cos(mid), math.sin(mid)) * (side * spread);
      canvas.drawArc(
        ring.shift(away),
        from,
        arc * sweep,
        false,
        Paint()
          ..color = colours[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    if (boltOpacity <= 0) return;

    // A bolt, drawn rather than borrowed from an icon font so it stays crisp
    // at 1024 and readable at 48.
    final h = side * 0.40;
    final w = side * 0.22;
    final path = Path()
      ..moveTo(center.dx + w * 0.30, center.dy - h * 0.50)
      ..lineTo(center.dx - w * 0.55, center.dy + h * 0.08)
      ..lineTo(center.dx - w * 0.02, center.dy + h * 0.08)
      ..lineTo(center.dx - w * 0.30, center.dy + h * 0.50)
      ..lineTo(center.dx + w * 0.55, center.dy - h * 0.10)
      ..lineTo(center.dx + w * 0.02, center.dy - h * 0.10)
      ..close();

    canvas.drawPath(
      path,
      Paint()..color = AppColors.text.withValues(alpha: boltOpacity),
    );
  }

  @override
  bool shouldRepaint(_BrandPainter old) =>
      old.sweep != sweep ||
      old.spread != spread ||
      old.boltOpacity != boltOpacity ||
      old.background != background;
}


/// The hero block: the mark, the name, and the line under it.
///
/// These numbers live here, in one place, because two screens draw the same
/// block and the whole point is that they draw it *identically*. The intro
/// holds this block at the end and the sign-in screen opens with it already
/// there, so the swap between them is invisible -- and it is only invisible
/// for as long as nobody nudges a font size on one side.
abstract final class BrandStack {
  /// The box the mark sits in. Wider than the ring on purpose: the intro
  /// starts its three arcs well outside it.
  static const double width = 300;
  static const double height = 190;

  /// How big the mark itself is drawn.
  static const double markSize = 128;

  /// The gap between the name and the line under it.
  static const double underWord = 10;

  static const double wordSize = 34;

  static const String tagline = 'SIXTY SECONDS. ONE WINNER.';
}

/// The name, growing into place under the mark.
///
/// No shader. The sheen this used to have was one more thing to compile on
/// the coldest frames of the app's life, and it was spending that budget on a
/// label that is only on screen for half a second.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.reveal = 1.0});

  /// 0 to 1. The sign-in screen passes 1: by the time it is on screen the
  /// name has already arrived, and arriving twice is what a jump looks like.
  final double reveal;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: reveal.clamp(0.0, 1.0),
    child: Transform.scale(
      scale: 0.92 + 0.08 * reveal.clamp(0.0, 1.0),
      child: const Text(
        'MindRush',
        style: TextStyle(
          fontSize: BrandStack.wordSize,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.6,
          color: AppColors.text,
        ),
      ),
    ),
  );
}

/// The light the mark sits in.
class BrandGlow extends CustomPainter {
  const BrandGlow(this.value);

  /// 0 for nothing, 1 for the resting warmth the intro settles on.
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    if (value <= 0) return;
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = 62 + 66 * value;
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.math.withValues(alpha: 0.16 * value),
            AppColors.memory.withValues(alpha: 0.06 * value),
            Colors.transparent,
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Rect.fromCircle(center: centre, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(BrandGlow old) => old.value != value;
}
