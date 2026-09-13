import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image_picker/image_picker.dart';

import 'error_report.dart';

/// Where a photograph comes from.
enum PhotoOrigin { camera, gallery }

/// Getting a photograph off the device and into an avatar.
///
/// An interface because the picker is a platform channel: nothing behind it
/// can run in a test, while everything in front of it -- how the picture is
/// cut down, what happens when the player cancels, what a failure does to the
/// avatar they already had -- is exactly what wants testing.
abstract class PhotoSource {
  /// The photo as a small square PNG, base64 encoded, or null if the player
  /// backed out or the device refused.
  Future<String?> take(PhotoOrigin origin);
}

/// The real one: the system camera or photo picker, cut down to an avatar.
class DevicePhotoSource implements PhotoSource {
  DevicePhotoSource([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// The square an avatar is stored at.
  ///
  /// Small on purpose. The photo travels inside the player's row so a face
  /// can appear on somebody else's leaderboard with no file hosting anywhere
  /// -- which is only reasonable while it stays a thumbnail. A phone camera
  /// gives back several megabytes; this is a few tens of kilobytes.
  static const int side = 96;

  /// A hard ceiling on what may be published, in base64 characters.
  ///
  /// Roughly sixty kilobytes. Nothing at [side] pixels should come close; the
  /// cap is here so that if something ever did, it would be dropped rather
  /// than quietly making everybody's leaderboard slow.
  static const int maxEncodedLength = 60 * 1024;

  @override
  Future<String?> take(PhotoOrigin origin) async {
    try {
      final file = await _picker.pickImage(
        source: origin == PhotoOrigin.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        // Asks the plugin to do the first, biggest reduction itself, so a
        // twelve-megapixel photo is never decoded whole in this process.
        maxWidth: 720,
        maxHeight: 720,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.front,
      );
      if (file == null) return null; // Backed out. Not a failure.
      return await encode(await file.readAsBytes());
    } catch (error, stack) {
      // A refused permission, a camera in use, a corrupt file: the player
      // keeps the avatar they had.
      Report.swallowed(error, stack, 'could not take a photo');
      return null;
    }
  }

  /// Cuts [bytes] to a centred square of [side] pixels and encodes it.
  ///
  /// Centre-cropped rather than squashed: a portrait photo scaled to a square
  /// makes a face look wrong in a way people notice immediately, even when
  /// they cannot say why.
  static Future<String?> encode(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;

      final edge = image.width < image.height ? image.width : image.height;
      final source = ui.Rect.fromLTWH(
        (image.width - edge) / 2,
        (image.height - edge) / 2,
        edge.toDouble(),
        edge.toDouble(),
      );

      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        image,
        source,
        const ui.Rect.fromLTWH(0, 0, side * 1.0, side * 1.0),
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      final square = await recorder.endRecording().toImage(side, side);
      final png = await square.toByteData(format: ui.ImageByteFormat.png);

      image.dispose();
      square.dispose();
      if (png == null) return null;

      final encoded = base64Encode(png.buffer.asUint8List());
      if (encoded.length > maxEncodedLength) {
        debugPrint('MindRush: photo too large to publish, keeping the avatar');
        return null;
      }
      return encoded;
    } catch (error, stack) {
      Report.swallowed(error, stack, 'could not read that picture');
      return null;
    }
  }
}

/// Used where there is no camera: tests, and any platform the picker does not
/// support. Always cancels, which every caller already handles.
class NoPhotoSource implements PhotoSource {
  const NoPhotoSource();

  @override
  Future<String?> take(PhotoOrigin origin) async => null;
}
