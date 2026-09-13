import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_rush/core/players/avatar.dart';
import 'package:mind_rush/data/game_store.dart';
import 'package:mind_rush/data/player_profile.dart';
import 'package:mind_rush/main.dart';
import 'package:mind_rush/state/providers.dart';

Widget _app(GameStore store) => ProviderScope(
  overrides: [
    gameStoreProvider.overrideWithValue(store),
    randomProvider.overrideWithValue(Random(2)),
  ],
  child: const MindRushApp(),
);

void _usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('a fresh profile has no name yet', () {
    // "Player" used to be the default, which put a placeholder on the
    // leaderboard between Aryan and Meera and read as a bug.
    expect(PlayerProfile.fresh().displayName, isEmpty);
    expect(PlayerProfile.fresh().needsOnboarding, isTrue);
    expect(PlayerProfile.fresh(name: 'Naman').needsOnboarding, isFalse);
  });

  test('whitespace is not a name', () {
    expect(PlayerProfile.fresh(name: '   ').needsOnboarding, isTrue);
  });

  testWidgets('a first launch asks for a name instead of the home screen', (
    tester,
  ) async {
    _usePhoneScreen(tester);
    await tester.pumpWidget(_app(InMemoryGameStore()));
    await tester.pumpAndSettle();

    expect(find.text('WHAT SHOULD WE CALL YOU?'), findsOneWidget);
    expect(find.text('Start playing'), findsOneWidget);
    expect(find.text('DUELS'), findsNothing);
    // The point of doing this locally rather than behind a sign-in.
    expect(find.textContaining('No account needed'), findsOneWidget);
  });

  testWidgets('cannot start without typing something', (tester) async {
    _usePhoneScreen(tester);
    await tester.pumpWidget(_app(InMemoryGameStore()));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start playing'),
    );
    expect(button.onPressed, isNull, reason: 'disabled until named');

    await tester.enterText(find.byType(TextField), 'Naman');
    await tester.pump();

    final enabled = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start playing'),
    );
    expect(enabled.onPressed, isNotNull);
  });

  testWidgets('naming yourself drops you straight into the game', (
    tester,
  ) async {
    _usePhoneScreen(tester);
    final store = InMemoryGameStore();
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Naman');
    await tester.pump();
    await tester.tap(find.text('Start playing'));
    await tester.pumpAndSettle();

    expect(find.text('DUELS'), findsOneWidget);
    // Home carries a face rather than the name in full. It is a character
    // now, not an initial: a board of lettered discs is a spreadsheet.
    expect(find.text(Avatars.glyphFor(0)), findsWidgets);
    expect(store.loadProfile().displayName, 'Naman');
  });

  testWidgets('an avatar chosen during onboarding is the one that sticks', (
    tester,
  ) async {
    _usePhoneScreen(tester);
    final store = InMemoryGameStore();
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Naman');
    await tester.pump();
    // Fifth avatar in the picker.
    await tester.tap(find.byType(GestureDetector).at(4));
    await tester.pump();
    await tester.tap(find.text('Start playing'));
    await tester.pumpAndSettle();

    expect(store.loadProfile().avatarId, 4);
  });

  testWidgets('a returning player is never asked again', (tester) async {
    _usePhoneScreen(tester);
    final store = InMemoryGameStore();

    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Naman');
    await tester.pump();
    await tester.tap(find.text('Start playing'));
    await tester.pumpAndSettle();

    // Relaunch against the same storage.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    expect(find.text('WHAT SHOULD WE CALL YOU?'), findsNothing);
    expect(find.text('DUELS'), findsOneWidget);
  });

  testWidgets('the leaderboard shows the real name, not a placeholder', (
    tester,
  ) async {
    _usePhoneScreen(tester);
    final store = InMemoryGameStore();
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Naman');
    await tester.pump();
    await tester.tap(find.text('Start playing'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ranks'));
    await tester.pumpAndSettle();

    expect(find.text('Naman  (you)'), findsOneWidget);
    expect(find.textContaining('Player'), findsNothing);
  });
}
