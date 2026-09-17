import 'package:mind_rush/data/sign_in.dart';

/// Signing in, without Google and without a network.
///
/// Onboarding is a screen with one button on it; what that button does is
/// somebody else's problem, and a test that had to reach a real account
/// picker would not be a test of onboarding at all.
class FakeSignIn implements SignInGateway {
  FakeSignIn({
    this.user = const SignedInUser(
      uid: 'uid-google',
      name: 'Naman',
      email: 'naman@example.com',
    ),
    this.refuses = false,
  });

  /// Who the account picker comes back with.
  SignedInUser user;

  /// Set to stand in for a cancelled picker or an unreachable Google.
  bool refuses;

  int prompts = 0;
  int signOuts = 0;

  @override
  Future<SignedInUser?> prompt() async {
    prompts++;
    return refuses ? null : user;
  }

  @override
  Future<void> signOut() async => signOuts++;
}
