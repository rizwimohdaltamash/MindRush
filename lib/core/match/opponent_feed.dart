/// Where the other side's score on the scoreboard comes from.
///
/// A duel does not care whether it is being fed by a simulated bot or by a
/// friend's phone reporting in over Firestore. Both answer the same four
/// questions, so [MatchEngine] never needs to know which one it has.
abstract class OpponentFeed {
  /// Their score as it stood at [elapsedMs] into the match.
  int scoreAt(int elapsedMs);

  /// Their score when the minute was up.
  int get totalScore;

  /// When their last answer landed -- the tiebreaker on a level score.
  int get totalTimeMs;

  /// Time spent on each question, for the result screen's speed chart.
  /// Empty when the source cannot know it, as a live opponent cannot.
  List<int> get answerDurations;
}
