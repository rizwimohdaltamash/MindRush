import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mind_rush/core/players/avatar.dart';
import 'package:mind_rush/data/game_store.dart';
import 'package:mind_rush/data/photo_source.dart';
import 'package:mind_rush/data/player_profile.dart';
import 'package:mind_rush/notifications/reminder_plan.dart';
import 'package:mind_rush/router/app_router.dart';
import 'package:mind_rush/state/providers.dart';
import 'package:mind_rush/ui/theme.dart';

/// A camera that hands back whatever the test says it does.
class FakePhotos implements PhotoSource {
  FakePhotos([this.result]);

  /// Null stands for the player backing out, or a refused permission.
  String? result;
  final List<PhotoOrigin> asked = [];

  @override
  Future<String?> take(PhotoOrigin origin) async {
    asked.add(origin);
    return result;
  }
}

/// A one-pixel PNG, base64 encoded. Small, valid, and enough to prove a photo
/// is being carried rather than a placeholder.
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
    'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

void main() {
  Widget app(
    GameStore store,
    GoRouter router, {
    PhotoSource? photos,
    ReminderScheduler? scheduler,
  }) => ProviderScope(
    overrides: [
      gameStoreProvider.overrideWithValue(store),
      randomProvider.overrideWithValue(Random(3)),
      photoSourceProvider.overrideWithValue(photos ?? const NoPhotoSource()),
      if (scheduler != null)
        reminderSchedulerProvider.overrideWithValue(scheduler),
    ],
    child: MaterialApp.router(theme: buildTheme(), routerConfig: router),
  );

  GameStore named(String name) =>
      InMemoryGameStore()..saveProfile(PlayerProfile.fresh(name: name));

  Future<GoRouter> openSettings(
    WidgetTester tester,
    GameStore store, {
    PhotoSource? photos,
    ReminderScheduler? scheduler,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      app(store, router, photos: photos, scheduler: scheduler),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pumpAndSettle();
    return router;
  }

  group('the profile page', () {
    testWidgets('no longer wears a level number', (tester) async {
      // It was the rating restated in a smaller unit, and told nobody
      // anything they could not already see.
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = buildRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(app(named('Naman'), router));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Level'), findsNothing);
    });
  });

  group('choosing a face', () {
    testWidgets('the characters are characters, not initials', (tester) async {
      await openSettings(tester, named('Naman'));

      expect(find.text('ROBOTS'), findsOneWidget);
      expect(find.text('ANIMALS'), findsOneWidget);
      expect(find.text('HATS'), findsOneWidget);
      // The one thing a row of coloured initials could never do: be picked
      // out of a list without reading it.
      expect(find.text(Avatars.all.first), findsWidgets);
    });

    testWidgets('tapping one wears it', (tester) async {
      final store = named('Naman');
      await openSettings(tester, store);

      // The fox, somewhere down the animals row.
      await tester.scrollUntilVisible(find.text('🦊').first, 120);
      await tester.tap(find.text('🦊').first);
      await tester.pumpAndSettle();

      expect(Avatars.glyphFor(store.loadProfile().avatarId), '🦊');
    });

    testWidgets('a photo taken becomes the avatar', (tester) async {
      final store = named('Naman');
      final photos = FakePhotos(_png);
      await openSettings(tester, store, photos: photos);

      await tester.tap(find.text('Camera'));
      await tester.pumpAndSettle();

      expect(photos.asked, [PhotoOrigin.camera]);
      expect(store.loadProfile().photo, _png);
    });

    testWidgets('the gallery is the other way in', (tester) async {
      final store = named('Naman');
      final photos = FakePhotos(_png);
      await openSettings(tester, store, photos: photos);

      await tester.tap(find.text('Gallery'));
      await tester.pumpAndSettle();

      expect(photos.asked, [PhotoOrigin.gallery]);
      expect(store.loadProfile().photo, _png);
    });

    testWidgets('backing out of the camera keeps the avatar you had', (
      tester,
    ) async {
      final store = named('Naman');
      await store.saveProfile(
        PlayerProfile.fresh(name: 'Naman', avatarId: 4).copyWith(photo: _png),
      );
      // Cancelling, a refused permission and a camera in use all arrive here
      // as null, and none of them should cost the player their face.
      await openSettings(tester, store, photos: FakePhotos());

      await tester.tap(find.text('Camera'));
      await tester.pumpAndSettle();

      expect(store.loadProfile().photo, _png);
    });

    testWidgets('a photo can be taken off again', (tester) async {
      final store = named('Naman');
      await store.saveProfile(
        PlayerProfile.fresh(name: 'Naman').copyWith(photo: _png),
      );
      await openSettings(tester, store);

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(store.loadProfile().photo, isNull);
    });

    testWidgets('picking a character also takes the photo off', (tester) async {
      // Otherwise the face on screen would not be the thing just tapped.
      final store = named('Naman');
      await store.saveProfile(
        PlayerProfile.fresh(name: 'Naman').copyWith(photo: _png),
      );
      await openSettings(tester, store);

      await tester.scrollUntilVisible(find.text('🤖').first, 120);
      await tester.tap(find.text('🤖').first);
      await tester.pumpAndSettle();

      expect(store.loadProfile().photo, isNull);
    });
  });

  group('the notification switch', () {
    testWidgets('is on to begin with', (tester) async {
      // A streak game that never reminds you is a streak you lose.
      final store = named('Naman');
      await openSettings(tester, store);

      expect(store.loadProfile().remindersEnabled, isTrue);
      await tester.scrollUntilVisible(find.byType(Switch), 120);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('turning it off cancels what is already queued', (
      tester,
    ) async {
      // Not merely stopping the next one being scheduled: an alarm the player
      // has just switched off must not still go off tonight.
      final store = named('Naman');
      final scheduler = RecordingScheduler();
      await openSettings(tester, store, scheduler: scheduler);

      await tester.scrollUntilVisible(find.byType(Switch), 120);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(store.loadProfile().remindersEnabled, isFalse);
      expect(scheduler.cancelCount, greaterThan(0));
      expect(scheduler.scheduled, isEmpty);
    });

    testWidgets('the answer survives leaving the screen', (tester) async {
      final store = named('Naman');
      await openSettings(tester, store, scheduler: RecordingScheduler());

      await tester.scrollUntilVisible(find.byType(Switch), 120);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // Read back off the store rather than the widget, which is what a
      // relaunch would do.
      expect(store.loadProfile().remindersEnabled, isFalse);
    });
  });

  group('signing out', () {
    testWidgets('says what it costs before doing it', (tester) async {
      // There is no password behind an anonymous account, so this is not a
      // door that can be walked back through. Saying anything softer would
      // be a lie.
      final store = named('Naman');
      await openSettings(tester, store);

      await tester.scrollUntilVisible(find.text('Sign out'), 200);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(find.text('Sign out?'), findsOneWidget);
      expect(find.textContaining('no password'), findsOneWidget);
      expect(
        store.loadProfile().displayName,
        'Naman',
        reason: 'nothing happens until it is confirmed',
      );
    });

    testWidgets('cancelling leaves everything alone', (tester) async {
      final store = named('Naman');
      await openSettings(tester, store);

      await tester.scrollUntilVisible(find.text('Sign out'), 200);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(store.loadProfile().displayName, 'Naman');
    });

    testWidgets('confirming clears the player off this device', (tester) async {
      final store = named('Naman');
      await openSettings(tester, store);

      await tester.scrollUntilVisible(find.text('Sign out'), 200);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await tester.pumpAndSettle();

      expect(store.loadProfile().displayName, isEmpty);
      expect(
        store.loadProfile().needsOnboarding,
        isTrue,
        reason: 'which is what puts them back on the welcome screen',
      );
    });
  });
}
