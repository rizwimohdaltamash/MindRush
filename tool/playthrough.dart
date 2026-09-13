// ignore_for_file: avoid_print -- dev-only end-to-end check, not shipped.
import 'dart:math';

import 'package:mind_rush/core/bots/bot_profile.dart';
import 'package:mind_rush/core/match/match_engine.dart';
import 'package:mind_rush/core/match/match_result.dart';
import 'package:mind_rush/core/models/game_mode.dart';
import 'package:mind_rush/core/questions/question.dart';
import 'package:mind_rush/core/rating/rating_engine.dart';
import 'package:mind_rush/core/rating/streak.dart';

double _gauss(Random rng, double mean, double sd) {
  final z = sqrt(-2 * log(1 - rng.nextDouble())) *
      cos(2 * pi * (1 - rng.nextDouble()));
  return mean + z * sd;
}

/// Plays a whole match through the real MatchEngine, the way the UI will.
void _play(MatchEngine e, double accuracy, double paceMs, Random rng) {
  var t = 0;
  while (true) {
    final step = max(150, _gauss(rng, paceMs, paceMs * 0.25).round());
    if (t + step > kMatchDurationMs) break;
    t += step;
    final gotIt = rng.nextDouble() < accuracy;

    switch (e.current) {
      case NumericQuestion q:
        e.submitNumber(gotIt ? q.answer : q.answer + 1, atMs: t);
      case ChoiceQuestion q:
        e.submitOption(
          gotIt ? q.correctIndex : (q.correctIndex + 1) % q.options.length,
          atMs: t,
        );
      case PatternRound q:
        e.submitPattern(
          {for (final c in q.litCells) if (rng.nextDouble() < accuracy) c},
          atMs: t,
        );
    }
  }
  e.advanceTo(kMatchDurationMs);
}

void main() {
  final rng = Random(2026);
  final roster = BotProfile.seedRoster();
  final factory = MatchFactory(roster: roster, random: rng);

  // A single player of fixed real skill, across every mode, for a season.
  const accuracy = 0.91;
  const paceFactor = 0.92; // slightly faster than a typical player

  print('One player (91% accurate, 0.92x pace), 120 matches per mode\n');
  print('mode              rating  W-L-D      avg score  avg acc  slower-in');

  for (final mode in GameMode.values) {
    var rating = RatingEngine.initial;
    var wins = 0, losses = 0, draws = 0;
    var scoreSum = 0, accSum = 0.0, slowerSum = 0;
    late MatchResult last;

    for (var i = 0; i < 120; i++) {
      final engine = factory.create(mode: mode, playerRating: rating);
      _play(engine, accuracy, mode.baselineMs * paceFactor, rng);
      final r = engine.finish();
      rating = r.ratingAfter;
      switch (r.outcome) {
        case MatchOutcome.win:
          wins++;
        case MatchOutcome.loss:
          losses++;
        case MatchOutcome.draw:
          draws++;
      }
      scoreSum += r.playerScore;
      accSum += r.accuracy;
      slowerSum += r.questionsSlower;
      last = r;
    }

    final head = '  ${mode.label.padRight(16)}${rating.toString().padLeft(6)}'
        '  $wins-$losses-$draws';
    final tail = '${(scoreSum / 120).round().toString().padLeft(5)}'
        '${((accSum / 120) * 100).round().toString().padLeft(9)}%'
        '${(slowerSum / 120).round().toString().padLeft(11)}';
    print('${head.padRight(38)}$tail');
    if (mode == GameMode.sprint) {
      print('      last match: you ${last.playerScore} vs '
          '${last.opponentName} ${last.opponentScore} '
          '-> ${last.ratingDelta >= 0 ? "+" : ""}${last.ratingDelta} '
          '(${last.outcome.name}), slower in ${last.questionsSlower} questions');
    }
  }

  print('\nBot roster after the season (math):');
  for (final b in roster) {
    print('  ${b.tier.codename.padRight(9)} ${b.ratingIn(Category.math)}');
  }

  var streak = const StreakState();
  final start = DateTime(2026, 9, 1);
  for (final day in [0, 1, 2, 3, 4, 7, 8]) {
    streak = StreakCalculator.register(streak, start.add(Duration(days: day)));
  }
  print('\nStreak after playing days 0-4 then 7-8: '
      'current ${streak.current}, best ${streak.best}, badge ${streak.badge}');
}
