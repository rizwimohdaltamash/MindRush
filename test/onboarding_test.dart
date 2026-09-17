import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_rush/core/players/avatar.dart';
import 'package:mind_rush/data/game_store.dart';
import 'package:mind_rush/data/player_profile.dart';
import 'package:mind_rush/data/sign_in.dart';
import 'package:mind_rush/main.dart';
import 'package:mind_rush/state/providers.dart';
import 'package:mind_rush/ui/theme.dart';

import 'support/fake_sign_in.dart';

Widget _app(GameStore store, {SignInGateway? signIn}) => ProviderScope(
  overrides: [
    gameStoreProvider.overrideWithValue(store),
    randomProvider.overrideWithValue(Random(2)),
    signInGatewayProvider.overrideWithValue(signIn ?? FakeSignIn()),
  ],
  child: const MindRushApp(),
);

void _usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Through the account picker and into the game.
Future<void> _signIn(WidgetTester tester) async {
  await tester.tap(find.text('Continue with Google'));
  await tester.pumpAndSettle();
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

  testWidgets('a first launch asks you to sign in, not to play', (
    tester,
  ) async {
    _usePhoneScreen(tester);
    await tester.pumpWidget(_app(InMemoryGameStore()));
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('DUELS'), findsNothing);
    // The name is not asked for: it arrives with the account.
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('Google account'), findsOneWidget);
  });

  testWidgets('the name comes from the account that signed in', (tester) async {
    _usePhoneScreen(tester);
    final store = InMemoryGameStore();
    await tester.pumpWidget(
      _app(
        store,
        signIn: FakeSignIn(
          user: const SignedInUser(uid: 'uid-google', name: 'Naman'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _signIn(tester);

    expect(find.text('DUELS'), findsOneWidget);
    // Home carries a face rather than the name in full. It is a character
    // now, not an initial: a board of lettered discs is a spreadsheet.
    expect(
      find.text(Avatars.glyphFor(store.loadProfile().avatarId)),
      findsWidgets,
    );
    expect(store.loadProfile().displayName, 'Naman');
  });

  testWidgets('a refused sign-in says so and stays put', (tester) async {
    _usePhoneScreen(tester);
    final store = InMemoryGameStore();
    final gateway = FakeSignIn(refuses: true);
    await tester.pumpWidget(_app(store, signIn: gateway));
    await tester.pumpAndSettle();

    await _signIn(tester);

    // Backing out of the picker is not an error to be swallowed: without
    // something on screen the button would simply look broken.
    expect(find.textContaining('Could not sign in'), findsOneWidget);
    expect(find.text('DUELS'), findsNothing);
    expect(store.loadProfile().needsOnboarding, isTrue);
    expect(gateway.prompts, 1);

    // And it can be tried again.
    gateway.refuses = false;
    await _signIn(tester);
    expect(find.text('DUELS'), findsOneWidget);
  });

  testWidgets('onboarding asks for nothing but the account', (tester) async {
    // The avatar grid used to be here, which made choosing a face the first
    // thing the game asked of somebody who had not yet played it. It lives in
    // Settings now, so the only thing on this screen is the way in.
    _usePhoneScreen(tester);
    await tester.pumpWidget(_app(InMemoryGameStore()));
    await tester.pumpAndSettle();

    expect(find.text('PICK AN AVATAR'), findsNothing);
    expect(find.byType(AvatarBadge), findsNothing);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('the avatar comes from the account, and is stable', (
    tester,
  ) async {
    // Nobody picks one any more, so the uid has to supply it -- and it has to
    // supply the same one every time, or reinstalling would change the
    // player's face on the leaderboard.
    _usePhoneScreen(tester);
    final first = InMemoryGameStore();
    await tester.pumpWidget(_app(first));
    await tester.pumpAndSettle();
    await _signIn(tester);

    final chosen = first.loadProfile().avatarId;
    expect(chosen, inInclusiveRange(0, Avatars.count - 1));

    final second = InMemoryGameStore();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_app(second));
    await tester.pumpAndSettle();
    await _signIn(tester);

    expect(second.loadProfile().avatarId, chosen);
  });

  testWidgets('a returning player is never asked again', (tester) async {
    _usePhoneScreen(tester);
    final store = InMemoryGameStore();

    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    await _signIn(tester);

    // Relaunch against the same storage. The saved name is what stands in for
    // the cached credential here: a player who has signed in once has one.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsNothing);
    expect(find.text('DUELS'), findsOneWidget);
  });

  testWidgets('the leaderboard shows the real name, not a placeholder', (
    tester,
  ) async {
    _usePhoneScreen(tester);
    final store = InMemoryGameStore();
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    await _signIn(tester);

    await tester.tap(find.text('Ranks'));
    await tester.pumpAndSettle();

    expect(find.text('Naman  (you)'), findsOneWidget);
    expect(find.textContaining('Player'), findsNothing);
  });
}
