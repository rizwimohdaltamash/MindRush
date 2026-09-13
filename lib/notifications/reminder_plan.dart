import '../core/models/game_mode.dart';
import '../core/rating/streak.dart';
import '../data/player_profile.dart';

/// A reminder the app intends to show, decided entirely on device.
class ReminderPlan {
  const ReminderPlan({
    required this.id,
    required this.when,
    required this.title,
    required this.body,
  });

  /// Distinct per slot, so the afternoon reminder and the evening one are two
  /// notifications rather than the second quietly replacing the first.
  final int id;

  final DateTime when;
  final String title;
  final String body;
}

/// Works out when to nudge the player and what to say.
///
/// Pure logic with no plugin and no clock of its own, so the scheduling rule
/// can be tested directly instead of by waiting a day.
///
/// The rule is one line: **the reminder always sits one day after the last
/// match played.** Rescheduling after every match is what makes that correct
/// without any background work -- play again and the pending reminder is
/// replaced, skip a day and the one already queued fires exactly when the
/// streak is about to lapse. No server, no background isolate, no polling.
abstract final class ReminderPlanner {
  /// Two slots a day. Early afternoon catches a lunch break; the evening one
  /// is the last call before the day -- and the streak -- is gone.
  ///
  /// Two rather than one because a single evening nudge is easy to miss and
  /// impossible to act on once it has been swiped away.
  static const List<int> hoursOfDay = [14, 20];

  /// Empty when there is nothing worth saying -- the player has never played,
  /// so there is no streak to protect and no rating to defend.
  static List<ReminderPlan> plans(PlayerProfile profile, DateTime now) {
    final lastDay = profile.streak.lastPlayedDay;
    if (lastDay == null) return const [];

    // dayNumber was built from local calendar fields, so read them back the
    // same way rather than treating the value as a real instant.
    final lastDate = DateTime.fromMillisecondsSinceEpoch(
      lastDay * Duration.millisecondsPerDay,
      isUtc: true,
    );

    return [
      for (final (index, hour) in hoursOfDay.indexed)
        ReminderPlan(
          id: index,
          when: _nextSlot(lastDate, hour, now),
          title: _wordingFor(profile, now, index).title,
          body: _wordingFor(profile, now, index).body,
        ),
    ];
  }

  /// The day after the last match at [hour], pushed forward a day at a time
  /// until it is actually in the future -- a match played late in the evening,
  /// or after the afternoon slot, would otherwise schedule into the past.
  static DateTime _nextSlot(DateTime lastDate, int hour, DateTime now) {
    var when = DateTime(lastDate.year, lastDate.month, lastDate.day + 1, hour);
    while (!when.isAfter(now)) {
      when = DateTime(when.year, when.month, when.day + 1, hour);
    }
    return when;
  }

  /// What this reminder says.
  ///
  /// Four phrasings of the same point, rotated by the date and by which slot
  /// it is. The rotation is the feature: a notification that arrives in
  /// identical words every single day stops being read after about the third
  /// one, and the eight o'clock repeating the two o'clock word for word is
  /// the fastest way there is to teach somebody to swipe it away. Same
  /// information, different sentence.
  ///
  /// Rotated rather than random, so the message is a function of the day and
  /// can be asserted about rather than hoped at.
  static ({String title, String body}) _wordingFor(
    PlayerProfile profile,
    DateTime now,
    int slot,
  ) {
    final streak = profile.streak.displayed(now);
    final options = streak >= 2
        ? _endangered(streak)
        : streak == 1
        ? _dayOne
        : _defendTheRating(profile);

    // Slot is added rather than multiplied, so the two of a day are always
    // neighbours in the list and never the same entry.
    final turn = (_dayOf(now) + slot) % options.length;
    return options[turn];
  }

  /// Days since the epoch, so the wording moves on at midnight rather than
  /// on the first of the month.
  static int _dayOf(DateTime now) =>
      DateTime(now.year, now.month, now.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  /// A streak with something to lose. Every one of these names the number:
  /// that is the whole reason the notification works.
  static List<({String title, String body})> _endangered(int streak) => [
    (
      title: 'Your $streak-day streak ends tonight',
      body: 'One duel keeps it alive. Sixty seconds.',
    ),
    (
      title: 'Do not lose a $streak-day streak now',
      body: 'Sixty seconds is the whole ask.',
    ),
    (
      title: 'Your $streak-day streak is on the line',
      body: 'One minute, and it lives another day.',
    ),
    (
      title: '$streak-day streak, one duel from safe',
      body: 'Nobody else is going to play it for you.',
    ),
  ];

  static const List<({String title, String body})> _dayOne = [
    (
      title: 'Keep your streak going',
      body: 'A minute now and tomorrow counts too.',
    ),
    (title: 'Day two starts here', body: 'Sixty seconds, and the run is on.'),
    (
      title: 'One day in. Make it two.',
      body: 'That is all a streak is: the next one.',
    ),
    (
      title: 'Your streak is one duel old',
      body: 'Second day is the one that sticks.',
    ),
  ];

  /// Nothing on the line, so the rating is the thing worth defending -- and
  /// the phone already knows it, which is the whole reason this needs no
  /// server. Every one of these names it.
  static List<({String title, String body})> _defendTheRating(
    PlayerProfile profile,
  ) {
    final best = Category.values.reduce(
      (a, b) => profile.ratingIn(a) >= profile.ratingIn(b) ? a : b,
    );
    final rating = profile.ratingIn(best);

    return [
      (
        title: 'Ready for a duel?',
        body: 'Your ${best.name} rating is $rating. Come defend it.',
      ),
      (
        title: 'Sixty seconds?',
        body: '$rating at ${best.name}. One duel could move it.',
      ),
      (
        title: 'Your rating is getting comfortable',
        body: 'Still $rating at ${best.name}. Go and change that.',
      ),
      (
        title: 'One minute, one duel',
        body: '${best.name}: $rating. Higher is right there.',
      ),
    ];
  }
}

/// Anything that can queue a reminder on the device.
///
/// An interface so the scheduling rule can be tested without a platform
/// channel, the same way [StreakCalculator] is testable without a calendar.
abstract class ReminderScheduler {
  Future<void> cancelAll();
  Future<void> schedule(ReminderPlan plan);

  /// Prompts the OS. Call at a moment the player is enjoying the game, never
  /// on first launch -- a prompt shown cold is refused far more often.
  Future<bool> requestPermission();
}

/// Records what it was asked to do. Used by tests.
class RecordingScheduler implements ReminderScheduler {
  final List<ReminderPlan> scheduled = [];
  int cancelCount = 0;

  @override
  Future<void> cancelAll() async {
    cancelCount++;
    scheduled.clear();
  }

  @override
  Future<void> schedule(ReminderPlan plan) async => scheduled.add(plan);

  int permissionRequests = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }
}

/// Discards everything. Used when the player has declined notifications, so
/// the rest of the app needs no null checks.
class NoopScheduler implements ReminderScheduler {
  const NoopScheduler();

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> schedule(ReminderPlan plan) async {}

  @override
  Future<bool> requestPermission() async => false;
}
