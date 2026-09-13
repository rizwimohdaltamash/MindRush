import 'dart:math' as math;

import '../difficulty.dart';
import '../question.dart';

/// Sprint Duels: arithmetic answered on a keypad.
///
/// Answers are always non-negative whole numbers -- the keypad has no minus
/// key, and a negative answer would be unenterable.
abstract final class SprintGenerator {
  static NumericQuestion next(math.Random rng, Difficulty d) => switch (d) {
    Difficulty.easy => _addSub(rng, max: 9),
    Difficulty.light => _mix(rng, [
      () => _addSub(rng, max: 40),
      () => _multiply(rng, aMax: 9, bMax: 9),
    ]),
    Difficulty.medium => _mix(rng, [
      () => _addSub(rng, max: 99),
      () => _multiply(rng, aMax: 12, bMax: 9),
      () => _divide(rng, divisorMax: 9, quotientMax: 9),
    ]),
    Difficulty.hard => _mix(rng, [
      () => _addSub(rng, max: 199),
      () => _multiply(rng, aMin: 6, aMax: 25, bMin: 3, bMax: 9),
      () => _divide(
        rng,
        divisorMin: 3,
        divisorMax: 12,
        quotientMin: 4,
        quotientMax: 12,
      ),
    ]),
    Difficulty.brutal => _mix(rng, [
      () => _threeTerm(rng),
      () => _multiply(rng, aMin: 12, aMax: 40, bMin: 3, bMax: 12),
      () => _divide(
        rng,
        divisorMin: 4,
        divisorMax: 15,
        quotientMin: 6,
        quotientMax: 15,
      ),
    ]),
  };

  static NumericQuestion _mix(
    math.Random rng,
    List<NumericQuestion Function()> options,
  ) => options[rng.nextInt(options.length)]();

  static NumericQuestion _addSub(math.Random rng, {required int max}) {
    final a = rng.nextInt(max) + 1;
    final b = rng.nextInt(max) + 1;
    if (rng.nextBool()) {
      return NumericQuestion(prompt: '$a + $b = ?', answer: a + b);
    }
    // Order the operands so the result never goes negative.
    final hi = math.max(a, b);
    final lo = math.min(a, b);
    return NumericQuestion(prompt: '$hi - $lo = ?', answer: hi - lo);
  }

  static NumericQuestion _multiply(
    math.Random rng, {
    int aMin = 2,
    required int aMax,
    int bMin = 2,
    required int bMax,
  }) {
    final a = rng.nextInt(aMax - aMin + 1) + aMin;
    final b = rng.nextInt(bMax - bMin + 1) + bMin;
    return NumericQuestion(prompt: '$a x $b = ?', answer: a * b);
  }

  /// Operand floors matter as much as ceilings: without a [divisorMin] and
  /// [quotientMin] the hardest difficulty happily emits "6 / 3 = ?".
  static NumericQuestion _divide(
    math.Random rng, {
    int divisorMin = 2,
    required int divisorMax,
    int quotientMin = 2,
    required int quotientMax,
  }) {
    // Built from the answer outwards so the division is always exact.
    final divisor = rng.nextInt(divisorMax - divisorMin + 1) + divisorMin;
    final quotient = rng.nextInt(quotientMax - quotientMin + 1) + quotientMin;
    return NumericQuestion(
      prompt: '${divisor * quotient} / $divisor = ?',
      answer: quotient,
    );
  }

  static NumericQuestion _threeTerm(math.Random rng) {
    final a = rng.nextInt(20) + 2;
    final b = rng.nextInt(9) + 2;
    final c = rng.nextInt(30) + 1;
    if (rng.nextBool()) {
      return NumericQuestion(prompt: '$a x $b + $c = ?', answer: a * b + c);
    }
    final product = a * b;
    final sub = math.min(c, product);
    return NumericQuestion(prompt: '$a x $b - $sub = ?', answer: product - sub);
  }
}
