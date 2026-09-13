import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_rush/core/models/game_mode.dart';
import 'package:mind_rush/core/questions/question.dart';
import 'package:mind_rush/core/rating/rating_engine.dart';
import 'package:mind_rush/data/game_store.dart';
import 'package:mind_rush/data/player_profile.dart';
import 'package:mind_rush/state/providers.dart';
import 'package:mind_rush/ui/screens/duel_screen.dart';
import 'package:mind_rush/ui/screens/home_screen.dart';
import 'package:mind_rush/ui/screens/leaderboard_screen.dart';
import 'package:mind_rush/ui/screens/stats_screen.dart';
import 'package:mind_rush/ui/theme.dart';

ProviderContainer _container(GameStore store) => ProviderContainer(
  overrides: [
    gameStoreProvider.overrideWithValue(store),
    randomProvider.overrideWithValue(Random(1)),
  ],
);

Widget _wrap(GameStore store, Widget child) => ProviderScope(
  overrides: [
    gameStoreProvider.overrideWithValue(store),
    randomProvider.overrideWithValue(Random(1)),
  ],
  child: MaterialApp(theme: buildTheme(), home: child),
);

/// The app locks to portrait, so test it at a phone's shape rather than the
/// 800x600 landscape default -- otherwise the keypad alone overflows.
void _usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('persistence', () {
    test('a fresh install starts every category at 1000', () {
      final container = _container(InMemoryGameStore());
      addTearDown(container.dispose);
      final profile = container.read(profileProvider);

      for (final c in Category.values) {
        expect(profile.ratingIn(c), RatingEngine.initial);
      }
      expect(profile.streak.current, 0);
      expect(profile.history, isEmpty);
    });

    test('a profile survives a round trip through JSON', () async {
      final store = InMemoryGameStore();
      final first = _container(store);
      addTearDown(first.dispose);

      await first.read(profileProvider.notifier).setName('Naman');
      await first.read(profileProvider.notifier).setAvatar(5);

      final second = _container(store);
      addTearDown(second.dispose);
      final reloaded = second.read(profileProvider);

      expect(reloaded.displayName, 'Naman');
      expect(reloaded.avatarId, 5);
    });

    test('bot ratings persist between sessions', () async {
      final store = InMemoryGameStore();
      final first = _container(store);
      addTearDown(first.dispose);

      final roster = first.read(rosterProvider);
      roster.first.applyResult(Category.math, 7); // player gained 7
      await first.read(rosterProvider.notifier).persist();

      final second = _container(store);
      addTearDown(second.dispose);
      expect(
        second.read(rosterProvider).first.ratingIn(Category.math),
        RatingEngine.initial - 7,
      );
    });

    test('reset clears ratings, streak and history', () async {
      final store = InMemoryGameStore();
      final container = _container(store);
      addTearDown(container.dispose);

      await container.read(profileProvider.notifier).setName('Temp');
      await container.read(profileProvider.notifier).resetEverything();

      expect(
        container.read(profileProvider).displayName,
        PlayerProfile.fresh().displayName,
      );
      expect(store.loadProfile().history, isEmpty);
    });
  });

  group('home screen', () {
    testWidgets('shows all three ratings and every mode', (tester) async {
      _usePhoneScreen(tester);
      await tester.pumpWidget(_wrap(InMemoryGameStore(), const HomeScreen()));
      // The ratings count into place, so frame zero shows values on their way
      // there rather than the final ones.
      await tester.pumpAndSettle();

      for (final category in Category.values) {
        expect(
          find.byKey(ValueKey('category-${category.name}')),
          findsOneWidget,
        );
      }
      // Only the selected category's modes are listed; the rest arrive when
      // that category is chosen.
      for (final mode in GameMode.values.where(
        (m) => m.category == Category.math,
      )) {
        expect(find.text(mode.label.toUpperCase()), findsOneWidget);
      }
      expect(find.text('Mind Snap'.toUpperCase()), findsNothing);
      // All three, side by side: seeing that your memory is a hundred points
      // behind your arithmetic is the reason to tap the other tile.
      expect(find.text('1000'), findsNWidgets(Category.values.length));
    });

    testWidgets('the rating counts up again when its tile is picked', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      await tester.pumpWidget(_wrap(InMemoryGameStore(), const HomeScreen()));
      await tester.pumpAndSettle();

      // All three have finished counting and are sitting at their value.
      expect(find.text('1000'), findsNWidgets(Category.values.length));

      await tester.tap(find.byKey(const ValueKey('category-memory')));
      await tester.pump();

      // The one just picked is mid-count, so it is not showing 1000 yet. A
      // number that only ever animated on the first build of the app's life
      // is a number nobody ever sees move.
      expect(find.text('1000'), findsNWidgets(Category.values.length - 1));

      await tester.pumpAndSettle();
      expect(find.text('1000'), findsNWidgets(Category.values.length));
    });

    testWidgets('prompts for a first streak when there is none', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      await tester.pumpWidget(_wrap(InMemoryGameStore(), const HomeScreen()));
      await tester.scrollUntilVisible(
        find.text('Play a duel to start one'),
        200,
        // Home has a horizontal row of online players as well as the page
        // itself, so the page has to be named.
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Play a duel to start one'), findsOneWidget);
    });
  });

  group('duel screen', () {
    testWidgets('counts in before the clock starts', (tester) async {
      _usePhoneScreen(tester);
      await tester.pumpWidget(
        _wrap(InMemoryGameStore(), const DuelScreen(mode: GameMode.sprint)),
      );
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Sprint Duels'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('shows a question and a keypad once play begins', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      await tester.pumpWidget(
        _wrap(InMemoryGameStore(), const DuelScreen(mode: GameMode.sprint)),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('Enter answer'), findsOneWidget);
      // Both sides are named now: no more "YOU vs OPPONENT".
      expect(find.text('OPPONENT'), findsNothing);
      expect(find.byType(AvatarBadge), findsNWidgets(2));
      expect(find.text('1:00'), findsOneWidget);
      for (final digit in ['1', '5', '9', '0']) {
        expect(find.text(digit), findsWidgets);
      }
    });

    testWidgets('Fastest Fingers offers two tappable options', (tester) async {
      _usePhoneScreen(tester);
      await tester.pumpWidget(
        _wrap(
          InMemoryGameStore(),
          const DuelScreen(mode: GameMode.fastestFingers),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(
        find.text('Larger?').evaluate().isNotEmpty ||
            find.text('Smaller?').evaluate().isNotEmpty,
        isTrue,
      );
    });

    testWidgets('Mind Snap flashes the pattern, then asks for it', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      await tester.pumpWidget(
        _wrap(InMemoryGameStore(), const DuelScreen(mode: GameMode.mindSnap)),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(find.text('MEMORISE'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2500));
      expect(find.text('TAP $kMindSnapCells CELLS'), findsOneWidget);
    });
  });

  group('leaderboard', () {
    testWidgets('ranks the player among the whole roster', (tester) async {
      _usePhoneScreen(tester);
      await tester.pumpWidget(
        _wrap(InMemoryGameStore(), const LeaderboardScreen()),
      );
      await tester.pumpAndSettle();

      // Ten bots plus the player, every one of them named.
      expect(find.textContaining('(you)'), findsOneWidget);
      expect(find.byType(AvatarBadge), findsNWidgets(11));
    });

    testWidgets('sorts by rating, highest first', (tester) async {
      _usePhoneScreen(tester);
      final store = InMemoryGameStore();
      final container = _container(store);
      addTearDown(container.dispose);

      // Push three bots apart so the ordering is unambiguous.
      final roster = container.read(rosterProvider);
      roster[0].ratings[Category.math] = 1400;
      roster[1].ratings[Category.math] = 700;
      await container.read(rosterProvider.notifier).persist();

      await tester.pumpWidget(_wrap(store, const LeaderboardScreen()));
      await tester.pumpAndSettle();

      final ratings = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => int.tryParse(t.data ?? ''))
          .whereType<int>()
          .where((v) => v >= 700)
          .toList();
      final sorted = [...ratings]..sort((a, b) => b.compareTo(a));
      expect(ratings, sorted, reason: 'board must read high to low');
    });
  });

  group('stats', () {
    testWidgets('invites a first match when there is no history', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      await tester.pumpWidget(_wrap(InMemoryGameStore(), const StatsScreen()));
      await tester.pumpAndSettle();

      expect(
        find.text('Play a couple of duels to see your progress'),
        findsOneWidget,
      );
      expect(find.text('Not played yet'), findsWidgets);
    });
  });
}
