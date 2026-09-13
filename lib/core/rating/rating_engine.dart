import 'dart:math' as math;

/// Rating changes are driven purely by the **score margin** of the match.
///
/// The opponent's rating never affects the delta: beating a 700-rated
/// opponent by 30% of the score earns exactly what beating a 1600-rated one
/// by 30% earns. Opponent rating decides only *who you face*, never *what you
/// earn*. This is deliberately not Elo -- it is far easier for a player to
/// read ("I won by a lot, so I gained a lot"), and it still converges because
/// opponent selection tracks your rating.
///
/// The margin is taken *relative* to the higher score rather than as a raw
/// point difference. That makes it comparable across modes: a 40-point margin
/// is a blowout in Mind Snap (~80 points a match) and a close call in Fastest
/// Fingers (~700). A raw margin would award the cap on nearly every Fastest
/// Fingers match.
abstract final class RatingEngine {
  /// Largest rating swing a single match can produce.
  static const int maxDelta = 11;

  /// Relative margin at which [maxDelta] is reached. Win or lose by 35% of
  /// the higher score and the change is capped.
  static const double fullMarginRatio = 0.35;

  /// Ratings never go below this, so a bad run never shows a negative number.
  static const int floor = 100;

  /// Every player and bot starts here, in every category.
  static const int initial = 1000;

  /// Rating change for one match, from this player's point of view.
  ///
  /// When scores are level the match is decided on total answer time (faster
  /// player wins) and moves the rating by a single point. With no timing data
  /// a tie is a genuine draw and nothing changes.
  static int delta({
    required int myScore,
    required int oppScore,
    int? myTimeMs,
    int? oppTimeMs,
  }) {
    if (myScore == oppScore) {
      if (myTimeMs == null || oppTimeMs == null || myTimeMs == oppTimeMs) {
        return 0;
      }
      return myTimeMs < oppTimeMs ? 1 : -1;
    }

    final higher = math.max(math.max(myScore, oppScore), 1);
    final relativeMargin = (myScore - oppScore).abs() / higher;
    final progress = math.min(relativeMargin / fullMarginRatio, 1.0);
    final magnitude = (maxDelta * math.sqrt(progress)).round();

    return myScore > oppScore ? magnitude : -magnitude;
  }

  /// Applies [delta] to [rating], respecting the [floor].
  static int apply(int rating, int delta) => math.max(floor, rating + delta);
}
