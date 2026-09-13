import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mind_rush/core/challenge/duel_room.dart';
import 'package:mind_rush/core/challenge/live_opponent.dart';
import 'package:mind_rush/core/match/match_result.dart';
import 'package:mind_rush/core/models/game_mode.dart';
import 'package:mind_rush/core/questions/difficulty.dart';
import 'package:mind_rush/data/game_store.dart';
import 'package:mind_rush/data/player_profile.dart';
import 'package:mind_rush/router/app_router.dart';
import 'package:mind_rush/state/providers.dart';
import 'package:mind_rush/ui/theme.dart';

import 'support/fake_rooms.dart';

const _me = 'uid-naman';
const _them = 'uid-aarav';

/// A one-pixel PNG, base64 encoded: valid, tiny, and enough to tell a
/// photograph apart from the character glyph underneath it.
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
    'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

MatchResult _result({
  String? opponentUid,
  String? opponentPhoto,
  LiveOpponentFeed? feed,
}) => MatchResult(
  playerScore: 8,
  opponentScore: 6,
  ratingBefore: 1000,
  ratingDelta: 14,
  answers: const [
    AnswerRecord(questionIndex: 0, atMs: 1200, durationMs: 1200, points: 10),
    AnswerRecord(questionIndex: 1, atMs: 2600, durationMs: 1400, points: 10),
  ],
  opponentFeed: feed ?? LiveOpponentFeed(),
  opponentName: 'Aarav',
  opponentAvatarId: 3,
  opponentUid: opponentUid,
  opponentPhoto: opponentPhoto,
  shareCode: 'sprint-1',
);

void main() {
  group('a friend who gives up mid-duel', () {
    test('is seen as having aborted rather than simply finished', () {
      final feed = LiveOpponentFeed();
      feed.update(
        const RoomPlayer(uid: 'them', name: 'Ira', avatarId: 0, score: 12),
      );
      expect(feed.hasAborted, isFalse);

      feed.update(
        const RoomPlayer(
          uid: 'them',
          name: 'Ira',
          avatarId: 0,
          finished: true,
          aborted: true,
        ),
      );
      expect(
        feed.hasAborted,
        isTrue,
        reason: 'this phone ends unrated too rather than banking a free win',
      );
    });

    test('survives the round trip through a room document', () {
      const player = RoomPlayer(
        uid: 'them',
        name: 'Ira',
        avatarId: 0,
        finished: true,
        aborted: true,
      );
      expect(RoomPlayer.fromJson(player.toJson())!.aborted, isTrue);
      // Absent by default, so an ordinary report is not a byte longer.
      const played = RoomPlayer(uid: 'them', name: 'Ira', avatarId: 0);
      expect(played.toJson().containsKey('aborted'), isFalse);
      expect(RoomPlayer.fromJson(played.toJson())!.aborted, isFalse);
    });
  });

  group('a live opponent on the speed chart', () {
    test('their per-question times arrive with their final score', () {
      final feed = LiveOpponentFeed();

      // Mid-match: a score, and nothing to draw a chart from yet.
      feed.update(
        const RoomPlayer(uid: _them, name: 'Aarav', avatarId: 3, score: 4),
      );
      expect(feed.answerDurations, isEmpty);

      feed.update(
        const RoomPlayer(
          uid: _them,
          name: 'Aarav',
          avatarId: 3,
          score: 6,
          finished: true,
          timeMs: 41000,
          durations: [900, 1500, 2200],
        ),
      );

      expect(feed.answerDurations, [900, 1500, 2200]);
    });

    test('the chart pairs both sides rather than showing one line', () {
      final feed = LiveOpponentFeed()
        ..update(
          const RoomPlayer(
            uid: _them,
            name: 'Aarav',
            avatarId: 3,
            score: 6,
            finished: true,
            timeMs: 41000,
            durations: [900, 1500],
          ),
        );

      final points = _result(feed: feed).speedByQuestion;

      expect(points.map((p) => p.playerMs), [1200, 1400]);
      expect(points.map((p) => p.opponentMs), [900, 1500]);
      // Slower on the first question, quicker on the second.
      expect(points.first.playerWasSlower, isTrue);
      expect(points.last.playerWasSlower, isFalse);
    });

    test('a phone that never reported in leaves its bars empty', () {
      final points = _result().speedByQuestion;

      expect(points.map((p) => p.playerMs), [1200, 1400]);
      // Not zeroes, which would draw as a friend who answered instantly.
      expect(points.every((p) => p.opponentMs == null), isTrue);
    });
  });

  group('the room carries', () {
    late FakeRoomBackend backend;

    setUp(() => backend = FakeRoomBackend());
    tearDown(() => backend.dispose());

    test('per-question times from one phone to the other', () async {
      final host = FakeRooms(backend, _me);
      await host.create(
        DuelRoom.open(
          mode: GameMode.sprint,
          seed: 41,
          difficulty: Difficulty.medium,
          host: const RoomPlayer(uid: _me, name: 'Naman', avatarId: 1),
        ),
      );
      await FakeRooms(backend, _them).join(
        'sprint-41',
        const RoomPlayer(uid: _them, name: 'Aarav', avatarId: 3),
      );

      // Mid-match reports carry the score alone; the times ride the last one.
      await host.report('sprint-41', asHost: true, score: 4);
      expect(backend.rooms['sprint-41']!.host.durations, isEmpty);

      await host.report(
        'sprint-41',
        asHost: true,
        score: 8,
        finished: true,
        timeMs: 52000,
        durations: [1200, 1400],
      );

      // What the guest's phone sees of the host.
      final asSeenByGuest = backend.rooms['sprint-41']!.opponentOf(_them)!;
      expect(asSeenByGuest.durations, [1200, 1400]);
    });

    test('a face, so the other phone shows a person', () {
      const seat = RoomPlayer(
        uid: _me,
        name: 'Naman',
        avatarId: 1,
        photo: _png,
      );

      expect(RoomPlayer.fromJson(seat.toJson())!.photo, _png);
    });
  });

  group('the result screen', () {
    late FakeRoomBackend backend;

    setUp(() => backend = FakeRoomBackend());
    tearDown(() => backend.dispose());

    Widget app(GameStore store, GoRouter router, FakeRooms rooms) =>
        ProviderScope(
          overrides: [
            gameStoreProvider.overrideWithValue(store),
            randomProvider.overrideWithValue(Random(7)),
            duelRoomServiceProvider.overrideWithValue(rooms),
          ],
          child: MaterialApp.router(theme: buildTheme(), routerConfig: router),
        );

    Future<GoRouter> showResult(
      WidgetTester tester,
      MatchResult result, {
      GameStore? store,
    }) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        app(
          store ??
              (InMemoryGameStore()
                ..saveProfile(PlayerProfile.fresh(name: 'Naman'))),
          router,
          FakeRooms(backend, _me),
        ),
      );
      await tester.pumpAndSettle();

      router.push(AppRoutes.result, extra: ResultArgs(result, GameMode.sprint));
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('offers a rematch after a real person', (tester) async {
      await showResult(tester, _result(opponentUid: _them));

      expect(find.text('Rematch Aarav'), findsOneWidget);
    });

    testWidgets('offers none after a bot, which has no phone to ask', (
      tester,
    ) async {
      await showResult(tester, _result());

      expect(find.textContaining('Rematch'), findsNothing);
      // The generic ways on are still there.
      expect(find.text('Play a friend'), findsOneWidget);
      expect(find.text('Play again'), findsOneWidget);
    });

    testWidgets('sends one addressed to the person just played', (
      tester,
    ) async {
      await showResult(tester, _result(opponentUid: _them));

      await tester.tap(find.text('Rematch Aarav'));
      // Pumped rather than settled: the lobby the challenger lands in waits
      // with an animation that never finishes, which is the point of it.
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final sent = backend.rooms.values.single;
      expect(sent.invitedUid, _them);
      expect(sent.invitedName, 'Aarav');
      // The duel they have just played, not a fresh question about which one.
      expect(sent.mode, GameMode.sprint);
      expect(sent.host.name, 'Naman');
      // And the challenger is left waiting in their own lobby for the answer,
      // rather than back on the result screen wondering if it went.
      expect(find.text('Waiting for them to accept…'), findsOneWidget);
    });

    testWidgets('is where the other player can accept it', (tester) async {
      // Aarav is looking at the result of the match he has just lost when
      // Naman's rematch arrives.
      final store = InMemoryGameStore()
        ..saveProfile(PlayerProfile.fresh(name: 'Aarav'));
      final router = buildRouter();
      addTearDown(router.dispose);
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(app(store, router, FakeRooms(backend, _them)));
      await tester.pumpAndSettle();
      router.push(
        AppRoutes.result,
        extra: ResultArgs(_result(opponentUid: _me), GameMode.sprint),
      );
      await tester.pumpAndSettle();

      await FakeRooms(backend, _me).create(
        DuelRoom.open(
          mode: GameMode.sprint,
          seed: 77,
          difficulty: Difficulty.medium,
          host: const RoomPlayer(uid: _me, name: 'Naman', avatarId: 1),
          invitedUid: _them,
          invitedName: 'Aarav',
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text('Naman challenges you'), findsOneWidget);

      await tester.tap(find.text('Accept'));
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(backend.rooms['sprint-77']!.guest?.name, 'Aarav');
    });
  });

  test('a challenge answered on one screen is answered for all of them', () {
    // Every inbox in the app reads this one set, and it has to survive being
    // read from a callback rather than watched -- otherwise a challenge
    // declined on the result screen is asked again by the tabs underneath.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(answeredChallengesProvider).add('sprint-77');

    expect(container.read(answeredChallengesProvider), contains('sprint-77'));
  });

  group('a photograph', () {
    testWidgets('is the face on the home screen, not the character under it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final store = InMemoryGameStore()
        ..saveProfile(PlayerProfile.fresh(name: 'Naman').copyWith(photo: _png));
      final router = buildRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gameStoreProvider.overrideWithValue(store),
            randomProvider.overrideWithValue(Random(2)),
          ],
          child: MaterialApp.router(theme: buildTheme(), routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // Two of them: the badge top right, and your own face on the online row.
      expect(
        find.descendant(
          of: find.byType(AvatarBadge),
          matching: find.byType(Image),
        ),
        findsNWidgets(2),
      );
    });
  });
}
