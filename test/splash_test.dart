import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_rush/ui/screens/splash_screen.dart';
import 'package:mind_rush/ui/theme.dart';

import 'support/test_fonts.dart';

void main() {
  setUpAll(loadRealFonts);

  Widget wrap(VoidCallback onFinished) => MaterialApp(
    theme: buildTheme(),
    debugShowCheckedModeBanner: false,
    home: SplashScreen(onFinished: onFinished),
  );

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('hands over once, and only once', (tester) async {
    var finished = 0;
    await tester.pumpWidget(wrap(() => finished++));

    expect(finished, 0, reason: 'must not skip its own animation');
    await tester.pumpAndSettle();
    expect(finished, 1);

    await tester.pump(const Duration(seconds: 2));
    expect(finished, 1, reason: 'the intro must never fire twice');
  });

  testWidgets('is short enough to sit through on the fifth launch', (
    tester,
  ) async {
    // It now runs to the end before the app appears, so its length is felt on
    // every single launch. Under two seconds: long enough to be worth
    // watching, short enough not to be in the way on demo day.
    expect(SplashScreen.duration.inMilliseconds, lessThan(2000));

    await tester.pumpWidget(wrap(() {}));
    await tester.pumpAndSettle();
    expect(find.text('MindRush'), findsOneWidget);
    expect(find.text('SIXTY SECONDS. ONE WINNER.'), findsOneWidget);
  });

  testWidgets('the animation actually progresses', (tester) async {
    phone(tester);
    var finished = false;
    await tester.pumpWidget(wrap(() => finished = true));

    // The very first frame Flutter draws. It must not be empty: Android is
    // showing its own still picture of the mark right up until this frame,
    // so a blank one makes the icon blink out of existence before the
    // animation starts. The three arcs are already here, out on their
    // bearings, at full strength.
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/splash_first.png'),
    );

    // Early: the arcs are on their way in and the name has not arrived.
    await tester.pump(const Duration(milliseconds: 200));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/splash_early.png'),
    );

    await tester.pump(const Duration(milliseconds: 500));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/splash_mid.png'),
    );

    // The composed frame, after the name has arrived and before the whole
    // thing lifts away. Shooting it at the very end would only ever capture
    // the empty screen it fades to.
    await tester.pump(const Duration(milliseconds: 700));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/splash_end.png'),
    );

    await tester.pumpAndSettle();
    expect(finished, isTrue);
  });
}
