import '../rating/rating_engine.dart';

/// How hard the questions are, derived from the player's rating in that
/// category.
///
/// Both sides of a match play at the same difficulty, and a bot tier's
/// accuracy is defined as its accuracy *at whatever difficulty it is playing*.
/// So scaling questions with rating does not tilt the ladder -- it just keeps
/// a 1500 player from grinding through sums a 900 player finds challenging.
enum Difficulty {
  easy(1),
  light(2),
  medium(3),
  hard(4),
  brutal(5);

  const Difficulty(this.level);

  final int level;

  /// Roughly one band per 200 rating points either side of the 1000 start.
  static Difficulty fromRating(int rating) {
    final offset = (rating - RatingEngine.initial) / 200.0;
    final index = (2 + offset).round().clamp(0, Difficulty.values.length - 1);
    return Difficulty.values[index];
  }
}
