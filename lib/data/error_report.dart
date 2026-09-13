import 'package:flutter/foundation.dart' show debugPrint;

/// Where a failure the app decided to survive is sent.
///
/// MindRush swallows a great deal on purpose. A finished match must never
/// wait on a network, a refused camera must not lose the avatar you had, and
/// a share sheet that will not open must not strand you outside your own
/// lobby. Every one of those is a caught exception and a shrug -- which is
/// the right behaviour, and which also means the app is at its quietest
/// exactly when something is most wrong with it.
///
/// This is where that quiet goes. Nothing here knows about Crashlytics: the
/// sink is a hook, set once in `main`, so every file that reports a failure
/// stays free of Firebase and testable without it. Null in tests, and on any
/// build with no crash reporting -- in which case this is only the debug
/// print it replaced.
///
/// It is a global for the same reason `FlutterError.onError` is one: threading
/// a reporter through thirty constructors to reach a catch block would cost
/// more than it is worth, and there is only ever one place reports go.
typedef ErrorSink =
    void Function(Object error, StackTrace? stack, String reason);

abstract final class Report {
  static ErrorSink? sink;

  /// A failure the app has already handled. [reason] says what was being
  /// attempted, in the words the log used to use, because that is what a
  /// report is filed under and read as months later.
  static void swallowed(Object error, StackTrace? stack, String reason) {
    debugPrint('MindRush: $reason ($error)');
    sink?.call(error, stack, reason);
  }
}
