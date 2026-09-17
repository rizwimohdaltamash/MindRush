import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mind_rush/core/challenge/duel_room.dart';
import 'package:mind_rush/core/models/game_mode.dart';
import 'package:mind_rush/core/players/player_record.dart';
import 'package:mind_rush/core/questions/difficulty.dart';
import 'package:mind_rush/data/game_store.dart';
import 'package:mind_rush/data/player_profile.dart';
import 'package:mind_rush/data/players_repository.dart';
import 'package:mind_rush/router/app_router.dart';
import 'package:mind_rush/state/providers.dart';
import 'package:mind_rush/ui/theme.dart';

import 'support/fake_rooms.dart';

const _hostUid = 'uid-naman';
const _guestUid = 'uid-aarav';

/// The register held in memory, so the online dot can be driven from a test.
class FakePlayers implements PlayerService {
  FakePlayers(this.myUid, this._entries);

  @override
  final String myUid;

  List<PlayerRecord> _entries;
  int beats = 0;
  int departures = 0;

  set entries(List<PlayerRecord> value) {
    _entries = value;
    _controller.add(value);
  }

  final _controller = StreamController<List<PlayerRecord>>.broadcast();

  @override
  Future<void> beat() async {
    beats++;
  }

  @override
  Future<void> leave() async {
    departures++;
  }

  int signOuts = 0;

  @override
  Future<void> signOut() async => signOuts++;

  @override
  Stream<List<PlayerRecord>> watch() async* {
    yield _entries;
    yield* _controller.stream;
  }

  Future<void> dispose() => _controller.close();
}

DuelRoom _invite({
  String? invitedUid = _guestUid,
  RoomStatus status = RoomStatus.waiting,
  int createdAtMs = 0,
}) => DuelRoom(
  code: 'mindSnap-849213',
  mode: GameMode.mindSnap,
  seed: 849213,
  difficulty: Difficulty.medium,
  host: const RoomPlayer(
    uid: _hostUid,
    name: 'Naman',
    avatarId: 1,
    rating: 1000,
  ),
  status: status,
  invitedUid: invitedUid,
  invitedName: 'Aarav',
  createdAtMs: createdAtMs,
);

void main() {
  late FakeRoomBackend backend;

  setUp(() => backend = FakeRoomBackend());
  tearDown(() => backend.dispose());

  Widget app(
    GameStore store,
    GoRouter router,
    FakeRooms rooms, {
    PlayerService? presence,
  }) => ProviderScope(
    overrides: [
      gameStoreProvider.overrideWithValue(store),
      randomProvider.overrideWithValue(Random(5)),
      duelRoomServiceProvider.overrideWithValue(rooms),
      playerServiceProvider.overrideWithValue(presence),
    ],
    child: MaterialApp.router(theme: buildTheme(), routerConfig: router),
  );

  void usePhoneScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> tick(WidgetTester tester, [int frames = 16]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  GameStore named(String name) =>
      InMemoryGameStore()..saveProfile(PlayerProfile.fresh(name: name));

  group('a guest arriving before the cloud is up', () {
    /// The app with no room service at all, which is what a tapped link
    /// actually lands in: the lobby is built the moment the app is, and
    /// Firebase is still starting behind it.
    Widget cloudless(GameStore store, GoRouter router) => ProviderScope(
      overrides: [
        gameStoreProvider.overrideWithValue(store),
        randomProvider.overrideWithValue(Random(5)),
      ],
      child: MaterialApp.router(theme: buildTheme(), routerConfig: router),
    );

    ProviderContainer containerIn(WidgetTester tester) =>
        ProviderScope.containerOf(
          tester.element(find.byType(MaterialApp).first),
        );

    testWidgets('is not told to check their connection', (tester) async {
      usePhoneScreen(tester);
      await FakeRooms(backend, _hostUid).create(_invite(invitedUid: null));

      final router = buildRouter(
        initialLocation: AppRoutes.challenge('mindSnap-849213'),
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(cloudless(named('Aarav'), router));
      await tester.pump();

      // The screen used to give up here, on the one player who most needs it
      // to work. Waiting is the honest answer: nothing has failed yet.
      expect(find.textContaining('internet connection'), findsNothing);
    });

    testWidgets('takes the seat once Firebase finishes starting', (
      tester,
    ) async {
      usePhoneScreen(tester);
      await FakeRooms(backend, _hostUid).create(_invite(invitedUid: null));

      final router = buildRouter(
        initialLocation: AppRoutes.challenge('mindSnap-849213'),
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(cloudless(named('Aarav'), router));
      await tester.pump();
      expect(backend.rooms['mindSnap-849213']?.guest, isNull);

      // A second and a half later, the cloud arrives.
      await tester.pump(const Duration(milliseconds: 1500));
      containerIn(
        tester,
      ).read(runtimeProvider.notifier).arrived(
        rooms: FakeRooms(backend, _guestUid),
      );
      await tester.pumpAndSettle();

      expect(backend.rooms['mindSnap-849213']?.guest?.uid, _guestUid);
    });

    testWidgets('gives up if it really never comes', (tester) async {
      usePhoneScreen(tester);
      await FakeRooms(backend, _hostUid).create(_invite(invitedUid: null));

      final router = buildRouter(
        initialLocation: AppRoutes.challenge('mindSnap-849213'),
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(cloudless(named('Aarav'), router));
      await tester.pump(const Duration(seconds: 13));
      await tester.pumpAndSettle();

      // Waiting for ever would be its own kind of broken.
      expect(find.textContaining('internet connection'), findsOneWidget);
    });
  });

  group('a challenge that arrives', () {
    testWidgets('is put in front of the player wherever they are', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      final guest = FakeRooms(backend, _guestUid);

      await tester.pumpWidget(app(named('Aarav'), router, guest));
      await tester.pumpAndSettle();

      // Naman challenges Aarav while Aarav is sitting on the home screen.
      await FakeRooms(
        backend,
        _hostUid,
      ).create(_invite(createdAtMs: DateTime.now().millisecondsSinceEpoch));
      await tick(tester);

      expect(find.text('Naman challenges you'), findsOneWidget);
      expect(find.textContaining('Mind Snap'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
    });

    testWidgets('accepting takes the seat', (tester) async {
      usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      final guest = FakeRooms(backend, _guestUid);

      await tester.pumpWidget(app(named('Aarav'), router, guest));
      await tester.pumpAndSettle();
      await FakeRooms(
        backend,
        _hostUid,
      ).create(_invite(createdAtMs: DateTime.now().millisecondsSinceEpoch));
      await tick(tester);

      await tester.tap(find.text('Accept'));
      await tick(tester);

      expect(backend.rooms['mindSnap-849213']!.guest?.name, 'Aarav');
    });

    testWidgets('declining says no and does not ask twice', (tester) async {
      usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      final guest = FakeRooms(backend, _guestUid);

      await tester.pumpWidget(app(named('Aarav'), router, guest));
      await tester.pumpAndSettle();
      await FakeRooms(
        backend,
        _hostUid,
      ).create(_invite(createdAtMs: DateTime.now().millisecondsSinceEpoch));
      await tick(tester);

      await tester.tap(find.text('Decline'));
      await tick(tester);

      expect(backend.rooms['mindSnap-849213']!.status, RoomStatus.declined);
      expect(backend.rooms['mindSnap-849213']!.guest, isNull);
      // The declined room is still in the collection; it must not come back
      // round as a fresh question.
      expect(find.text('Naman challenges you'), findsNothing);
    });

    testWidgets('a challenge meant for someone else is not shown', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        app(named('Aarav'), router, FakeRooms(backend, _guestUid)),
      );
      await tester.pumpAndSettle();
      await FakeRooms(backend, _hostUid).create(
        _invite(
          invitedUid: 'uid-ishita',
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await tick(tester);

      expect(find.text('Naman challenges you'), findsNothing);
    });

    testWidgets('a link-shared room does not ring anybody', (tester) async {
      usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        app(named('Aarav'), router, FakeRooms(backend, _guestUid)),
      );
      await tester.pumpAndSettle();
      // No invitedUid: this one travels by WhatsApp, as before.
      await FakeRooms(backend, _hostUid).create(_invite(invitedUid: null));
      await tick(tester);

      expect(find.text('Naman challenges you'), findsNothing);
    });
  });

  group('a challenge nobody answered', () {
    test('stops ringing once it is stale', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final fresh = _invite(createdAtMs: nowMs);
      final old = _invite(createdAtMs: nowMs - DuelRoom.inviteExpiryMs - 1);

      expect(fresh.isLiveInviteFor(_guestUid, nowMs: nowMs), isTrue);
      expect(
        old.isLiveInviteFor(_guestUid, nowMs: nowMs),
        isFalse,
        reason: 'a challenge from an hour ago must not resurface',
      );
    });

    test('an answered one is no longer live', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      expect(
        _invite(
          status: RoomStatus.declined,
          createdAtMs: nowMs,
        ).isLiveInviteFor(_guestUid, nowMs: nowMs),
        isFalse,
      );
      expect(
        _invite(createdAtMs: nowMs)
            .copyWith(
              guest: const RoomPlayer(
                uid: _guestUid,
                name: 'Aarav',
                avatarId: 3,
              ),
            )
            .isLiveInviteFor(_guestUid, nowMs: nowMs),
        isFalse,
      );
    });

    test('it survives the trip through a document', () {
      final sent = _invite(createdAtMs: 999);
      final got = DuelRoom.fromJson(sent.toJson())!;
      expect(got.invitedUid, _guestUid);
      expect(got.invitedName, 'Aarav');
      expect(got.createdAtMs, 999);
    });
  });

  group('the challenger', () {
    testWidgets('is told when they are turned down', (tester) async {
      usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      final host = FakeRooms(backend, _hostUid);
      await host.create(
        _invite(createdAtMs: DateTime.now().millisecondsSinceEpoch),
      );

      await tester.pumpWidget(app(named('Naman'), router, host));
      await tester.pumpAndSettle();
      router.go(AppRoutes.lobby('mindSnap-849213'));
      await tick(tester);

      expect(find.text('Waiting for them to accept…'), findsOneWidget);

      await FakeRooms(
        backend,
        _guestUid,
      ).setStatus('mindSnap-849213', RoomStatus.declined);
      await tick(tester);

      expect(find.textContaining('Aarav declined'), findsOneWidget);
    });
  });

  group('the Ranks screen', () {
    /// Aarav as the register reports him, rated above every bot so he sorts to
    /// the top and the test is not quietly asserting about a row below the
    /// fold.
    PlayerRecord aarav({required int lastSeenAtMs}) => PlayerRecord(
      uid: _guestUid,
      name: 'Aarav',
      avatarId: 3,
      lastSeenAtMs: lastSeenAtMs,
      ratings: const {
        Category.math: 1120,
        Category.memory: 1120,
        Category.logic: 1120,
      },
    );

    PlayerRecord me({required int lastSeenAtMs}) => PlayerRecord(
      uid: _hostUid,
      name: 'Naman',
      avatarId: 1,
      lastSeenAtMs: lastSeenAtMs,
    );

    testWidgets('everyone registered is ranked, duelled or not', (
      tester,
    ) async {
      // The old rule -- you appear only once someone has played you -- meant a
      // new player was invisible to everybody, including themselves.
      usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final presence = FakePlayers(_hostUid, [
        me(lastSeenAtMs: nowMs),
        // Registered but not online, and never played by this device.
        aarav(lastSeenAtMs: 0),
      ]);
      addTearDown(presence.dispose);

      await tester.pumpWidget(
        app(
          named('Naman'),
          router,
          FakeRooms(backend, _hostUid),
          presence: presence,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ranks'));
      await tester.pumpAndSettle();

      expect(find.text('Aarav'), findsOneWidget);
      expect(
        find.text('1120'),
        findsOneWidget,
        reason: 'their rating comes from their own phone',
      );
    });

    testWidgets('an offline player cannot be challenged', (tester) async {
      usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final presence = FakePlayers(_hostUid, [
        me(lastSeenAtMs: nowMs),
        aarav(lastSeenAtMs: 0),
      ]);
      addTearDown(presence.dispose);

      await tester.pumpWidget(
        app(
          named('Naman'),
          router,
          FakeRooms(backend, _hostUid),
          presence: presence,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ranks'));
      await tester.pumpAndSettle();

      expect(find.text('Aarav'), findsOneWidget);
      // No bolt: challenging a closed app would only produce a room nobody
      // ever answers.
      expect(find.byIcon(Icons.bolt_rounded), findsNothing);
    });

    testWidgets('an online player gets a bolt to challenge them', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final presence = FakePlayers(_hostUid, [
        me(lastSeenAtMs: nowMs),
        aarav(lastSeenAtMs: nowMs),
      ]);
      addTearDown(presence.dispose);

      await tester.pumpWidget(
        app(
          named('Naman'),
          router,
          FakeRooms(backend, _hostUid),
          presence: presence,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ranks'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
    });

    testWidgets('a real player takes the name off the bot who shared it', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      // Aryan is the first name on the bot roster. Somebody signing up as
      // Aryan is not unlikely -- there are ten bots and they all have
      // ordinary first names.
      final presence = FakePlayers(_hostUid, [
        me(lastSeenAtMs: nowMs),
        PlayerRecord(
          uid: _guestUid,
          name: 'Aryan',
          avatarId: 3,
          lastSeenAtMs: nowMs,
          ratings: const {
            Category.math: 1120,
            Category.memory: 1120,
            Category.logic: 1120,
          },
        ),
      ]);
      addTearDown(presence.dispose);

      await tester.pumpWidget(
        app(
          named('Naman'),
          router,
          FakeRooms(backend, _hostUid),
          presence: presence,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ranks'));
      await tester.pumpAndSettle();

      // One Aryan, not two. Two rows with one name and two ratings reads as
      // a broken board.
      expect(find.text('Aryan'), findsOneWidget);

      // And the one left standing is the person: they can be challenged.
      await tester.tap(find.text('Aryan'));
      await tester.pumpAndSettle();
      expect(find.text('Challenge Aryan to'), findsOneWidget);
    });

    testWidgets('the whole row sends the challenge, not just the bolt', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final presence = FakePlayers(_hostUid, [
        me(lastSeenAtMs: nowMs),
        aarav(lastSeenAtMs: nowMs),
      ]);
      addTearDown(presence.dispose);

      await tester.pumpWidget(
        app(
          named('Naman'),
          router,
          FakeRooms(backend, _hostUid),
          presence: presence,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ranks'));
      await tester.pumpAndSettle();

      // The name, which is nowhere near the bolt. A thumb aimed at a person
      // lands on their row, not on a 22-pixel icon at the end of it.
      await tester.tap(find.text('Aarav'));
      await tester.pumpAndSettle();

      expect(find.text('Challenge Aarav to'), findsOneWidget);
    });

    testWidgets('a row for somebody offline does not send anything', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final presence = FakePlayers(_hostUid, [
        me(lastSeenAtMs: nowMs),
        // Yesterday: on the board, but not here.
        aarav(lastSeenAtMs: nowMs - const Duration(days: 1).inMilliseconds),
      ]);
      addTearDown(presence.dispose);

      await tester.pumpWidget(
        app(
          named('Naman'),
          router,
          FakeRooms(backend, _hostUid),
          presence: presence,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ranks'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bolt_rounded), findsNothing);

      await tester.tap(find.text('Aarav'));
      await tester.pumpAndSettle();

      // Inert, rather than opening a duel nobody is there to accept.
      expect(find.text('Challenge Aarav to'), findsNothing);
      expect(backend.rooms, isEmpty);
    });

    testWidgets('the mode is chosen before anything is sent', (tester) async {
      usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final presence = FakePlayers(_hostUid, [
        me(lastSeenAtMs: nowMs),
        aarav(lastSeenAtMs: nowMs),
      ]);
      addTearDown(presence.dispose);

      await tester.pumpWidget(
        app(
          named('Naman'),
          router,
          FakeRooms(backend, _hostUid),
          presence: presence,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ranks'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.bolt_rounded));
      await tester.pumpAndSettle();

      // Nothing has been sent yet: the other phone must not be asked to accept
      // a duel before anybody has said what it is.
      expect(find.text('Challenge Aarav to'), findsOneWidget);
      expect(backend.rooms, isEmpty);
      for (final mode in GameMode.values) {
        expect(find.text(mode.label), findsOneWidget);
      }

      await tester.tap(find.text('Mind Snap'));
      await tick(tester, 30);

      final room = backend.rooms.values.single;
      expect(room.invitedUid, _guestUid);
      expect(room.invitedName, 'Aarav');
      expect(room.mode, GameMode.mindSnap);
      expect(find.text('Waiting for them to accept…'), findsOneWidget);
    });

    testWidgets('a duel already chosen is not asked about twice', (
      tester,
    ) async {
      // Arriving from Mind Snap's own page, having pressed Play a Friend on
      // it. The mode is settled; the only open question is who.
      usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final presence = FakePlayers(_hostUid, [
        me(lastSeenAtMs: nowMs),
        aarav(lastSeenAtMs: nowMs),
      ]);
      addTearDown(presence.dispose);

      await tester.pumpWidget(
        app(
          named('Naman'),
          router,
          FakeRooms(backend, _hostUid),
          presence: presence,
        ),
      );
      await tester.pumpAndSettle();
      router.go(AppRoutes.findFriend(GameMode.mindSnap));
      await tester.pumpAndSettle();

      // Search the board down to the one person being challenged.
      await tester.enterText(find.byType(TextField), 'aarav');
      await tester.pumpAndSettle();
      expect(backend.rooms, isEmpty, reason: 'typing sends nothing');

      await tester.tap(find.byIcon(Icons.bolt_rounded));
      await tick(tester, 30);

      expect(
        find.text('Challenge Aarav to'),
        findsNothing,
        reason: 'the duel was chosen a screen ago',
      );
      final room = backend.rooms.values.single;
      expect(room.mode, GameMode.mindSnap);
      expect(room.invitedUid, _guestUid);
    });

    testWidgets('with no duel carried in, the picker still comes first', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final presence = FakePlayers(_hostUid, [
        me(lastSeenAtMs: nowMs),
        aarav(lastSeenAtMs: nowMs),
      ]);
      addTearDown(presence.dispose);

      await tester.pumpWidget(
        app(
          named('Naman'),
          router,
          FakeRooms(backend, _hostUid),
          presence: presence,
        ),
      );
      await tester.pumpAndSettle();
      router.go(AppRoutes.findFriend(GameMode.mindSnap));
      await tester.pumpAndSettle();
      // Put the carried duel down again, and the board goes back to asking.
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.bolt_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Challenge Aarav to'), findsOneWidget);
      expect(backend.rooms, isEmpty);
    });
  });

  group('the online row on home', () {
    testWidgets('shows you first, then whoever else is here', (tester) async {
      usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final presence = FakePlayers(_hostUid, [
        PlayerRecord(
          uid: _hostUid,
          name: 'Naman',
          avatarId: 1,
          lastSeenAtMs: nowMs,
        ),
        PlayerRecord(
          uid: _guestUid,
          name: 'Aarav',
          avatarId: 3,
          lastSeenAtMs: nowMs,
        ),
        // Registered, but long gone. Not reachable, so not in this row.
        const PlayerRecord(
          uid: 'uid-ishita',
          name: 'Ishita',
          avatarId: 5,
          lastSeenAtMs: 0,
        ),
      ]);
      addTearDown(presence.dispose);

      await tester.pumpWidget(
        app(
          named('Naman'),
          router,
          FakeRooms(backend, _hostUid),
          presence: presence,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('YOU'), findsOneWidget);
      expect(find.text('AARAV'), findsOneWidget);
      expect(
        find.text('ISHITA'),
        findsNothing,
        reason: 'a closed app cannot answer a challenge',
      );
    });

    testWidgets('says so plainly when nobody else is here', (tester) async {
      usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      final presence = FakePlayers(_hostUid, [
        PlayerRecord(
          uid: _hostUid,
          name: 'Naman',
          avatarId: 1,
          lastSeenAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      ]);
      addTearDown(presence.dispose);

      await tester.pumpWidget(
        app(
          named('Naman'),
          router,
          FakeRooms(backend, _hostUid),
          presence: presence,
        ),
      );
      await tester.pumpAndSettle();

      // An empty row with no explanation reads as a loading bug.
      expect(find.textContaining('Nobody else is online'), findsOneWidget);
    });

    testWidgets('tapping a face asks which duel, then sends it', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final presence = FakePlayers(_hostUid, [
        PlayerRecord(
          uid: _hostUid,
          name: 'Naman',
          avatarId: 1,
          lastSeenAtMs: nowMs,
        ),
        PlayerRecord(
          uid: _guestUid,
          name: 'Aarav',
          avatarId: 3,
          lastSeenAtMs: nowMs,
        ),
      ]);
      addTearDown(presence.dispose);

      await tester.pumpWidget(
        app(
          named('Naman'),
          router,
          FakeRooms(backend, _hostUid),
          presence: presence,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('online-$_guestUid')));
      await tester.pumpAndSettle();
      expect(find.text('Challenge Aarav to'), findsOneWidget);
      expect(
        backend.rooms,
        isEmpty,
        reason: 'nothing sent until a mode is picked',
      );

      await tester.tap(find.text('Fastest Fingers'));
      await tick(tester, 30);

      final room = backend.rooms.values.single;
      expect(room.mode, GameMode.fastestFingers);
      expect(room.invitedUid, _guestUid);
    });
  });
}
