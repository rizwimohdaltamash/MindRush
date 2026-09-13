import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_rush/core/models/game_mode.dart';
import 'package:mind_rush/core/rating/streak.dart';
import 'package:mind_rush/data/game_store.dart';
import 'package:mind_rush/data/player_profile.dart';
import 'package:mind_rush/notifications/reminder_plan.dart';
import 'package:mind_rush/state/providers.dart';

PlayerProfile _profile({
  required DateTime lastPlayed,
  int streak = 1,
  int mathRating = 1000,
}) => PlayerProfile.fresh().copyWith(
  ratings: {
    Category.math: mathRating,
    Category.memory: 1000,
    Category.logic: 1000,
  },
  streak: StreakState(
    current: streak,
    best: streak,
    lastPlayedDay: StreakCalculator.dayNumber(lastPlayed),
  ),
);

void main() {
  group('when the reminders land', () {
    test('a player who has never played gets nothing to say', () {
      final plans = ReminderPlanner.plans(
        PlayerProfile.fresh(),
        DateTime(2026, 9, 6, 12),
      );
      expect(plans, isEmpty);
    });

    test('two a day: one in the afternoon, one in the evening', () {
      // One evening nudge is easy to miss and impossible to act on once it
      // has been swiped away.
      final plans = ReminderPlanner.plans(
        _profile(lastPlayed: DateTime(2026, 9, 6, 9)),
        DateTime(2026, 9, 6, 9),
      );

      expect(plans.map((p) => p.when), [
        DateTime(2026, 9, 7, 14),
        DateTime(2026, 9, 7, 20),
      ]);
    });

    test('each slot is its own notification', () {
      // Sharing an id would mean the evening one silently replaced the
      // afternoon one at scheduling time.
      final plans = ReminderPlanner.plans(
        _profile(lastPlayed: DateTime(2026, 9, 6, 9)),
        DateTime(2026, 9, 6, 9),
      );

      expect(plans.map((p) => p.id).toSet(), hasLength(plans.length));
    });

    test('a late-night match still schedules for the following day', () {
      final plans = ReminderPlanner.plans(
        _profile(lastPlayed: DateTime(2026, 9, 6, 23, 40)),
        DateTime(2026, 9, 6, 23, 40),
      );
      expect(plans.first.when, DateTime(2026, 9, 7, 14));
    });

    test('never schedules a time that has already passed', () {
      // Reopening the app days later must not queue a reminder for the past,
      // and each slot has to be pushed forward on its own -- at nine in the
      // evening, today's two o'clock is gone but tomorrow's is not.
      final now = DateTime(2026, 9, 6, 21);
      final plans = ReminderPlanner.plans(
        _profile(lastPlayed: DateTime(2026, 9, 1, 10)),
        now,
      );

      for (final plan in plans) {
        expect(plan.when.isAfter(now), isTrue, reason: 'slot ${plan.id}');
      }
    });

    test('both land at a civil hour', () {
      final plans = ReminderPlanner.plans(
        _profile(lastPlayed: DateTime(2026, 9, 6, 9)),
        DateTime(2026, 9, 6, 9),
      );
      for (final plan in plans) {
        expect(plan.when.hour, inInclusiveRange(9, 21));
      }
    });
  });

  group('what it says', () {
    test('a streak worth losing is named explicitly', () {
      final now = DateTime(2026, 9, 6, 10);
      final plans = ReminderPlanner.plans(
        _profile(lastPlayed: now, streak: 4),
        now,
      );
      expect(plans.first.title, contains('4-day streak'));
      expect(plans.first.body, contains('Sixty seconds'));
    });

    test('the evening does not repeat the afternoon word for word', () {
      // The fastest way to teach somebody to swipe a notification away is to
      // send them the same sentence twice in six hours.
      final now = DateTime(2026, 9, 6, 10);
      final plans = ReminderPlanner.plans(
        _profile(lastPlayed: now, streak: 4),
        now,
      );

      expect(plans.map((p) => p.title).toSet(), hasLength(plans.length));
      expect(plans.map((p) => p.body).toSet(), hasLength(plans.length));
      // Different words, same fact: both still name what is at stake.
      for (final plan in plans) {
        expect(plan.title, contains('4-day streak'));
      }
    });

    test('and tomorrow does not repeat today', () {
      final today = DateTime(2026, 9, 6, 10);
      final tomorrow = DateTime(2026, 9, 7, 10);

      String wordingOn(DateTime day) {
        final plans = ReminderPlanner.plans(
          _profile(lastPlayed: day, streak: 4),
          day,
        );
        return '${plans.first.title}|${plans.first.body}';
      }

      expect(wordingOn(today), isNot(wordingOn(tomorrow)));
    });

    test('a one-day streak is talked about as a beginning, not a loss', () {
      final now = DateTime(2026, 9, 6, 10);
      final plans = ReminderPlanner.plans(
        _profile(lastPlayed: now, streak: 1),
        now,
      );

      // Nothing dramatic to lose yet, so nothing dramatic is claimed.
      expect(plans.first.title, isNot(contains('ends tonight')));
      expect(plans.first.body, isNotEmpty);
    });

    test('with no streak it falls back to the rating -- which the phone '
        'already knows, so no server is involved', () {
      final now = DateTime(2026, 9, 6, 10);
      // Played four days ago, so the streak is already gone: there is nothing
      // left to protect and the rating is the only thing worth mentioning.
      final plans = ReminderPlanner.plans(
        _profile(
          lastPlayed: now.subtract(const Duration(days: 4)),
          streak: 4,
          mathRating: 1287,
        ),
        now,
      );

      for (final plan in plans) {
        expect(plan.body, contains('1287'));
        expect(plan.body, contains('math'));
      }
    });
  });

  group('rescheduling on every match', () {
    ProviderContainer container(RecordingScheduler scheduler, GameStore store) {
      final c = ProviderContainer(
        overrides: [
          gameStoreProvider.overrideWithValue(store),
          randomProvider.overrideWithValue(Random(1)),
          reminderSchedulerProvider.overrideWithValue(scheduler),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<void> playOne(ProviderContainer c) async {
      final engine = c
          .read(matchFactoryProvider)
          .create(mode: GameMode.sprint, playerRating: 1000);
      await c
          .read(profileProvider.notifier)
          .recordMatch(engine.finish(), GameMode.sprint);
    }

    test('a finished match queues both of the day\'s reminders', () async {
      final scheduler = RecordingScheduler();
      final c = container(scheduler, InMemoryGameStore());

      await playOne(c);

      expect(
        scheduler.cancelCount,
        1,
        reason: 'the old ones are cleared first',
      );
      expect(scheduler.scheduled.length, 2);
      for (final plan in scheduler.scheduled) {
        expect(plan.when.isAfter(DateTime.now()), isTrue);
      }
    });

    test(
      'playing again replaces the pending reminder rather than stacking',
      () async {
        final scheduler = RecordingScheduler();
        final c = container(scheduler, InMemoryGameStore());

        await playOne(c);
        await playOne(c);
        await playOne(c);

        // This is what makes a plain scheduled notification correct without any
        // background work.
        expect(scheduler.cancelCount, 3);
        expect(scheduler.scheduled.length, 2, reason: 'the two slots, once');
      },
    );

    test('resetting progress clears the reminder too', () async {
      final scheduler = RecordingScheduler();
      final c = container(scheduler, InMemoryGameStore());

      await playOne(c);
      await c.read(profileProvider.notifier).resetEverything();

      expect(scheduler.scheduled, isEmpty);
    });

    test('a scheduler that throws never breaks recording a match', () async {
      final c = ProviderContainer(
        overrides: [
          gameStoreProvider.overrideWithValue(InMemoryGameStore()),
          randomProvider.overrideWithValue(Random(1)),
          reminderSchedulerProvider.overrideWithValue(_BrokenScheduler()),
        ],
      );
      addTearDown(c.dispose);

      await playOne(c);

      expect(
        c.read(profileProvider).history.length,
        1,
        reason: 'a nudge is a convenience, never a requirement',
      );
    });
  });

  group('asking for permission', () {
    test('asks once and never again', () async {
      final scheduler = RecordingScheduler();
      final c = ProviderContainer(
        overrides: [
          gameStoreProvider.overrideWithValue(InMemoryGameStore()),
          randomProvider.overrideWithValue(Random(1)),
          reminderSchedulerProvider.overrideWithValue(scheduler),
        ],
      );
      addTearDown(c.dispose);

      expect(
        await c.read(profileProvider.notifier).askAboutRemindersOnce(),
        isTrue,
      );
      expect(
        await c.read(profileProvider.notifier).askAboutRemindersOnce(),
        isFalse,
      );
      expect(scheduler.permissionRequests, 1);
    });

    test('the answer survives a restart, so it is not asked twice', () async {
      final store = InMemoryGameStore();
      final scheduler = RecordingScheduler();
      ProviderContainer session() {
        final c = ProviderContainer(
          overrides: [
            gameStoreProvider.overrideWithValue(store),
            randomProvider.overrideWithValue(Random(1)),
            reminderSchedulerProvider.overrideWithValue(scheduler),
          ],
        );
        addTearDown(c.dispose);
        return c;
      }

      await session().read(profileProvider.notifier).askAboutRemindersOnce();
      expect(
        await session().read(profileProvider.notifier).askAboutRemindersOnce(),
        isFalse,
      );
      expect(scheduler.permissionRequests, 1);
    });
  });
}

class _BrokenScheduler implements ReminderScheduler {
  @override
  Future<void> cancelAll() async => throw StateError('no notifications here');

  @override
  Future<void> schedule(ReminderPlan plan) async =>
      throw StateError('no notifications here');

  @override
  Future<bool> requestPermission() async =>
      throw StateError('no notifications here');
}
