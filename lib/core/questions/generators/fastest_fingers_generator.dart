import 'dart:math' as math;

import '../difficulty.dart';
import '../question.dart';

/// Fastest Fingers: pure reflex.
///
/// Every question must be answerable in well under a second -- the mode's
/// baseline is 850ms, and roughly 70 of these fit in a match. The challenge is
/// reaction speed, not arithmetic, so the prompt flips between "Larger" and
/// "Smaller" to stop the player answering on autopilot.
abstract final class FastestFingersGenerator {
  static ChoiceQuestion next(math.Random rng, Difficulty d) {
    final wantLarger = d.level < 3 ? true : rng.nextBool();

    final (
      String left,
      String right,
      int leftValue,
      int rightValue,
    ) = switch (d) {
      Difficulty.easy => _plainPair(rng, max: 99),
      Difficulty.light => _plainPair(rng, max: 999),
      Difficulty.medium => _plainPair(rng, max: 9999),
      Difficulty.hard => _sumPair(rng),
      Difficulty.brutal => _productPair(rng),
    };

    final leftWins = wantLarger
        ? leftValue > rightValue
        : leftValue < rightValue;
    return ChoiceQuestion(
      prompt: wantLarger ? 'Larger?' : 'Smaller?',
      options: [left, right],
      correctIndex: leftWins ? 0 : 1,
    );
  }

  static (String, String, int, int) _plainPair(
    math.Random rng, {
    required int max,
  }) {
    final a = rng.nextInt(max) + 1;
    var b = rng.nextInt(max) + 1;
    while (b == a) {
      b = rng.nextInt(max) + 1;
    }
    return ('$a', '$b', a, b);
  }

  static (String, String, int, int) _sumPair(math.Random rng) {
    (int, int) pair() => (rng.nextInt(9) + 1, rng.nextInt(9) + 1);
    var (a1, a2) = pair();
    var (b1, b2) = pair();
    while (a1 + a2 == b1 + b2) {
      (b1, b2) = pair();
    }
    return ('$a1+$a2', '$b1+$b2', a1 + a2, b1 + b2);
  }

  static (String, String, int, int) _productPair(math.Random rng) {
    (int, int) pair() => (rng.nextInt(8) + 2, rng.nextInt(8) + 2);
    var (a1, a2) = pair();
    var (b1, b2) = pair();
    while (a1 * a2 == b1 * b2) {
      (b1, b2) = pair();
    }
    return ('${a1}x$a2', '${b1}x$b2', a1 * a2, b1 * b2);
  }
}
