import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mind_rush/core/rating/streak.dart';
import 'package:mind_rush/data/game_store.dart';
import 'package:mind_rush/data/player_profile.dart';
import 'package:mind_rush/router/app_router.dart';
import 'package:mind_rush/state/providers.dart';
import 'package:mind_rush/ui/theme.dart';
import 'package:mind_rush/ui/widgets/streak_flare.dart';

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

/// A player mid-streak, so the ladder has both earned and locked rungs.
GameStore _onStreak(int current, int best) => InMemoryGameStore()
  ..saveProfile(
    PlayerProfile.fresh(name: 'Naman').copyWith(
      streak: StreakState(
        current: current,
        best: best,
        lastPlayedDay: StreakCalculator.dayNumber(DateTime.now()),
      ),
    ),
  );

/// Home now has two scrollables -- the page, and the horizontal row of who is
/// online -- so the page has to be named or scrollUntilVisible cannot tell
/// which one to drive.
Finder get _page => find.byType(Scrollable).first;

void main() {
  group('the streak card', () {
    testWidgets('opens the ladder when tapped', (tester) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(_app(_onStreak(4, 4), router));
      await tester.pumpAndSettle();

      // It used to be a dead card: a number with nothing behind it.
      await tester.scrollUntilVisible(
        find.text('Daily Streak'),
        200,
        scrollable: _page,
      );
      await tester.tap(find.text('Daily Streak'));
      await tester.pumpAndSettle();

      expect(find.text('Streak Rewards'), findsOneWidget);
    });

    testWidgets('points at the next reward rather than a stale best', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(_app(_onStreak(4, 4), router));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Daily Streak'),
        200,
        scrollable: _page,
      );

      // Day 5 is the next rung, worth 120.
      expect(find.text('1 day to +120 XP'), findsOneWidget);
    });

    testWidgets('the level chip is gone, XP is in its place', (tester) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(_app(_onStreak(7, 7), router));
      await tester.pumpAndSettle();

      expect(find.textContaining('Lv '), findsNothing);
      expect(find.text('450 XP'), findsOneWidget);
    });
  });

  group('the ways in', () {
    Future<void> open(WidgetTester tester) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(_onStreak(4, 4), router));
      await tester.pumpAndSettle();
    }

    testWidgets('the streak chip on home opens the ladder', (tester) async {
      await open(tester);

      await tester.tap(find.byKey(const ValueKey('streak-chip')));
      await tester.pumpAndSettle();

      expect(find.text('Streak Rewards'), findsOneWidget);
    });

    testWidgets('so does the XP beside it', (tester) async {
      // It is the same number counted differently, so it answers to the same
      // page rather than being a figure with nothing behind it.
      await open(tester);

      await tester.tap(find.byKey(const ValueKey('xp-chip')));
      await tester.pumpAndSettle();

      expect(find.text('Streak Rewards'), findsOneWidget);
    });

    testWidgets('and the streak card on the profile', (tester) async {
      await open(tester);
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('4 day streak'));
      await tester.pumpAndSettle();

      expect(find.text('Streak Rewards'), findsOneWidget);
    });
  });

  group('the ladder', () {
    testWidgets('marks what has been earned and what has not', (tester) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(_app(_onStreak(5, 5), router));
      await tester.pumpAndSettle();
      router.go(AppRoutes.streak);
      await tester.pumpAndSettle();

      expect(
        find.text('DAY 1'),
        findsOneWidget,
        reason: 'the ladder starts on the first day a player turns up',
      );
      expect(find.text('DAY 3'), findsOneWidget);
      expect(find.text('Best 5 · 200 XP earned'), findsOneWidget);
      // Days one, three and five cleared, so three ticks.
      expect(find.byIcon(Icons.check_rounded), findsNWidgets(3));

      // The whole ladder is there, not just the part in view.
      await tester.scrollUntilVisible(find.text('DAY 100'), 250);
      expect(find.text('DAY 100'), findsOneWidget);
    });

    testWidgets('a fresh player sees the whole ladder locked', (tester) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _app(
          InMemoryGameStore()..saveProfile(PlayerProfile.fresh(name: 'N')),
          router,
        ),
      );
      await tester.pumpAndSettle();
      router.go(AppRoutes.streak);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(find.text('Best 0 · 0 XP earned'), findsOneWidget);
    });
  });

  group('the daily flare', () {
    testWidgets('counts to the streak and then gets out of the way', (
      tester,
    ) async {
      var done = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: StreakFlare(days: 7, onDone: () => done = true),
        ),
      );

      await tester.pump(const Duration(milliseconds: 50));
      expect(done, isFalse);
      expect(find.text('DAY STREAK'), findsOneWidget);

      await tester.pump(StreakFlare.duration);
      await tester.pump();
      expect(find.text('7'), findsOneWidget);
      expect(
        done,
        isTrue,
        reason: 'the result screen is waiting on this to finish',
      );
    });

    testWidgets('reads differently on the very first day', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: StreakFlare(days: 1, onDone: () {}),
        ),
      );
      await tester.pump(StreakFlare.duration);
      expect(find.text('A streak begins.'), findsOneWidget);
    });
  });
}
