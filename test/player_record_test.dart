import 'package:flutter_test/flutter_test.dart';
import 'package:mind_rush/core/models/game_mode.dart';
import 'package:mind_rush/core/rating/streak.dart';
import 'package:mind_rush/data/match_summary.dart';
import 'package:mind_rush/data/player_profile.dart';
import 'package:mind_rush/data/players_repository.dart';

const _uid = 'uid-naman';

MatchSummary _match({required int playedAtMs, required int ratingDelta}) =>
    MatchSummary(
      mode: GameMode.sprint,
      playerScore: 200,
      opponentScore: 180,
      opponentName: 'Meera',
      ratingBefore: 1000,
      ratingDelta: ratingDelta,
      accuracy: 0.9,
      averageAnswerMs: 2100,
      playedAtMs: playedAtMs,
    );

PlayerProfile _profile() =>
    PlayerProfile.fresh(name: 'Naman', avatarId: 3).copyWith(
      ratings: {
        Category.math: 1120,
        Category.memory: 980,
        Category.logic: 1000,
      },
      streak: const StreakState(current: 4, best: 9, lastPlayedDay: 20345),
      history: [
        _match(playedAtMs: 300, ratingDelta: 7),
        _match(playedAtMs: 200, ratingDelta: -4),
        _match(playedAtMs: 100, ratingDelta: 5),
      ],
      updatedAtMs: 4242,
    );

void main() {
  group('what a player publishes about themselves', () {
    test('who they are and how they are doing', () {
      final record = publicRecordOf(_profile(), _uid);

      expect(record.uid, _uid);
      expect(record.name, 'Naman');
      expect(record.avatarId, 3);
      expect(record.ratingIn(Category.math), 1120);
      expect(record.ratingIn(Category.memory), 980);
      expect(record.streak.current, 4);
      expect(record.streak.best, 9);
      expect(record.updatedAtMs, 4242);
      // Worked out on this device and stored, so another phone can rank the
      // row without knowing how either number is calculated.
      expect(record.xp, _profile().streakXp);
      expect(record.level, _profile().level);
    });

    test("and nothing that is nobody else's business", () {
      final published = publicRecordOf(_profile(), _uid).toJson();

      // The save is not the row. A hundred match summaries on every
      // leaderboard entry is a leaderboard nobody can afford to load.
      expect(published.containsKey('history'), isFalse);
      expect(published.containsKey('bots'), isFalse);
      expect(published.containsKey('askedAboutReminders'), isFalse);
    });
  });

  group('fields the server owns', () {
    test('a device never writes the clock or the counters', () {
      final fields = clientFieldsOf(_profile(), _uid);

      // A phone that keeps its last hundred matches must not be allowed to
      // decide a career total, and neither device should be voting on what
      // time it is.
      expect(fields.containsKey('tally'), isFalse);
      expect(fields.containsKey('lastSeenAtMs'), isFalse);
      expect(fields.containsKey('createdAtMs'), isFalse);
      // Everything else still goes.
      expect(fields['name'], 'Naman');
      expect(fields['ratings'], {'math': 1120, 'memory': 980, 'logic': 1000});
    });

    test('the counters open at what this device can still see', () {
      // Only used once, when a player who existed before the counters did
      // gets their first row.
      final tally = tallyOf(_profile());

      expect(tally.played, 3);
      expect(tally.won, 2);
      expect(tally.lost, 1);
    });

    test('a player with no games behind them starts at nothing', () {
      final tally = tallyOf(PlayerProfile.fresh(name: 'Naman'));

      expect(tally.played, 0);
      expect(tally.winRate, 0, reason: 'and not a division by zero');
    });
  });
}
