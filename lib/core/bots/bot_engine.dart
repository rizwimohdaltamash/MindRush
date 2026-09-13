import 'dart:math' as math;

import '../match/opponent_feed.dart';
import '../models/game_mode.dart';
import '../questions/question.dart';
import '../scoring/scoring.dart';
import 'bot_tier.dart';

/// One scoring moment in a bot's run.
class BotAnswerEvent {
  const BotAnswerEvent({required this.atMs, required this.points});

  /// Milliseconds from the start of the match.
  final int atMs;
  final int points;

  bool get wasCorrect => points > 0;
}

/// A complete simulated bot performance over one 60-second match.
///
/// The events carry timestamps so the in-game screen can tick the opponent's
/// score up live, the way it would against a real person.
class BotRun implements OpponentFeed {
  BotRun(this.events) : totalScore = events.fold(0, (sum, e) => sum + e.points);

  final List<BotAnswerEvent> events;

  @override
  final int totalScore;

  int get answered => events.length;

  int get correct => events.where((e) => e.wasCorrect).length;

  /// Total time the bot spent answering -- the tiebreaker when scores level.
  @override
  int get totalTimeMs => events.isEmpty ? 0 : events.last.atMs;

  /// Time the bot spent on each question, for the result screen's speed chart.
  @override
  List<int> get answerDurations {
    final durations = <int>[];
    var previous = 0;
    for (final e in events) {
      durations.add(e.atMs - previous);
      previous = e.atMs;
    }
    return durations;
  }

  /// The opponent's visible score partway through the match.
  @override
  int scoreAt(int elapsedMs) {
    var sum = 0;
    for (final e in events) {
      if (e.atMs > elapsedMs) break;
      sum += e.points;
    }
    return sum;
  }
}

/// Simulates bot performances.
abstract final class BotEngine {
  /// Plays out a full match for [tier] in [mode].
  ///
  /// Form is rolled once per match, not per question: the bot is uniformly
  /// sharp or sluggish for the whole minute, which is how a real person's bad
  /// day actually looks.
  static BotRun simulate(GameMode mode, BotTier tier, math.Random rng) {
    final form = _gauss(rng, 1.0, BotTier.formVariance);
    final pace = math.max(200.0, mode.baselineMs * tier.speedFactor * form);

    // A bot that is slow today is also slightly less accurate, and vice versa,
    // at a quarter of the strength of the speed swing.
    final accuracy = (tier.accuracy * (1 + (1 - form) * 0.25)).clamp(0.35, 1.0);

    return mode.isRoundBased
        ? _simulateRounds(pace, accuracy, rng)
        : _simulateQuestions(pace, accuracy, rng);
  }

  static BotRun _simulateQuestions(
    double pace,
    double accuracy,
    math.Random rng,
  ) {
    final events = <BotAnswerEvent>[];
    var t = 0.0;
    while (true) {
      // Per-question jitter on top of the match-long form.
      final step = math.max(150.0, _gauss(rng, pace, pace * 0.25));
      if (t + step > kMatchDurationMs) break;
      t += step;
      final hit = rng.nextDouble() < accuracy;
      events.add(
        BotAnswerEvent(atMs: t.round(), points: hit ? Scoring.perfect : 0),
      );
    }
    return BotRun(events);
  }

  static BotRun _simulateRounds(double pace, double accuracy, math.Random rng) {
    final events = <BotAnswerEvent>[];
    var t = 0.0;
    var round = 0;
    while (true) {
      // Rounds grow through the match for the bot exactly as they do for the
      // player, so the two are always solving the same size of problem.
      final lit = mindSnapCellsFor(round);
      // The beat and the board clearing after it are dead time for the
      // player, so they are dead time for the bot as well. Without this the
      // bot would fit noticeably more rounds into the same minute and Mind
      // Snap would quietly get harder.
      final step =
          math.max(1200.0, _gauss(rng, pace, pace * 0.18)) +
          kMindSnapReviewMs +
          kMindSnapVanishMs;
      if (t + step > kMatchDurationMs) break;
      t += step;
      var recalled = 0;
      for (var i = 0; i < lit; i++) {
        if (rng.nextDouble() < accuracy) recalled++;
      }
      events.add(
        BotAnswerEvent(
          atMs: t.round(),
          points: Scoring.roundPoints(total: lit, correct: recalled),
        ),
      );
      round++;
    }
    return BotRun(events);
  }

  /// Box-Muller normal sample.Used this math so the bots feel incredibly human.
  /// Because of this Bell Curve, the bot will answer most of the questions
  /// right at its average speed, but it will occasionally have a very fast
  /// "lucky" answer, or a slow "stumbling" answer.

  /// It prevents the bot from feeling like a perfectly metronomic machine or
  /// completely chaotic random number generator.
  static double _gauss(math.Random rng, double mean, double sd) {
    final u1 = 1.0 - rng.nextDouble();
    final u2 = 1.0 - rng.nextDouble();
    final z = math.sqrt(-2.0 * math.log(u1)) * math.cos(2 * math.pi * u2);
    return mean + z * sd;
  }

  /// A friend's finished round, replayed as this match's opponent.
  ///
  /// Only the final score and finishing time survive the trip through a URL,
  /// so the points are spread evenly across the minute rather than following
  /// the shape of the real round. The scoreboard still ticks the way it does
  /// against a bot, and the number it arrives at is the friend's actual score
  /// -- which is the part that decides the match.
  static BotRun replay({required int totalScore, required int totalTimeMs}) {
    if (totalScore <= 0) return BotRun(const []);
    final finish = totalTimeMs <= 0 || totalTimeMs > kMatchDurationMs
        ? kMatchDurationMs
        : totalTimeMs;
    final count = (totalScore / Scoring.perfect).ceil();
    final base = totalScore ~/ count;
    var remainder = totalScore - base * count;
    final events = <BotAnswerEvent>[];
    for (var i = 0; i < count; i++) {
      final extra = remainder > 0 ? 1 : 0;
      if (remainder > 0) remainder--;
      events.add(
        BotAnswerEvent(
          atMs: ((i + 1) * finish / count).round(),
          points: base + extra,
        ),
      );
    }
    return BotRun(events);
  }
}
