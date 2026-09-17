import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mind_rush/core/challenge/duel_room.dart';
import 'package:mind_rush/core/challenge/live_opponent.dart';
import 'package:mind_rush/core/models/game_mode.dart';
import 'package:mind_rush/core/questions/difficulty.dart';
import 'package:mind_rush/data/duel_room_service.dart';
import 'package:mind_rush/data/game_store.dart';
import 'package:mind_rush/data/player_profile.dart';
import 'package:mind_rush/router/app_router.dart';
import 'package:mind_rush/state/providers.dart';
import 'package:mind_rush/ui/theme.dart';

import 'support/fake_rooms.dart';

const _hostUid = 'uid-host';
const _guestUid = 'uid-guest';

DuelRoom _room({
  GameMode mode = GameMode.sprint,
  RoomPlayer? guest,
  RoomStatus status = RoomStatus.waiting,
}) => DuelRoom(
  code: '${mode.name}-849213',
  mode: mode,
  seed: 849213,
  difficulty: Difficulty.medium,
  host: const RoomPlayer(uid: _hostUid, name: 'Naman', avatarId: 1),
  guest: guest,
  status: status,
);

Widget _app(GameStore store, GoRouter router, DuelRoomService? service) =>
    ProviderScope(
      overrides: [
        gameStoreProvider.overrideWithValue(store),
        randomProvider.overrideWithValue(Random(5)),
        duelRoomServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp.router(theme: buildTheme(), routerConfig: router),
    );

void _usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

GameStore _named(String name) =>
    InMemoryGameStore()..saveProfile(PlayerProfile.fresh(name: name));

/// The waiting line breathes on a repeating animation, so pumpAndSettle never
/// returns while the lobby is on screen. Advance in fixed steps instead.
Future<void> _tick(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('the room is the only shared truth', () {
    test('it survives the trip through a document', () {
      final sent = _room(
        guest: const RoomPlayer(uid: _guestUid, name: 'Aarav', avatarId: 3),
        status: RoomStatus.playing,
      );
      final got = DuelRoom.fromJson(sent.toJson())!;

      expect(got.code, sent.code);
      expect(got.mode, sent.mode);
      expect(got.seed, sent.seed);
      expect(got.difficulty, sent.difficulty);
      expect(got.host.name, 'Naman');
      expect(got.guest?.name, 'Aarav');
      expect(got.status, RoomStatus.playing);
    });

    test('both phones build the identical deck from it', () {
      // The point of fixing difficulty in the room rather than deriving it
      // per device: two friends are rarely the same rating, and the same seed
      // at two difficulties is two different matches.
      final room = _room();
      final mine = room.deck;
      final theirs = DuelRoom.fromJson(room.toJson())!.deck;
      for (var i = 0; i < 8; i++) {
        expect(theirs.at(i).runtimeType, mine.at(i).runtimeType);
      }
      expect(theirs.difficulty, mine.difficulty);
      expect(theirs.seed, mine.seed);
    });

    test('a half-written document is refused rather than half-played', () {
      expect(DuelRoom.fromJson(null), isNull);
      expect(DuelRoom.fromJson({'code': 'sprint-1'}), isNull);
      expect(DuelRoom.fromJson({'code': 'sprint-1', 'mode': 'nope'}), isNull);
    });

    test('each side reads the other as the opponent', () {
      final room = _room(
        guest: const RoomPlayer(uid: _guestUid, name: 'Aarav', avatarId: 3),
      );
      expect(room.opponentOf(_hostUid)?.name, 'Aarav');
      expect(room.opponentOf(_guestUid)?.name, 'Naman');
      expect(room.isHost(_hostUid), isTrue);
      expect(room.isHost(_guestUid), isFalse);
    });
  });

  group('joining', () {
    late FakeRoomBackend backend;
    setUp(() => backend = FakeRoomBackend());
    tearDown(() => backend.dispose());

    test('the second player takes the empty seat', () async {
      final host = FakeRooms(backend, _hostUid);
      final guest = FakeRooms(backend, _guestUid);
      final room = _room();
      await host.create(room);

      final failure = await guest.join(
        room.code,
        const RoomPlayer(uid: _guestUid, name: 'Aarav', avatarId: 3),
      );

      expect(failure, isNull);
      expect(backend.rooms[room.code]!.guest?.name, 'Aarav');
      expect(backend.rooms[room.code]!.status, RoomStatus.ready);
    });

    test('a third player is turned away', () async {
      final host = FakeRooms(backend, _hostUid);
      final room = _room();
      await host.create(room);
      await FakeRooms(backend, _guestUid).join(
        room.code,
        const RoomPlayer(uid: _guestUid, name: 'Aarav', avatarId: 3),
      );

      final failure = await FakeRooms(backend, 'uid-third').join(
        room.code,
        const RoomPlayer(uid: 'uid-third', name: 'Ishita', avatarId: 5),
      );

      expect(failure, RoomError.full);
      expect(backend.rooms[room.code]!.guest?.name, 'Aarav');
    });

    test('rejoining after a dropped connection is not gatecrashing', () async {
      final host = FakeRooms(backend, _hostUid);
      final room = _room();
      await host.create(room);
      const guest = RoomPlayer(uid: _guestUid, name: 'Aarav', avatarId: 3);
      final guestPhone = FakeRooms(backend, _guestUid);

      await guestPhone.join(room.code, guest);
      expect(await guestPhone.join(room.code, guest), isNull);
    });

    test('a link to a room that never existed says so', () async {
      final failure = await FakeRooms(backend, _guestUid).join(
        'sprint-000',
        const RoomPlayer(uid: _guestUid, name: 'Aarav', avatarId: 3),
      );
      expect(failure, RoomError.notFound);
    });

    test('the host cannot duel themselves', () async {
      final host = FakeRooms(backend, _hostUid);
      final room = _room();
      await host.create(room);
      final failure = await host.join(
        room.code,
        const RoomPlayer(uid: _hostUid, name: 'Naman', avatarId: 1),
      );
      expect(failure, RoomError.full);
    });
  });

  group('scores move between the phones', () {
    late FakeRoomBackend backend;
    setUp(() => backend = FakeRoomBackend());
    tearDown(() => backend.dispose());

    test('each side writes only its own half', () async {
      final host = FakeRooms(backend, _hostUid);
      final guest = FakeRooms(backend, _guestUid);
      final room = _room();
      await host.create(room);
      await guest.join(
        room.code,
        const RoomPlayer(uid: _guestUid, name: 'Aarav', avatarId: 3),
      );

      await host.report(room.code, asHost: true, score: 40);
      await guest.report(room.code, asHost: false, score: 70);

      final latest = backend.rooms[room.code]!;
      expect(latest.host.score, 40, reason: 'the guest overwrote the host');
      expect(latest.guest?.score, 70);
    });

    test('the feed follows the opponent up the scoreboard', () async {
      final feed = LiveOpponentFeed();
      expect(feed.totalScore, 0);

      feed.update(
        const RoomPlayer(uid: _guestUid, name: 'Aarav', avatarId: 3, score: 40),
      );
      expect(feed.scoreAt(20000), 40);

      feed.update(
        const RoomPlayer(uid: _guestUid, name: 'Aarav', avatarId: 3, score: 90),
      );
      expect(feed.scoreAt(40000), 90);
    });

    test('an out-of-order snapshot cannot walk the score backwards', () {
      // Watching the opponent's score drop mid-match reads as a bug, and
      // Firestore makes no promise about snapshot ordering.
      final feed = LiveOpponentFeed();
      const them = RoomPlayer(uid: _guestUid, name: 'Aarav', avatarId: 3);
      feed.update(them.copyWith(score: 90));
      feed.update(them.copyWith(score: 40));
      expect(feed.totalScore, 90);
    });

    test('until they report in, a tie is not broken in our favour', () {
      final feed = LiveOpponentFeed();
      expect(feed.hasFinished, isFalse);
      expect(feed.totalTimeMs, kMatchDurationMs);

      feed.update(
        const RoomPlayer(
          uid: _guestUid,
          name: 'Aarav',
          avatarId: 3,
          score: 90,
          finished: true,
          timeMs: 51200,
        ),
      );
      expect(feed.hasFinished, isTrue);
      expect(feed.totalTimeMs, 51200);
    });
  });

  group('inviting', () {
    late FakeRoomBackend backend;
    setUp(() => backend = FakeRoomBackend());
    tearDown(() => backend.dispose());

    testWidgets('a mode card opens a room and waits in its lobby', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      final host = FakeRooms(backend, _hostUid);

      await tester.pumpWidget(_app(_named('Naman'), router, host));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('category-memory')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('invite-mindSnap')));
      await tester.pumpAndSettle();

      expect(find.text('Challenge a friend'), findsOneWidget);
      expect(
        find.textContaining('They tap it and join your lobby'),
        findsOneWidget,
      );

      await tester.tap(find.text('Send the invite'));
      // Sheet dismissal, the room write, and the share sheet all resolve
      // before the lobby is pushed.
      await _tick(tester, 40);

      // The room is for the card that was tapped, not for whatever was
      // played last.
      final opened = backend.rooms.values.single;
      expect(opened.mode, GameMode.mindSnap);
      expect(opened.host.name, 'Naman');
      expect(opened.status, RoomStatus.waiting);
      expect(find.text('Waiting for your friend to join…'), findsOneWidget);
    });

    testWidgets('every mode can open its own room', (tester) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _app(_named('Naman'), router, FakeRooms(backend, _hostUid)),
      );
      await tester.pumpAndSettle();

      for (final mode in GameMode.values) {
        await tester.tap(
          find.byKey(ValueKey('category-${mode.category.name}')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('invite-${mode.name}')),
          findsOneWidget,
          reason: '${mode.name} has no way to challenge a friend',
        );
      }
    });
  });

  group('the lobby', () {
    late FakeRoomBackend backend;
    setUp(() => backend = FakeRoomBackend());
    tearDown(() => backend.dispose());

    testWidgets('the host waits, and cannot start alone', (tester) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      final host = FakeRooms(backend, _hostUid);
      final room = _room();
      await host.create(room);

      await tester.pumpWidget(_app(_named('Naman'), router, host));
      await tester.pumpAndSettle();
      router.go(AppRoutes.lobby(room.code));
      await _tick(tester);

      expect(find.text('Waiting for your friend to join…'), findsOneWidget);
      expect(find.text('Naman'), findsOneWidget);
      expect(find.text('Empty'), findsOneWidget);
      // The whole point: no questions until there are two people.
      expect(find.textContaining('= ?'), findsNothing);
    });

    testWidgets('the match begins the moment the second player joins', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      final host = FakeRooms(backend, _hostUid);
      final room = _room();
      await host.create(room);

      await tester.pumpWidget(_app(_named('Naman'), router, host));
      await tester.pumpAndSettle();
      router.go(AppRoutes.lobby(room.code));
      await _tick(tester);
      expect(find.text('Waiting for your friend to join…'), findsOneWidget);

      // The other phone taps the link.
      await FakeRooms(backend, _guestUid).join(
        room.code,
        const RoomPlayer(uid: _guestUid, name: 'Aarav', avatarId: 3),
      );
      await _tick(tester);

      // Straight into the count-in, with the opponent named.
      expect(find.text('Waiting for your friend to join…'), findsNothing);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();
      expect(find.text('Aarav'), findsOneWidget);
      expect(find.text('Naman'), findsOneWidget);
    });

    testWidgets('a guest arriving from the link joins and waits', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      final room = _room();
      await FakeRooms(backend, _hostUid).create(room);
      final guest = FakeRooms(backend, _guestUid);

      await tester.pumpWidget(_app(_named('Aarav'), router, guest));
      await tester.pumpAndSettle();
      router.go('/c/${room.code}?by=Naman');
      await _tick(tester);

      // Joining fills the room, so the host's phone flips it to counting.
      expect(backend.rooms[room.code]!.guest?.name, 'Aarav');
    });

    testWidgets('an expired link is explained, not left spinning', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _app(_named('Aarav'), router, FakeRooms(backend, _guestUid)),
      );
      await tester.pumpAndSettle();
      router.go('/c/sprint-000');
      await _tick(tester);

      expect(find.textContaining('expired'), findsOneWidget);
    });

    testWidgets('with no connection it says so rather than faking a duel', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);

      // No service at all: this is the phone with no signal.
      await tester.pumpWidget(_app(_named('Naman'), router, null));
      await tester.pumpAndSettle();
      router.go(AppRoutes.lobby('sprint-1'));
      await _tick(tester);

      // Not straight away. A service that is missing because Firebase is
      // still starting looks identical from here to one that is missing
      // because there is no signal, and a guest off a tapped link is always
      // in the first case -- so the screen waits before it says anything.
      expect(find.textContaining('need an internet connection'), findsNothing);

      await tester.pump(const Duration(seconds: 13));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('need an internet connection'),
        findsOneWidget,
      );
      expect(
        find.textContaining('= ?'),
        findsNothing,
        reason: 'a bot must never be quietly substituted for a friend',
      );
    });
  });
}
