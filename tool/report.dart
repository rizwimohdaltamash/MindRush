// ignore_for_file: avoid_print -- dev-only calibration report, not shipped.

import 'dart:math' as math;
import 'package:mind_rush/core/bots/bot_engine.dart';
import 'package:mind_rush/core/bots/bot_profile.dart';
import 'package:mind_rush/core/bots/bot_tier.dart';
import 'package:mind_rush/core/bots/opponent_picker.dart';
import 'package:mind_rush/core/models/game_mode.dart';
import 'package:mind_rush/core/rating/rating_engine.dart';

double mean(Iterable<num> xs) => xs.fold<double>(0, (a, b) => a + b) / xs.length;

void main() {
  final rng = math.Random(42);
  print('BOT LADDER -- average score by mode');
  print('        ${GameMode.values.map((m) => m.label.padLeft(16)).join()}');
  for (final t in BotTier.values) {
    final cells = GameMode.values.map((m) => mean([
          for (var i = 0; i < 500; i++)
            BotEngine.simulate(m, t, rng).totalScore
        ]).round().toString().padLeft(16));
    print('  ${t.codename.padRight(8)}${cells.join()}');
  }

  print('\n250 matches, rating after a season (sprint):');
  for (final skill in [BotTier.t2, BotTier.t5, BotTier.t9]) {
    final finals = <int>[];
    for (var run = 0; run < 8; run++) {
      final roster = BotProfile.seedRoster();
      var r = RatingEngine.initial;
      for (var m = 0; m < 250; m++) {
        final bot = OpponentPicker.pick(
            roster: roster, category: Category.math, playerRating: r, rng: rng);
        final me = BotEngine.simulate(GameMode.sprint, skill, rng);
        final them = BotEngine.simulate(GameMode.sprint, bot.tier, rng);
        final d = RatingEngine.delta(
            myScore: me.totalScore, oppScore: them.totalScore,
            myTimeMs: me.totalTimeMs, oppTimeMs: them.totalTimeMs);
        r = RatingEngine.apply(r, d);
        bot.applyResult(Category.math, d);
      }
      finals.add(r);
    }
    print('  player skill ${skill.codename.padRight(8)} -> ${mean(finals).round()}');
  }
}
