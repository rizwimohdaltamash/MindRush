import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/challenge/duel_room.dart';
import 'anonymous_auth.dart';
import 'error_report.dart';

/// Why a room could not be opened or joined.
enum RoomError { offline, notFound, full, unknown }

/// The shared half of a friend duel.
///
/// An interface, so the lobby's rules -- who may join, when a match may start,
/// what happens when nobody turns up -- are testable without a network or a
/// Firebase project.
abstract class DuelRoomService {
  /// This device's identity in a room.
  String get myUid;

  /// Publishes a new room. Returns null on success, or why it failed.
  Future<RoomError?> create(DuelRoom room);

  /// Live view of a room. Emits on every change either side makes.
  Stream<DuelRoom> watch(String code);

  /// Takes the empty seat. Fails if the room is gone or already has two
  /// people in it.
  Future<RoomError?> join(String code, RoomPlayer guest);

  /// Moves the room along; only the host calls this.
  Future<void> setStatus(String code, RoomStatus status);

  /// Challenges addressed to [uid] and still waiting for an answer.
  ///
  /// One equality filter and nothing else, deliberately: Firestore serves
  /// that from an automatic single-field index, so adding this needs no
  /// composite index to be created by hand. Freshness and status are settled
  /// on the device.
  Stream<List<DuelRoom>> watchInvites(String uid);

  /// Reports this player's own half of the room and nothing else, so the two
  /// phones can never overwrite each other's scores.
  ///
  /// [durations] is how long each question took, and is only worth sending on
  /// the last report of a match -- it is what the other phone's speed chart
  /// draws the opponent's bars from.
  Future<void> report(
    String code, {
    required bool asHost,
    required int score,
    bool finished = false,
    int timeMs = 0,
    List<int> durations = const [],
    bool aborted = false,
  });
}

/// A room held in a Firestore document, watched by both phones.
class FirestoreDuelRooms implements DuelRoomService {
  FirestoreDuelRooms(this._rooms, this.myUid);

  final CollectionReference<Map<String, dynamic>> _rooms;

  @override
  final String myUid;

  /// Signs in anonymously and returns a service, or null when there is no
  /// network, no project, or no signal. A friend duel genuinely cannot happen
  /// without a connection, so the caller's job is to say so plainly rather
  /// than to quietly substitute something else.
  static Future<FirestoreDuelRooms?> connect() async {
    try {
      final user = await signedInAnonymously();
      if (user == null) return null;
      return FirestoreDuelRooms(
        FirebaseFirestore.instance.collection('duels'),
        user.uid,
      );
    } catch (error, stack) {
      Report.swallowed(error, stack, 'friend duels unavailable');
      return null;
    }
  }

  @override
  Future<RoomError?> create(DuelRoom room) async {
    try {
      await _rooms.doc(room.code).set(room.toJson());
      return null;
    } catch (error, stack) {
      Report.swallowed(error, stack, 'could not open a room');
      return RoomError.offline;
    }
  }

  @override
  Stream<DuelRoom> watch(String code) => _rooms
      .doc(code)
      .snapshots()
      .map((snapshot) => DuelRoom.fromJson(snapshot.data()))
      .where((room) => room != null)
      .cast<DuelRoom>();

  @override
  Future<RoomError?> join(String code, RoomPlayer guest) async {
    try {
      // A transaction, not a plain write: two people opening the same link at
      // once would otherwise both believe they had the seat, and one of them
      // would silently be playing against nobody.
      return await FirebaseFirestore.instance.runTransaction<RoomError?>((
        transaction,
      ) async {
        final reference = _rooms.doc(code);
        final snapshot = await transaction.get(reference);
        final room = DuelRoom.fromJson(snapshot.data());
        if (room == null) return RoomError.notFound;

        final seated = room.guest;
        // Rejoining after a dropped connection is not the same as gatecrashing.
        if (seated != null && seated.uid != guest.uid) return RoomError.full;
        if (room.host.uid == guest.uid) return RoomError.full;

        transaction.update(reference, {
          'guest': guest.toJson(),
          'status': RoomStatus.ready.name,
        });
        return null;
      });
    } catch (error, stack) {
      Report.swallowed(error, stack, 'could not join a room');
      return RoomError.offline;
    }
  }

  @override
  Future<void> setStatus(String code, RoomStatus status) async {
    try {
      await _rooms.doc(code).update({'status': status.name});
    } catch (error, stack) {
      Report.swallowed(error, stack, 'could not move the room on');
    }
  }

  @override
  Stream<List<DuelRoom>> watchInvites(String uid) => _rooms
      .where('invitedUid', isEqualTo: uid)
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs) ?DuelRoom.fromJson(doc.data()),
        ],
      );

  @override
  Future<void> report(
    String code, {
    required bool asHost,
    required int score,
    bool finished = false,
    int timeMs = 0,
    List<int> durations = const [],
    bool aborted = false,
  }) async {
    final side = asHost ? 'host' : 'guest';
    try {
      await _rooms.doc(code).update({
        '$side.score': score,
        if (finished) ...{
          '$side.finished': true,
          '$side.timeMs': timeMs,
          if (durations.isNotEmpty) '$side.durations': durations,
          // Worth the extra field: it is what stops the other phone from
          // rating a minute nobody played against it.
          if (aborted) '$side.aborted': true,
        },
      });
    } catch (error, stack) {
      // A dropped score is survivable: the next one carries the running total
      // anyway, and the final report is what settles the match.
      Report.swallowed(error, stack, 'score not reported');
    }
  }
}
