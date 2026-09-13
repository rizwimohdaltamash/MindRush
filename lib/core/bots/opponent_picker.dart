import 'dart:math' as math;

import '../models/game_mode.dart';
import 'bot_profile.dart';

/// Chooses which bot the player faces.
///
/// This is the only thing keeping ratings meaningful. The rating formula
/// itself has no brake -- nothing stops a strong player gaining forever
/// except facing stronger opponents. Simulation of a fully random draw sent a
/// strong player past 3000 and pinned a weak one at the floor, with neither
/// converging; drawing near the player's rating converges all skill levels
/// into a correctly ordered spread.
///
/// With a roster of only ten, a fixed rating window often comes back empty,
/// so this takes the [poolSize] nearest bots by rating and picks randomly
/// among them. Always finds an opponent, still feels random, still self-
/// correcting.
abstract final class OpponentPicker {
  static const int poolSize = 3;

  static BotProfile pick({
    required List<BotProfile> roster,
    required Category category,
    required int playerRating,
    required math.Random rng,
  }) {
    assert(roster.isNotEmpty, 'roster must not be empty');
    final sorted = [...roster]
      ..sort((a, b) {
        final da = (a.ratingIn(category) - playerRating).abs();
        final db = (b.ratingIn(category) - playerRating).abs();
        return da.compareTo(db);
      });
    final take = math.min(poolSize, sorted.length);
    return sorted[rng.nextInt(take)];
  }
}
