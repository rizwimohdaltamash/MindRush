import '../models/game_mode.dart';
import '../rating/rating_engine.dart';
import '../questions/difficulty.dart';
import '../questions/question_deck.dart';

/// Where a friend duel is up to.
///
/// The room is the only shared truth between the two phones. Both sides read
/// it, both write their own half of it, and neither can start without the
/// other -- which is the whole point: a duel is two people in the same minute.
enum RoomStatus {
  /// Created, link sent, nobody else here yet.
  waiting,

  /// Both players present. The host flips this to [counting].
  ready,

  /// Count-in running on both phones.
  counting,

  /// The minute is live.
  playing,

  /// Both sides have reported a final score.
  done,

  /// The invited player said no. The challenger sees this and stops waiting.
  declined;

  static RoomStatus parse(Object? value) =>
      RoomStatus.values.where((s) => s.name == value).firstOrNull ??
      RoomStatus.waiting;
}

/// One side of a friend duel.
class RoomPlayer {
  const RoomPlayer({
    required this.uid,
    required this.name,
    required this.avatarId,
    this.photo,
    this.rating = RatingEngine.initial,
    this.score = 0,
    this.finished = false,
    this.timeMs = 0,
    this.durations = const [],
    this.aborted = false,
  });

  final String uid;
  final String name;
  final int avatarId;

  /// Their photograph, as a small square PNG in base64, or null if they are
  /// wearing a character.
  ///
  /// Carried in the room rather than looked up from their player row: the
  /// lobby, the scoreboard and the result all want the face of the person in
  /// the other seat, and that person may well be somebody this phone has
  /// never seen a row for.
  final String? photo;

  /// Their rating in this mode's category, as it stood when they sat down.
  ///
  /// Carried so each phone learns who it actually played. A friend's real
  /// rating lives on their own device; without this the only way to show them
  /// on a leaderboard would be to guess.
  final int rating;

  /// Their score as it stands, pushed as they play.
  final int score;

  /// Set when their minute is over and [score] is final.
  final bool finished;

  /// When their last answer landed -- the tiebreaker on a level score.
  final int timeMs;

  /// Set when their phone called the duel off rather than played it out.
  ///
  /// The other side needs to know the difference. A friend who finishes on
  /// nought was beaten; a friend who stopped answering was never there, and
  /// taking rating off them for it would make walking away a way of feeding
  /// points to whoever you walked away from.
  final bool aborted;

  /// How long they spent on each question, in order.
  ///
  /// Written once, with the final score, rather than pushed as they play: the
  /// only thing that reads it is the result screen's speed chart, and a live
  /// duel should not spend a document write per question on a number nobody
  /// is looking at yet. Empty until they finish -- and still empty afterwards
  /// if their phone never reported in.
  final List<int> durations;

  ///This class holds the data for one side of the duel
  ///(either you or your friend).
  RoomPlayer copyWith({
    int? score,
    bool? finished,
    int? timeMs,
    List<int>? durations,
    bool? aborted,
  }) => RoomPlayer(
    uid: uid,
    name: name,
    avatarId: avatarId,
    photo: photo,
    rating: rating,
    score: score ?? this.score,
    finished: finished ?? this.finished,
    timeMs: timeMs ?? this.timeMs,
    durations: durations ?? this.durations,
    aborted: aborted ?? this.aborted,
  );

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'name': name,
    'avatarId': avatarId,
    if (photo != null) 'photo': photo,
    'rating': rating,
    'score': score,
    'finished': finished,
    'timeMs': timeMs,
    if (durations.isNotEmpty) 'durations': durations,
    if (aborted) 'aborted': true,
  };

  static RoomPlayer? fromJson(Object? json) {
    if (json is! Map) return null;
    final uid = json['uid'];
    if (uid is! String || uid.isEmpty) return null;
    return RoomPlayer(
      uid: uid,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name'] as String
          : 'A friend',
      avatarId: (json['avatarId'] as num?)?.toInt() ?? 0,
      photo: json['photo'] is String ? json['photo'] as String : null,
      rating: (json['rating'] as num?)?.toInt() ?? RatingEngine.initial,
      score: (json['score'] as num?)?.toInt() ?? 0,
      finished: json['finished'] == true,
      timeMs: (json['timeMs'] as num?)?.toInt() ?? 0,
      durations: [
        for (final value in (json['durations'] as List?) ?? const [])
          if (value is num) value.toInt(),
      ],
      aborted: json['aborted'] == true,
    );
  }
}

/// A friend duel, as both phones see it.
///This represents the entire Firebase database document. It holds
///the host (who created the link) and the guest (who clicked it).
///There are two brilliant design decisions in this class:
class DuelRoom {
  const DuelRoom({
    required this.code,
    required this.mode,
    required this.seed,
    required this.difficulty,
    required this.host,
    this.guest,
    this.status = RoomStatus.waiting,
    this.invitedUid,
    this.invitedName,
    this.createdAtMs = 0,
  });

  /// Doubles as the document id and as the tail of the shared link.
  final String code;

  final GameMode mode;
  final int seed;

  /// Fixed by the host when the room is made, so both sides answer the same
  /// questions even when their ratings differ. Deriving it per device would
  /// hand the higher-rated player harder questions for the same match.
  final Difficulty difficulty;

  final RoomPlayer host;
  final RoomPlayer? guest;
  final RoomStatus status;

  /// Set when this was aimed at one person rather than shared as a link.
  ///
  /// Their app watches for rooms addressed to them, which is what turns a
  /// challenge into something that arrives rather than something you have to
  /// be sent.
  final String? invitedUid;

  /// Who [invitedUid] is, so the challenger can be told who declined without
  /// waiting for them to fill a seat they never took.
  final String? invitedName;

  /// When the room was opened, so a challenge nobody answered stops ringing
  /// instead of resurfacing days later.
  final int createdAtMs;

  bool get isFull => guest != null;

  /// How long a direct challenge stays live before it is treated as missed.
  static const int inviteExpiryMs = 120000;

  /// Still worth showing [uid] as an incoming challenge.
  bool isLiveInviteFor(String uid, {required int nowMs}) =>
      invitedUid == uid &&
      guest == null &&
      status == RoomStatus.waiting &&
      nowMs - createdAtMs <= inviteExpiryMs;

  /// The identical deck both sides play.
  QuestionDeck get deck =>
      QuestionDeck(seed: seed, mode: mode, difficulty: difficulty);

  /// True once both players have reported a final score.
  bool get bothFinished => host.finished && (guest?.finished ?? false);

  RoomPlayer? me(String uid) =>
      host.uid == uid ? host : (guest?.uid == uid ? guest : null);

  RoomPlayer? opponentOf(String uid) =>
      host.uid == uid ? guest : (guest?.uid == uid ? host : null);

  bool isHost(String uid) => host.uid == uid;

  DuelRoom copyWith({
    RoomPlayer? host,
    RoomPlayer? guest,
    RoomStatus? status,
  }) => DuelRoom(
    code: code,
    mode: mode,
    seed: seed,
    difficulty: difficulty,
    host: host ?? this.host,
    guest: guest ?? this.guest,
    status: status ?? this.status,
    invitedUid: invitedUid,
    invitedName: invitedName,
    createdAtMs: createdAtMs,
  );

  Map<String, dynamic> toJson() => {
    'code': code,
    'mode': mode.name,
    'seed': seed,
    'difficulty': difficulty.level,
    'host': host.toJson(),
    if (guest != null) 'guest': guest!.toJson(),
    'status': status.name,
    if (invitedUid != null) 'invitedUid': invitedUid,
    if (invitedName != null) 'invitedName': invitedName,
    'createdAtMs': createdAtMs,
  };

  /// Rebuilds a room from a document. Returns null rather than throwing, so a
  /// half-written or foreign document cannot crash a lobby.
  static DuelRoom? fromJson(Object? json) {
    if (json is! Map) return null;
    final code = json['code'];
    final mode = GameMode.values
        .where((m) => m.name == json['mode'])
        .firstOrNull;
    final seed = (json['seed'] as num?)?.toInt();
    final difficulty = Difficulty.values
        .where((d) => d.level == (json['difficulty'] as num?)?.toInt())
        .firstOrNull;
    final host = RoomPlayer.fromJson(json['host']);
    if (code is! String || mode == null || seed == null || host == null) {
      return null;
    }
    return DuelRoom(
      code: code,
      mode: mode,
      seed: seed,
      // An older or malformed document still plays; it just plays at the
      // middle band rather than at nothing.
      difficulty: difficulty ?? Difficulty.medium,
      host: host,
      guest: RoomPlayer.fromJson(json['guest']),
      status: RoomStatus.parse(json['status']),
      invitedUid: json['invitedUid'] is String
          ? json['invitedUid'] as String
          : null,
      invitedName: json['invitedName'] is String
          ? json['invitedName'] as String
          : null,
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  /// A fresh room opened by [host] for [mode].
  static DuelRoom open({
    required GameMode mode,
    required int seed,
    required Difficulty difficulty,
    required RoomPlayer host,
    String? invitedUid,
    String? invitedName,
    int createdAtMs = 0,
  }) => DuelRoom(
    code: '${mode.name}-$seed',
    mode: mode,
    seed: seed,
    difficulty: difficulty,
    host: host,
    invitedUid: invitedUid,
    invitedName: invitedName,
    createdAtMs: createdAtMs,
  );
}
