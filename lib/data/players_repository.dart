import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../core/bots/bot_profile.dart';
import '../core/players/player_record.dart';
import 'cloud_status.dart';
import 'error_report.dart';
import 'match_summary.dart';
import 'player_profile.dart';

/// Everything MindRush stores about registered people, and nothing else.
///
/// The shape, in one place so it can be read without opening the console:
///
///   players/{uid}                  who they are, how they are rated, when
///                                  they were last seen. Readable by everyone
///                                  signed in -- this is the leaderboard.
///   players/{uid}/matches/{ms}     one document per finished duel, id being
///                                  the millisecond it ended.
///   players/{uid}/private/state    the bot ladder. Owner-only, and never
///                                  read by anybody else's phone.
///
/// Two things this deliberately is not. It is not the old `users` document,
/// which was the player's entire save -- history, bots and all -- pushed as
/// one blob on every match; growing history made every write bigger, and a
/// row could not be read without reading the save. And it holds no bots: the
/// ten opponents on the ladder are generated on the device, identical for
/// everyone, and have no business in a collection of registered people.
///
/// Adding to it later means a new field group on the record, or a new
/// subcollection under the player. Neither disturbs what is already there.
abstract class PlayerCloud {
  String get myUid;

  /// The player's whole save as the cloud has it, or null if this is a phone
  /// the cloud has never seen.
  Future<CloudSnapshot?> fetch();

  /// Writes who they are and how they are rated. Called whenever the profile
  /// changes, so a rating earned this minute ranks this minute.
  Future<void> pushProfile(PlayerProfile profile);

  /// Files one finished duel, and moves the career counters.
  Future<void> pushMatch(MatchSummary summary);

  /// The bot ladder, kept private to the owner.
  Future<void> pushRoster(List<BotProfile> roster);

  /// Removes the player from the cloud entirely. Reset means reset.
  Future<void> wipe();

  /// Puts the player's chosen name on the account itself, so the auth record
  /// describes a person rather than being a nameless row.
  Future<void> setDisplayName(String name);
}

/// The public half of the same collection: who else exists, and who is here.
///
/// Separate from [PlayerCloud] because they are used by different parts of
/// the app for different reasons -- one backs a save up, the other draws a
/// leaderboard -- and each can be faked on its own in a test.
abstract class PlayerService {
  String get myUid;

  /// Stamps this player as here, now.
  ///
  /// Only the timestamp: everything else in their row is written by the store
  /// when it actually changes, so a heartbeat every fifteen seconds does not
  /// re-upload a profile that has not moved.
  Future<void> beat();

  /// Says "gone" immediately, rather than leaving others to wait out the
  /// staleness window when the app is backgrounded. The row itself stays --
  /// leaving the app does not take a player off the leaderboard.
  Future<void> leave();

  /// Everyone registered, this device included.
  Stream<List<PlayerRecord>> watch();

  /// Throws this device's anonymous credential away.
  ///
  /// The Google account stays; what ends is this device's session with it.
  /// Signing back in with the same account returns the same uid, and with it
  /// the ratings, streak and history the cloud was holding. The caller is
  /// responsible for having cleared the local copy first.
  Future<void> signOut();
}

/// What the cloud holds for one player, assembled back into the shapes the
/// app already uses.
class CloudSnapshot {
  const CloudSnapshot({this.profile, this.roster = const []});

  final PlayerProfile? profile;
  final List<BotProfile> roster;
}

/// The public row for [profile]: what of a player's save is everybody else's
/// business, and nothing more.
///
/// Pure, and deliberately the only place that decision is made. Their match
/// history, their bot ladder and their app settings are not here -- not
/// because they are secret, but because a leaderboard row that carries a
/// hundred matches is a leaderboard nobody can afford to load.
PlayerRecord publicRecordOf(PlayerProfile profile, String uid) => PlayerRecord(
  uid: uid,
  name: profile.displayName,
  avatarId: profile.avatarId,
  photo: profile.photo,
  ratings: profile.ratings,
  streak: profile.streak,
  xp: profile.streakXp,
  level: profile.level,
  updatedAtMs: profile.updatedAtMs,
  lastSeenAtMs: 0,
);

/// The fields a player's own device is allowed to write.
///
/// Three are held back. The heartbeat and the registration date are the
/// server's to stamp -- a client that wrote either would be voting on what
/// time it is. The tally is the server's because it moves one match at a
/// time: a phone that keeps only its last hundred matches would otherwise cap
/// somebody's career at a hundred games every time it saved.
Map<String, dynamic> clientFieldsOf(PlayerProfile profile, String uid) =>
    publicRecordOf(profile, uid).toJson()
      ..remove('lastSeenAtMs')
      ..remove('createdAtMs')
      ..remove('tally');

/// What this device can still see of a career. Used once, to open the
/// counters at a sensible number for a player who existed before them.
PlayerTally tallyOf(PlayerProfile profile) {
  final won = profile.history.where((m) => m.won).length;
  return PlayerTally(
    played: profile.history.length,
    won: won,
    lost: profile.history.length - won,
  );
}

/// The real thing, on Firestore.
class FirestorePlayers implements PlayerCloud, PlayerService {
  FirestorePlayers(
    this._players,
    this.myUid, {
    FirebaseFirestore? db,
    CloudMonitor? monitor,
  }) : _db = db,
       _monitor = monitor ?? CloudMonitor.none;

  final CollectionReference<Map<String, dynamic>> _players;
  final FirebaseFirestore? _db;

  /// Where every write reports what happened to it. Without this the uploads
  /// are silent by design, and an app whose writes are all being refused
  /// looks exactly like one that is working.
  final CloudMonitor _monitor;

  @override
  final String myUid;

  /// How many players to watch.
  ///
  /// A cap rather than the whole collection, ordered by who was seen most
  /// recently, so an unbounded register cannot grow the listener without
  /// limit. Ranking is then done on the device, where the selected category
  /// is known.
  static const int watchLimit = 100;

  /// How much history to pull back when restoring onto a new phone. The
  /// device only keeps this many anyway.
  static const int historyLimit = PlayerProfile.historyLimit;

  /// The collection this replaced. Read once, on a phone that has a document
  /// there and none here, so an existing player keeps their progress across
  /// the change. Nothing is ever written to it again.
  static const String legacyCollection = 'users';

  /// True once a fetch has found no row for this player, which is the only
  /// moment it is safe to stamp "registered on".
  bool _isNew = false;

  DocumentReference<Map<String, dynamic>> get _me => _players.doc(myUid);

  CollectionReference<Map<String, dynamic>> get _matches =>
      _me.collection('matches');

  DocumentReference<Map<String, dynamic>> get _private =>
      _me.collection('private').doc('state');

  /// A repository for whoever is signed in, or null when nobody is.
  ///
  /// Signing in is the welcome screen's job now, not this one's. A player who
  /// has never signed in still gets the whole game from local storage; what
  /// they do not get is a row on the leaderboard, which is correct, because
  /// there is no durable identity to put on it.
  static Future<FirestorePlayers?> connect({CloudMonitor? monitor}) async {
    try {
      final credential = FirebaseAuth.instance.currentUser;
      if (credential == null) return null;
      monitor?.signedIn(credential.uid);
      final db = FirebaseFirestore.instance;
      return FirestorePlayers(
        db.collection('players'),
        credential.uid,
        db: db,
        monitor: monitor,
      );
    } catch (error, stack) {
      Report.swallowed(error, stack, 'cloud unavailable');
      return null;
    }
  }

  @override
  Future<CloudSnapshot?> fetch() async {
    try {
      final row = await _me.get();
      final record = PlayerRecord.fromJson(row.data());
      if (record == null) {
        _isNew = !row.exists;
        return await _fetchLegacy();
      }
      return CloudSnapshot(
        profile: PlayerProfile(
          displayName: record.name,
          avatarId: record.avatarId,
          photo: record.photo,
          ratings: record.ratings,
          streak: record.streak,
          history: await _fetchHistory(),
          updatedAtMs: record.updatedAtMs,
        ),
        roster: await _fetchRoster(),
      );
    } catch (error, stack) {
      Report.swallowed(error, stack, 'cloud fetch failed');
      return null;
    }
  }

  Future<List<MatchSummary>> _fetchHistory() async {
    try {
      final page = await _matches
          .orderBy('playedAtMs', descending: true)
          .limit(historyLimit)
          .get();
      return [for (final doc in page.docs) ?MatchSummary.fromJson(doc.data())];
    } catch (error, stack) {
      // A profile without its history is still worth restoring.
      Report.swallowed(error, stack, 'could not read match history');
      return const [];
    }
  }

  Future<List<BotProfile>> _fetchRoster() async {
    try {
      final doc = await _private.get();
      final rows = doc.data()?['roster'];
      if (rows is! List) return const [];
      return [
        for (final row in rows)
          if (row is Map) ?BotProfile.fromJson(row),
      ];
    } catch (error, stack) {
      Report.swallowed(error, stack, 'could not read the ladder');
      return const [];
    }
  }

  /// The one-time bridge off the old whole-save document.
  Future<CloudSnapshot?> _fetchLegacy() async {
    final db = _db;
    if (db == null) return null;
    try {
      final doc = await db.collection(legacyCollection).doc(myUid).get();
      final data = doc.data();
      if (data == null) return null;
      final profile = data['profile'];
      if (profile is! Map) return null;
      final bots = data['bots'];
      return CloudSnapshot(
        profile: PlayerProfile.fromJson(profile),
        roster: [
          if (bots is List)
            for (final row in bots)
              if (row is Map) ?BotProfile.fromJson(row),
        ],
      );
    } catch (error) {
      debugPrint('MindRush: no legacy save to carry over ($error)');
      return null;
    }
  }

  @override
  Future<void> pushProfile(PlayerProfile profile) async {
    // Somebody mid-onboarding has not said who they are yet, and a blank row
    // on the leaderboard helps nobody.
    if (profile.displayName.trim().isEmpty) return;
    try {
      final document = clientFieldsOf(profile, myUid);
      if (_isNew) {
        document['createdAtMs'] = FieldValue.serverTimestamp();
        // The counters open at whatever this device can still see, so a
        // player carried over from the old collection does not restart at
        // zero games played.
        document['tally'] = tallyOf(profile).toJson();
      }
      await _me.set(document, SetOptions(merge: true));
      // Only once the write landed: a registration date lost to a failed
      // write should be stamped by the next attempt, not skipped.
      _isNew = false;
      _monitor.ok();
    } catch (error, stack) {
      _monitor.failed(error);
      Report.swallowed(error, stack, 'could not publish the player');
    }
  }

  @override
  Future<void> pushMatch(MatchSummary summary) async {
    try {
      // Keyed by when it ended, so the same match uploaded twice is the same
      // document rather than two.
      await _matches.doc('${summary.playedAtMs}').set(summary.toJson());
      await _me.set({
        'tally': {
          'played': FieldValue.increment(1),
          'won': FieldValue.increment(summary.won ? 1 : 0),
          'lost': FieldValue.increment(summary.won ? 0 : 1),
        },
        'lastPlayedAtMs': summary.playedAtMs,
      }, SetOptions(merge: true));
      _monitor.ok();
    } catch (error, stack) {
      _monitor.failed(error);
      Report.swallowed(error, stack, 'could not file the match');
    }
  }

  @override
  Future<void> pushRoster(List<BotProfile> roster) async {
    try {
      await _private.set({
        'roster': [for (final bot in roster) bot.toJson()],
      }, SetOptions(merge: true));
    } catch (error, stack) {
      Report.swallowed(error, stack, 'could not save the ladder');
    }
  }

  @override
  Future<void> wipe() async {
    try {
      final matches = await _matches.limit(500).get();
      for (final doc in matches.docs) {
        await doc.reference.delete();
      }
      await _private.delete();
      await _me.delete();
      // The next push is a registration again.
      _isNew = true;
    } catch (error, stack) {
      Report.swallowed(error, stack, 'could not clear the cloud copy');
    }
  }

  @override
  Future<void> setDisplayName(String name) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.displayName == name) return;
      await user.updateDisplayName(name);
    } catch (error, stack) {
      Report.swallowed(error, stack, 'could not name the account');
    }
  }

  @override
  Future<void> beat() async {
    try {
      await _me.set({
        'uid': myUid,
        'lastSeenAtMs': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _monitor.ok();
    } catch (error, stack) {
      // A missed beat is survivable; the next one carries the same meaning --
      // but it is also the write that happens every fifteen seconds whether
      // or not anybody is playing, which makes it the one that notices first.
      _monitor.failed(error);
      Report.swallowed(error, stack, 'could not check in');
    }
  }

  @override
  Future<void> leave() async {
    try {
      // Backdated rather than deleted: the player stays on the leaderboard,
      // they are simply no longer reachable.
      await _me.set({'lastSeenAtMs': 0}, SetOptions(merge: true));
    } catch (error, stack) {
      Report.swallowed(error, stack, 'could not sign off');
    }
  }

  @override
  Future<void> signOut() async {
    // Off the board first, while the credential still works.
    await leave();
    await FirebaseAuth.instance.signOut();
  }

  @override
  Stream<List<PlayerRecord>> watch() => _players
      .orderBy('lastSeenAtMs', descending: true)
      .limit(watchLimit)
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs) ?_read(doc.id, doc.data()),
        ],
      );

  /// Our own last heartbeat as the server actually stamped it.
  ///
  /// Firestore echoes a write back locally before the server has seen it,
  /// with any `serverTimestamp()` field still null. For another player's row
  /// that is right -- reading it as epoch zero says "offline", which they
  /// are, until their real stamp arrives. For *our* row it is not, because
  /// our row is the clock every other player is measured against.
  int _confirmedBeatMs = 0;

  /// Turns a document into a [PlayerRecord], converting server timestamps.
  PlayerRecord? _read(String id, Map<String, dynamic> data) {
    var seen = _ms(data['lastSeenAtMs']);
    if (id == myUid) {
      // Mid-beat, hold the last stamp the server confirmed rather than
      // dropping to zero for a frame. Being a few seconds out of date costs
      // nothing -- the staleness window is three beats wide -- whereas a
      // reference of zero makes everybody who ever played look online.
      if (seen > 0) {
        _confirmedBeatMs = seen;
      } else {
        seen = _confirmedBeatMs;
      }
    }
    return PlayerRecord.fromJson({
      ...data,
      'uid': data['uid'] ?? id,
      'lastSeenAtMs': seen,
      'createdAtMs': _ms(data['createdAtMs']),
    });
  }

  static int _ms(Object? stamp) => switch (stamp) {
    Timestamp() => stamp.millisecondsSinceEpoch,
    final num value => value.toInt(),
    _ => 0,
  };
}
