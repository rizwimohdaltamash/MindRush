import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_rush/ui/screens/duel_screen.dart';
import 'package:mind_rush/ui/screens/splash_screen.dart';
import 'package:mind_rush/ui/theme.dart';

import 'support/test_fonts.dart';

/// A phone with system animations turned off.
///
/// Plenty of them are: Developer options sets the three animation scales to
/// zero, Accessibility has "Remove animations", and several manufacturers ship
/// battery modes that do it without asking. Flutter honours the setting by
/// running *every* AnimationController at five per cent of its duration --
/// the right default for interface chrome, and quite wrong for an animation
/// that is the thing on screen, or for a timer the game depends on.
///
/// None of the rest of the suite can see this, because the flag is false
/// everywhere else. That is exactly why the app shipped with an intro that
/// played in a tenth of a second on those phones and a five-second grace
/// period that lasted a quarter of one.
void main() {
  setUpAll(loadRealFonts);

  setUp(() {
    debugSemanticsDisableAnimations = true;
    addTearDown(() => debugSemanticsDisableAnimations = null);
  });

  testWidgets('the intro still plays in full', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        debugShowCheckedModeBanner: false,
        home: SplashScreen(onFinished: () => finished = true),
      ),
    );

    // Five per cent of the intro is under a tenth of a second. Well past
    // that, and it must still be going.
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      finished,
      isFalse,
      reason: 'the intro must not be cut to a flash by a system setting',
    );

    // Still running most of the way through.
    await tester.pump(const Duration(milliseconds: 1200));
    expect(finished, isFalse);

    // And it finishes on its own clock.
    await tester.pumpAndSettle();
    expect(finished, isTrue);
    expect(find.text('MindRush'), findsOneWidget);
  });

  testWidgets('the grace period is still five seconds', (tester) async {
    // Not decoration: when this runs out the match is called off. At five per
    // cent it was a quarter of a second, so a player who had not scored yet
    // was asked whether they were still there and abandoned before they could
    // answer.
    final controller = AnimationController(
      vsync: tester,
      duration: DuelScreen.grace,
      animationBehavior: AnimationBehavior.preserve,
    );
    addTearDown(controller.dispose);

    controller.forward();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(controller.isCompleted, isFalse);

    await tester.pump(const Duration(seconds: 4));
    expect(controller.isCompleted, isTrue);
  });

  testWidgets('and a plain controller would not have been', (tester) async {
    // The behaviour being guarded against, so the test above is measuring
    // something rather than asserting that time passes.
    final controller = AnimationController(
      vsync: tester,
      duration: DuelScreen.grace,
    );
    addTearDown(controller.dispose);

    controller.forward();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      controller.isCompleted,
      isTrue,
      reason: 'five seconds became a quarter of one',
    );
  });
}
