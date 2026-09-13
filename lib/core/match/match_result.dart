import 'opponent_feed.dart';
import '../scoring/scoring.dart';

/// One answer the player gave during a match.
class AnswerRecord {
  const AnswerRecord({
    required this.questionIndex,
    required this.atMs,
    required this.durationMs,
    required this.points,
  });

  final int questionIndex;

  /// Milliseconds from the start of the match.
  final int atMs;

  /// Time spent on this question alone.
  final int durationMs;

  final int points;

  /// Full marks. In Mind Snap that means the whole pattern, not a
  /// partial-credit round -- otherwise recalling four cells of six would count
  /// towards accuracy and the stat would read near 100% for everyone.
  bool get wasCorrect => points == Scoring.perfect;

  /// Scored anything at all, including partial Mind Snap credit.
  bool get scoredPoints => points > 0;
}

/// Player and opponent time on the same question, for the result screen's
/// answer-speed chart.
class SpeedPoint {
  const SpeedPoint({
    required this.questionIndex,
    required this.playerMs,
    required this.opponentMs,
  });

  final int questionIndex;

  /// Null when that side never reached this question.
  final int? playerMs;
  final int? opponentMs;

  /// True only when both sides answered and the player took longer.
  bool get playerWasSlower =>
      playerMs != null && opponentMs != null && playerMs! > opponentMs!;
}

enum MatchOutcome { win, loss, draw }

/// Everything the result screen needs, computed once when the clock runs out.
class MatchResult {
  MatchResult({
    required this.playerScore,
    required this.opponentScore,
    required this.ratingBefore,
    required this.ratingDelta,
    required this.answers,
    required this.opponentFeed,
    required this.opponentName,
    required this.opponentAvatarId,
    required this.shareCode,
    this.opponentUid,
    this.opponentPhoto,
    this.abandoned = false,
    this.abandonedByYou = false,
  });

  final int playerScore;
  final int opponentScore;
  final int ratingBefore;
  final int ratingDelta;
  final List<AnswerRecord> answers;

  /// A bot's simulated run, or a friend's phone reporting in live.
  final OpponentFeed opponentFeed;
  final String opponentName;
  final int opponentAvatarId;

  /// The person on the other phone, or null when the opponent was a bot.
  ///
  /// This is the whole difference between an opponent you can send a rematch
  /// to and one you cannot: a bot has no phone for a challenge to arrive on,
  /// so the result screen offers one only when this is set.
  final String? opponentUid;

  /// Their photograph, if they have set one, so the result shows the face
  /// that was on the scoreboard a second ago.
  final String? opponentPhoto;

  /// True when the other side was a real person.
  bool get opponentIsReal => opponentUid != null;

  /// Nobody was playing on one side of it, so there is nothing to rate.
  ///
  /// A duel called off because a player stopped answering is not a loss and
  /// not a draw -- it never happened. The scores still read what each side
  /// had actually reached, because that is the truth about the minute up to
  /// the point it stopped, but no rating moves either way and it is never
  /// filed in the history: a walked-away match that counted towards a streak
  /// would be a way of keeping one without playing.
  final bool abandoned;

  /// Which side stopped answering, so the screen can say so.
  ///
  /// Only meaningful when [abandoned]. The phone that went quiet calls the
  /// match off for both of them, so the other player lands here too -- and
  /// telling them it was not their doing is the difference between an
  /// explanation and an accusation.
  final bool abandonedByYou;

  /// Identifies the exact question set this match used, so a friend can be
  /// challenged to the same one.
  final String shareCode;

  int get ratingAfter => ratingBefore + ratingDelta;

  MatchOutcome get outcome => switch (ratingDelta) {
    > 0 => MatchOutcome.win,
    < 0 => MatchOutcome.loss,
    _ => MatchOutcome.draw,
  };

  int get questionsAnswered => answers.length;

  int get questionsCorrect => answers.where((a) => a.wasCorrect).length;

  double get accuracy =>
      answers.isEmpty ? 0 : questionsCorrect / answers.length;

  /// Average time per answer, the headline stat on the profile chart.
  int get averageAnswerMs => answers.isEmpty
      ? 0
      : (answers.fold<int>(0, (s, a) => s + a.durationMs) / answers.length)
            .round();

  /// Paired per-question timings, one entry per question either side reached.
  List<SpeedPoint> get speedByQuestion {
    final botDurations = opponentFeed.answerDurations;
    final count = answers.length > botDurations.length
        ? answers.length
        : botDurations.length;
    return [
      for (var i = 0; i < count; i++)
        SpeedPoint(
          questionIndex: i,
          playerMs: i < answers.length ? answers[i].durationMs : null,
          opponentMs: i < botDurations.length ? botDurations[i] : null,
        ),
    ];
  }

  /// Drives the "You were slower in N questions" line.
  int get questionsSlower =>
      speedByQuestion.where((p) => p.playerWasSlower).length;

  /// When the player's last answer landed -- the tiebreaker on a level score.
  int get finishedAtMs => answers.isEmpty ? 0 : answers.last.atMs;
}
