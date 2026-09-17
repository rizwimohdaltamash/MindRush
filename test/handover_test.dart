import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_rush/data/game_store.dart';
import 'package:mind_rush/state/providers.dart';
import 'package:mind_rush/ui/screens/splash_screen.dart';
import 'package:mind_rush/ui/screens/welcome_screen.dart';
import 'package:mind_rush/ui/theme.dart';

import 'support/fake_sign_in.dart';
import 'support/test_fonts.dart';

/// The join between the intro and the sign-in screen.
///
/// Tapping the icon should look like one continuous thing: three arcs arrive,
/// the mark turns, and then a button rises into place under a logo that never
/// moved. That only holds while the intro's last frame and the sign-in
/// screen's first frame are the *same picture* -- so this shoots both and
/// compares the files.
///
/// It is a strict test on purpose. A nudged font size, a changed padding or a
/// SafeArea added to one side and not the other all break the illusion, and
/// all of them are easy to do by accident and hard to notice by eye.
///
/// Regenerate with:
///   flutter test test/handover_test.dart --update-goldens
void main() {
  setUpAll(loadRealFonts);

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('the intro holds its last frame', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        debugShowCheckedModeBanner: false,
        home: SplashScreen(onFinished: () {}),
      ),
    );

    // A hair short of the end: the frame the player is looking at when the
    // app decides the intro is over.
    await tester.pump(
      SplashScreen.duration - const Duration(milliseconds: 1),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/handover_intro.png'),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('the sign-in screen opens on it', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameStoreProvider.overrideWithValue(InMemoryGameStore()),
          signInGatewayProvider.overrideWithValue(FakeSignIn()),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          debugShowCheckedModeBanner: false,
          home: const WelcomeScreen(),
        ),
      ),
    );

    // The very first frame, before the button has begun to arrive.
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/handover_welcome.png'),
    );
  });

  test('and they are the same picture', () {
    final intro = File('test/goldens/handover_intro.png');
    final welcome = File('test/goldens/handover_welcome.png');
    expect(intro.existsSync() && welcome.existsSync(), isTrue);

    expect(
      welcome.readAsBytesSync(),
      orderedEquals(intro.readAsBytesSync()),
      reason:
          'the sign-in screen must open on the frame the intro ends on, or '
          'the handover reads as a jump: one logo fading out and another '
          'fading in somewhere else',
    );
  });
}
