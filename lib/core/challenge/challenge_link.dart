import '../models/game_mode.dart';

///This file (challenge_link.dart) is entirely dedicated to making the
///WhatsApp invite links work.
/// The link that carries a friend duel from one phone to another.
///
/// It holds only the room code and who sent it. Everything that decides the
/// match -- the seed, the difficulty, both scores -- lives in the room
/// document that both phones watch, so there is exactly one source of truth
/// and a forwarded or edited link cannot contradict it.
class ChallengeInvite {
  const ChallengeInvite({
    required this.mode,
    required this.seed,
    required this.byName,
  });

  final GameMode mode;
  final int seed;

  /// Who sent it. Shown on the web page a friend without the app lands on.
  final String byName;

  /// Doubles as the room's document id.
  String get code => '${mode.name}-$seed';

  /// The domain the links point at.
  ///
  /// An https link is the only kind WhatsApp turns into something tappable --
  /// a custom `mindrush://` scheme arrives as dead grey text. See
  /// `hosting/README.md` for what has to be served here for that tap to open
  /// the app rather than a browser.
  static const String host = 'mindrush-d92c3.web.app';

  /// The custom scheme, a second door into the same route. Useful for
  /// `adb shell am start` while testing, and for apps that do linkify it.
  static const String scheme = 'mindrush';

  Uri get uri => Uri(
    scheme: 'https',
    host: host,
    pathSegments: ['c', code],
    queryParameters: {if (byName.trim().isNotEmpty) 'by': byName},
  );

  /// The message that goes into WhatsApp.
  String get shareText {
    final who = byName.trim().isEmpty ? 'A friend' : byName;
    return '$who wants to duel you in MindRush ${mode.label}.\n'
        'Same questions, same sixty seconds, side by side.\n\n'
        'Tap to join: $uri';
  }

  /// Rebuilds an invite from an incoming link. Returns null for anything that
  /// is not one of ours, so a stray URL cannot open a lobby.

  ///parse takes the URL apart and looks for the /c/ part
  ///(which stands for challenge).
  ///It finds the mindSnap-849213 part and passes it to fromCode().
  static ChallengeInvite? parse(Uri uri) {
    // In `mindrush://c/<code>` the marker lands in the host slot rather than
    // the path, so it is folded back in before looking for it. The https link
    // needs no such help.
    final segments = [
      if (uri.scheme == scheme && uri.host.isNotEmpty) uri.host,
      ...uri.pathSegments,
    ];
    final index = segments.indexOf('c');
    if (index == -1 || index + 1 >= segments.length) return null;
    return fromCode(segments[index + 1], uri.queryParameters);
  }

  /// Builds an invite from a bare room code plus its parameters.
  static ChallengeInvite? fromCode(String code, Map<String, String> params) {
    final parts = code.trim().split('-');
    if (parts.length != 2) return null;
    final mode = GameMode.values.where((m) => m.name == parts[0]).firstOrNull;
    final seed = int.tryParse(parts[1]);
    if (mode == null || seed == null || seed < 0) return null;
    return ChallengeInvite(
      mode: mode,
      seed: seed,
      byName: (params['by'] ?? '').trim(),
    );
  }

  /// Pulls a challenge out of pasted text, which is what arrives when someone
  /// copies the whole WhatsApp message rather than just the link.
  static ChallengeInvite? parseText(String text) {
    for (final word in text.split(RegExp(r'\s+'))) {
      final uri = Uri.tryParse(word);
      if (uri == null) continue;
      final invite = parse(uri);
      if (invite != null) return invite;
    }
    return null;
  }
}
