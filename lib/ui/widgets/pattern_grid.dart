import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/questions/question.dart';
import '../theme.dart';

/// The Mind Snap board.
///
/// While [revealed] is true the lit cells glow and taps are ignored; once the
/// flash ends the board clears and the player reproduces it from memory.
class PatternGrid extends StatelessWidget {
  const PatternGrid({
    super.key,
    required this.round,
    required this.revealed,
    required this.tapped,
    required this.accent,
    this.onTap,
    this.vanish = 0,
  });

  final PatternRound round;
  final bool revealed;
  final Set<int> tapped;
  final Color accent;
  final void Function(int cell)? onTap;

  /// How far through clearing the answered board this is, 0 to 1.
  ///
  /// Only the filled cells go: they shrink into their own squares and leave
  /// the empty board standing, so what disappears is the answer rather than
  /// the grid. Driven from the duel screen so the next pattern can wait for
  /// it to finish instead of cutting over the top of it.
  final double vanish;

  /// How big a cell is allowed to get, and the space between two of them.
  ///
  /// A cap rather than a share of the screen. Left to fill the width, a
  /// four-by-four board draws cells the size of a matchbox and a six-by-six
  /// draws them half that -- so the same game feels like a different one
  /// depending on how many cells it happens to have. Fixing the cell instead
  /// means the *board* grows with the round while a cell always looks like a
  /// cell, which is what the eye is actually tracking.
  static const double maxCell = 52;

  /// Deliberately hairline. The gap is dead space -- a tap that lands in it
  /// does nothing -- so every pixel spent on it is a pixel taken off the two
  /// cells beside it, and off the margin for a thumb that is slightly out.
  /// The rounded corners already separate one square from the next; the gap
  /// only has to stop them touching.
  static const double gap = 4;

  /// What the board comes to at [across] cells wide, given [available] room.
  /// Public so a test can state the size rather than measure a screenshot.
  static double sideFor(int across, double available) =>
      cellFor(across, available) * across + gap * (across - 1);

  static double cellFor(int across, double available) =>
      math.min(maxCell, (available - gap * (across - 1)) / across);

  @override
  Widget build(BuildContext context) {
    // No caption here: the state is announced once, below the grid, next to
    // the tap counter. Saying it twice on one screen is noise.
    return LayoutBuilder(
      builder: (context, constraints) {
        final across = round.gridSize;
        final cell = cellFor(across, constraints.maxWidth);
        final side = sideFor(across, constraints.maxWidth);

        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: GridView.count(
              crossAxisCount: across,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: gap,
              crossAxisSpacing: gap,
              children: [
                for (var index = 0; index < round.cellCount; index++)
                  _Cell(
                    lit: revealed && round.litCells.contains(index),
                    picked: !revealed && tapped.contains(index),
                    // A tap on a cell that was never lit turns red on the
                    // spot. Showing every tap in the same colour hid the one
                    // piece of information the player actually wants back.
                    wrong:
                        !revealed &&
                        tapped.contains(index) &&
                        !round.litCells.contains(index),
                    accent: accent,
                    // Scaled with the cell rather than fixed: the same corner
                    // on a smaller square reads as a sharper one.
                    radius: cell * 0.22,
                    // Staggered across the board, so it clears like a wave
                    // rather than a switch being thrown.
                    gone: _goneBy(index, round.cellCount),
                    onTap: onTap == null ? null : () => onTap!(index),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// How far cell [index] of [count] has vanished, given [vanish].
  ///
  /// Each cell waits a fraction of the run before it starts, the later ones
  /// waiting longest, and every one of them is gone by the end.
  double _goneBy(int index, int count) {
    if (vanish <= 0) return 0;
    const spread = 0.4;
    final start = count <= 1 ? 0.0 : (index / (count - 1)) * spread;
    final local = ((vanish - start) / (1 - spread)).clamp(0.0, 1.0);
    return Curves.easeInCubic.transform(local);
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.lit,
    required this.picked,
    required this.wrong,
    required this.accent,
    required this.radius,
    required this.gone,
    this.onTap,
  });

  final bool lit;
  final bool picked;
  final bool wrong;
  final Color accent;
  final double radius;

  /// 0 while the cell is on the board, 1 once it has shrunk away.
  final double gone;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final active = lit || picked;
    final colour = wrong ? AppColors.loss : accent;

    // The empty square stays put underneath. Only what was filled in leaves,
    // which is why the board does not appear to fall apart between rounds.
    final leaving = active ? 1 - gone : 1.0;

    final square = AnimatedScale(
      scale: active ? 1.0 : 0.92,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutBack,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          color: active
              ? colour.withValues(alpha: lit ? 0.9 : 0.55)
              : AppColors.surfaceHigh,
          border: Border.all(color: active ? colour : AppColors.border),
        ),
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The board itself, always drawn, so a vanishing cell shrinks into
          // an empty square rather than into a hole.
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              color: AppColors.surfaceHigh,
              border: Border.all(color: AppColors.border),
            ),
          ),
          if (leaving > 0)
            Transform.scale(scale: leaving, child: square)
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}
