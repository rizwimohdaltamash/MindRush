import '../match/opponent_feed.dart';
import '../models/game_mode.dart';
import 'duel_room.dart';

///This file (live_opponent.dart) handles the Live Scoreboard during a
///multiplayer match.

/// The friend on the other phone, as this phone's scoreboard sees them.
///
///When you are playing against a friend, this code is responsible for making
///your friend's score tick upwards on your screen every time they get a
///question right.
class LiveOpponentFeed implements OpponentFeed {
  int _score = 0;
  int _timeMs = 0;
  bool _finished = false;
  bool _aborted = false;
  List<int> _durations = const [];

  /// Takes in the other side of the room document.
  void update(RoomPlayer? player) {
    if (player == null) return;
    // Snapshots can arrive out of order, and a score that walks backwards
    // mid-match reads as a bug to the player watching it.
    if (player.score > _score) _score = player.score;
    if (player.aborted) _aborted = true;
    if (player.finished && !_finished) {
      _finished = true;
      _timeMs = player.timeMs;
      _score = player.score;
      _durations = player.durations;
    }
  }

  /// True once their minute is over and [totalScore] is final.
  bool get hasFinished => _finished;

  /// True once they have stopped answering and their phone has called the
  /// duel off. This side then ends unrated as well.
  bool get hasAborted => _aborted;

  @override
  int scoreAt(int elapsedMs) => _score;

  @override
  int get totalScore => _score;

  /// Until they report in, assume they used the whole minute -- that way a
  /// tie is never broken in this player's favour by a number we do not have.
  @override
  int get totalTimeMs => _finished ? _timeMs : kMatchDurationMs;

  /// How long they took on each question, as sent with their final score.
  ///
  /// Empty until they finish, and empty afterwards if their phone never
  /// reported in -- the chart then draws this player's bars alone rather than
  /// inventing an opponent's.
  @override
  List<int> get answerDurations => _durations;
}
