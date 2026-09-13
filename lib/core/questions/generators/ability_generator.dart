import 'dart:math' as math;

import '../difficulty.dart';
import '../question.dart';

/// Ability Duels: number reasoning, answered on the keypad.
///
/// Every question resolves to a single non-negative whole number, so the mode
/// uses the same keypad as Sprint rather than multiple choice. Options would
/// let a player guess their way through a quarter of the match; typing an
/// answer means they either worked it out or they did not.
abstract final class AbilityGenerator {
  static NumericQuestion next(
    math.Random rng,
    Difficulty d, {
    required int index,
  }) {
    final kinds = _kindsFor(d);
    return kinds[rng.nextInt(kinds.length)](rng, d);
  }

  static List<NumericQuestion Function(math.Random, Difficulty)> _kindsFor(
    Difficulty d,
  ) => switch (d) {
    Difficulty.easy => [_hcf, _lcm, _sequence, _solveForX],
    Difficulty.light => [_hcf, _lcm, _sequence, _solveForX, _remainder],
    Difficulty.medium => [
      _hcf,
      _lcm,
      _sequence,
      _solveForX,
      _remainder,
      _digitSum,
    ],
    Difficulty.hard => [
      _hcf,
      _lcm,
      _sequence,
      _solveForX,
      _remainder,
      _digitSum,
      _percentage,
      _factorCount,
    ],
    Difficulty.brutal => [
      _hcf,
      _lcm,
      _sequence,
      _solveForX,
      _remainder,
      _percentage,
      _factorCount,
    ],
  };

  // ------------------------------------------------------------- number pairs

  static int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

  /// Built from a shared factor rather than two random numbers, so the answer
  /// is rarely a trivial 1 and the question is actually worth asking.
  static (int, int) _pairWithFactor(math.Random rng, Difficulty d) {
    final factor = switch (d) {
      Difficulty.easy => rng.nextInt(4) + 2, // 2..5
      Difficulty.light => rng.nextInt(6) + 2, // 2..7
      Difficulty.medium => rng.nextInt(8) + 3, // 3..10
      Difficulty.hard => rng.nextInt(10) + 4, // 4..13
      Difficulty.brutal => rng.nextInt(13) + 6, // 6..18
    };
    final capA = switch (d) {
      Difficulty.easy || Difficulty.light => 6,
      Difficulty.medium => 9,
      _ => 12,
    };
    var a = rng.nextInt(capA) + 2;
    var b = rng.nextInt(capA) + 2;
    while (b == a) {
      b = rng.nextInt(capA) + 2;
    }
    return (factor * a, factor * b);
  }

  static NumericQuestion _hcf(math.Random rng, Difficulty d) {
    final (a, b) = _pairWithFactor(rng, d);
    return NumericQuestion(prompt: 'HCF of $a and $b = ?', answer: _gcd(a, b));
  }

  static NumericQuestion _lcm(math.Random rng, Difficulty d) {
    // Smaller operands than HCF: the answer grows fast and a 60-second match
    // is no place for six-digit mental arithmetic.
    final cap = switch (d) {
      Difficulty.easy => 9,
      Difficulty.light => 12,
      Difficulty.medium => 15,
      Difficulty.hard => 20,
      Difficulty.brutal => 25,
    };
    final a = rng.nextInt(cap - 1) + 2;
    var b = rng.nextInt(cap - 1) + 2;
    // Reject pairs where one divides the other: the LCM is then just the
    // larger number, and the question answers itself.
    var guard = 0;
    while ((b == a || a % b == 0 || b % a == 0) && guard++ < 40) {
      b = rng.nextInt(cap - 1) + 2;
    }
    return NumericQuestion(
      prompt: 'LCM of $a and $b = ?',
      answer: a ~/ _gcd(a, b) * b,
    );
  }

  // ----------------------------------------------------------------- patterns

  static NumericQuestion _sequence(math.Random rng, Difficulty d) {
    final rules = <(List<int>, int) Function()>[
      // Constant step.
      () {
        final start = rng.nextInt(9) + 1;
        final step = rng.nextInt(2 + d.level * 2) + 2;
        return (
          [for (var i = 0; i < 4; i++) start + step * i],
          start + step * 4,
        );
      },
      // Constant ratio.
      () {
        final start = rng.nextInt(4) + 1;
        final ratio = rng.nextInt(2) + 2;
        final terms = <int>[];
        var v = start;
        for (var i = 0; i < 4; i++) {
          terms.add(v);
          v *= ratio;
        }
        return (terms, v);
      },
      // Squares.
      () {
        final from = rng.nextInt(4) + 1;
        final n = from + 4;
        return ([for (var i = 0; i < 4; i++) (from + i) * (from + i)], n * n);
      },
    ];

    if (d.level >= 3) {
      // Each term is the sum of the previous two.
      rules.add(() {
        var a = rng.nextInt(5) + 1;
        var b = rng.nextInt(6) + 2;
        final terms = <int>[a, b];
        for (var i = 0; i < 2; i++) {
          final next = a + b;
          terms.add(next);
          a = b;
          b = next;
        }
        return (terms, a + b);
      });
    }
    if (d.level >= 4) {
      // Growing step: +2, +4, +6...
      rules.add(() {
        final start = rng.nextInt(6) + 1;
        final step = rng.nextInt(3) + 2;
        final terms = <int>[start];
        var v = start;
        for (var i = 1; i <= 3; i++) {
          v += step * i;
          terms.add(v);
        }
        return (terms, v + step * 4);
      });
    }

    final (terms, answer) = rules[rng.nextInt(rules.length)]();
    return NumericQuestion(
      prompt: '${terms.join(', ')}, ? = ?',
      answer: answer,
    );
  }

  // ------------------------------------------------------------------ algebra

  static NumericQuestion _solveForX(math.Random rng, Difficulty d) {
    final scale = 4 + d.level * 4;
    if (d.level <= 2 || rng.nextBool()) {
      final x = rng.nextInt(scale) + 2;
      final a = rng.nextInt(scale) + 1;
      return NumericQuestion(prompt: 'x + $a = ${x + a},  x = ?', answer: x);
    }
    // Two-step, kept to exact division so the answer stays a whole number.
    final x = rng.nextInt(scale) + 2;
    final a = rng.nextInt(6) + 2;
    final b = rng.nextInt(scale) + 1;
    return NumericQuestion(
      prompt: '${a}x + $b = ${a * x + b},  x = ?',
      answer: x,
    );
  }

  // ------------------------------------------------------------ number sense

  static NumericQuestion _remainder(math.Random rng, Difficulty d) {
    final divisor = rng.nextInt(4 + d.level * 2) + 3;
    var dividend = rng.nextInt(40 + d.level * 30) + divisor + 1;
    // A remainder of zero is a question with nothing in it, and the keypad
    // submits a single digit instantly -- so nudge past the exact multiples.
    var guard = 0;
    while (dividend % divisor == 0 && guard++ < 40) {
      dividend++;
    }
    return NumericQuestion(
      prompt: 'Remainder of $dividend / $divisor = ?',
      answer: dividend % divisor,
    );
  }

  static NumericQuestion _digitSum(math.Random rng, Difficulty d) {
    final value = rng.nextInt(400 + d.level * 400) + 100;
    var sum = 0;
    for (final ch in value.toString().split('')) {
      sum += int.parse(ch);
    }
    return NumericQuestion(prompt: 'Digit sum of $value = ?', answer: sum);
  }

  static NumericQuestion _percentage(math.Random rng, Difficulty d) {
    // Percentages chosen so the result is always whole.
    const percents = [10, 20, 25, 50, 75];
    final percent = percents[rng.nextInt(percents.length)];
    final step = 100 ~/ _gcd(percent, 100);
    final base = (rng.nextInt(6 + d.level * 3) + 1) * step;
    return NumericQuestion(
      prompt: '$percent% of $base = ?',
      answer: base * percent ~/ 100,
    );
  }

  static NumericQuestion _factorCount(math.Random rng, Difficulty d) {
    final value = rng.nextInt(40 + d.level * 15) + 12;
    var count = 0;
    for (var i = 1; i <= value; i++) {
      if (value % i == 0) count++;
    }
    return NumericQuestion(
      prompt: 'How many factors has $value?',
      answer: count,
    );
  }
}
