import 'package:flutter_test/flutter_test.dart';
import 'package:mind_rush/core/challenge/challenge_link.dart';
import 'package:mind_rush/core/models/game_mode.dart';

ChallengeInvite _invite({
  GameMode mode = GameMode.sprint,
  int seed = 849213,
  String by = 'Naman',
}) => ChallengeInvite(mode: mode, seed: seed, byName: by);

void main() {
  group('a link survives the round trip', () {
    test('the room it points at comes back out', () {
      final sent = _invite();
      final got = ChallengeInvite.parse(sent.uri)!;

      expect(got.mode, sent.mode);
      expect(got.seed, sent.seed);
      expect(got.code, sent.code);
      expect(got.byName, 'Naman');
    });

    test('a name with spaces and punctuation is not mangled', () {
      final sent = _invite(by: 'Mohd. Altamash R');
      expect(ChallengeInvite.parse(sent.uri)!.byName, 'Mohd. Altamash R');
    });

    test('every mode makes a link that parses', () {
      for (final mode in GameMode.values) {
        final sent = _invite(mode: mode);
        expect(
          ChallengeInvite.parse(sent.uri)?.mode,
          mode,
          reason: '${mode.name} did not survive the trip',
        );
      }
    });

    test('the code is the room id, so both phones open the same document', () {
      expect(_invite(mode: GameMode.mindSnap, seed: 42).code, 'mindSnap-42');
    });
  });

  group('links that arrive in odd shapes', () {
    test('pulled out of a pasted WhatsApp message', () {
      final sent = _invite();
      expect(ChallengeInvite.parseText(sent.shareText)?.code, sent.code);
    });

    test('the custom scheme puts the marker in the host slot', () {
      final got = ChallengeInvite.parse(
        Uri.parse('mindrush://c/mindSnap-42?by=Aarav'),
      );
      expect(got?.mode, GameMode.mindSnap);
      expect(got?.seed, 42);
      expect(got?.byName, 'Aarav');
    });

    test('a stray link is not a challenge', () {
      for (final url in [
        'https://example.com/hello',
        'https://${ChallengeInvite.host}/',
        'https://${ChallengeInvite.host}/c/',
        'https://${ChallengeInvite.host}/c/notamode-12',
        'https://${ChallengeInvite.host}/c/sprint-abc',
        'https://${ChallengeInvite.host}/c/sprint--4',
      ]) {
        expect(ChallengeInvite.parse(Uri.parse(url)), isNull, reason: url);
      }
    });

    test('a link stripped of its name still opens the room', () {
      final got = ChallengeInvite.parse(
        Uri.parse('https://${ChallengeInvite.host}/c/sprint-7'),
      );
      expect(got, isNotNull);
      expect(got!.code, 'sprint-7');
      expect(got.byName, isEmpty);
    });

    test('the message tells them what tapping does', () {
      // The link is useless if nobody realises it is an invitation.
      final text = _invite().shareText;
      expect(text, contains('Sprint Duels'));
      expect(text, contains('Naman'));
      expect(text, contains('https://'));
    });
  });
}
