import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_rush/data/error_report.dart';
import 'package:mind_rush/data/photo_source.dart';
import 'package:mind_rush/main.dart' show isJustTheNetwork;

/// One report, as the sink receives it.
typedef Filed = ({Object error, StackTrace? stack, String reason});

void main() {
  final filed = <Filed>[];

  setUp(() {
    filed.clear();
    Report.sink = (error, stack, reason) =>
        filed.add((error: error, stack: stack, reason: reason));
  });

  tearDown(() => Report.sink = null);

  group('a failure the app survived', () {
    test('reaches the sink with what was being attempted', () {
      final stack = StackTrace.current;
      Report.swallowed('boom', stack, 'could not publish the player');

      expect(filed.single.error, 'boom');
      expect(filed.single.stack, stack);
      // The reason is what the report is filed under and read as months
      // later, so it says what failed rather than merely that something did.
      expect(filed.single.reason, 'could not publish the player');
    });

    test('is harmless when nothing is listening', () {
      // Every test in this suite, and every build without crash reporting.
      Report.sink = null;

      expect(
        () => Report.swallowed('boom', null, 'nobody home'),
        returnsNormally,
      );
    });
  });

  group('what is worth reporting', () {
    FirebaseException failure(String code) =>
        FirebaseException(plugin: 'cloud_firestore', code: code);

    test('a dropped connection is not a bug', () {
      // A phone on a train fails every write it attempts. Reporting each one
      // would bury the single real fault under a thousand copies of "the wifi
      // went", which is not a thing anybody can fix.
      expect(isJustTheNetwork(failure('unavailable')), isTrue);
      expect(isJustTheNetwork(failure('deadline-exceeded')), isTrue);
      expect(isJustTheNetwork(failure('network-request-failed')), isTrue);
    });

    test('a refused write is', () {
      // This one means the security rules and the app disagree, which is
      // exactly the silence this reporting exists to break.
      expect(isJustTheNetwork(failure('permission-denied')), isFalse);
      expect(isJustTheNetwork(failure('unauthenticated')), isFalse);
    });

    test('and so is anything that is not a Firebase failure at all', () {
      expect(isJustTheNetwork(StateError('bad state')), isFalse);
      expect(isJustTheNetwork('boom'), isFalse);
    });
  });

  group('the instrumentation is really wired', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test(
      'a picture that will not decode is reported, not just shrugged at',
      () async {
        // Proof that the catch blocks call this rather than merely printing:
        // the photo path swallows its failure and hands back null, and the
        // report is the only way anybody would ever know it happened.
        final result = await DevicePhotoSource.encode(
          Uint8List.fromList([1, 2, 3, 4]),
        );

        expect(result, isNull);
        expect(filed.single.reason, 'could not read that picture');
      },
    );
  });
}
