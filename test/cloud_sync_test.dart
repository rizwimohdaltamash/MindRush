import 'package:flutter_test/flutter_test.dart';
import 'package:mind_rush/core/bots/bot_profile.dart';
import 'package:mind_rush/core/models/game_mode.dart';
import 'package:mind_rush/data/cloud_sync.dart';
import 'package:mind_rush/data/game_store.dart';
import 'package:mind_rush/data/match_summary.dart';
import 'package:mind_rush/data/player_profile.dart';
import 'package:mind_rush/data/players_repository.dart';

/// The players collection held in memory, so what goes where can be checked
/// without a network or a Firebase project.
class FakeCloud implements PlayerCloud {
  FakeCloud([this.stored]);

  CloudSnapshot? stored;

  @override
  String get myUid => 'uid-me';

  /// Each write kept apart, because the point of the shape is that they *are*
  /// apart: a row on the board, a match, and a private ladder.
  final List<PlayerProfile> rows = [];
  final List<MatchSummary> matches = [];
  final List<List<BotProfile>> rosters = [];
  final List<String> names = [];
  int wipes = 0;

  @override
  Future<CloudSnapshot?> fetch() async => stored;

  @override
  Future<void> pushProfile(PlayerProfile profile) async => rows.add(profile);

  @override
  Future<void> pushMatch(MatchSummary summary) async => matches.add(summary);

  @override
  Future<void> pushRoster(List<BotProfile> roster) async => rosters.add(roster);

  @override
  Future<void> wipe() async => wipes++;

  @override
  Future<void> setDisplayName(String name) async => names.add(name);
}

/// A cloud that is always broken, standing in for no signal at all.
class DeadCloud implements PlayerCloud {
  @override
  String get myUid => 'uid-me';

  Never _fail() => throw StateError('no network');

  @override
  Future<CloudSnapshot?> fetch() async => _fail();

  @override
  Future<void> pushProfile(PlayerProfile profile) async => _fail();

  @override
  Future<void> pushMatch(MatchSummary summary) async => _fail();

  @override
  Future<void> pushRoster(List<BotProfile> roster) async => _fail();

  @override
  Future<void> wipe() async => _fail();

  @override
  Future<void> setDisplayName(String name) async => _fail();
}

PlayerProfile _profile({
  required String name,
  required int at,
  int rating = 1000,
  List<MatchSummary> history = const [],
}) => PlayerProfile.fresh(name: name).copyWith(
  ratings: {Category.math: rating, Category.memory: 1000, Category.logic: 1000},
  history: history,
  updatedAtMs: at,
);

MatchSummary _match({required int playedAtMs, int ratingDelta = 6}) =>
    MatchSummary(
      mode: GameMode.sprint,
      playerScore: 210,
      opponentScore: 180,
      opponentName: 'Meera',
      ratingBefore: 1000,
      ratingDelta: ratingDelta,
      accuracy: 0.9,
      averageAnswerMs: 2100,
      playedAtMs: playedAtMs,
    );

/// Lets the fire-and-forget uploads run before anything is asserted.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('deciding whose progress survives', () {
    test('a newer cloud copy is adopted when this device is behind', () async {
      final local = InMemoryGameStore();
      await local.saveProfile(_profile(name: 'Old', at: 1000, rating: 1010));
      final cloud = FakeCloud(
        CloudSnapshot(profile: _profile(name: 'New', at: 5000, rating: 1250)),
      );

      await SyncedGameStore.open(local, cloud);

      expect(local.loadProfile().displayName, 'New');
      expect(local.loadProfile().ratingIn(Category.math), 1250);
    });

    test(
      'a stale cloud copy never overwrites fresher local progress',
      () async {
        final local = InMemoryGameStore();
        await local.saveProfile(
          _profile(name: 'Fresh', at: 9000, rating: 1300),
        );
        final cloud = FakeCloud(
          CloudSnapshot(
            profile: _profile(name: 'Stale', at: 200, rating: 1000),
          ),
        );

        await SyncedGameStore.open(local, cloud);

        expect(
          local.loadProfile().displayName,
          'Fresh',
          reason: 'losing a session to an old backup is unforgivable',
        );
        expect(local.loadProfile().ratingIn(Category.math), 1300);
      },
    );

    test('history comes back with the profile it belongs to', () async {
      // The matches live in their own subcollection now; restoring a player
      // without them would show somebody with a rating and no games.
      final local = InMemoryGameStore();
      final cloud = FakeCloud(
        CloudSnapshot(
          profile: _profile(
            name: 'Naman',
            at: 5000,
            history: [_match(playedAtMs: 900), _match(playedAtMs: 800)],
          ),
        ),
      );

      await SyncedGameStore.open(local, cloud);

      expect(local.loadProfile().history.length, 2);
      expect(local.loadProfile().history.first.playedAtMs, 900);
    });

    test('an empty cloud is seeded from this device', () async {
      final local = InMemoryGameStore();
      await local.saveProfile(_profile(name: 'Naman', at: 4000, rating: 1120));
      final cloud = FakeCloud();

      await SyncedGameStore.open(local, cloud);

      expect(cloud.rows.single.displayName, 'Naman');
      expect(cloud.rosters, hasLength(1), reason: 'the ladder goes up too');
    });

    test(
      'a cloud that knows nothing about this player changes nothing',
      () async {
        final local = InMemoryGameStore();
        await local.saveProfile(
          _profile(name: 'Naman', at: 4000, rating: 1120),
        );
        final cloud = FakeCloud(const CloudSnapshot());

        await SyncedGameStore.open(local, cloud);

        expect(local.loadProfile().displayName, 'Naman');
      },
    );
  });

  group('what goes where', () {
    test('a finished match is filed on its own, not as a whole save', () async {
      final local = InMemoryGameStore();
      final cloud = FakeCloud();
      final store = SyncedGameStore(local, cloud);

      await store.saveProfile(
        _profile(name: 'Naman', at: 1, history: [_match(playedAtMs: 500)]),
      );
      await settle();

      expect(cloud.matches.single.playedAtMs, 500);
      expect(
        cloud.rows.single.displayName,
        'Naman',
        reason: 'the row moves as well, so the board is current',
      );
    });

    test('saving anything else does not re-upload the last match', () async {
      // Renaming yourself, changing an avatar, or answering the reminder
      // prompt all save the profile. None of them is a new duel.
      final local = InMemoryGameStore();
      final cloud = FakeCloud();
      final store = SyncedGameStore(local, cloud);
      final history = [_match(playedAtMs: 500)];

      await store.saveProfile(_profile(name: 'Naman', at: 1, history: history));
      await store.saveProfile(_profile(name: 'Naman', at: 2, history: history));
      await store.saveProfile(
        _profile(name: 'Altamash', at: 3, history: history),
      );
      await settle();

      expect(cloud.matches, hasLength(1));
    });

    test('each new duel is one more document', () async {
      final local = InMemoryGameStore();
      final cloud = FakeCloud();
      final store = SyncedGameStore(local, cloud);

      await store.saveProfile(
        _profile(name: 'Naman', at: 1, history: [_match(playedAtMs: 500)]),
      );
      await store.saveProfile(
        _profile(
          name: 'Naman',
          at: 2,
          history: [_match(playedAtMs: 900), _match(playedAtMs: 500)],
        ),
      );
      await settle();

      expect(cloud.matches.map((m) => m.playedAtMs), [500, 900]);
    });

    test('the bot ladder is written apart from the player', () async {
      // Ten generated opponents have no business in a collection of
      // registered people, and were the reason the old one was unreadable.
      final local = InMemoryGameStore();
      final cloud = FakeCloud();
      final store = SyncedGameStore(local, cloud);

      await store.saveRoster(BotProfile.seedRoster());
      await settle();

      expect(cloud.rosters.single, hasLength(10));
      expect(cloud.rows, isEmpty, reason: 'a bot is not a profile change');
    });

    test('resetting progress takes the row off the board', () async {
      final local = InMemoryGameStore();
      final cloud = FakeCloud();
      final store = SyncedGameStore(local, cloud);

      await store.clear();
      await settle();

      expect(cloud.wipes, 1);
    });
  });

  group('the cloud stays out of the way', () {
    test('reads come from local storage, never the network', () async {
      final local = InMemoryGameStore();
      await local.saveProfile(_profile(name: 'Naman', at: 1, rating: 1075));
      final store = SyncedGameStore(local, DeadCloud());

      // A cloud that throws on every call must not affect a read at all.
      expect(store.loadProfile().ratingIn(Category.math), 1075);
      expect(store.loadRoster().length, 10);
    });

    test('a save survives even when the upload fails', () async {
      final local = InMemoryGameStore();
      final store = SyncedGameStore(local, DeadCloud());

      await store.saveProfile(_profile(name: 'Naman', at: 0, rating: 1234));
      await settle();

      expect(
        local.loadProfile().ratingIn(Category.math),
        1234,
        reason: 'no network must never cost the player a match',
      );
    });

    test('a match still lands on disk when it cannot be filed', () async {
      final local = InMemoryGameStore();
      final store = SyncedGameStore(local, DeadCloud());

      await store.saveProfile(
        _profile(name: 'Naman', at: 0, history: [_match(playedAtMs: 500)]),
      );
      await settle();

      expect(local.loadProfile().history.single.playedAtMs, 500);
    });

    test(
      'every save stamps the profile so the next merge can be decided',
      () async {
        final local = InMemoryGameStore();
        final store = SyncedGameStore(local, FakeCloud());
        final before = DateTime.now().millisecondsSinceEpoch;

        await store.saveProfile(_profile(name: 'Naman', at: 0));

        expect(local.loadProfile().updatedAtMs, greaterThanOrEqualTo(before));
      },
    );
  });

  group('naming the account', () {
    test('a chosen name is pushed onto the auth record', () async {
      final local = InMemoryGameStore();
      final cloud = FakeCloud();
      final store = SyncedGameStore(local, cloud);

      await store.saveProfile(_profile(name: 'Naman', at: 0));
      await settle();

      expect(cloud.names, ['Naman']);
    });

    test('finishing a match does not rewrite the name', () async {
      final local = InMemoryGameStore();
      final cloud = FakeCloud();
      final store = SyncedGameStore(local, cloud);

      await store.saveProfile(_profile(name: 'Naman', at: 0));
      await store.saveProfile(_profile(name: 'Naman', at: 1, rating: 1050));
      await store.saveProfile(_profile(name: 'Naman', at: 2, rating: 1090));
      await settle();

      expect(cloud.names, ['Naman'], reason: 'only on an actual rename');
    });

    test('renaming yourself updates the account again', () async {
      final local = InMemoryGameStore();
      final cloud = FakeCloud();
      final store = SyncedGameStore(local, cloud);

      await store.saveProfile(_profile(name: 'Naman', at: 0));
      await store.saveProfile(_profile(name: 'Altamash', at: 1));
      await settle();

      expect(cloud.names, ['Naman', 'Altamash']);
    });

    test('an empty name is never written', () async {
      // A fresh profile has no name until onboarding finishes.
      final local = InMemoryGameStore();
      final cloud = FakeCloud();
      final store = SyncedGameStore(local, cloud);

      await store.saveProfile(PlayerProfile.fresh());
      await settle();

      expect(cloud.names, isEmpty);
    });

    test('a failed auth write never costs the player their save', () async {
      final local = InMemoryGameStore();
      final store = SyncedGameStore(local, DeadCloud());

      await store.saveProfile(_profile(name: 'Naman', at: 0, rating: 1234));
      await settle();

      expect(local.loadProfile().ratingIn(Category.math), 1234);
    });
  });
}
