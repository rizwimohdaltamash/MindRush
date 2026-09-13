import 'dart:math' as math;

import '../models/game_mode.dart';
import 'difficulty.dart';
import 'generators/ability_generator.dart';
import 'generators/fastest_fingers_generator.dart';
import 'generators/mind_snap_generator.dart';
import 'generators/sprint_generator.dart';
import 'question.dart';

/// The deterministic source of questions for one match.
///
/// A deck is fully described by (seed, mode, difficulty): the same three
/// values always produce the same questions in the same order. That is what
/// makes the share-a-challenge feature possible -- a link carrying the seed
/// lets a friend play the exact match you played, so the two scores are
/// genuinely comparable.
///
/// Questions are produced lazily and cached, because a match is time-limited
/// rather than question-limited: a Fastest Fingers player might get through
/// 90 of them, a Sprint player 23.
class QuestionDeck {
  QuestionDeck({
    required this.seed,
    required this.mode,
    required this.difficulty,
  }) : _rng = math.Random(seed);

  /// Builds the deck a player of [rating] should face in [mode].
  factory QuestionDeck.forRating({
    required int seed,
    required GameMode mode,
    required int rating,
  }) => QuestionDeck(
    seed: seed,
    mode: mode,
    difficulty: Difficulty.fromRating(rating),
  );

  final int seed;
  final GameMode mode;
  final Difficulty difficulty;

  final math.Random _rng;
  final List<Question> _drawn = [];

  /// The question at [index], generating it if the match has not reached it
  /// yet. Always the same value for the same index.
  Question at(int index) {
    RangeError.checkNotNegative(index, 'index');
    while (_drawn.length <= index) {
      _drawn.add(_generate(_drawn.length));
    }
    return _drawn[index];
  }

  /// Questions produced so far this match.
  int get drawnCount => _drawn.length;

  Question _generate(int index) => switch (mode) {
    GameMode.sprint => SprintGenerator.next(_rng, difficulty),
    GameMode.fastestFingers => FastestFingersGenerator.next(_rng, difficulty),
    GameMode.mindSnap => MindSnapGenerator.next(_rng, difficulty, index: index),
    GameMode.ability => AbilityGenerator.next(_rng, difficulty, index: index),
  };

  /// A fresh seed for an ordinary match.
  static int newSeed([math.Random? rng]) =>
      (rng ?? math.Random()).nextInt(0x7FFFFFFF);

  /// Compact form for a shared challenge link, e.g. `sprint-1842391`.
  String get shareCode => '${mode.name}-$seed';

  /// Parses a [shareCode] back into a deck for [rating]. Returns null if the
  /// code is malformed, so a mistyped link fails cleanly.
  static QuestionDeck? fromShareCode(String code, {required int rating}) {
    final parts = code.trim().split('-');
    if (parts.length != 2) return null;
    final mode = GameMode.values.where((m) => m.name == parts[0]).firstOrNull;
    final seed = int.tryParse(parts[1]);
    if (mode == null || seed == null || seed < 0) return null;
    return QuestionDeck.forRating(seed: seed, mode: mode, rating: rating);
  }
}
