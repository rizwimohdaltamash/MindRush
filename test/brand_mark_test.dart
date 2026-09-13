import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_rush/ui/theme.dart';
import 'package:mind_rush/ui/widgets/brand_mark.dart';

/// Renders the launcher icon straight out of the app's own painter, so the
/// icon on the home screen and the mark inside the app can never drift apart.
///   flutter test test/brand_mark_test.dart --update-goldens
void main() {
  testWidgets('icon source, 1024px', (tester) async {
    tester.view.physicalSize = const Size(1024, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Center(child: BrandMark(size: 1024)),
      ),
    );
    await expectLater(
      find.byType(BrandMark),
      matchesGoldenFile('goldens/icon_1024.png'),
    );
  });

  testWidgets('legibility at launcher size', (tester) async {
    // The size an icon is actually seen at on a home screen. If the mark does
    // not read here, it does not work.
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        debugShowCheckedModeBanner: false,
        home: const Scaffold(
          body: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                BrandMark(size: 48),
                SizedBox(width: 16),
                BrandMark(size: 72),
                SizedBox(width: 16),
                BrandMark(size: 144),
              ],
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/icon_sizes.png'),
    );
  });
}
