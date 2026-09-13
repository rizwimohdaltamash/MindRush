import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bots/bot_profile.dart';
import '../core/challenge/duel_room.dart';
import '../core/challenge/friend_duel.dart';
import '../core/players/player_directory.dart';
import '../core/match/match_engine.dart';
import '../core/match/match_result.dart';
import '../core/models/game_mode.dart';
import '../data/duel_room_service.dart';
import '../data/error_report.dart';
import '../data/cloud_status.dart';
import '../data/photo_source.dart';
import '../data/players_repository.dart';
import '../data/game_store.dart';
import '../data/match_summary.dart';
import '../data/player_profile.dart';
import '../notifications/reminder_plan.dart';

/// Replaced at startup in `main` once the box is open, so every other
/// provider can read the store synchronously.
final gameStoreProvider = Provider<GameStore>(
  (ref) => throw StateError('gameStoreProvider must be overridden in main()'),
);

final randomProvider = Provider<Random>((ref) => Random());

/// Where an avatar photograph comes from. Overridden in main() with the
/// device camera and photo picker; the default one always cancels, so tests
/// and unsupported platforms need no camera.
final photoSourceProvider = Provider<PhotoSource>(
  (ref) => const NoPhotoSource(),
);

/// The parts of the app that cannot be ready at launch.
///
/// Firebase, signing in and the notification plugin are all slow enough to be
/// worth seeing the app without: they take a few hundred milliseconds each on
/// a good connection, and unbounded time on a bad one. So the app opens on
/// local storage -- which is the source of truth anyway -- and these arrive
/// afterwards, switching on the features that need them.
class Runtime {
  const Runtime({this.players, this.rooms, this.scheduler});

  final PlayerService? players;
  final DuelRoomService? rooms;
  final ReminderScheduler? scheduler;
}

class RuntimeNotifier extends Notifier<Runtime> {
  @override
  Runtime build() => const Runtime();

  /// Called once, when the slow half of startup has finished.
  void arrived({
    PlayerService? players,
    DuelRoomService? rooms,
    ReminderScheduler? scheduler,
  }) => state = Runtime(
    players: players ?? state.players,
    rooms: rooms ?? state.rooms,
    scheduler: scheduler ?? state.scheduler,
  );
}

final runtimeProvider = NotifierProvider<RuntimeNotifier, Runtime>(
  RuntimeNotifier.new,
);

/// Queues the daily streak reminder. Does nothing until the platform plugin
/// is ready, and on web and desktop where there is none.
final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => ref.watch(runtimeProvider).scheduler ?? const NoopScheduler(),
);

/// The bot roster, ratings included. Mutated in place by the match engine
/// (zero-sum against the player) and written back after every match.
class RosterNotifier extends Notifier<List<BotProfile>> {
  @override
  List<BotProfile> build() => ref.read(gameStoreProvider).loadRoster();

  Future<void> persist() {
    // The match engine applies the zero-sum rating change to the bot object
    // in place, which Riverpod cannot observe. Re-emit the list so anything
    // already watching -- the leaderboard, which stays alive in the tab
    // IndexedStack -- refreshes instead of showing yesterday's ratings.
    state = [...state];
    return ref.read(gameStoreProvider).saveRoster(state);
  }

  void reset() {
    state = BotProfile.seedRoster();
  }
}

final rosterProvider = NotifierProvider<RosterNotifier, List<BotProfile>>(
  RosterNotifier.new,
);

/// The player. Every change writes straight through to disk, so closing the
/// app mid-session never loses a match.
class ProfileNotifier extends Notifier<PlayerProfile> {
  @override
  PlayerProfile build() => ref.read(gameStoreProvider).loadProfile();

  Future<void> _save() => ref.read(gameStoreProvider).saveProfile(state);

  Future<void> setName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(displayName: trimmed);
    await _save();
  }

  /// Choosing a character is also how a photo is taken off: whatever was
  /// tapped is what the face becomes.
  Future<void> setAvatar(int avatarId) async {
    state = state.copyWith(avatarId: avatarId, clearPhoto: true);
    await _save();
  }

  /// A photograph as a small square PNG, base64 encoded, or null to go back
  /// to the character underneath.
  Future<void> setPhoto(String? photo) async {
    state = state.copyWith(photo: photo, clearPhoto: photo == null);
    await _save();
  }

  /// Turning reminders off cancels what is already queued rather than merely
  /// stopping the next one being scheduled -- an alarm the player has just
  /// switched off must not still go off tonight.
  Future<void> setReminders(bool enabled) async {
    state = state.copyWith(remindersEnabled: enabled);
    await _save();
    if (enabled) {
      await ref.read(reminderSchedulerProvider).requestPermission();
    }
    await _rescheduleReminder(DateTime.now());
  }

  /// Files a finished match: rating, streak and history for the player, plus
  /// the bot's opposing rating change that the engine already applied.
  Future<MatchSummary> recordMatch(MatchResult result, GameMode mode) async {
    final now = DateTime.now();
    final summary = MatchSummary.from(result, mode, now);
    state = state.withMatch(summary, now);
    await _save();
    await ref.read(rosterProvider.notifier).persist();
    await _rescheduleReminder(now);
    return summary;
  }

  /// Moves the streak reminder to one day after this match.
  ///
  /// Doing it on every match is what keeps a plain scheduled notification
  /// correct with no background work: playing again replaces the pending
  /// reminder, and skipping a day leaves the queued one to fire exactly when
  /// the streak is about to lapse. Failures are swallowed -- a phone that
  /// will not schedule a nudge must never break recording a match.
  Future<void> _rescheduleReminder(DateTime now) async {
    final scheduler = ref.read(reminderSchedulerProvider);
    try {
      await scheduler.cancelAll();
      if (!state.remindersEnabled) return;
      for (final plan in ReminderPlanner.plans(state, now)) {
        await scheduler.schedule(plan);
      }
    } catch (error, stack) {
      // Reminders are a convenience, never a requirement -- but one that has
      // stopped working for everybody is worth hearing about.
      Report.swallowed(error, stack, 'could not queue the reminders');
    }
  }

  /// Prompts for notification permission the first time it is worth asking,
  /// and never again. Returns true only if this call did the asking.
  Future<bool> askAboutRemindersOnce() async {
    if (state.askedAboutReminders) return false;
    state = state.copyWith(askedAboutReminders: true);
    await _save();
    try {
      await ref.read(reminderSchedulerProvider).requestPermission();
    } catch (error, stack) {
      // Declined or unavailable; the app is unchanged either way.
      Report.swallowed(error, stack, 'could not ask about reminders');
    }
    return true;
  }

  /// Ends this device's account for good.
  ///
  /// The account is anonymous -- a credential on this phone and nothing else
  /// -- so signing out is not a door that can be walked back through. The
  /// cloud row goes with it rather than being left on the leaderboard under
  /// a name nobody can log into again.
  Future<void> signOut() async {
    final service = ref.read(playerServiceProvider);
    await resetEverything();
    try {
      await service?.signOut();
    } catch (error, stack) {
      // Already signed out, or no network. The save is cleared either way,
      // and the next launch makes a new account.
      Report.swallowed(error, stack, 'could not sign out');
    }
  }

  Future<void> resetEverything() async {
    try {
      await ref.read(reminderSchedulerProvider).cancelAll();
    } catch (error, stack) {
      // Nothing to undo if the platform refused.
      Report.swallowed(error, stack, 'could not cancel the reminders');
    }
    await ref.read(gameStoreProvider).clear();
    ref.read(rosterProvider.notifier).reset();
    state = PlayerProfile.fresh();
  }
}

final profileProvider = NotifierProvider<ProfileNotifier, PlayerProfile>(
  ProfileNotifier.new,
);

/// The shared half of a friend duel, or null when this device has no
/// connection to Firestore.
///
/// Null is a real state the UI has to handle rather than paper over: two
/// people cannot play the same minute on two phones without a network, and
/// pretending otherwise by quietly substituting a bot would be a lie about
/// who the player just beat. It is also null for the first moment of every
/// launch, before the connection has been made.
final duelRoomServiceProvider = Provider<DuelRoomService?>(
  (ref) => ref.watch(runtimeProvider).rooms,
);

/// The register of registered players -- the heartbeat and the board --
/// or null when this device has no connection.
final playerServiceProvider = Provider<PlayerService?>(
  (ref) => ref.watch(runtimeProvider).players,
);

/// What the cloud last did. Overridden in main() with the monitor the
/// repository reports into; the default one nothing writes to, so tests and
/// offline builds simply read "playing on this device only".
final cloudMonitorProvider = Provider<CloudMonitor>((ref) => CloudMonitor.none);

/// Every registered player, with this device's own heartbeat as the reference
/// clock for deciding who counts as online.
///
/// This is the whole player base, not a list of people this device has
/// happened to duel. Anyone who has opened MindRush and picked a name is on
/// it, which is what makes the leaderboard a leaderboard.
final directoryProvider = StreamProvider<PlayerDirectory>((ref) {
  final service = ref.watch(playerServiceProvider);
  if (service == null) return Stream.value(PlayerDirectory.empty);
  return service.watch().map(
    (players) => PlayerDirectory(players, myUid: service.myUid),
  );
});

/// Challenges addressed to this player, filtered to the ones still worth
/// answering. Stale and answered rooms are dropped here rather than in the UI,
/// so nothing has to remember the rule twice.
final invitesProvider = StreamProvider<List<DuelRoom>>((ref) {
  final service = ref.watch(duelRoomServiceProvider);
  if (service == null) return Stream.value(const []);
  return service.watchInvites(service.myUid).map((rooms) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return [
      for (final room in rooms)
        if (room.isLiveInviteFor(service.myUid, nowMs: nowMs)) room,
    ];
  });
});

/// Challenges already answered, so declining one does not bring it back round
/// as a fresh question.
///
/// It lives here rather than in the widget because more than one screen asks:
/// the tabs and the result screen both carry an inbox, and a challenge turned
/// down on one must not be put again by the other. Held per app rather than
/// per process, so a room code is not remembered across a restart -- or, more
/// to the point, across a test.
final answeredChallengesProvider = Provider<Set<String>>((ref) {
  // Kept alive explicitly. Providers dispose themselves once nothing is
  // listening, and every reader of this one reads it from a callback rather
  // than watching it -- so without this the set would be thrown away between
  // reads and a declined challenge would come straight back.
  ref.keepAlive();
  return <String>{};
});

/// Builds matches against the live roster at the player's current rating.
final matchFactoryProvider = Provider<MatchFactory>(
  (ref) => MatchFactory(
    roster: ref.watch(rosterProvider),
    random: ref.watch(randomProvider),
  ),
);

/// Convenience for the duel screen: a fresh engine for [mode], optionally
/// against a shared challenge [seed].
MatchEngine createMatch(WidgetRef ref, GameMode mode, {int? seed}) {
  final profile = ref.read(profileProvider);
  return ref
      .read(matchFactoryProvider)
      .create(
        mode: mode,
        playerRating: profile.ratingIn(mode.category),
        seed: seed,
      );
}

/// A live duel against the person in the other seat of [friend]'s room.
MatchEngine createFriendMatch(WidgetRef ref, FriendDuel friend) {
  final profile = ref.read(profileProvider);
  return ref
      .read(matchFactoryProvider)
      .createFriendDuel(
        friend: friend,
        playerRating: profile.ratingIn(friend.room.mode.category),
      );
}
