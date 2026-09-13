import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_rush/core/bots/bot_engine.dart';
import 'package:mind_rush/core/bots/bot_profile.dart';
import 'package:mind_rush/core/bots/bot_tier.dart';
import 'package:mind_rush/core/match/match_engine.dart';
import 'package:mind_rush/core/match/match_result.dart';
import 'package:mind_rush/core/models/game_mode.dart';
import 'package:mind_rush/core/questions/difficulty.dart';
import 'package:mind_rush/core/questions/question.dart';
import 'package:mind_rush/core/questions/question_deck.dart';
import 'package:mind_rush/core/rating/rating_engine.dart';
import 'package:mind_rush/core/rating/streak.dart';

/// A bot run with hand-placed events, so score and timing assertions do not
/// depend on the simulator's randomness.
BotRun _fixedRun(List<(int, int)> atMsAndPoints) => BotRun([
  for (final (atMs, points) in atMsAndPoints)
    BotAnswerEvent(atMs: atMs, points: points),
]);

MatchEngine _engine({
  GameMode mode = GameMode.sprint,
  BotRun? opponentFeed,
  int playerRating = 1000,
  int seed = 7,
}) {
  return MatchEngine(
    deck: QuestionDeck(seed: seed, mode: mode, difficulty: Difficulty.medium),
    opponentFeed:
        opponentFeed ?? _fixedRun([(10000, 10), (20000, 10), (30000, 10)]),
    opponent: BotProfile(
      id: 'test',
      tier: BotTier.t5,
      name: 'Aryan',
      avatarId: 0,
    ),
    opponentName: 'Aryan',
    opponentAvatarId: 3,
    playerRating: playerRating,
  );
}

/// Answers the current Sprint question correctly.
void _answerCorrectly(MatchEngine e, int atMs) =>
    e.submitNumber((e.current as NumericQuestion).answer, atMs: atMs);

void main() {
  group('scoring during a match', () {
    test('a correct answer scores ten, a wrong one nothing', () {
      final e = _engine();
      _answerCorrectly(e, 2000);
      expect(e.playerScore, 10);

      e.submitNumber((e.current as NumericQuestion).answer + 1, atMs: 4000);
      expect(e.playerScore, 10);
      expect(e.answers.last.wasCorrect, isFalse);
    });

    test('the question advances after every answer, right or wrong', () {
      final e = _engine();
      final first = e.current.signature;
      e.submitNumber(-999, atMs: 1000);
      expect(e.current.signature, isNot(first));
      expect(e.questionIndex, 1);
    });

    test('per-question duration is measured from the previous answer', () {
      final e = _engine();
      _answerCorrectly(e, 3000);
      _answerCorrectly(e, 7500);
      expect(e.answers[0].durationMs, 3000);
      expect(e.answers[1].durationMs, 4500);
    });

    test('Mind Snap partial recall scores partial points', () {
      final e = _engine(mode: GameMode.mindSnap);
      final round = e.current as PatternRound;
      // Five of six cells: worth 7 by the agreed curve.
      e.submitPattern(round.litCells.take(5).toSet(), atMs: 5000);
      expect(e.playerScore, 7);
    });

    test('partial Mind Snap credit does not count towards accuracy', () {
      final e = _engine(mode: GameMode.mindSnap);
      final partial = e.current as PatternRound;
      e.submitPattern(partial.litCells.take(5).toSet(), atMs: 5000);
      final full = e.current as PatternRound;
      e.submitPattern(full.litCells.toSet(), atMs: 10000);

      final r = e.finish();
      expect(r.playerScore, 17);
      expect(r.answers[0].scoredPoints, isTrue);
      expect(
        r.answers[0].wasCorrect,
        isFalse,
        reason: 'four or five of six is not a correct answer',
      );
      expect(r.answers[1].wasCorrect, isTrue);
      expect(r.accuracy, 0.5);
    });
  });

  group('the clock', () {
    test('counts down from a full minute', () {
      final e = _engine();
      expect(e.remainingMs, kMatchDurationMs);
      e.advanceTo(20000);
      expect(e.remainingMs, 40000);
      expect(e.isOver, isFalse);
      e.advanceTo(kMatchDurationMs);
      expect(e.isOver, isTrue);
      expect(e.remainingMs, 0);
    });

    test('never runs backwards on a jittery ticker', () {
      final e = _engine();
      e.advanceTo(30000);
      e.advanceTo(25000);
      expect(e.elapsedMs, 30000);
    });

    test('an answer arriving after the buzzer does not count', () {
      final e = _engine();
      _answerCorrectly(e, 59000);
      expect(e.playerScore, 10);
      _answerCorrectly(e, 60500);
      expect(e.playerScore, 10, reason: 'late tap must be discarded');
      expect(e.answers.length, 1);
    });

    test('the opponent score ticks up as the match runs', () {
      final e = _engine(
        opponentFeed: _fixedRun([(10000, 10), (20000, 10), (30000, 10)]),
      );
      expect(e.opponentScore, 0);
      e.advanceTo(15000);
      expect(e.opponentScore, 10);
      e.advanceTo(35000);
      expect(e.opponentScore, 30);
    });
  });

  group('settling the match', () {
    test('rates the result and moves the bot the opposite way', () {
      final bot = BotProfile(
        id: 'test',
        tier: BotTier.t5,
        name: 'Aryan',
        avatarId: 0,
      );
      final e = MatchEngine(
        deck: QuestionDeck(
          seed: 1,
          mode: GameMode.sprint,
          difficulty: Difficulty.medium,
        ),
        opponentFeed: _fixedRun([(30000, 10)]),
        opponent: bot,
        opponentName: 'Meera',
        opponentAvatarId: 1,
        playerRating: 1000,
      );
      for (var i = 0; i < 14; i++) {
        _answerCorrectly(e, 2000 + i * 2000);
      }

      final before = bot.ratingIn(Category.math);
      final result = e.finish();

      expect(result.playerScore, 140);
      expect(result.opponentScore, 10);
      expect(result.outcome, MatchOutcome.win);
      expect(result.ratingDelta, RatingEngine.maxDelta);
      expect(result.ratingAfter, 1000 + RatingEngine.maxDelta);
      expect(
        bot.ratingIn(Category.math),
        before - RatingEngine.maxDelta,
        reason: 'zero-sum: the bot loses exactly what the player gains',
      );
    });

    test('is idempotent -- a match is never rated twice', () {
      final bot = BotProfile(
        id: 'test',
        tier: BotTier.t5,
        name: 'Aryan',
        avatarId: 0,
      );
      final e = MatchEngine(
        deck: QuestionDeck(
          seed: 1,
          mode: GameMode.sprint,
          difficulty: Difficulty.medium,
        ),
        opponentFeed: _fixedRun([(30000, 10)]),
        opponent: bot,
        opponentName: 'Meera',
        opponentAvatarId: 1,
        playerRating: 1000,
      );
      _answerCorrectly(e, 5000);

      final first = e.finish();
      final ratingAfterOnce = bot.ratingIn(Category.math);
      final second = e.finish();

      expect(identical(first, second), isTrue);
      expect(bot.ratingIn(Category.math), ratingAfterOnce);
    });

    test('carries the share code so the match can be re-challenged', () {
      final e = _engine(seed: 4242);
      expect(e.finish().shareCode, 'sprint-4242');
    });

    test('a level match with no answers either side is a draw', () {
      final e = _engine(opponentFeed: BotRun(const []));
      final result = e.finish();
      expect(result.playerScore, 0);
      expect(result.opponentScore, 0);
      expect(result.outcome, MatchOutcome.draw);
      expect(result.ratingDelta, 0);
    });
  });

  group('a duel called off mid-minute', () {
    test('keeps the score each side had actually reached', () {
      final e = _engine();
      _answerCorrectly(e, 2000);
      _answerCorrectly(e, 5000);
      e.advanceTo(25000); // two of the bot's three answers are in.

      // The other phone was the one that stopped, so this player has twenty
      // points on the board and every right to see them.
      final r = e.abandon(byPlayer: false);

      expect(r.playerScore, 20);
      expect(
        r.opponentScore,
        20,
        reason: 'a real number beats a pair of noughts: that minute happened',
      );
      expect(r.answers, hasLength(2));
    });

    test('moves nobody the rating, whichever phone gave up', () {
      for (final byPlayer in [true, false]) {
        final e = _engine();
        e.advanceTo(30000);

        final r = e.abandon(byPlayer: byPlayer);

        expect(r.ratingDelta, 0);
        expect(r.ratingAfter, r.ratingBefore);
        expect(r.abandoned, isTrue);
        expect(
          r.abandonedByYou,
          byPlayer,
          reason: 'the screen has to say who stopped answering',
        );
      }
    });
  });

  group('result screen data', () {
    test('reports accuracy and average answer time', () {
      final e = _engine();
      _answerCorrectly(e, 2000);
      e.submitNumber(-1, atMs: 6000);
      _answerCorrectly(e, 8000);
      final r = e.finish();

      expect(r.questionsAnswered, 3);
      expect(r.questionsCorrect, 2);
      expect(r.accuracy, closeTo(2 / 3, 0.001));
      // 8000 / 3 = 2666.67, rounded rather than truncated.
      expect(r.averageAnswerMs, 2667);
    });

    test('pairs per-question timings against the opponent', () {
      final e = _engine(opponentFeed: _fixedRun([(1000, 10), (5000, 10)]));
      _answerCorrectly(e, 3000); // slower than the bot's 1000ms
      _answerCorrectly(e, 4000); // faster than the bot's 4000ms? equal
      final r = e.finish();

      final points = r.speedByQuestion;
      expect(points.length, 2);
      expect(points[0].playerMs, 3000);
      expect(points[0].opponentMs, 1000);
      expect(points[0].playerWasSlower, isTrue);
      expect(r.questionsSlower, 1);
    });

    test('leaves a gap where only one side reached the question', () {
      final e = _engine(opponentFeed: _fixedRun([(1000, 10), (2000, 10)]));
      _answerCorrectly(e, 3000);
      final points = e.finish().speedByQuestion;

      expect(points.length, 2);
      expect(points[1].playerMs, isNull);
      expect(points[1].opponentMs, 1000);
      expect(points[1].playerWasSlower, isFalse);
    });
  });

  group('MatchFactory', () {
    test('builds a playable match from the roster', () {
      final factory = MatchFactory(
        roster: BotProfile.seedRoster(),
        random: Random(4),
      );
      final e = factory.create(mode: GameMode.ability, playerRating: 1400);

      expect(e.mode, GameMode.ability);
      expect(e.current, isA<NumericQuestion>());
      expect(e.deck.difficulty, Difficulty.fromRating(1400));
      expect(e.opponentName, isNotEmpty);
      expect(e.opponentFeed.totalScore, greaterThan(0));
    });

    test('a supplied seed reproduces the same questions', () {
      final a = MatchFactory(
        roster: BotProfile.seedRoster(),
        random: Random(1),
      ).create(mode: GameMode.sprint, playerRating: 1000, seed: 555);
      final b = MatchFactory(
        roster: BotProfile.seedRoster(),
        random: Random(2),
      ).create(mode: GameMode.sprint, playerRating: 1000, seed: 555);

      for (var i = 0; i < 20; i++) {
        expect(a.deck.at(i).signature, b.deck.at(i).signature);
      }
    });
  });

  group('daily streak', () {
    final monday = DateTime(2026, 9, 7, 20);

    test('a first match starts the streak at one', () {
      final s = StreakCalculator.register(const StreakState(), monday);
      expect(s.current, 1);
      expect(s.best, 1);
    });

    test('playing twice in a day changes nothing', () {
      var s = StreakCalculator.register(const StreakState(), monday);
      s = StreakCalculator.register(s, monday.add(const Duration(hours: 2)));
      expect(s.current, 1);
    });

    test('consecutive days extend it', () {
      var s = const StreakState();
      for (var day = 0; day < 5; day++) {
        s = StreakCalculator.register(s, monday.add(Duration(days: day)));
      }
      expect(s.current, 5);
      expect(s.best, 5);
    });

    test('a missed day starts over, but keeps the best', () {
      var s = const StreakState();
      for (var day = 0; day < 5; day++) {
        s = StreakCalculator.register(s, monday.add(Duration(days: day)));
      }
      s = StreakCalculator.register(s, monday.add(const Duration(days: 8)));
      expect(s.current, 1);
      expect(s.best, 5);
    });

    test('yesterday still shows, older has lapsed', () {
      final s = StreakCalculator.register(const StreakState(), monday);
      expect(s.displayed(monday), 1);
      expect(s.displayed(monday.add(const Duration(days: 1))), 1);
      expect(s.displayed(monday.add(const Duration(days: 2))), 0);
    });

    test('badges unlock at the published thresholds', () {
      expect(const StreakState(current: 0).badge, isNull);
      expect(const StreakState(current: 1).badge, 1);
      expect(const StreakState(current: 6).badge, 3);
      expect(const StreakState(current: 30).badge, 30);
      expect(const StreakState(current: 99).badge, 30);
    });
  });
}
