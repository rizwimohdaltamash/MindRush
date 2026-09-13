import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mind_rush/core/models/game_mode.dart';
import 'package:mind_rush/data/game_store.dart';
import 'package:mind_rush/router/app_router.dart';
import 'package:mind_rush/state/providers.dart';
import 'package:mind_rush/ui/theme.dart';

/// The real router, so a page that exists but cannot be reached still fails.
Widget _app(GameStore store, GoRouter router) => ProviderScope(
  overrides: [
    gameStoreProvider.overrideWithValue(store),
    randomProvider.overrideWithValue(Random(3)),
  ],
  child: MaterialApp.router(theme: buildTheme(), routerConfig: router),
);

void _usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Home to a duel's own page: pick the discipline, then the mode card.
Future<void> _openPoster(WidgetTester tester, GameMode mode) async {
  await tester.tap(find.byKey(ValueKey('category-${mode.category.name}')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('mode-${mode.name}')));
  await tester.pumpAndSettle();
}

void main() {
  group('a duel has its own page', () {
    testWidgets('a mode card opens it rather than starting a match', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(InMemoryGameStore(), router));
      await tester.pumpAndSettle();

      await _openPoster(tester, GameMode.mindSnap);

      expect(find.text('MIND SNAP DUELS'), findsOneWidget);
      expect(find.text('WHO CAN SNAP FASTER?'), findsOneWidget);
      expect(find.text('1 MIN DUEL'), findsOneWidget);
      // The count-in has not begun: the card is a choice of duel, and who you
      // are playing is still an open question.
      expect(find.text('Enter answer'), findsNothing);
    });

    testWidgets('every mode has a page of its own', (tester) async {
      _usePhoneScreen(tester);
      for (final mode in GameMode.values) {
        final router = buildRouter();
        addTearDown(router.dispose);
        await tester.pumpWidget(_app(InMemoryGameStore(), router));
        await tester.pumpAndSettle();

        await _openPoster(tester, mode);
        expect(
          find.text(mode.headline),
          findsOneWidget,
          reason: '${mode.name} has no page',
        );
        expect(find.text('PLAY DUEL'), findsOneWidget);
        expect(find.text('PLAY A FRIEND'), findsOneWidget);
      }
    });

    testWidgets('play starts the match', (tester) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(InMemoryGameStore(), router));
      await tester.pumpAndSettle();

      await _openPoster(tester, GameMode.sprint);
      await tester.tap(find.byKey(const ValueKey('play-duel')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();

      expect(find.text('Enter answer'), findsOneWidget);
    });

    testWidgets('leaving a match returns home, not to the page it came from', (
      tester,
    ) async {
      // The page is replaced rather than stacked on. Backing out of a duel
      // onto the poster you just pressed play on reads as the back button
      // having failed.
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(InMemoryGameStore(), router));
      await tester.pumpAndSettle();

      await _openPoster(tester, GameMode.sprint);
      await tester.tap(find.byKey(const ValueKey('play-duel')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();

      await router.routerDelegate.popRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Leave'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('DUELS'), findsOneWidget);
      // The tagline is the poster's alone; its title is also the card's.
      expect(find.text('WHO ADDS UP FASTER?'), findsNothing);
    });

    testWidgets('there is no how-to-play detour', (tester) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(InMemoryGameStore(), router));
      await tester.pumpAndSettle();

      await _openPoster(tester, GameMode.mindSnap);
      expect(
        find.textContaining('HOW TO PLAY', findRichText: true),
        findsNothing,
      );
    });

    testWidgets('back returns to home with the card still there', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(InMemoryGameStore(), router));
      await tester.pumpAndSettle();

      await _openPoster(tester, GameMode.ability);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      expect(find.text('DUELS'), findsOneWidget);
    });
  });

  group('play a friend goes to the board', () {
    testWidgets('carrying the duel that was already chosen', (tester) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(InMemoryGameStore(), router));
      await tester.pumpAndSettle();

      await _openPoster(tester, GameMode.mindSnap);
      await tester.tap(find.byKey(const ValueKey('play-a-friend')));
      await tester.pumpAndSettle();

      expect(find.text('Leaderboard'), findsOneWidget);
      expect(find.text('Search a player'), findsOneWidget);
      // Said out loud, because a challenge that goes out in a mode the player
      // cannot see chosen anywhere is a challenge they did not send.
      expect(find.text('Challenging for Mind Snap'), findsOneWidget);
      // And on that duel's own discipline, so the ratings on screen are the
      // ones about to be played for.
      expect(find.text('MEMORY'), findsWidgets);
    });

    testWidgets('the mode can be put down again', (tester) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(InMemoryGameStore(), router));
      await tester.pumpAndSettle();

      await _openPoster(tester, GameMode.mindSnap);
      await tester.tap(find.byKey(const ValueKey('play-a-friend')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Challenging for Mind Snap'), findsNothing);
      expect(find.text('Leaderboard'), findsOneWidget);
    });

    test('the location says which duel it is for', () {
      for (final mode in GameMode.values) {
        expect(
          AppRoutes.findFriend(mode),
          '${AppRoutes.ranks}?find=${mode.name}',
        );
      }
    });
  });

  group('searching the board', () {
    Future<void> openRanks(WidgetTester tester) async {
      await tester.tap(find.text('Ranks'));
      await tester.pumpAndSettle();
    }

    testWidgets('narrows it to the name typed', (tester) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(InMemoryGameStore(), router));
      await tester.pumpAndSettle();
      await openRanks(tester);

      expect(find.text('Meera'), findsOneWidget);
      expect(find.text('Rohan'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'meer');
      await tester.pumpAndSettle();

      // Case does not matter -- nobody types their friend's name the way the
      // board spells it.
      expect(find.text('Meera'), findsOneWidget);
      expect(find.text('Rohan'), findsNothing);
    });

    testWidgets('a searched player keeps the rank they actually hold', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final store = InMemoryGameStore();
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(store, router));
      await tester.pumpAndSettle();
      await openRanks(tester);

      // The row sitting fourth on the whole board.
      final fourth = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(ListView),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data)
          .toList();
      final name = fourth[fourth.indexOf('4') + 2]!;

      await tester.enterText(find.byType(TextField), name);
      await tester.pumpAndSettle();

      // Searched for by name, so the search field holds it too; the row is
      // the one inside the board.
      expect(
        find.descendant(of: find.byType(ListView), matching: find.text(name)),
        findsOneWidget,
      );
      expect(
        find.text('4'),
        findsOneWidget,
        reason: 'filtering must not renumber them 1st',
      );
    });

    testWidgets('a name nobody has says so, with the reason', (tester) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(InMemoryGameStore(), router));
      await tester.pumpAndSettle();
      await openRanks(tester);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();

      expect(find.text('Nobody by that name'), findsOneWidget);
      expect(
        find.textContaining('Only players who have opened MindRush'),
        findsOneWidget,
      );
    });

    testWidgets('the keyboard stays down when the board was opened to read', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(InMemoryGameStore(), router));
      await tester.pumpAndSettle();
      await openRanks(tester);

      expect(
        tester.widget<TextField>(find.byType(TextField)).autofocus,
        isFalse,
      );
    });
  });
}
