import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_rush/ui/theme.dart';
import 'package:mind_rush/ui/widgets/wiggle_button.dart';

void main() {
  Future<void> pumpButton(WidgetTester tester, VoidCallback? onPressed) =>
      tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: Center(
              child: Wiggle(
                onPressed: onPressed,
                haptic: false,
                builder: (context, press) =>
                    FilledButton(onPressed: press, child: const Text('GO')),
              ),
            ),
          ),
        ),
      );

  testWidgets('the press is seen before the screen it opens', (tester) async {
    var opened = false;
    await pumpButton(tester, () => opened = true);
    final atRest = tester.getRect(find.text('GO'));

    await tester.tap(find.text('GO'));
    // Two pumps: the first starts the controller's ticker, the second is the
    // one that actually advances it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    // Mid-squash: the button has visibly moved, and the next screen has not
    // arrived yet. Firing on the frame of the tap would mean the animation
    // played out on a page nobody was looking at any more -- which is what a
    // button that starts a duel does to it.
    expect(tester.getRect(find.text('GO')), isNot(atRest));
    expect(opened, isFalse);

    await tester.pumpAndSettle();
    expect(opened, isTrue);
    expect(tester.getRect(find.text('GO')), atRest);
  });

  testWidgets('an impatient second tap does not open it twice', (tester) async {
    var opens = 0;
    await pumpButton(tester, () => opens++);

    await tester.tap(find.text('GO'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.text('GO'));
    await tester.pumpAndSettle();

    expect(opens, 1);
  });

  testWidgets('a disabled button neither wiggles nor fires', (tester) async {
    await pumpButton(tester, null);
    final atRest = tester.getRect(find.text('GO'));

    await tester.tap(find.text('GO'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(tester.getRect(find.text('GO')), atRest);
  });
}
