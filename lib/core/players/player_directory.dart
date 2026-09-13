import 'player_record.dart';

/// Every registered player, and the rule for who counts as reachable.
class PlayerDirectory {
  const PlayerDirectory(this.players, {required this.myUid});

  final List<PlayerRecord> players;
  final String myUid;

  static const PlayerDirectory empty = PlayerDirectory([], myUid: '');

  /// How stale a heartbeat may be before its owner is treated as gone.
  ///
  /// Comfortably more than the beat interval, so one dropped write does not
  /// blink someone offline mid-conversation.
  static const int staleAfterMs = 45000;

  /// Everyone but this device.
  List<PlayerRecord> get others => [
    for (final p in players)
      if (p.uid != myUid) p,
  ];

  /// This device's own last heartbeat, used as the reference clock.
  ///
  /// Comparing someone's server timestamp against this device's `now` would
  /// reintroduce exactly the skew the server stamps removed. Comparing it
  /// against *our own* server-stamped heartbeat keeps both sides of the
  /// subtraction on the server's clock.
  ///
  /// Null when we have not got one yet. A zero counts as not got: a heartbeat
  /// is written as a server timestamp, and Firestore reports that field as
  /// null until the server fills it in -- which reads as 1970, and 1970 is
  /// not a clock to measure anybody against.
  int? get _reference {
    final mine = players.where((p) => p.uid == myUid).firstOrNull?.lastSeenAtMs;
    return mine != null && mine > 0 ? mine : null;
  }

  /// True when [uid] has beaten recently enough to be worth challenging.
  ///
  /// [now] is the local fallback for the first moments after launch, before
  /// this device's own heartbeat has come back from the server.
  bool isOnline(String uid, {required DateTime now}) {
    if (uid == myUid) return true;
    final player = players.where((p) => p.uid == uid).firstOrNull;
    // Never beaten, or signed off -- either way, not there.
    if (player == null || player.lastSeenAtMs <= 0) return false;

    final reference = _reference ?? now.millisecondsSinceEpoch;
    final age = reference - player.lastSeenAtMs;

    // Measured in both directions on purpose. Everyone beats every fifteen
    // seconds, so a player who is really here sits within a beat or two of
    // our own stamp either side of it. A stamp that is *hours newer* than the
    // clock we are holding is not somebody who is very online -- it is our
    // own reference being wrong, and reading it as presence is what put a
    // ghost on the home screen for a frame after every beat.
    return age.abs() <= staleAfterMs;
  }

  /// Everyone online right now, this device excluded, most recent first.
  List<PlayerRecord> onlineNow(DateTime now) => [
    for (final player in others)
      if (isOnline(player.uid, now: now)) player,
  ]..sort((a, b) => b.lastSeenAtMs.compareTo(a.lastSeenAtMs));
}
