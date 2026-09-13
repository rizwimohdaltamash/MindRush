import 'dart:async';

import 'package:mind_rush/core/challenge/duel_room.dart';
import 'package:mind_rush/data/duel_room_service.dart';

/// Two phones, one map. Stands in for the Firestore collection so the lobby's
/// rules can be tested without a network or a Firebase project.
class FakeRoomBackend {
  final Map<String, DuelRoom> rooms = {};
  final Map<String, StreamController<DuelRoom>> _controllers = {};

  /// Every document write, so a test can show that a score is not pushed on
  /// every keypress.
  int writes = 0;

  StreamController<DuelRoom> _channel(String code) => _controllers.putIfAbsent(
    code,
    () => StreamController<DuelRoom>.broadcast(),
  );

  Stream<DuelRoom> watch(String code) async* {
    // Firestore hands a new listener the current document immediately; a
    // lobby that only saw later changes would sit blank until someone moved.
    final current = rooms[code];
    if (current != null) yield current;
    yield* _channel(code).stream;
  }

  void put(DuelRoom room) {
    writes++;
    rooms[room.code] = room;
    _channel(room.code).add(room);
    _invites.add(rooms.values.toList());
  }

  /// Stands in for the collection query on `invitedUid`.
  final StreamController<List<DuelRoom>> _invites =
      StreamController<List<DuelRoom>>.broadcast();

  Stream<List<DuelRoom>> watchInvites(String uid) async* {
    List<DuelRoom> addressedTo(Iterable<DuelRoom> all) => [
      for (final room in all)
        if (room.invitedUid == uid) room,
    ];

    yield addressedTo(rooms.values);
    yield* _invites.stream.map(addressedTo);
  }

  Future<void> dispose() async {
    for (final controller in _controllers.values) {
      await controller.close();
    }
    _controllers.clear();
    await _invites.close();
  }
}

/// One phone's view of [backend].
class FakeRooms implements DuelRoomService {
  FakeRooms(this.backend, this.myUid);

  final FakeRoomBackend backend;

  @override
  final String myUid;

  /// Flipped on to stand in for a phone with no signal.
  bool offline = false;

  @override
  Future<RoomError?> create(DuelRoom room) async {
    if (offline) return RoomError.offline;
    backend.put(room);
    return null;
  }

  @override
  Stream<DuelRoom> watch(String code) => backend.watch(code);

  @override
  Stream<List<DuelRoom>> watchInvites(String uid) => backend.watchInvites(uid);

  @override
  Future<RoomError?> join(String code, RoomPlayer guest) async {
    if (offline) return RoomError.offline;
    final room = backend.rooms[code];
    if (room == null) return RoomError.notFound;
    if (room.host.uid == guest.uid) return RoomError.full;
    final seated = room.guest;
    if (seated != null && seated.uid != guest.uid) return RoomError.full;
    backend.put(room.copyWith(guest: guest, status: RoomStatus.ready));
    return null;
  }

  @override
  Future<void> setStatus(String code, RoomStatus status) async {
    final room = backend.rooms[code];
    if (room != null) backend.put(room.copyWith(status: status));
  }

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
    if (offline) return;
    final room = backend.rooms[code];
    if (room == null) return;
    final side = asHost ? room.host : room.guest;
    if (side == null) return;
    final updated = side.copyWith(
      score: score,
      finished: finished ? true : null,
      timeMs: finished ? timeMs : null,
      durations: finished && durations.isNotEmpty ? durations : null,
      aborted: aborted ? true : null,
    );
    backend.put(
      asHost ? room.copyWith(host: updated) : room.copyWith(guest: updated),
    );
  }
}
