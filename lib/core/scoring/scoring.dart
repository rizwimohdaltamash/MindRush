/// Points awarded during a match.
///
/// Question modes are all-or-nothing: a correct answer is [perfect] points, a
/// wrong one is zero, and there is no penalty for guessing (guessing costs
/// time, which is punishment enough in a 60-second race).
///
/// Mind Snap rounds award partial credit, because remembering five cells of
/// six is genuinely different from remembering none.
abstract final class Scoring {
  static const int perfect = 10;

  /// Points for one Mind Snap round: [correct] of [total] cells recalled.
  ///
  /// Judged as a proportion rather than a miss count, because rounds grow
  /// from six cells to twelve as a match goes on. Missing two of twelve is a
  /// good round; missing two of six is a poor one, and a flat miss count
  /// would score them identically.
  ///
  /// On a six-cell round this reproduces the original table exactly:
  /// 6/6 -> 10, 5/6 -> 7, 4/6 -> 6, and anything less -> 0.
  static int roundPoints({required int total, required int correct}) {
    if (total <= 0) return 0;
    final hit = correct.clamp(0, total);
    if (hit == total) return perfect;

    final share = hit / total;
    if (share >= 0.80) return 7;
    if (share >= 0.65) return 6;
    return 0;
  }
}
