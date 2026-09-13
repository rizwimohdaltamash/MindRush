import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_rush/core/bots/bot_engine.dart';
import 'package:mind_rush/core/bots/bot_profile.dart';
import 'package:mind_rush/core/bots/bot_tier.dart';
import 'package:mind_rush/core/bots/opponent_picker.dart';
import 'package:mind_rush/core/models/game_mode.dart';
import 'package:mind_rush/core/rating/rating_engine.dart';

double _mean(Iterable<num> xs) =>
    xs.fold<double>(0, (a, b) => a + b) / xs.length;

void main() {
  group('mode pacing', () {
    test('each mode produces a sane question count', () {
      final rng = math.Random(1);
      int avgAnswered(GameMode m) => _mean([
        for (var i = 0; i < 300; i++)
          BotEngine.simulate(m, BotTier.t4, rng).answered,
      ]).round();

      // Fastest Fingers must be a flurry; Sprint a considered pace.
      expect(avgAnswered(GameMode.fastestFingers), greaterThan(50));
      expect(avgAnswered(GameMode.sprint), inInclusiveRange(15, 30));
      expect(avgAnswered(GameMode.mindSnap), inInclusiveRange(8, 20));
    });

    test('speed factor scales per mode, so one ladder fits all', () {
      final rng = math.Random(2);
      for (final mode in GameMode.values) {
        final slow = _mean([
          for (var i = 0; i < 200; i++)
            BotEngine.simulate(mode, BotTier.t1, rng).totalScore,
        ]);
        final fast = _mean([
          for (var i = 0; i < 200; i++)
            BotEngine.simulate(mode, BotTier.t10, rng).totalScore,
        ]);
        expect(
          fast,
          greaterThan(slow),
          reason: '${mode.label}: T10 must outscore T1',
        );
      }
    });
  });

  group('the ladder is ordered', () {
    test('average score rises monotonically from T1 to T10', () {
      final rng = math.Random(3);
      var previous = -1.0;
      for (final tier in BotTier.values) {
        final avg = _mean([
          for (var i = 0; i < 400; i++)
            BotEngine.simulate(GameMode.sprint, tier, rng).totalScore,
        ]);
        expect(
          avg,
          greaterThan(previous),
          reason: '${tier.codename} regressed',
        );
        previous = avg;
      }
    });
  });

  group('bots read as human', () {
    test('T1 still wins a fair share against a weak player', () {
      // The bottom tier must not be a punching bag: a weak human should lose
      // to it often enough that it never feels like a free win.
      final rng = math.Random(4);
      var botWins = 0;
      const trials = 1500;
      for (var i = 0; i < trials; i++) {
        final bot = BotEngine.simulate(GameMode.sprint, BotTier.t1, rng);
        final human = BotEngine.simulate(GameMode.sprint, BotTier.t2, rng);
        if (bot.totalScore > human.totalScore) botWins++;
      }
      expect(botWins / trials, greaterThan(0.25));
    });

    test('form variance stops scores being robotic', () {
      final rng = math.Random(5);
      final scores = [
        for (var i = 0; i < 400; i++)
          BotEngine.simulate(GameMode.sprint, BotTier.t7, rng).totalScore,
      ];
      final avg = _mean(scores);
      final spread = math.sqrt(
        _mean(scores.map((s) => math.pow(s - avg, 2).toDouble())),
      );
      // A machine-like bot would sit near zero spread.
      expect(
        spread / avg,
        greaterThan(0.10),
        reason: 'consistency, not the name, is what exposes a bot',
      );
    });

    test('a bot score can be read live mid-match', () {
      final run = BotEngine.simulate(
        GameMode.sprint,
        BotTier.t5,
        math.Random(6),
      );
      expect(run.scoreAt(0), 0);
      expect(run.scoreAt(30000), lessThanOrEqualTo(run.totalScore));
      expect(run.scoreAt(kMatchDurationMs), run.totalScore);
    });
  });

  group('opponent selection', () {
    test('draws from the nearest bots by rating', () {
      final roster = BotProfile.seedRoster();
      for (var i = 0; i < roster.length; i++) {
        roster[i].ratings[Category.math] = 600 + i * 100;
      }
      final rng = math.Random(7);
      final picks = {
        for (var i = 0; i < 200; i++)
          OpponentPicker.pick(
            roster: roster,
            category: Category.math,
            playerRating: 1500,
            rng: rng,
          ).id,
      };
      // Only the three nearest to 1500 (1400/1500/1300 -> t9,t10,t8).
      expect(picks.length, OpponentPicker.poolSize);
      for (final id in picks) {
        final bot = roster.firstWhere((b) => b.id == id);
        expect(
          (bot.ratingIn(Category.math) - 1500).abs(),
          lessThanOrEqualTo(200),
        );
      }
    });

    test('every bot has a settled, distinct identity', () {
      // Stable names are what let the leaderboard show opponents the player
      // has actually faced, rather than ten strangers.
      final roster = BotProfile.seedRoster();
      expect(roster.map((b) => b.name).toSet().length, roster.length);
      expect(roster.every((b) => b.name.isNotEmpty), isTrue);

      final again = BotProfile.seedRoster();
      for (var i = 0; i < roster.length; i++) {
        expect(again[i].name, roster[i].name);
        expect(again[i].avatarId, roster[i].avatarId);
      }
    });
  });

  group('ratings converge', () {
    test('players of different skill separate correctly over a season', () {
      final rng = math.Random(9);
      int seasonFor(BotTier skill) {
        final roster = BotProfile.seedRoster();
        var rating = RatingEngine.initial;
        for (var m = 0; m < 250; m++) {
          final bot = OpponentPicker.pick(
            roster: roster,
            category: Category.math,
            playerRating: rating,
            rng: rng,
          );
          final me = BotEngine.simulate(GameMode.sprint, skill, rng);
          final them = BotEngine.simulate(GameMode.sprint, bot.tier, rng);
          final d = RatingEngine.delta(
            myScore: me.totalScore,
            oppScore: them.totalScore,
            myTimeMs: me.totalTimeMs,
            oppTimeMs: them.totalTimeMs,
          );
          rating = RatingEngine.apply(rating, d);
          bot.applyResult(Category.math, d);
        }
        return rating;
      }

      final weak = seasonFor(BotTier.t2);
      final mid = seasonFor(BotTier.t5);
      final strong = seasonFor(BotTier.t9);

      expect(weak, lessThan(mid));
      expect(mid, lessThan(strong));
      // And nobody runs away to infinity the way a random draw did.
      expect(strong, lessThan(2600));
      expect(weak, greaterThan(RatingEngine.floor));
    });
  });
}
