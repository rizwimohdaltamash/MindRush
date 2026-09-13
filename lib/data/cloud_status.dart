import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// What the cloud is doing, in terms a person can act on.
enum CloudState {
  /// No Firebase, no sign-in, or no network at launch. The game is entirely
  /// on this device, which is a supported way to play, not a fault.
  offline,

  /// Signed in, and the last write landed.
  synced,

  /// Signed in, and the server refused the write. Almost always the security
  /// rules: a build writing somewhere the published rules do not allow.
  refused,

  /// Signed in, and the write failed for some other reason -- usually the
  /// network coming and going.
  failing,
}

/// The last thing the cloud did, and when.
@immutable
class CloudHealth {
  const CloudHealth({
    required this.state,
    this.uid,
    this.detail,
    this.lastSyncedAtMs,
  });

  static const CloudHealth offline = CloudHealth(state: CloudState.offline);

  final CloudState state;

  /// The anonymous account this device is signed in as. Shown short, because
  /// its only real use is telling two phones apart while testing.
  final String? uid;

  /// The server's own words for a refusal, kept so a problem can be read off
  /// the phone rather than guessed at from a desk.
  final String? detail;

  final int? lastSyncedAtMs;

  /// One line, written for whoever is holding the phone.
  String get summary => switch (state) {
    CloudState.offline => 'Playing on this device only',
    CloudState.synced => 'Saved to the cloud',
    CloudState.refused => 'The server refused the write',
    CloudState.failing => 'Could not reach the server',
  };

  /// What to do about it, when there is something to do.
  String? get advice => switch (state) {
    CloudState.offline =>
      'Your progress is safe on this phone. It will sync when a '
          'connection is available.',
    CloudState.synced => null,
    CloudState.refused =>
      'Check the Firestore security rules in the Firebase console: this '
          'build writes to the players collection.',
    CloudState.failing => 'Check the connection and play again.',
  };
}

/// Where the cloud reports what happened to its last write.
///
/// Every upload in this app is deliberately fire-and-forget: a finished match
/// must never wait on a network. The cost of that is silence -- an app whose
/// writes are all being refused looks exactly like one that is working. This
/// is the fix for the silence, and it is on the Profile screen so the answer
/// to "is it saving?" is somewhere a person can look.
class CloudMonitor extends ValueNotifier<CloudHealth> {
  CloudMonitor([super.initial = CloudHealth.offline]);

  /// Nothing reports into this one. The default, so tests and offline builds
  /// need no monitor at all.
  static final CloudMonitor none = CloudMonitor();

  void signedIn(String uid) => value = CloudHealth(
    state: CloudState.offline,
    uid: uid,
    lastSyncedAtMs: value.lastSyncedAtMs,
  );

  void ok() => value = CloudHealth(
    state: CloudState.synced,
    uid: value.uid,
    lastSyncedAtMs: DateTime.now().millisecondsSinceEpoch,
  );

  void failed(Object error) => value = CloudHealth(
    state: stateOf(error),
    uid: value.uid,
    detail: detailOf(error),
    lastSyncedAtMs: value.lastSyncedAtMs,
  );

  /// A refusal and a dropped connection need different answers from whoever
  /// is looking, so they are told apart rather than both reading "error".
  static CloudState stateOf(Object error) {
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' || 'unauthenticated' => CloudState.refused,
        _ => CloudState.failing,
      };
    }
    return CloudState.failing;
  }

  static String detailOf(Object error) =>
      error is FirebaseException ? error.code : error.toString();
}
