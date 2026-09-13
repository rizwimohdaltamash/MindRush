import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mind_rush/core/models/game_mode.dart';
import 'package:mind_rush/router/app_router.dart';
import 'package:mind_rush/data/game_store.dart';
import 'package:mind_rush/state/providers.dart';
import 'package:mind_rush/ui/theme.dart';

/// Drives the real router, not individual screens, so a route that exists but
/// cannot be reached still fails the test.
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

/// Home filters modes by category and a mode card opens that duel's own page,
/// so starting a match is three taps: the discipline, the mode, then play.
/// Keyed finders because the category name also appears as a chip on each
/// mode card.
Future<void> _openMode(WidgetTester tester, GameMode mode) async {
  await tester.tap(find.byKey(ValueKey('category-${mode.category.name}')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('mode-${mode.name}')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('play-duel')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every tab is reachable from the bottom bar', (tester) async {
    _usePhoneScreen(tester);
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(InMemoryGameStore(), router));
    await tester.pumpAndSettle();

    for (final tab in ['Home', 'Stats', 'Ranks', 'Profile']) {
      expect(find.text(tab), findsOneWidget, reason: '$tab tab missing');
    }

    await tester.tap(find.text('Stats'));
    await tester.pumpAndSettle();
    expect(find.text('RATING OVER TIME'), findsOneWidget);

    await tester.tap(find.text('Ranks'));
    await tester.pumpAndSettle();
    expect(find.textContaining('(you)'), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    // Choosing a face moved to Settings; RATINGS is what Profile is for.
    expect(find.text('RATINGS'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('DUELS'), findsOneWidget);
  });

  testWidgets('the header profile button switches tab instead of stacking', (
    tester,
  ) async {
    _usePhoneScreen(tester);
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(InMemoryGameStore(), router));
    await tester.pumpAndSettle();

    // The header avatar doubles as the route to Profile.
    await tester.tap(find.byType(AvatarBadge).first);
    await tester.pumpAndSettle();

    // Choosing a face moved to Settings; RATINGS is what Profile is for.
    expect(find.text('RATINGS'), findsOneWidget);
    // A pushed shell would render a second navigation bar over the first.
    expect(find.text('Ranks'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('home to duel to result to home, with the match recorded', (
    tester,
  ) async {
    _usePhoneScreen(tester);
    final store = InMemoryGameStore();
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(store, router));
    await tester.pumpAndSettle();

    await _openMode(tester, GameMode.sprint);

    // Count-in, and the nav bar must be gone -- nothing competes with the clock.
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Ranks'), findsNothing);

    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump();
    expect(find.text('1:00'), findsOneWidget);
    expect(find.text('Enter answer'), findsOneWidget);

    // Run the clock out with somebody still holding the phone -- ten seconds
    // of nothing at all now calls a duel off, so a full minute has to be
    // played rather than waited through. The taps land on the scoreboard and
    // answer nothing; they are only proof of life.
    for (var i = 0; i < 11; i++) {
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      await tester.tapAt(const Offset(200, 60));
    }
    await tester.pumpAndSettle();

    // The first duel now crosses day one of the ladder, so the milestone
    // lands over the result. Dismiss it before reaching what is behind.
    if (find.text('Nice').evaluate().isNotEmpty) {
      await tester.tap(find.text('Nice'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Back to Home'), findsOneWidget);
    expect(find.text('Play a friend'), findsOneWidget);
    expect(
      store.loadProfile().history.length,
      1,
      reason: 'the finished match must be persisted',
    );

    await tester.tap(find.text('Back to Home'));
    await tester.pumpAndSettle();
    expect(find.text('DUELS'), findsOneWidget);
    expect(find.text('Ranks'), findsOneWidget, reason: 'nav bar is back');
  });

  testWidgets('leaving mid-match asks first and does not rate it', (
    tester,
  ) async {
    _usePhoneScreen(tester);
    final store = InMemoryGameStore();
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(store, router));
    await tester.pumpAndSettle();

    await _openMode(tester, GameMode.sprint);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump(const Duration(seconds: 5));

    // pumpAndSettle cannot be used from here: the match ticker schedules a
    // frame every pump, so settling would run the full minute out and land on
    // the result screen. Pump in fixed steps instead.
    Future<void> settleDialog() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    // Android back / swipe back.
    final popped = await router.routerDelegate.popRoute();
    await settleDialog();
    expect(popped, isTrue);
    expect(find.text('Leave the duel?'), findsOneWidget);

    await tester.tap(find.text('Keep playing'));
    await settleDialog();
    expect(
      find.text('Enter answer'),
      findsOneWidget,
      reason: 'declining must return to the duel, still running',
    );

    await router.routerDelegate.popRoute();
    await settleDialog();
    await tester.tap(find.text('Leave'));
    await settleDialog();
    await tester.pumpAndSettle();

    expect(find.text('DUELS'), findsOneWidget);
    expect(
      store.loadProfile().history,
      isEmpty,
      reason: 'an abandoned match must not count',
    );
  });

  group('AppRoutes is the single source of truth for paths', () {
    test('builds duel locations that match the declared pattern', () {
      final prefix = AppRoutes.duelPattern.split(':').first; // '/duel/'
      for (final mode in GameMode.values) {
        expect(AppRoutes.duel(mode), '$prefix${mode.name}');
        expect(AppRoutes.duel(mode, seed: 42), '$prefix${mode.name}?seed=42');
      }
    });

    test('the tab list matches the shell branch order', () {
      expect(AppRoutes.tabs, [
        AppRoutes.home,
        AppRoutes.stats,
        AppRoutes.ranks,
        AppRoutes.profile,
      ]);
    });
  });

  testWidgets('a seeded duel location opens that exact match', (tester) async {
    _usePhoneScreen(tester);
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(InMemoryGameStore(), router));
    await tester.pumpAndSettle();

    router.push(AppRoutes.duel(GameMode.mindSnap, seed: 4242));
    await tester.pumpAndSettle();
    expect(find.text('Mind Snap'), findsOneWidget);
  });

  testWidgets('an unknown mode falls back to home instead of crashing', (
    tester,
  ) async {
    _usePhoneScreen(tester);
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(InMemoryGameStore(), router));
    await tester.pumpAndSettle();

    router.push('/duel/doesNotExist');
    await tester.pumpAndSettle();
    expect(find.text('DUELS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
