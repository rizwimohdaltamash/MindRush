/// A milestone on the streak ladder.
class StreakReward {
  const StreakReward({
    required this.day,
    required this.xp,
    required this.title,
    required this.blurb,
  });

  /// The streak length that earns it.
  final int day;

  /// What it pays. Rises faster than the days do, so the fourteenth day is
  /// worth more than the second week of ones and twos would suggest.
  final int xp;

  final String title;
  final String blurb;
}

/// The streak ladder, and everything derived from it.
///
/// Nothing here is stored. A milestone is earned exactly when the player's
/// best streak has ever reached it, so the whole ladder is a function of one
/// number already on the profile. That means it cannot drift out of step with
/// the streak itself, and a streak that breaks and climbs again cannot pay
/// twice.
abstract final class StreakRewards {
  static const List<StreakReward> all = [
    StreakReward(
      day: 1,
      xp: 30,
      title: 'Day one',
      blurb: 'You turned up. Every streak starts here.',
    ),
    StreakReward(
      day: 3,
      xp: 50,
      title: 'Getting warm',
      blurb: 'Three days running. The habit starts here.',
    ),
    StreakReward(
      day: 5,
      xp: 120,
      title: 'Working week',
      blurb: 'Five straight days of showing up.',
    ),
    StreakReward(
      day: 7,
      xp: 250,
      title: 'Seven up',
      blurb: 'A full week without missing a day.',
    ),
    StreakReward(
      day: 14,
      xp: 500,
      title: 'Fortnight',
      blurb: 'Two weeks. This is no longer an accident.',
    ),
    StreakReward(
      day: 30,
      xp: 1000,
      title: 'Month deep',
      blurb: 'Thirty days. Most people never get here.',
    ),
    StreakReward(
      day: 60,
      xp: 2000,
      title: 'Two months',
      blurb: 'Sixty days of turning up to think.',
    ),
    StreakReward(
      day: 100,
      xp: 4000,
      title: 'Century',
      blurb: 'One hundred days. Nothing left to prove.',
    ),
  ];

  /// Total XP a player whose best streak is [bestStreak] has earned.
  static int xpFor(int bestStreak) => all
      .where((reward) => bestStreak >= reward.day)
      .fold(0, (sum, reward) => sum + reward.xp);

  /// True once [bestStreak] has ever reached [reward].
  static bool isEarned(StreakReward reward, int bestStreak) =>
      bestStreak >= reward.day;

  /// The next rung above [currentStreak], or null at the top of the ladder.
  static StreakReward? nextAfter(int currentStreak) =>
      all.where((reward) => reward.day > currentStreak).firstOrNull;

  /// The milestones crossed by a streak moving from [before] to [after].
  ///
  /// Usually one, but a profile restored from a backup can jump several rungs
  /// at once and should be paid for all of them.
  static List<StreakReward> newlyEarned({
    required int before,
    required int after,
  }) => [
    for (final reward in all)
      if (reward.day > before && reward.day <= after) reward,
  ];
}
