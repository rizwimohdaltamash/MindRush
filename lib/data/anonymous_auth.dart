import 'package:firebase_auth/firebase_auth.dart';

import 'error_report.dart';

/// The anonymous account this device plays as, checked rather than assumed.
///
/// Firebase caches a signed-in user on the device and keeps handing it back
/// forever, whether or not the account still exists on the server. Delete the
/// user in the console -- or wipe the project -- and every phone that ever
/// signed in carries on believing it is signed in: `currentUser` is not null,
/// so nothing tries to sign in again, and every read and write is refused
/// from then on. Because the uploads are fire-and-forget, that failure is
/// completely silent; the game keeps playing from local storage and nothing
/// ever reaches Firestore again.
///
/// So the cached credential is verified before it is trusted. Forcing a token
/// refresh is what asks the server whether this account is real; if the
/// answer is no, the stale credential is thrown away and a new anonymous
/// account is made in its place.
Future<User?> signedInAnonymously() async {
  final auth = FirebaseAuth.instance;
  final cached = auth.currentUser;

  if (cached != null) {
    try {
      await cached.getIdToken(true);
      return cached;
    } on FirebaseAuthException catch (error, stack) {
      // user-not-found: deleted in the console. user-token-expired and
      // user-disabled: revoked. All three mean this device is holding a
      // credential the server will not honour again.
      //
      // Worth reporting even though it is handled: this is the failure that
      // silently cut a whole build off from Firestore, and a phone hitting it
      // is a phone that was about to stop saving.
      Report.swallowed(error, stack, 'stale sign-in, starting over');
      await auth.signOut();
    } catch (error, stack) {
      // Anything else -- no network, most likely. The cached credential is
      // still the right one to use; it simply cannot be checked right now.
      Report.swallowed(error, stack, 'could not verify sign-in');
      return cached;
    }
  }

  return (await auth.signInAnonymously()).user;
}
