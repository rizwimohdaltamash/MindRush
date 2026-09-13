/// Daily play streak.
///
/// Play any duel on a given day and the streak advances; skip a day and it
/// starts over. Days are compared as calendar dates in the device's local
/// timezone, normalised through UTC so a daylight-saving shift cannot make
/// two consecutive days look 0 or 2 apart.
///
/// Note this trusts the device clock. Winding the clock forward would let
/// someone farm a streak, which is acceptable while ratings are computed on
/// device and there is nothing to win; if a real backend arrives later, move
/// [StreakCalculator.register] behind it.
class StreakState {
  const StreakState({this.current = 0, this.best = 0, this.lastPlayedDay});

  final int current;
  final int best;

  /// Days since the epoch, or null if the player has never played.
  final int? lastPlayedDay;

  /// The streak to show right now. A streak earned yesterday still stands
  /// today until the day ends; anything older has already lapsed.
  int displayed(DateTime now) {
    final last = lastPlayedDay;
    if (last == null) return 0;
    final gap = StreakCalculator.dayNumber(now) - last;
    return gap <= 1 ? current : 0;
  }

  /// Highest badge tier reached, or null below the first threshold.
  int? get badge {
    int? earned;
    for (final t in StreakCalculator.badgeThresholds) {
      if (current >= t) earned = t;
    }
    return earned;
  }

  StreakState copyWith({int? current, int? best, int? lastPlayedDay}) =>
      StreakState(
        current: current ?? this.current,
        best: best ?? this.best,
        lastPlayedDay: lastPlayedDay ?? this.lastPlayedDay,
      );
}

abstract final class StreakCalculator {
  static const List<int> badgeThresholds = [1, 3, 7, 14, 30];

  /// Whole days since the epoch for the local calendar date of [when].
  static int dayNumber(DateTime when) {
    final local = when.toLocal();
    return DateTime.utc(
          local.year,
          local.month,
          local.day,
        ).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
  }

  /// Records a completed match. Playing twice in one day changes nothing.
  static StreakState register(StreakState state, DateTime now) {
    final today = dayNumber(now);
    final last = state.lastPlayedDay;

    if (last == today) return state;

    // Consecutive day extends the run; any longer gap starts a fresh one at
    // one, because the player is playing right now.
    final next = (last != null && today - last == 1) ? state.current + 1 : 1;

    return StreakState(
      current: next,
      best: next > state.best ? next : state.best,
      lastPlayedDay: today,
    );
  }
}
