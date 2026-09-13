import 'dart:io';

import 'package:flutter/services.dart';

/// The golden test environment ships a placeholder font, so text and icons
/// render as blank rectangles. Loading the real Roboto and MaterialIcons from
/// the Flutter SDK cache makes screenshots legible.
///
/// Call from `setUpAll` in any test that captures a golden containing text.
Future<void> loadRealFonts() async {
  final dir = _materialFontsDir();

  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final name in files) {
      final file = File('${dir.path}/$name');
      if (!file.existsSync()) throw StateError('missing font ${file.path}');
      loader.addFont(file.readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
    await loader.load();
  }

  await load('Roboto', [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-black.ttf',
  ]);
  await load('MaterialIcons', ['materialicons-regular.otf']);
}

/// Found by walking up from the running Dart executable rather than assuming a
/// layout -- and it throws if it cannot be found, because a silent skip here
/// produces screenshots full of empty boxes that look like a broken app.
Directory _materialFontsDir() {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6; i++) {
    for (final candidate in [
      Directory('${dir.path}/artifacts/material_fonts'),
      Directory('${dir.path}/bin/cache/artifacts/material_fonts'),
    ]) {
      if (candidate.existsSync()) return candidate;
    }
    dir = dir.parent;
  }
  throw StateError(
    'material_fonts not found under ${Platform.resolvedExecutable}',
  );
}
