import 'package:flutter_test/flutter_test.dart';
import 'package:mind_rush/core/rating/streak.dart';
import 'package:mind_rush/core/rating/streak_rewards.dart';
import 'package:mind_rush/data/player_profile.dart';

void main() {
  group('the ladder', () {
    test('climbs, and never pays less for a longer streak', () {
      var previousDay = 0;
      var previousXp = 0;
      for (final reward in StreakRewards.all) {
        expect(
          reward.day,
          greaterThan(previousDay),
          reason: 'rungs must be in order',
        );
        expect(
          reward.xp,
          greaterThan(previousXp),
          reason: 'a longer streak must be worth more',
        );
        previousDay = reward.day;
        previousXp = reward.xp;
      }
    });

    test('the ladder starts on the first day, not the third', () {
      // A player who has just played their first duel should be able to see
      // what they earned, not an empty ladder telling them to come back on
      // Wednesday.
      expect(StreakRewards.all.first.day, 1);
      expect(StreakRewards.all.first.xp, 30);
      expect(StreakRewards.xpFor(1), 30);
    });

    test('pays for everything reached and nothing beyond', () {
      expect(StreakRewards.xpFor(0), 0);
      expect(StreakRewards.xpFor(1), 30);
      expect(StreakRewards.xpFor(2), 30);
      expect(StreakRewards.xpFor(3), 30 + 50);
      expect(StreakRewards.xpFor(4), 30 + 50);
      expect(StreakRewards.xpFor(5), 30 + 50 + 120);
      expect(StreakRewards.xpFor(7), 30 + 50 + 120 + 250);
    });

    test('names the next rung to aim at', () {
      expect(StreakRewards.nextAfter(0)?.day, 1);
      expect(StreakRewards.nextAfter(1)?.day, 3);
      expect(StreakRewards.nextAfter(3)?.day, 5);
      expect(StreakRewards.nextAfter(7)?.day, 14);
      expect(
        StreakRewards.nextAfter(100),
        isNull,
        reason: 'the top of the ladder has nothing above it',
      );
    });
  });

  group('crossing a rung', () {
    test('is reported once, on the match that does it', () {
      expect(StreakRewards.newlyEarned(before: 2, after: 3).single.day, 3);
      // Playing again the next day is not the same milestone again.
      expect(StreakRewards.newlyEarned(before: 3, after: 4), isEmpty);
    });

    test('a jump pays for every rung it passes', () {
      // A profile restored from a backup can arrive several days ahead.
      final crossed = StreakRewards.newlyEarned(before: 0, after: 8);
      expect(crossed.map((r) => r.day), [1, 3, 5, 7]);
    });

    test('a streak that breaks and climbs again does not pay twice', () {
      // Earning is keyed on the best streak ever, which only goes up.
      const profile = StreakState(current: 1, best: 7, lastPlayedDay: 10);
      expect(StreakRewards.xpFor(profile.best), 450);
      expect(StreakRewards.newlyEarned(before: 7, after: 7), isEmpty);
    });
  });

  group('the profile', () {
    test('reports XP derived from the best streak, not stored', () {
      final fresh = PlayerProfile.fresh(name: 'Naman');
      expect(fresh.streakXp, 0);

      final week = fresh.copyWith(
        streak: const StreakState(current: 7, best: 7, lastPlayedDay: 20),
      );
      expect(week.streakXp, 450);

      // Streak lapses; the XP it earned does not evaporate with it.
      final lapsed = week.copyWith(
        streak: const StreakState(current: 0, best: 7, lastPlayedDay: 20),
      );
      expect(lapsed.streakXp, 450);
    });
  });

  group('the streak itself still behaves', () {
    test('a second match the same day changes nothing', () {
      final day = DateTime(2026, 9, 9, 10);
      final first = StreakCalculator.register(const StreakState(), day);
      final second = StreakCalculator.register(first, DateTime(2026, 9, 9, 22));

      expect(first.current, 1);
      expect(second.current, 1);
      expect(
        second.lastPlayedDay,
        first.lastPlayedDay,
        reason: 'the celebration must not fire twice in one day',
      );
    });

    test('a consecutive day extends it', () {
      final first = StreakCalculator.register(
        const StreakState(),
        DateTime(2026, 9, 9),
      );
      final next = StreakCalculator.register(first, DateTime(2026, 9, 10));
      expect(next.current, 2);
      expect(next.lastPlayedDay, isNot(first.lastPlayedDay));
    });
  });
}
