import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mind_rush/data/cloud_status.dart';
import 'package:mind_rush/data/game_store.dart';
import 'package:mind_rush/data/player_profile.dart';
import 'package:mind_rush/router/app_router.dart';
import 'package:mind_rush/state/providers.dart';
import 'package:mind_rush/ui/theme.dart';

FirebaseException _firestore(String code) =>
    FirebaseException(plugin: 'cloud_firestore', code: code);

void main() {
  group('telling one kind of failure from another', () {
    test('rules refusing a write is not the same as a bad connection', () {
      // They need different answers from whoever is looking at the phone, so
      // they must not both read "error".
      final refused = CloudMonitor()..failed(_firestore('permission-denied'));
      final dropped = CloudMonitor()..failed(_firestore('unavailable'));

      expect(refused.value.state, CloudState.refused);
      expect(dropped.value.state, CloudState.failing);
      expect(refused.value.advice, contains('security rules'));
      expect(dropped.value.advice, isNot(contains('security rules')));
    });

    test('a signed-out account reads as refused, not as a network fault', () {
      final monitor = CloudMonitor()..failed(_firestore('unauthenticated'));
      expect(monitor.value.state, CloudState.refused);
    });

    test('the server\'s own word for it is kept', () {
      // The thing worth reading out to somebody who can fix it.
      final monitor = CloudMonitor()..failed(_firestore('permission-denied'));
      expect(monitor.value.detail, 'permission-denied');
    });

    test('a plain crash is a failure, not a refusal', () {
      final monitor = CloudMonitor()..failed(StateError('no network'));
      expect(monitor.value.state, CloudState.failing);
    });
  });

  group('what the monitor remembers', () {
    test('signing in is not yet the same as saving anything', () {
      // Auth working and Firestore accepting writes are two different
      // questions; the whole point of this screen is not to conflate them.
      final monitor = CloudMonitor()..signedIn('uid-naman');

      expect(monitor.value.uid, 'uid-naman');
      expect(monitor.value.state, CloudState.offline);
    });

    test('a good write keeps the account and stamps the time', () {
      final monitor = CloudMonitor()
        ..signedIn('uid-naman')
        ..ok();

      expect(monitor.value.state, CloudState.synced);
      expect(monitor.value.uid, 'uid-naman');
      expect(monitor.value.lastSyncedAtMs, isNotNull);
      expect(monitor.value.advice, isNull, reason: 'nothing to do about it');
    });

    test('a later failure does not lose that it once worked', () {
      final monitor = CloudMonitor()
        ..signedIn('uid-naman')
        ..ok();
      final synced = monitor.value.lastSyncedAtMs;

      monitor.failed(_firestore('permission-denied'));

      expect(monitor.value.lastSyncedAtMs, synced);
      expect(monitor.value.uid, 'uid-naman');
    });
  });

  group('the settings screen says what is happening', () {
    Widget app(GoRouter router, CloudMonitor monitor) => ProviderScope(
      overrides: [
        gameStoreProvider.overrideWithValue(
          InMemoryGameStore()..saveProfile(PlayerProfile.fresh(name: 'Naman')),
        ),
        randomProvider.overrideWithValue(Random(3)),
        cloudMonitorProvider.overrideWithValue(monitor),
      ],
      child: MaterialApp.router(theme: buildTheme(), routerConfig: router),
    );

    /// The card lives in Settings, with the rest of what a player can change
    /// or needs to act on.
    Future<void> openProfile(WidgetTester tester, CloudMonitor monitor) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(app(router, monitor));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('CLOUD'), 200);
      await tester.pumpAndSettle();
    }

    testWidgets('a refused write is reported, not swallowed', (tester) async {
      // The bug this screen exists for: uploads are fire-and-forget, so a
      // build whose writes are all being refused plays exactly like one that
      // is working, and nothing ever reaches Firestore.
      final monitor = CloudMonitor()
        ..signedIn('uid-naman-1234567')
        ..failed(_firestore('permission-denied'));

      await openProfile(tester, monitor);

      expect(find.text('The server refused the write'), findsOneWidget);
      expect(find.text('permission-denied'), findsOneWidget);
      expect(find.textContaining('security rules'), findsOneWidget);
    });

    testWidgets('a working sync says so', (tester) async {
      final monitor = CloudMonitor()
        ..signedIn('uid-naman-1234567')
        ..ok();

      await openProfile(tester, monitor);

      expect(find.text('Saved to the cloud'), findsOneWidget);
      // Enough of the account to tell two phones apart while testing.
      expect(find.text('Account uid-nama'), findsOneWidget);
    });

    testWidgets('no cloud at all is a state, not a fault', (tester) async {
      await openProfile(tester, CloudMonitor());

      expect(find.text('Playing on this device only'), findsOneWidget);
      expect(find.textContaining('safe on this phone'), findsOneWidget);
    });

    testWidgets('it updates without the screen being reopened', (tester) async {
      final monitor = CloudMonitor()..signedIn('uid-naman');
      await openProfile(tester, monitor);
      expect(find.text('Playing on this device only'), findsOneWidget);

      monitor.ok();
      await tester.pumpAndSettle();

      expect(find.text('Saved to the cloud'), findsOneWidget);
    });
  });
}
