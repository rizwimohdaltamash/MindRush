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
    this.boltOpacity = 1.0,
    this.background = true,
  });

  final double size;

  /// How much of the tri-colour ring is drawn, 0 to 1. Animated on the intro.
  final double sweep;

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
      boltOpacity: boltOpacity.clamp(0.0, 1.0),
      background: background,
    ),
  );
}

class _BrandPainter extends CustomPainter {
  const _BrandPainter({
    required this.sweep,
    required this.boltOpacity,
    required this.background,
  });

  final double sweep;
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
    for (var i = 0; i < colours.length; i++) {
      final from = start + i * (arc + gap);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
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
      old.boltOpacity != boltOpacity ||
      old.background != background;
}
