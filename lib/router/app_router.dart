import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/challenge/challenge_link.dart';
import '../core/challenge/friend_duel.dart';
import '../core/match/match_result.dart';
import '../core/rating/streak_rewards.dart';
import '../core/models/game_mode.dart';
import '../ui/screens/duel_screen.dart';
import '../ui/screens/home_screen.dart';
import '../ui/screens/leaderboard_screen.dart';
import '../ui/screens/mode_screen.dart';
import '../ui/screens/lobby_screen.dart';
import '../ui/screens/profile_screen.dart';
import '../ui/screens/result_screen.dart';
import '../ui/screens/settings_screen.dart';
import '../ui/screens/stats_screen.dart';
import '../ui/screens/streak_screen.dart';
import '../ui/shell.dart';

/// Every route in the app, and the only place that knows how a path is spelt.
///
/// Screens call [duel] rather than writing '/duel/${mode.name}' by hand --
/// the path was previously built in three separate files, so a change to the
/// pattern would have compiled fine and broken navigation at runtime.
abstract final class AppRoutes {
  static const String home = '/';
  static const String stats = '/stats';
  static const String ranks = '/ranks';
  static const String profile = '/profile';
  static const String result = '/result';

  /// The player's own settings: their face, their notifications, their
  /// account. Outside the tab shell, like the streak ladder -- somewhere you
  /// go and come back from.
  static const String settings = '/settings';

  /// The streak ladder. Outside the tab shell: it is opened from the streak
  /// card and closed again, not somewhere you live.
  static const String streak = '/streak';

  /// The declaration; use [duel] to build a real location.
  static const String duelPattern = '/duel/:mode';

  /// The poster for one duel, where play-anyone and play-a-friend part ways.
  static const String modePattern = '/mode/:mode';

  static String mode(GameMode mode) => '/mode/${mode.name}';

  /// Ranks, opened to find one person for a duel that has already been
  /// chosen. The mode rides in the query so the board can say what the
  /// challenge will be and skip asking a second time.
  static String findFriend(GameMode mode) => '$ranks?find=${mode.name}';

  /// Where a friend's WhatsApp link lands. Built by [ChallengeInvite.uri]
  /// rather than by hand, so the app and the link can never disagree about
  /// the shape of a challenge.
  static const String challengePattern = '/c/:code';

  /// An incoming challenge, accepted. Same route the WhatsApp link lands on.
  static String challenge(String code) => '/c/$code';

  /// The host's own lobby, waiting for the link to be tapped.
  static const String lobbyPattern = '/lobby/:code';

  static String lobby(String code) => '/lobby/$code';

  /// The live match itself. Takes a [FriendDuel] as its extra, so it is only
  /// ever reached from a lobby that has both players in it.
  static const String friendDuel = '/friend-duel';

  /// Location for a duel, optionally against a friend's exact question set.
  static String duel(GameMode mode, {int? seed}) {
    final base = '/duel/${mode.name}';
    return seed == null ? base : '$base?seed=$seed';
  }

  /// The tab order of the bottom bar; the shell branches follow this list.
  static const List<String> tabs = [home, stats, ranks, profile];
}

/// What the result screen needs, handed over through the router.
class ResultArgs {
  const ResultArgs(this.result, this.mode, {this.milestone});

  final MatchResult result;
  final GameMode mode;

  /// A streak rung crossed by this match, if any. Shown over the result.
  final StreakReward? milestone;
}

ChallengeInvite? _inviteFrom(GoRouterState state) => ChallengeInvite.fromCode(
  state.pathParameters['code'] ?? '',
  state.uri.queryParameters,
);

GoRoute _tab(String path, Widget child) =>
    GoRoute(path: path, builder: (_, _) => child);

/// The mode named in a path or query parameter, or null if it is not one.
GameMode? _modeNamed(String? name) =>
    GameMode.values.where((m) => m.name == name).firstOrNull;

/// Built per app instance rather than held in a top-level final, so tests get
/// a clean navigation stack instead of inheriting the previous test's.
///
/// [initialLocation] is where the app opens. It matters for one case: a friend
/// duel arriving as a tapped link on a phone that has to install the app and
/// pick a name first. That link is captured at launch and handed here, so it
/// is still waiting once the router finally exists.
GoRouter buildRouter({String? initialLocation}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    // Duels and results sit outside this shell, so the bottom bar
    // disappears during a match -- nothing competes with the clock.
    StatefulShellRoute.indexedStack(
      builder: (_, _, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(routes: [_tab(AppRoutes.home, const HomeScreen())]),
        StatefulShellBranch(
          routes: [_tab(AppRoutes.stats, const StatsScreen())],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.ranks,
              builder: (_, state) => LeaderboardScreen(
                findFor: _modeNamed(state.uri.queryParameters['find']),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [_tab(AppRoutes.profile, const ProfileScreen())],
        ),
      ],
    ),
    // The poster: one duel, and who you want to play it against.
    GoRoute(
      path: AppRoutes.modePattern,
      builder: (context, state) {
        final mode = _modeNamed(state.pathParameters['mode']);
        if (mode == null) return const HomeScreen();
        return ModeScreen(mode: mode);
      },
    ),
    GoRoute(
      path: AppRoutes.duelPattern,
      builder: (context, state) {
        final mode = _modeNamed(state.pathParameters['mode']);
        // An unknown mode means a mistyped or stale link; fall back to
        // home rather than crashing on a null.
        if (mode == null) return const HomeScreen();
        return DuelScreen(
          mode: mode,
          seed: int.tryParse(state.uri.queryParameters['seed'] ?? ''),
        );
      },
    ),
    // A challenge arriving from outside the app: a tapped link, or a cold
    // start from one. It opens the lobby and takes the empty seat; the
    // match cannot begin until the host is there too.
    GoRoute(
      path: AppRoutes.challengePattern,
      redirect: (context, state) => _inviteFrom(state) == null
          // A mistyped or truncated link drops the player on home rather
          // than into a lobby for a room that does not exist.
          ? AppRoutes.home
          : null,
      builder: (context, state) =>
          LobbyScreen(code: _inviteFrom(state)!.code, join: true),
    ),
    // The other side of the same room, where the host waits.
    GoRoute(
      path: AppRoutes.lobbyPattern,
      builder: (context, state) =>
          LobbyScreen(code: state.pathParameters['code'] ?? ''),
    ),
    GoRoute(
      path: AppRoutes.friendDuel,
      builder: (context, state) {
        final friend = state.extra;
        // Only ever reached from a lobby. A cold start on this path has no
        // room behind it, so there is nothing to play.
        if (friend is! FriendDuel) return const HomeScreen();
        return DuelScreen(mode: friend.room.mode, friend: friend);
      },
    ),
    GoRoute(
      path: AppRoutes.streak,
      builder: (context, state) => const StreakScreen(),
    ),
    GoRoute(
      path: AppRoutes.settings,
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: AppRoutes.result,
      builder: (context, state) {
        final args = state.extra;
        if (args is! ResultArgs) return const HomeScreen();
        return ResultScreen(
          result: args.result,
          mode: args.mode,
          milestone: args.milestone,
        );
      },
    ),
  ],
);
