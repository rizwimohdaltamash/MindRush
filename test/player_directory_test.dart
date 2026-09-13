import 'package:flutter_test/flutter_test.dart';
import 'package:mind_rush/core/models/game_mode.dart';
import 'package:mind_rush/core/players/player_directory.dart';
import 'package:mind_rush/core/players/player_record.dart';
import 'package:mind_rush/core/rating/rating_engine.dart';
import 'package:mind_rush/core/rating/streak.dart';

const _me = 'uid-me';
const _them = 'uid-aarav';

PlayerRecord _at(String uid, int ms) =>
    PlayerRecord(uid: uid, name: uid, avatarId: 0, lastSeenAtMs: ms);

/// Any wall-clock instant; the point of most of these is that it does not
/// matter what it says.
final _now = DateTime.fromMillisecondsSinceEpoch(500000);

void main() {
  group('who counts as online', () {
    test('a fresh heartbeat is online', () {
      final book = PlayerDirectory([
        _at(_me, 100000),
        _at(_them, 100000),
      ], myUid: _me);
      expect(book.isOnline(_them, now: _now), isTrue);
    });

    test('a stale heartbeat is not', () {
      final book = PlayerDirectory([
        _at(_me, 100000),
        _at(_them, 100000 - PlayerDirectory.staleAfterMs - 1),
      ], myUid: _me);
      expect(book.isOnline(_them, now: _now), isFalse);
    });

    test('one dropped write does not blink a friend offline', () {
      // The window is deliberately wider than the beat interval.
      final book = PlayerDirectory([
        _at(_me, 100000),
        _at(_them, 100000 - 30000),
      ], myUid: _me);
      expect(book.isOnline(_them, now: _now), isTrue);
    });

    test('someone who has never beaten is offline', () {
      final book = PlayerDirectory([_at(_me, 100000)], myUid: _me);
      expect(book.isOnline(_them, now: _now), isFalse);
    });

    test('signing off is immediate, not a wait', () {
      // leave() backdates the stamp rather than deleting the document, so the
      // friend disappears at once instead of after the staleness window.
      final book = PlayerDirectory([
        _at(_me, 100000),
        _at(_them, 0),
      ], myUid: _me);
      expect(book.isOnline(_them, now: _now), isFalse);
    });

    test('this device is always online to itself', () {
      expect(PlayerDirectory.empty.isOnline('', now: _now), isTrue);
    });

    test('nobody flashes online while our own beat is still in flight', () {
      // The bug this guards: a heartbeat is written as a server timestamp,
      // and for the moment before the server fills it in our own row reads as
      // epoch zero. Measured against zero, every stamp in history looks like
      // the future -- so everyone who had ever played appeared for one frame
      // after every beat, then vanished again.
      final midBeat = PlayerDirectory([
        _at(_me, 0),
        _at(_them, 100000 - 3 * 3600 * 1000),
      ], myUid: _me);

      expect(midBeat.isOnline(_them, now: _now), isFalse);
      expect(midBeat.onlineNow(_now), isEmpty);
    });

    test('a stamp from far in the future is a broken clock, not a friend', () {
      // Whatever produced it -- a pending write here, a device with its date
      // set wrong there -- it is not evidence that anybody is present.
      final book = PlayerDirectory([
        _at(_me, 100000),
        _at(_them, 100000 + 3 * 3600 * 1000),
      ], myUid: _me);
      expect(book.isOnline(_them, now: _now), isFalse);
    });

    test('a friend a beat ahead of us is still a friend', () {
      // Both phones beat every fifteen seconds and neither is synchronised to
      // the other, so being slightly the newer of the two is entirely normal.
      final book = PlayerDirectory([
        _at(_me, 100000),
        _at(_them, 100000 + 14000),
      ], myUid: _me);
      expect(book.isOnline(_them, now: _now), isTrue);
    });
  });

  group('two phones, two clocks', () {
    test(
      'a friend whose device clock runs fast is judged on the server one',
      () {
        // Both stamps come from the server, and both sides of the comparison are
        // server stamps -- so this device's own clock, however wrong, is not
        // consulted at all.
        final book = PlayerDirectory([
          _at(_me, 100000),
          _at(_them, 99000),
        ], myUid: _me);

        final wayBehind = DateTime.fromMillisecondsSinceEpoch(1);
        final wayAhead = DateTime.fromMillisecondsSinceEpoch(99999999);
        expect(book.isOnline(_them, now: wayBehind), isTrue);
        expect(book.isOnline(_them, now: wayAhead), isTrue);
      },
    );

    test('before our own beat lands, the local clock stands in', () {
      // The first seconds after launch: nothing of ours has come back from the
      // server yet, so there is nothing else to compare against.
      final book = PlayerDirectory([_at(_them, 480000)], myUid: _me);
      expect(book.isOnline(_them, now: _now), isTrue);

      final stale = PlayerDirectory([_at(_them, 1000)], myUid: _me);
      expect(stale.isOnline(_them, now: _now), isFalse);
    });
  });

  group('the roll call', () {
    test('lists everyone online but this device', () {
      final book = PlayerDirectory([
        _at(_me, 100000),
        _at(_them, 100000),
        _at('uid-ishita', 0),
      ], myUid: _me);
      expect(book.onlineNow(_now).map((p) => p.uid), [_them]);
    });

    test('the register keeps everyone, online or not', () {
      // Going offline must not take a player off the leaderboard.
      final book = PlayerDirectory([
        _at(_me, 100000),
        _at(_them, 100000),
        _at('uid-ishita', 0),
      ], myUid: _me);
      expect(book.others.map((p) => p.uid), [_them, 'uid-ishita']);
    });

    test('an empty register has nobody in it', () {
      expect(PlayerDirectory.empty.onlineNow(_now), isEmpty);
      expect(PlayerDirectory.empty.others, isEmpty);
    });
  });

  group('a player record', () {
    test('survives the trip through storage', () {
      const sent = PlayerRecord(
        uid: _them,
        name: 'Aarav',
        avatarId: 4,
        lastSeenAtMs: 1234567,
        ratings: {
          Category.math: 1140,
          Category.memory: 980,
          Category.logic: 1000,
        },
      );
      final got = PlayerRecord.fromJson(sent.toJson())!;
      expect(got.uid, _them);
      expect(got.name, 'Aarav');
      expect(got.avatarId, 4);
      expect(got.lastSeenAtMs, 1234567);
      // Ratings ride along, so the leaderboard shows their real standing
      // rather than a number this device worked out for them.
      expect(got.ratingIn(Category.math), 1140);
      expect(got.ratingIn(Category.memory), 980);
    });

    test('a rating this device has never seen falls back to the start', () {
      final got = PlayerRecord.fromJson({'uid': _them, 'name': 'Aarav'})!;
      expect(got.ratingIn(Category.logic), RatingEngine.initial);
    });

    test('a half-written one is refused, not half-shown', () {
      expect(PlayerRecord.fromJson(null), isNull);
      expect(PlayerRecord.fromJson({'name': 'Aarav'}), isNull);
      expect(PlayerRecord.fromJson({'uid': ''}), isNull);
    });

    test('everything worth knowing about a player survives with it', () {
      // The whole point of the shape: a row carries who they are, how they
      // are rated, and how they are doing -- so a screen can be built from it
      // without going back for a second document.
      const sent = PlayerRecord(
        uid: _them,
        name: 'Aarav',
        avatarId: 4,
        lastSeenAtMs: 1234567,
        streak: StreakState(current: 3, best: 11, lastPlayedDay: 20345),
        tally: PlayerTally(played: 40, won: 24, lost: 16),
        xp: 250,
        level: 6,
        updatedAtMs: 99,
        createdAtMs: 55,
      );
      final got = PlayerRecord.fromJson(sent.toJson())!;

      expect(got.streak.current, 3);
      expect(got.streak.best, 11);
      expect(got.streak.lastPlayedDay, 20345);
      expect(got.tally.played, 40);
      expect(got.tally.won, 24);
      expect(got.tally.winRate, 0.6);
      expect(got.xp, 250);
      expect(got.level, 6);
      expect(got.updatedAtMs, 99);
      expect(got.createdAtMs, 55);
    });

    test('it says which shape it is, and how to find it by name', () {
      const record = PlayerRecord(
        uid: _them,
        name: 'Aarav Sharma',
        avatarId: 0,
        lastSeenAtMs: 0,
      );
      final json = record.toJson();

      // Stamped so a later build can tell an old document from a new one
      // rather than guessing from which fields happen to be missing.
      expect(json['schemaVersion'], PlayerRecord.schemaVersion);
      // Written for a search that one day happens on the server instead of
      // after downloading the whole board.
      expect(json['nameLower'], 'aarav sharma');
    });

    test('a document written before a field existed still reads', () {
      // The reason for grouping fields rather than adding another blob: an
      // older row is missing whole groups, and must still produce a player.
      final got = PlayerRecord.fromJson({
        'uid': _them,
        'name': 'Aarav',
        'avatarId': 2,
      })!;

      expect(got.streak.current, 0);
      expect(got.streak.best, 0);
      expect(got.tally.played, 0);
      expect(got.tally.winRate, 0);
      expect(got.xp, 0);
      expect(got.level, 1, reason: 'levels start at one, not zero');
    });

    test('a document still awaiting its server stamp reads as offline', () {
      // Firestore reports null for a serverTimestamp until it lands, which
      // must not be mistaken for "seen at the dawn of time, therefore online".
      final pending = PlayerRecord.fromJson({'uid': _them, 'name': 'Aarav'})!;
      expect(pending.lastSeenAtMs, 0);
      expect(
        PlayerDirectory([
          _at(_me, 100000),
          pending,
        ], myUid: _me).isOnline(_them, now: _now),
        isFalse,
      );
    });
  });
}
