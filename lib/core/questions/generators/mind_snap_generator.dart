import 'dart:math' as math;

import '../difficulty.dart';
import '../question.dart';

/// Mind Snap: a grid flashes, then the player repeats it.
///
/// The board steps up as the match runs -- 4x4, then 5x5, then 6x6 -- and the
/// pattern grows with it. Difficulty changes only how long the flash lasts,
/// which keeps every round worth the same points and leaves Mind Snap scores
/// comparable between a 900 player and a 1500 one.
abstract final class MindSnapGenerator {
  static PatternRound next(
    math.Random rng,
    Difficulty d, {
    required int index,
  }) {
    final gridSize = mindSnapGridFor(index);
    final lit = mindSnapCellsFor(index);

    // Difficulty sets the base exposure; bigger patterns get a little longer,
    // because reading twelve positions simply takes more than reading six.
    final base = switch (d) {
      Difficulty.easy => 2200,
      Difficulty.light => 1900,
      Difficulty.medium => 1700,
      Difficulty.hard => 1500,
      Difficulty.brutal => 1300,
    };
    final flashMs = base + (lit - 6) * 130;

    final cellCount = gridSize * gridSize;
    final chosen = <int>{};
    while (chosen.length < lit) {
      chosen.add(rng.nextInt(cellCount));
    }

    return PatternRound(
      gridSize: gridSize,
      litCells: chosen.toList()..sort(),
      flashMs: flashMs,
    );
  }
}
