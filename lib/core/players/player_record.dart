import '../models/game_mode.dart';
import '../rating/rating_engine.dart';
import '../rating/streak.dart';

/// How a player's duels have gone, in total.
///
/// Kept as running counters on the server rather than worked out from the
/// match list: the phone only keeps its last hundred matches, and a career
/// total that silently stops at a hundred is worse than no total at all.
class PlayerTally {
  const PlayerTally({this.played = 0, this.won = 0, this.lost = 0});

  final int played;
  final int won;
  final int lost;

  static const PlayerTally none = PlayerTally();

  double get winRate => played == 0 ? 0 : won / played;

  Map<String, dynamic> toJson() => {'played': played, 'won': won, 'lost': lost};

  static PlayerTally fromJson(Object? json) {
    if (json is! Map) return none;
    int read(String key) => (json[key] as num?)?.toInt() ?? 0;
    return PlayerTally(
      played: read('played'),
      won: read('won'),
      lost: read('lost'),
    );
  }
}

/// One registered player, as everybody else sees them.
///
/// This is the shape of a document in the `players` collection, and the only
/// thing the app publishes about a person. It is deliberately not the
/// player's save: their match history, their bot ladder and their app
/// settings live elsewhere, so making this row readable by everyone does not
/// make anything else readable with it.
///
/// Every field is grouped by what it is about -- who they are, how they are
/// rated, how they are doing -- rather than flattened into one heap of keys.
/// A new thing to know about a player is then a new group or a new field
/// inside one, and every older build keeps reading the document unchanged
/// because [fromJson] defaults anything it has never heard of.
class PlayerRecord {
  const PlayerRecord({
    required this.uid,
    required this.name,
    required this.avatarId,
    required this.lastSeenAtMs,
    this.photo,
    this.ratings = const {},
    this.streak = const StreakState(),
    this.tally = PlayerTally.none,
    this.xp = 0,
    this.level = 1,
    this.updatedAtMs = 0,
    this.createdAtMs = 0,
  });

  /// Bumped only when a change would need old builds handled differently.
  /// Stored on every document so that day can be told from this one.
  static const int schemaVersion = 1;

  final String uid;
  final String name;
  final int avatarId;

  /// Milliseconds since epoch, written by the server rather than the phone.
  ///
  /// Two devices' clocks routinely disagree by seconds, and a player whose
  /// clock runs fast would otherwise look permanently online. Server stamps
  /// put every heartbeat on one clock; see `PlayerDirectory` for how they are
  /// then compared without trusting the local clock either.
  final int lastSeenAtMs;

  /// Their photograph as a small square PNG, base64 encoded, or null if they
  /// are wearing one of the characters.
  ///
  /// It rides on the row so a face appears on the board without a second
  /// fetch, and without the app needing a storage bucket at all. The size cap
  /// is what makes that reasonable: see `photoFor` on the picker.
  final String? photo;

  final Map<Category, int> ratings;
  final StreakState streak;
  final PlayerTally tally;

  /// Earned from streak milestones, and the profile level. Both are worked
  /// out from other numbers on the player's own device; they are stored so
  /// this row can be ranked and read on its own, without the reader having to
  /// know how either is calculated.
  final int xp;
  final int level;

  /// When the player's own device last changed this. Distinct from
  /// [lastSeenAtMs], which is a heartbeat: this one decides whose copy of a
  /// save is newer, so it must come from the same clock that made the change.
  final int updatedAtMs;

  /// When they first registered, by the server's clock. Written once.
  final int createdAtMs;

  int ratingIn(Category c) => ratings[c] ?? RatingEngine.initial;

  /// The one number to rank a player by when no category is in view.
  int get overallRating => Category.values.isEmpty
      ? RatingEngine.initial
      : Category.values.fold(0, (sum, c) => sum + ratingIn(c)) ~/
            Category.values.length;

  /// What another phone needs to know. Not what gets written -- the write
  /// path merges named groups so that server-owned fields, the tally and the
  /// heartbeat among them, are never clobbered by a client that has a stale
  /// idea of them.
  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'uid': uid,
    'name': name,
    // Lower-cased alongside the real name so the board can one day be
    // searched on the server instead of after downloading everybody.
    'nameLower': name.toLowerCase(),
    'avatarId': avatarId,
    'photo': photo,
    'ratings': {for (final e in ratings.entries) e.key.name: e.value},
    'streak': {
      'current': streak.current,
      'best': streak.best,
      'lastPlayedDay': streak.lastPlayedDay,
    },
    'progress': {'xp': xp, 'level': level},
    'tally': tally.toJson(),
    'updatedAtMs': updatedAtMs,
    'lastSeenAtMs': lastSeenAtMs,
    'createdAtMs': createdAtMs,
  };

  /// Null for a document that cannot describe a player: no uid, or no name.
  ///
  /// A player who has not finished onboarding has a row -- their heartbeat
  /// makes one -- but no business on a leaderboard as a blank line.
  static PlayerRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final uid = json['uid'];
    final name = json['name'];
    if (uid is! String || uid.isEmpty) return null;
    if (name is! String || name.trim().isEmpty) return null;

    final ratings = json['ratings'];
    final streak = json['streak'];
    final progress = json['progress'];

    int at(Object? map, String key) =>
        map is Map ? (map[key] as num?)?.toInt() ?? 0 : 0;

    return PlayerRecord(
      uid: uid,
      name: name.trim(),
      avatarId: (json['avatarId'] as num?)?.toInt() ?? 0,
      photo: json['photo'] as String?,
      lastSeenAtMs: (json['lastSeenAtMs'] as num?)?.toInt() ?? 0,
      ratings: {
        for (final c in Category.values)
          c: ratings is Map
              ? (ratings[c.name] as num?)?.toInt() ?? RatingEngine.initial
              : RatingEngine.initial,
      },
      streak: StreakState(
        current: at(streak, 'current'),
        best: at(streak, 'best'),
        lastPlayedDay: streak is Map
            ? (streak['lastPlayedDay'] as num?)?.toInt()
            : null,
      ),
      tally: PlayerTally.fromJson(json['tally']),
      xp: at(progress, 'xp'),
      // Levels start at one; a document written before levels existed reads
      // as level one rather than level zero.
      level: at(progress, 'level') == 0 ? 1 : at(progress, 'level'),
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}
