import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/game_mode.dart';
import '../../core/rating/streak.dart';
import '../../data/cloud_status.dart';
import '../../data/match_summary.dart';
import '../../data/player_profile.dart';
import '../../router/app_router.dart';
import '../../state/providers.dart';
import '../theme.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final streak = profile.streak.displayed(DateTime.now());

    // An inline header rather than an AppBar, matching Stats and Ranks --
    // this is a tab root, so a Material app bar would imply a back button
    // that has nowhere to go.
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text('Profile', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                AvatarBadge(
                  avatarId: profile.avatarId,
                  name: profile.displayName,
                  photo: profile.photo,
                  size: 56,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.displayName,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      Text(
                        _joined(profile),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _editName(context, ref, profile.displayName),
                  child: const Text('Edit'),
                ),
                IconButton(
                  tooltip: 'Settings',
                  onPressed: () => context.push(AppRoutes.settings),
                  icon: const Icon(
                    Icons.settings_rounded,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text('RATINGS', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 10),
            for (final category in Category.values) ...[
              AppCard(
                accent: category.color,
                child: Row(
                  children: [
                    Icon(category.icon, color: category.color, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        category.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      '${profile.winRate(category) * 100 ~/ 1}% win',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${profile.ratingIn(category)}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: category.color,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 20),
            AppCard(
              accent: AppColors.streak,
              // The badges say what has been earned; the ladder says what it
              // was worth and what is next, which is the question looking at
              // them provokes.
              onTap: () => context.push(AppRoutes.streak),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.local_fire_department_rounded,
                        color: AppColors.streak,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '$streak day streak',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      Text(
                        'Best ${profile.streak.best}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final threshold in StreakCalculator.badgeThresholds)
                        Expanded(
                          child: Opacity(
                            opacity: profile.streak.current >= threshold
                                ? 1
                                : 0.25,
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.local_fire_department_rounded,
                                  color: AppColors.streak,
                                  size: 20,
                                ),
                                Text(
                                  '$threshold',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'RECENT MATCHES',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 10),
            if (profile.history.isEmpty)
              const AppCard(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No matches yet',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                ),
              )
            else
              for (final match in profile.history.take(10)) ...[
                _HistoryRow(match: match),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }

  Future<void> _editName(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 16,
          decoration: const InputDecoration(hintText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null) {
      await ref.read(profileProvider.notifier).setName(name);
    }
  }
}

/// How long they have been playing, in place of the old level number --
/// which was a rating restated in a smaller unit and told nobody anything.
String _joined(PlayerProfile profile) {
  final played = profile.history.length;
  if (played == 0) return 'No duels yet';
  return '$played ${played == 1 ? 'duel' : 'duels'} played';
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.match});

  final MatchSummary match;

  @override
  Widget build(BuildContext context) {
    final color = match.won ? AppColors.win : AppColors.loss;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(match.mode.icon, size: 18, color: match.mode.color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  match.mode.label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  'vs ${match.opponentName}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          Text(
            '${match.playerScore} - ${match.opponentScore}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(width: 12),
          Text(
            '${match.ratingDelta >= 0 ? '+' : ''}${match.ratingDelta}',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Whether anything is actually reaching the server, said plainly.
///
/// This exists because every upload in the app is fire-and-forget: a finished
/// match is saved to disk and pushed without being waited on, so that a slow
/// network can never sit between a player and their result. The cost is that
/// a build whose writes are all being refused behaves exactly like one that
/// is working -- the game plays, the scores are right, and nothing at all
/// arrives in Firestore. This is the one place that says which of the two is
/// happening, and what to do about it.
class CloudStatusCard extends StatelessWidget {
  const CloudStatusCard({super.key, required this.monitor});

  final CloudMonitor monitor;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<CloudHealth>(
    valueListenable: monitor,
    builder: (context, health, _) {
      final colour = switch (health.state) {
        CloudState.synced => AppColors.win,
        CloudState.refused => AppColors.loss,
        CloudState.failing => AppColors.streak,
        CloudState.offline => AppColors.textMuted,
      };
      final icon = switch (health.state) {
        CloudState.synced => Icons.cloud_done_rounded,
        CloudState.refused => Icons.gpp_bad_rounded,
        CloudState.failing => Icons.cloud_off_rounded,
        CloudState.offline => Icons.smartphone_rounded,
      };

      return AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colour, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    health.summary,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (health.advice case final advice?) ...[
                    const SizedBox(height: 4),
                    Text(
                      advice,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(letterSpacing: 0.2),
                    ),
                  ],
                  if (health.detail case final detail?) ...[
                    const SizedBox(height: 6),
                    // The server's own word for it. Ugly on purpose:
                    // it is the thing worth reading out to somebody who
                    // can fix it.
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: colour,
                      ),
                    ),
                  ],
                  if (health.uid case final uid?) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Account ${uid.substring(0, uid.length.clamp(0, 8))}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
