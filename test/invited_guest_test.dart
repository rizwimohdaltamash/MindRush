import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_rush/core/challenge/challenge_link.dart';
import 'package:mind_rush/core/challenge/duel_room.dart';
import 'package:mind_rush/core/models/game_mode.dart';
import 'package:mind_rush/core/questions/difficulty.dart';
import 'package:mind_rush/data/game_store.dart';
import 'package:mind_rush/main.dart';
import 'package:mind_rush/state/providers.dart';

import 'support/fake_rooms.dart';

/// The journey of someone who has never heard of MindRush: a WhatsApp link
/// arrives, they install the app, and the link has to still be waiting for
/// them on the other side of the intro and the name prompt.
void main() {
  const hostUid = 'uid-host';
  const guestUid = 'uid-guest';

  late FakeRoomBackend backend;
  late FakeRooms guestPhone;
  late DuelRoom room;

  setUp(() async {
    backend = FakeRoomBackend();
    guestPhone = FakeRooms(backend, guestUid);
    room = DuelRoom.open(
      mode: GameMode.mindSnap,
      seed: 849213,
      difficulty: Difficulty.medium,
      host: const RoomPlayer(uid: hostUid, name: 'Naman', avatarId: 1),
    );
    // The host is already sitting in the lobby with the link sent.
    await FakeRooms(backend, hostUid).create(room);
  });

  tearDown(() => backend.dispose());

  Widget app(GameStore store, {String? launchRoute}) => ProviderScope(
    overrides: [
      gameStoreProvider.overrideWithValue(store),
      randomProvider.overrideWithValue(Random(2)),
      duelRoomServiceProvider.overrideWithValue(guestPhone),
    ],
    child: MindRushApp(launchRoute: launchRoute),
  );

  void usePhoneScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// The lobby's waiting line breathes forever, so pumpAndSettle cannot be
  /// used once it is on screen.
  Future<void> tick(WidgetTester tester, [int frames = 20]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// What Android hands the app when the WhatsApp link is tapped.
  String linkFor(DuelRoom room) => ChallengeInvite(
    mode: room.mode,
    seed: room.seed,
    byName: room.host.name,
  ).uri.path;

  testWidgets('a freshly installed guest is asked their name before the lobby', (
    tester,
  ) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(
      app(InMemoryGameStore(), launchRoute: linkFor(room)),
    );
    await tester.pumpAndSettle();

    // The name prompt comes first even though a duel is waiting: a player with
    // no name would join the room as an empty seat with a face and no person.
    expect(find.text('WHAT SHOULD WE CALL YOU?'), findsOneWidget);
    expect(
      backend.rooms[room.code]!.guest,
      isNull,
      reason: 'nobody should be seated before they have a name',
    );
  });

  testWidgets('naming yourself drops you straight into the duel you were '
      'invited to, not onto home', (tester) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(
      app(InMemoryGameStore(), launchRoute: linkFor(room)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Aarav');
    await tester.pump();
    await tester.tap(find.text('Start playing'));
    await tick(tester);

    // The link survived the intro and the name prompt.
    expect(find.text('DUELS'), findsNothing, reason: 'landed on home instead');
    expect(backend.rooms[room.code]!.guest?.name, 'Aarav');
  });

  testWidgets('the name they typed is the one their friend sees', (
    tester,
  ) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(
      app(InMemoryGameStore(), launchRoute: linkFor(room)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Aarav');
    await tester.pump();
    await tester.tap(find.text('Start playing'));
    await tick(tester);

    final seated = backend.rooms[room.code]!;
    expect(seated.guest?.name, 'Aarav');
    expect(seated.opponentOf(hostUid)?.name, 'Aarav');
    expect(
      seated.status,
      RoomStatus.ready,
      reason: 'the host must see the room fill up',
    );
  });

  testWidgets('a returning player skips the name and joins immediately', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final store = InMemoryGameStore();

    // First launch: install and name yourself.
    await tester.pumpWidget(app(store));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Aarav');
    await tester.pump();
    await tester.tap(find.text('Start playing'));
    await tester.pumpAndSettle();

    // Second launch, this time from a tapped link.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app(store, launchRoute: linkFor(room)));
    // Long enough for the intro animation to run before the router appears.
    await tick(tester, 100);

    expect(find.text('WHAT SHOULD WE CALL YOU?'), findsNothing);
    expect(backend.rooms[room.code]!.guest?.name, 'Aarav');
  });

  testWidgets('an ordinary launch still opens on home', (tester) async {
    // Guards the change above: capturing a launch route must not send every
    // cold start somewhere strange.
    usePhoneScreen(tester);
    await tester.pumpWidget(app(InMemoryGameStore()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Aarav');
    await tester.pump();
    await tester.tap(find.text('Start playing'));
    await tester.pumpAndSettle();

    expect(find.text('DUELS'), findsOneWidget);
  });
}
