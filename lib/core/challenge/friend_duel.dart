import '../../data/duel_room_service.dart';
import 'duel_room.dart';
import 'live_opponent.dart';

/// Everything a live friend duel needs, handed from the lobby to the match.
///
/// Bundled rather than passed as four separate arguments because the four are
/// meaningless apart: a room with no service cannot report a score, and a feed
/// with no room does not know whose score it is showing.

///When you are waiting in the Lobby screen and the countdown hits zero,
//the app has to instantly transition you to the live 60-second Game screen.
//When it does that transition, it has to hand the Game screen everything it
///needs to run a multiplayer match.
class FriendDuel {
  FriendDuel({required this.room, required this.service, required this.feed});

  final DuelRoom room;
  final DuelRoomService service;

  /// The opponent's live score, kept up to date by the lobby's subscription.
  final LiveOpponentFeed feed;

  String get myUid => service.myUid;

  bool get asHost => room.isHost(myUid);

  RoomPlayer? get opponent => room.opponentOf(myUid);
}
