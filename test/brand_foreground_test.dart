import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_rush/ui/widgets/brand_mark.dart';

/// The transparent mark used for the Android adaptive icon and the native
/// splash.
///
/// Drawn at roughly half the canvas because Android crops adaptive icons to
/// an inner safe zone and masks them to whatever shape the launcher uses --
/// anything near the edge gets cut off on some phones and not others.
///   flutter test test/brand_foreground_test.dart --update-goldens
void main() {
  testWidgets('transparent foreground, 1024px', (tester) async {
    tester.view.physicalSize = const Size(1024, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 1024,
          height: 1024,
          child: Center(child: BrandMark(size: 560, background: false)),
        ),
      ),
    );

    await expectLater(
      find.byType(SizedBox).first,
      matchesGoldenFile('goldens/icon_foreground.png'),
    );
  });
}
