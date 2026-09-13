import 'package:flutter_test/flutter_test.dart';
import 'package:mind_rush/core/models/game_mode.dart';
import 'package:mind_rush/core/questions/difficulty.dart';
import 'package:mind_rush/core/questions/question.dart';
import 'package:mind_rush/core/questions/question_deck.dart';

/// Evaluates a generated arithmetic prompt so the tests check the maths, not
/// just the formatting. Operators run left to right, which matches how the
/// generator builds three-term prompts (product first).
int _evaluate(String prompt) {
  final tokens = prompt.replaceAll(' = ?', '').trim().split(' ');
  int apply(int l, String op, int r) => switch (op) {
    '+' => l + r,
    '-' => l - r,
    'x' => l * r,
    '/' => l ~/ r,
    _ => throw ArgumentError('unknown operator $op'),
  };
  var acc = apply(int.parse(tokens[0]), tokens[1], int.parse(tokens[2]));
  if (tokens.length == 5) {
    acc = apply(acc, tokens[3], int.parse(tokens[4]));
  }
  return acc;
}

/// Fastest Fingers options are bare numbers, sums, or products.
int _valueOf(String option) {
  if (option.contains('+')) {
    final p = option.split('+');
    return int.parse(p[0]) + int.parse(p[1]);
  }
  if (option.contains('x')) {
    final p = option.split('x');
    return int.parse(p[0]) * int.parse(p[1]);
  }
  return int.parse(option);
}

QuestionDeck _deck(GameMode mode, Difficulty d, {int seed = 12345}) =>
    QuestionDeck(seed: seed, mode: mode, difficulty: d);

void main() {
  group('determinism -- the property the share feature depends on', () {
    test('same seed and mode gives an identical sequence', () {
      for (final mode in GameMode.values) {
        final a = _deck(mode, Difficulty.medium);
        final b = _deck(mode, Difficulty.medium);
        for (var i = 0; i < 80; i++) {
          expect(
            a.at(i).signature,
            b.at(i).signature,
            reason: '${mode.label} diverged at question $i',
          );
        }
      }
    });

    test('different seeds give different questions', () {
      final a = _deck(GameMode.sprint, Difficulty.medium, seed: 1);
      final b = _deck(GameMode.sprint, Difficulty.medium, seed: 2);
      final same = [
        for (var i = 0; i < 40; i++)
          if (a.at(i).signature == b.at(i).signature) i,
      ];
      expect(same.length, lessThan(10));
    });

    test('a question never changes once drawn', () {
      final deck = _deck(GameMode.ability, Difficulty.hard);
      final first = deck.at(7).signature;
      deck.at(30);
      expect(deck.at(7).signature, first);
    });

    test('share code round-trips', () {
      final deck = _deck(GameMode.fastestFingers, Difficulty.medium, seed: 99);
      final restored = QuestionDeck.fromShareCode(
        deck.shareCode,
        rating: 1000,
      )!;
      expect(restored.mode, GameMode.fastestFingers);
      expect(restored.seed, 99);
      for (var i = 0; i < 30; i++) {
        expect(restored.at(i).signature, deck.at(i).signature);
      }
    });

    test('a malformed share code fails cleanly', () {
      expect(QuestionDeck.fromShareCode('nonsense', rating: 1000), isNull);
      expect(QuestionDeck.fromShareCode('sprint-abc', rating: 1000), isNull);
      expect(QuestionDeck.fromShareCode('bogus-12', rating: 1000), isNull);
    });
  });

  group('Sprint Duels', () {
    test('every prompt evaluates to its stated answer', () {
      for (final d in Difficulty.values) {
        final deck = _deck(GameMode.sprint, d);
        for (var i = 0; i < 200; i++) {
          final q = deck.at(i) as NumericQuestion;
          expect(
            _evaluate(q.prompt),
            q.answer,
            reason: '${d.name}: "${q.prompt}" should be ${q.answer}',
          );
        }
      }
    });

    test('answers are never negative -- the keypad has no minus key', () {
      for (final d in Difficulty.values) {
        final deck = _deck(GameMode.sprint, d);
        for (var i = 0; i < 200; i++) {
          expect(
            (deck.at(i) as NumericQuestion).answer,
            greaterThanOrEqualTo(0),
          );
        }
      }
    });

    test('brutal never emits a trivial division', () {
      final deck = _deck(GameMode.sprint, Difficulty.brutal);
      for (var i = 0; i < 400; i++) {
        final q = deck.at(i) as NumericQuestion;
        if (!q.prompt.contains('/')) continue;
        final parts = q.prompt.replaceAll(' = ?', '').split(' / ');
        expect(
          int.parse(parts[1]),
          greaterThanOrEqualTo(4),
          reason: '"${q.prompt}" is not a brutal-level divisor',
        );
        expect(
          q.answer,
          greaterThanOrEqualTo(6),
          reason: '"${q.prompt}" is not a brutal-level quotient',
        );
      }
    });

    test('difficulty raises the arithmetic load', () {
      double avgAnswer(Difficulty d) {
        final deck = _deck(GameMode.sprint, d);
        final vals = [
          for (var i = 0; i < 300; i++) (deck.at(i) as NumericQuestion).answer,
        ];
        return vals.reduce((a, b) => a + b) / vals.length;
      }

      expect(
        avgAnswer(Difficulty.brutal),
        greaterThan(avgAnswer(Difficulty.easy)),
      );
    });
  });

  group('Fastest Fingers', () {
    test('two options, and the marked answer is genuinely right', () {
      for (final d in Difficulty.values) {
        final deck = _deck(GameMode.fastestFingers, d);
        for (var i = 0; i < 200; i++) {
          final q = deck.at(i) as ChoiceQuestion;
          expect(q.options.length, 2);
          final chosen = _valueOf(q.options[q.correctIndex]);
          final other = _valueOf(q.options[1 - q.correctIndex]);
          if (q.prompt == 'Larger?') {
            expect(chosen, greaterThan(other));
          } else {
            expect(chosen, lessThan(other));
          }
        }
      }
    });

    test('harder levels mix in Smaller so it stays a reflex test', () {
      final deck = _deck(GameMode.fastestFingers, Difficulty.brutal);
      final prompts = {
        for (var i = 0; i < 100; i++) (deck.at(i) as ChoiceQuestion).prompt,
      };
      expect(prompts, containsAll(['Larger?', 'Smaller?']));
    });
  });

  group('Mind Snap', () {
    test('the board steps up: four 4x4, five 5x5, then 6x6', () {
      for (final d in Difficulty.values) {
        final deck = _deck(GameMode.mindSnap, d);
        for (var i = 0; i < 20; i++) {
          final r = deck.at(i) as PatternRound;
          expect(r.litCells.length, mindSnapCellsFor(i), reason: 'round $i');
        }
        // Four rounds on the small board, five on the middle one, then the
        // big one for the rest of the minute.
        for (final (round, grid, lit) in [
          (0, 4, 6),
          (3, 4, 6),
          (4, 5, 8),
          (8, 5, 8),
          (9, 6, 12),
          (30, 6, 12),
        ]) {
          final r = deck.at(round) as PatternRound;
          expect(r.gridSize, grid, reason: 'round $round board');
          expect(r.litCells.length, lit, reason: 'round $round pattern');
        }
      }
    });

    test('lit cells are in range and never repeat', () {
      for (final d in Difficulty.values) {
        final deck = _deck(GameMode.mindSnap, d);
        for (var i = 0; i < 60; i++) {
          final r = deck.at(i) as PatternRound;
          expect(r.litCells.toSet().length, r.litCells.length);
          expect(r.litCells.every((c) => c >= 0 && c < r.cellCount), isTrue);
        }
      }
    });

    test('the board grows with the pattern, keeping density sane', () {
      final deck = _deck(GameMode.mindSnap, Difficulty.medium);
      for (final i in [0, 6, 8, 15]) {
        final r = deck.at(i) as PatternRound;
        final density = r.litCells.length / r.cellCount;
        expect(
          density,
          lessThan(0.45),
          reason: 'a crowded board is a blur, not a memory test',
        );
        expect(density, greaterThan(0.2));
      }
    });

    test('a bigger pattern is shown for longer', () {
      final deck = _deck(GameMode.mindSnap, Difficulty.medium);
      final six = (deck.at(0) as PatternRound).flashMs;
      final twelve = (deck.at(8) as PatternRound).flashMs;
      expect(twelve, greaterThan(six));
    });

    test('difficulty shortens the flash at the same round size', () {
      final easy =
          _deck(GameMode.mindSnap, Difficulty.easy).at(0) as PatternRound;
      final hard =
          _deck(GameMode.mindSnap, Difficulty.brutal).at(0) as PatternRound;
      expect(hard.flashMs, lessThan(easy.flashMs));
      expect(hard.litCells.length, easy.litCells.length);
    });

    test('scores recall from the player taps', () {
      final r =
          _deck(GameMode.mindSnap, Difficulty.medium).at(0) as PatternRound;
      expect(r.correctlyRecalled(r.litCells.toSet()), kMindSnapCells);
      expect(r.correctlyRecalled({}), 0);
      expect(r.correctlyRecalled(r.litCells.take(4).toSet()), 4);
    });
  });

  group('Ability Duels', () {
    int gcd(int a, int b) => b == 0 ? a : gcd(b, a % b);

    /// Recomputes the answer from the prompt, so the tests check the maths
    /// rather than the wording. Sequences are left out -- their rule is not
    /// recoverable from the text.
    int? recompute(String prompt) {
      final numbers = RegExp(
        r'\d+',
      ).allMatches(prompt).map((m) => int.parse(m.group(0)!)).toList();

      if (prompt.startsWith('HCF of')) return gcd(numbers[0], numbers[1]);
      if (prompt.startsWith('LCM of')) {
        return numbers[0] ~/ gcd(numbers[0], numbers[1]) * numbers[1];
      }
      if (prompt.startsWith('Remainder of')) return numbers[0] % numbers[1];
      if (prompt.startsWith('Digit sum of')) {
        return numbers[0]
            .toString()
            .split('')
            .fold<int>(0, (sum, c) => sum + int.parse(c));
      }
      if (prompt.contains('% of')) return numbers[1] * numbers[0] ~/ 100;
      if (prompt.startsWith('How many factors')) {
        final n = numbers[0];
        var count = 0;
        for (var i = 1; i <= n; i++) {
          if (n % i == 0) count++;
        }
        return count;
      }
      return null;
    }

    test('every question is typed, never multiple choice', () {
      for (final d in Difficulty.values) {
        final deck = _deck(GameMode.ability, d);
        for (var i = 0; i < 200; i++) {
          expect(
            deck.at(i),
            isA<NumericQuestion>(),
            reason: 'options would let a player guess a quarter of a match',
          );
        }
      }
    });

    test('answers are non-negative whole numbers', () {
      for (final d in Difficulty.values) {
        final deck = _deck(GameMode.ability, d);
        for (var i = 0; i < 200; i++) {
          expect(
            (deck.at(i) as NumericQuestion).answer,
            greaterThanOrEqualTo(0),
          );
        }
      }
    });

    test('the maths is right wherever it can be recomputed', () {
      var checked = 0;
      for (final d in Difficulty.values) {
        final deck = _deck(GameMode.ability, d);
        for (var i = 0; i < 400; i++) {
          final q = deck.at(i) as NumericQuestion;
          final expected = recompute(q.prompt);
          if (expected == null) continue;
          checked++;
          expect(q.answer, expected, reason: '"${q.prompt}"');
        }
      }
      expect(checked, greaterThan(200), reason: 'the check must have run');
    });

    test('solve-for-x always has a whole-number solution', () {
      for (final d in Difficulty.values) {
        final deck = _deck(GameMode.ability, d);
        for (var i = 0; i < 300; i++) {
          final q = deck.at(i) as NumericQuestion;
          if (!q.prompt.contains('x = ?')) continue;
          expect(q.answer, greaterThan(0));
        }
      }
    });

    test('LCM and HCF both show up, and HCF is rarely a pointless 1', () {
      final deck = _deck(GameMode.ability, Difficulty.medium);
      final prompts = [
        for (var i = 0; i < 400; i++) (deck.at(i) as NumericQuestion),
      ];
      expect(prompts.any((q) => q.prompt.startsWith('LCM')), isTrue);

      final hcf = prompts.where((q) => q.prompt.startsWith('HCF')).toList();
      expect(hcf, isNotEmpty);
      final trivial = hcf.where((q) => q.answer == 1).length;
      expect(
        trivial / hcf.length,
        lessThan(0.2),
        reason: 'pairs are built from a shared factor for this reason',
      );
    });

    test('questions that answer themselves are filtered out', () {
      for (final d in Difficulty.values) {
        final deck = _deck(GameMode.ability, d);
        for (var i = 0; i < 400; i++) {
          final q = deck.at(i) as NumericQuestion;
          if (q.prompt.startsWith('Remainder')) {
            expect(
              q.answer,
              greaterThan(0),
              reason: 'a zero remainder asks nothing: "${q.prompt}"',
            );
          }
          if (q.prompt.startsWith('LCM')) {
            final n = RegExp(
              r'\d+',
            ).allMatches(q.prompt).map((m) => int.parse(m.group(0)!)).toList();
            expect(
              n[0] % n[1] == 0 || n[1] % n[0] == 0,
              isFalse,
              reason: 'the LCM is just the larger number: "${q.prompt}"',
            );
          }
        }
      }
    });

    test('no word questions remain', () {
      for (final d in Difficulty.values) {
        final deck = _deck(GameMode.ability, d);
        for (var i = 0; i < 120; i++) {
          final prompt = (deck.at(i) as NumericQuestion).prompt;
          expect(prompt.contains('belong'), isFalse);
          for (final word in ['Apple', 'Eagle', 'Guitar', 'Venus']) {
            expect(prompt.contains(word), isFalse);
          }
        }
      }
    });
  });

  group('difficulty from rating', () {
    test('maps the rating range onto the five bands', () {
      expect(Difficulty.fromRating(400), Difficulty.easy);
      expect(Difficulty.fromRating(1000), Difficulty.medium);
      expect(Difficulty.fromRating(2000), Difficulty.brutal);
    });

    test('is monotonic', () {
      var previous = 0;
      for (var r = 200; r <= 2200; r += 100) {
        final level = Difficulty.fromRating(r).level;
        expect(level, greaterThanOrEqualTo(previous));
        previous = level;
      }
    });
  });
}
