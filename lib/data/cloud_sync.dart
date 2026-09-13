import '../core/bots/bot_profile.dart';
import 'error_report.dart';
import 'game_store.dart';
import 'player_profile.dart';
import 'players_repository.dart';

/// A [GameStore] that keeps the local one authoritative and treats the cloud
/// as a backup.
///
/// Every read is served from disk, so the app is exactly as fast and exactly
/// as offline-capable as it was before Firebase existed. Writes land locally
/// first and are then pushed without being waited on -- a slow or absent
/// network can never delay a finished match.
///
/// What goes up is now split by what it is, rather than being one document
/// re-uploaded whole every time anything moved: the player's row, the match
/// that just finished, and the private ladder are three separate writes to
/// three separate places. A five-hundred-match player therefore uploads one
/// small match document per duel instead of five hundred summaries per duel.
class SyncedGameStore implements GameStore {
  SyncedGameStore(this._local, this._cloud);

  final GameStore _local;
  final PlayerCloud _cloud;

  /// Pulls the cloud copy and adopts it only if it is genuinely newer than
  /// what is on this device, so a device that has been away catches up while a
  /// stale cloud copy never overwrites fresher local progress.
  ///
  /// Note what this does *not* currently buy: anonymous sign-in stores its uid
  /// on the device, so uninstalling produces a brand new user and orphans the
  /// old row. Surviving a reinstall, or moving between phones, needs a real
  /// identity -- linking the anonymous account to Google sign-in -- which is a
  /// separate piece of work.
  static Future<GameStore> open(GameStore local, PlayerCloud cloud) async {
    final store = SyncedGameStore(local, cloud);
    await store.catchUp(await cloud.fetch());
    return store;
  }

  /// Adopts the cloud's copy if it is newer, then sends this device's up.
  ///
  /// Split out of [open] because the cloud now arrives after the app is
  /// already on screen: the same catch-up has to be possible a second or two
  /// into a session, not only before the first frame.
  Future<void> catchUp(CloudSnapshot? snapshot) async {
    final incoming = snapshot?.profile;
    if (incoming != null &&
        incoming.updatedAtMs > _local.loadProfile().updatedAtMs) {
      await _local.saveProfile(incoming);
      if (snapshot!.roster.isNotEmpty) await _local.saveRoster(snapshot.roster);
    }
    await _pushAll();
  }

  /// Everything this device knows, in the shapes the cloud stores it in.
  /// Used on startup, which is also what turns a player carried over from the
  /// old collection into a properly structured row.
  Future<void> _pushAll() async {
    await _cloud.pushProfile(_local.loadProfile());
    await _cloud.pushRoster(_local.loadRoster());
  }

  @override
  PlayerProfile loadProfile() => _local.loadProfile();

  @override
  List<BotProfile> loadRoster() => _local.loadRoster();

  @override
  Future<void> saveProfile(PlayerProfile profile) async {
    final previous = _local.loadProfile();
    final renamed = previous.displayName != profile.displayName;
    final stamped = profile.touched(DateTime.now());
    await _local.saveProfile(stamped);

    // Only on an actual rename -- every finished match saves the profile, and
    // an auth write per match would be pure waste.
    if (renamed && stamped.displayName.trim().isNotEmpty) {
      unawaited(_cloud.setDisplayName(stamped.displayName));
    }

    // Not awaited: the match is already saved on disk, and the upload must
    // never sit between the player and the result screen.
    unawaited(_cloud.pushProfile(stamped));

    // A save that arrived with a new match at the front of the history is the
    // one save that has a duel to file. Recognised here rather than through a
    // second store method, so nothing that already calls saveProfile has to
    // learn a new step.
    final latest = stamped.history.firstOrNull;
    if (latest != null &&
        latest.playedAtMs != previous.history.firstOrNull?.playedAtMs) {
      unawaited(_cloud.pushMatch(latest));
    }
  }

  @override
  Future<void> saveRoster(List<BotProfile> roster) async {
    await _local.saveRoster(roster);
    unawaited(_cloud.pushRoster(roster));
  }

  @override
  Future<void> clear() async {
    await _local.clear();
    // Reset means reset: the row leaves the leaderboard rather than sitting
    // there under the old name with nobody behind it.
    unawaited(_cloud.wipe());
  }
}

/// Fire-and-forget, stated explicitly so it reads as a decision rather than a
/// forgotten await.
void unawaited(Future<void> future) {
  future.catchError((Object error, StackTrace stack) {
    Report.swallowed(error, stack, 'background sync failed');
  });
}
