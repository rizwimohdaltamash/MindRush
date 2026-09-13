import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mind_rush/core/challenge/duel_room.dart';
import 'package:mind_rush/core/challenge/friend_duel.dart';
import 'package:mind_rush/core/challenge/live_opponent.dart';
import 'package:mind_rush/core/models/game_mode.dart';
import 'package:mind_rush/core/questions/difficulty.dart';
import 'package:mind_rush/data/game_store.dart';
import 'package:mind_rush/data/player_profile.dart';
import 'package:mind_rush/router/app_router.dart';
import 'package:mind_rush/state/providers.dart';
import 'package:mind_rush/ui/screens/duel_screen.dart';
import 'package:mind_rush/ui/screens/result_screen.dart';
import 'package:mind_rush/ui/theme.dart';
import 'package:mind_rush/ui/widgets/pattern_grid.dart';

import 'support/fake_rooms.dart';

Widget _app(GameStore store, GoRouter router) => ProviderScope(
  overrides: [
    gameStoreProvider.overrideWithValue(store),
    randomProvider.overrideWithValue(Random(5)),
  ],
  child: MaterialApp.router(theme: buildTheme(), routerConfig: router),
);

void _usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Into a live match of [mode], past the count-in.
Future<void> _startMatch(WidgetTester tester, GameMode mode) async {
  await tester.tap(find.byKey(ValueKey('category-${mode.category.name}')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('mode-${mode.name}')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('play-duel')));
  await tester.pumpAndSettle();
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pump();
}

/// What the grace countdown currently reads.
String _countdown(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('grace-count'))).data!;

/// Home button, lock screen, or a swipe out of the app switcher: the app goes
/// to the background. Stepped through the legal transitions, because the
/// binding asserts on a jump straight to paused.
void _sendToBackground(WidgetTester tester) {
  for (final state in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

/// Moves the clock on without settling -- the match ticker never stops, so
/// pumpAndSettle would play the whole minute out.
Future<void> _wait(WidgetTester tester, Duration d) async {
  await tester.pump();
  await tester.pump(d);
}

void main() {
  late GameStore store;
  late GoRouter router;

  Future<void> openDuel(WidgetTester tester, [GameMode? mode]) async {
    _usePhoneScreen(tester);
    store = InMemoryGameStore()
      ..saveProfile(PlayerProfile.fresh(name: 'Naman'));
    router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(store, router));
    await tester.pumpAndSettle();
    await _startMatch(tester, mode ?? GameMode.sprint);
  }

  group('a player who has stopped playing', () {
    testWidgets('is asked whether they are still there', (tester) async {
      await openDuel(tester);

      // Nine seconds of nothing is still a player thinking.
      await _wait(tester, const Duration(seconds: 9));
      expect(find.text('Still there?'), findsNothing);

      await _wait(tester, const Duration(seconds: 2));
      expect(find.text('Still there?'), findsOneWidget);
      // With the seconds it has left on it. Keyed, because a keypad on the
      // same screen has a five on it too.
      expect(_countdown(tester), '5');
    });

    testWidgets('sees the count run down', (tester) async {
      await openDuel(tester);
      await _wait(tester, DuelScreen.idleAfter + const Duration(seconds: 1));
      expect(_countdown(tester), '5');

      await _wait(tester, const Duration(seconds: 2));
      expect(_countdown(tester), '3');

      await _wait(tester, const Duration(seconds: 1));
      expect(_countdown(tester), '2');
    });

    testWidgets('has the duel called off when the count runs out', (
      tester,
    ) async {
      await openDuel(tester);
      await _wait(tester, const Duration(seconds: 11));
      expect(find.text('Still there?'), findsOneWidget);

      await _wait(tester, const Duration(seconds: 6));
      await tester.pumpAndSettle();

      expect(find.text('GAME ABORTED'), findsOneWidget);
      expect(find.textContaining('You stopped answering'), findsOneWidget);

      final shown = tester
          .widget<ResultScreen>(find.byType(ResultScreen))
          .result;
      expect(shown.playerScore, 0);
      expect(
        shown.opponentScore,
        greaterThan(0),
        reason: 'the other side kept playing, so their score stands',
      );
      expect(
        shown.ratingDelta,
        0,
        reason: 'a called-off duel rates nobody, winner included',
      );
    });

    testWidgets('and none of it is saved', (tester) async {
      await openDuel(tester);
      await _wait(tester, const Duration(seconds: 17));
      await tester.pumpAndSettle();

      final profile = store.loadProfile();
      // A match that counted towards a streak without being played would be a
      // way of keeping one by opening a duel and walking off.
      expect(profile.history, isEmpty);
      expect(profile.streak.current, 0);
      expect(profile.ratingIn(GameMode.sprint.category), 1000);
    });
  });

  group('a player who is still there', () {
    testWidgets('makes the warning go away by touching anything', (
      tester,
    ) async {
      await openDuel(tester);
      await _wait(tester, const Duration(seconds: 11));
      expect(find.text('Still there?'), findsOneWidget);

      // Not an answer -- a finger on the scoreboard. The question is whether
      // somebody is holding the phone.
      await tester.tapAt(const Offset(200, 60));
      await _wait(tester, const Duration(milliseconds: 100));

      expect(find.text('Still there?'), findsNothing);
      expect(find.text('GAME ABORTED'), findsNothing);
    });

    testWidgets('is never asked at all while they keep answering', (
      tester,
    ) async {
      await openDuel(tester, GameMode.mindSnap);

      // Well past the idle window, a tap every few seconds.
      for (var i = 0; i < 5; i++) {
        await _wait(tester, const Duration(seconds: 6));
        await tester.tapAt(tester.getCenter(find.byType(PatternGrid)));
      }

      expect(find.text('Still there?'), findsNothing);
      expect(find.text('GAME ABORTED'), findsNothing);
    });

    testWidgets('is left alone the moment they are on the board', (
      tester,
    ) async {
      await openDuel(tester, GameMode.mindSnap);

      // Memorise, then reproduce the pattern: this puts points on the board.
      await tester.pump(const Duration(milliseconds: 2500));
      final grid = find.byType(PatternGrid);
      final lit = tester.widget<PatternGrid>(grid).round.litCells;
      final cells = find.descendant(
        of: grid,
        matching: find.byType(GestureDetector),
      );
      for (final index in lit) {
        await tester.tap(cells.at(index));
        await tester.pump();
      }

      // Twice the idle window with the phone untouched. A player who has
      // scored and then goes quiet is losing, not absent, and losing is
      // something the rating is allowed to say.
      await _wait(tester, const Duration(seconds: 20));

      expect(find.text('Still there?'), findsNothing);
      expect(find.text('GAME ABORTED'), findsNothing);
    });

    testWidgets('is not called off while reading the leave dialog', (
      tester,
    ) async {
      await openDuel(tester);
      await _wait(tester, const Duration(seconds: 3));

      await router.routerDelegate.popRoute();
      // Stepped rather than settled: the match ticker never stops, so
      // settling would play the whole minute out.
      await _wait(tester, const Duration(milliseconds: 400));
      expect(find.text('Leave the duel?'), findsOneWidget);

      // Somebody reading a question is plainly present.
      await _wait(tester, const Duration(seconds: 20));
      expect(find.text('Leave the duel?'), findsOneWidget);
      expect(find.text('GAME ABORTED'), findsNothing);
    });
  });

  group('a friend duel somebody walks out of', () {
    const code = 'sprint-77';
    late FakeRoomBackend backend;

    /// Both phones in one room, this one sitting in the guest seat, with the
    /// match already live.
    Future<void> startFriendDuel(
      WidgetTester tester, {
      bool throughCountIn = true,
    }) async {
      _usePhoneScreen(tester);
      backend = FakeRoomBackend();
      addTearDown(backend.dispose);

      const room = DuelRoom(
        code: code,
        mode: GameMode.sprint,
        seed: 77,
        difficulty: Difficulty.medium,
        host: RoomPlayer(uid: 'uid-zoya', name: 'Zoya', avatarId: 1),
        guest: RoomPlayer(uid: 'uid-me', name: 'Naman', avatarId: 0),
        status: RoomStatus.playing,
      );
      backend.put(room);

      store = InMemoryGameStore()
        ..saveProfile(PlayerProfile.fresh(name: 'Naman'));
      router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(store, router));
      await tester.pumpAndSettle();

      router.push(
        AppRoutes.friendDuel,
        extra: FriendDuel(
          room: room,
          service: FakeRooms(backend, 'uid-me'),
          feed: LiveOpponentFeed(),
        ),
      );
      await tester.pumpAndSettle();
      if (!throughCountIn) return;
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();
    }

    testWidgets('says so in the room rather than going quiet', (tester) async {
      await startFriendDuel(tester);

      await router.routerDelegate.popRoute();
      await _wait(tester, const Duration(milliseconds: 400));
      expect(find.text('Leave the duel?'), findsOneWidget);

      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      final me = backend.rooms[code]!.guest!;
      expect(
        me.aborted,
        isTrue,
        reason: 'a quiet nought would read as a friend who played and lost',
      );
      expect(me.finished, isTrue);
    });

    testWidgets('is told even when the leaver never saw a question', (
      tester,
    ) async {
      await startFriendDuel(tester, throughCountIn: false);
      expect(find.text('3'), findsOneWidget, reason: 'still counting in');

      await router.routerDelegate.popRoute();
      await tester.pumpAndSettle();

      // Nothing was asked on the way out: this player has answered nothing
      // and has nothing at stake. The friend does, and they are told.
      expect(find.text('Leave the duel?'), findsNothing);
      expect(
        backend.rooms[code]!.guest!.aborted,
        isTrue,
        reason:
            'the friend would otherwise play a minute against a name that '
            'left before the clock started',
      );
    });

    testWidgets('counts putting the phone away as walking out', (tester) async {
      await startFriendDuel(tester);

      _sendToBackground(tester);
      await tester.pumpAndSettle();

      expect(
        backend.rooms[code]!.guest!.aborted,
        isTrue,
        reason: 'the friend cannot see a home screen being pressed',
      );
      expect(
        find.text('GAME ABORTED'),
        findsOneWidget,
        reason:
            'coming back to a duel the other side has been told is over '
            'would let this phone play on alone',
      );
    });

    testWidgets('ends the duel for the player who stayed', (tester) async {
      await startFriendDuel(tester);

      // The other phone leaves, twenty-seven points into the minute.
      final room = backend.rooms[code]!;
      backend.put(
        room.copyWith(
          host: room.host.copyWith(score: 27, finished: true, aborted: true),
        ),
      );
      await _wait(tester, const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text('GAME ABORTED'), findsOneWidget);
      expect(find.textContaining('Zoya stopped playing'), findsOneWidget);

      final shown = tester
          .widget<ResultScreen>(find.byType(ResultScreen))
          .result;
      expect(
        shown.opponentScore,
        27,
        reason: 'they really did score that before walking off',
      );
      expect(
        shown.ratingDelta,
        0,
        reason: 'being deserted is not the same as winning',
      );
      expect(store.loadProfile().history, isEmpty);
    });
  });

  testWidgets('a match against a bot survives a phone call', (tester) async {
    await openDuel(tester);
    await _wait(tester, const Duration(seconds: 3));

    _sendToBackground(tester);
    await _wait(tester, const Duration(milliseconds: 100));

    // Nobody is sitting on the other side of this one waiting out a minute,
    // so an interruption costs the player their match and nothing more.
    expect(find.text('GAME ABORTED'), findsNothing);
  });
}
