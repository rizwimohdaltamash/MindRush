import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../firebase_options.dart';
import 'error_report.dart';

/// Who the player is, once they have signed in.
///
/// A plain value rather than a `User` or a `GoogleSignInAccount`, so the rest
/// of the app never has to import Firebase or Google to know who is playing.
class SignedInUser {
  const SignedInUser({
    required this.uid,
    required this.name,
    this.email,
    this.photoUrl,
  });

  /// The Firebase uid. Stable across reinstalls and across phones, which is
  /// the whole reason this replaced anonymous sign-in: an anonymous account
  /// lives on the device, so uninstalling the app orphaned the player's row
  /// and made a second one the next time they played.
  final String uid;

  /// Their Google display name, used as the opening MindRush name. They can
  /// change it afterwards from the profile screen.
  final String name;

  final String? email;
  final String? photoUrl;
}

/// How the app signs somebody in.
///
/// An interface, so onboarding can be driven in a test without a Google
/// account, a network, or a platform channel -- the same trick the camera
/// uses in [PhotoSource].
abstract class SignInGateway {
  /// Prompts for an account. Null when the player backed out, or when it
  /// could not be done at all.
  Future<SignedInUser?> prompt();

  /// Ends the session on this device, Google and Firebase both.
  Future<void> signOut();
}

/// Refuses, quietly.
///
/// Never the default any more -- the real gateway is. This is here for a
/// test that wants onboarding rendered with nothing behind the button, and
/// it has to be asked for by name.
class NoSignIn implements SignInGateway {
  const NoSignIn();

  @override
  Future<SignedInUser?> prompt() async => null;

  @override
  Future<void> signOut() async {}
}

/// The real thing: a Google account, exchanged for a Firebase one.
class GoogleSignInGateway implements SignInGateway {
  /// The OAuth web client Firebase issued for this project.
  ///
  /// Not a secret -- it is in `google-services.json`, which ships inside the
  /// APK. It is here as well because the Dart side of `google_sign_in` cannot
  /// read that file, and the ID token has to be minted for *this* audience or
  /// Firebase will not accept it.
  static const String serverClientId =
      '279536954313-9e3tiehpl8bunagullpuukh8smefni9o.apps.googleusercontent.com';

  bool _ready = false;

  /// Starts Firebase and the Google plugin, once.
  ///
  /// Done here rather than assumed, because the welcome screen can be on
  /// screen before the background startup has finished, and a player who taps
  /// the button in that first second should still get an account picker.
  Future<void> _prepare() async {
    if (_ready) return;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    await GoogleSignIn.instance.initialize(serverClientId: serverClientId);
    _ready = true;
  }

  @override
  Future<SignedInUser?> prompt() async {
    try {
      await _prepare();
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) return null;

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final result = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      final user = result.user;
      if (user == null) return null;

      return SignedInUser(
        uid: user.uid,
        // Firebase fills the display name in from Google, but a Google
        // account without one is possible; the email's local part is a
        // better fallback than an empty leaderboard row.
        name: _nameFor(user.displayName, account.displayName, account.email),
        email: user.email ?? account.email,
        photoUrl: user.photoURL ?? account.photoUrl,
      );
    } on GoogleSignInException catch (error, stack) {
      // Backing out of the account picker is not a fault worth reporting.
      if (error.code != GoogleSignInExceptionCode.canceled) {
        Report.swallowed(error, stack, 'google sign-in failed');
      }
      return null;
    } catch (error, stack) {
      Report.swallowed(error, stack, 'google sign-in failed');
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (error, stack) {
      Report.swallowed(error, stack, 'google sign-out failed');
    }
    await FirebaseAuth.instance.signOut();
  }

  /// The first of these that is actually something.
  static String _nameFor(String? first, String? second, String? email) {
    for (final candidate in [first, second]) {
      if (candidate != null && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    final local = (email ?? '').split('@').first.trim();
    return local.isEmpty ? 'Player' : local;
  }
}
