import '../core/bots/bot_profile.dart';
import 'error_report.dart';
import 'match_summary.dart';
import 'player_profile.dart';
import 'players_repository.dart';

/// A stand-in for the cloud, used for the seconds before there is one.
///
/// This exists to get the app on screen. Starting Firebase, signing in and
/// fetching the player's row are three network round trips, and doing them
/// before the first frame is why launching used to sit on a black screen: on
/// a slow connection the whole app waited on a backup nobody had asked for.
///
/// So the app now opens on local storage alone -- which is the source of
/// truth anyway -- and the cloud attaches itself a moment later. Anything
/// written in between is kept here and replayed on arrival, so a match played
/// in the first two seconds is uploaded like any other.
///
/// Only the latest of each thing is kept, because that is what the real cloud
/// would have ended up holding: the row is a snapshot, the ladder is a
/// snapshot, and only matches are events worth queueing one by one.
class DeferredCloud implements PlayerCloud {
  PlayerCloud? _real;

  PlayerProfile? _profile;
  List<BotProfile>? _roster;
  final List<MatchSummary> _matches = [];
  bool _wiped = false;

  /// True once the real cloud is behind this.
  bool get connected => _real != null;

  @override
  String get myUid => _real?.myUid ?? '';

  /// Hands over to the real cloud and replays everything held back.
  ///
  /// Order matters: a wipe that happened while offline has to land before the
  /// writes that came after it, or a reset would undo itself.
  Future<void> attach(PlayerCloud cloud) async {
    _real = cloud;
    try {
      if (_wiped) {
        _wiped = false;
        await cloud.wipe();
      }
      if (_profile case final profile?) await cloud.pushProfile(profile);
      for (final match in _matches) {
        await cloud.pushMatch(match);
      }
      if (_roster case final roster?) await cloud.pushRoster(roster);
    } catch (error, stack) {
      Report.swallowed(error, stack, 'could not catch the cloud up');
    }
    _profile = null;
    _roster = null;
    _matches.clear();
  }

  /// Nothing to restore from until there is a cloud. The store treats a null
  /// snapshot as "this device is the only copy", which it is.
  @override
  Future<CloudSnapshot?> fetch() async => _real?.fetch();

  @override
  Future<void> pushProfile(PlayerProfile profile) async {
    final real = _real;
    if (real != null) return real.pushProfile(profile);
    _profile = profile;
  }

  @override
  Future<void> pushMatch(MatchSummary summary) async {
    final real = _real;
    if (real != null) return real.pushMatch(summary);
    _matches.add(summary);
  }

  @override
  Future<void> pushRoster(List<BotProfile> roster) async {
    final real = _real;
    if (real != null) return real.pushRoster(roster);
    _roster = roster;
  }

  @override
  Future<void> wipe() async {
    final real = _real;
    if (real != null) return real.wipe();
    // Anything queued is about to be deleted anyway.
    _profile = null;
    _roster = null;
    _matches.clear();
    _wiped = true;
  }

  @override
  Future<void> setDisplayName(String name) async => _real?.setDisplayName(name);
}
