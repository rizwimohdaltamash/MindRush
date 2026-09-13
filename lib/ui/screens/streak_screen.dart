import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/rating/streak_rewards.dart';
import '../../router/app_router.dart';
import '../../state/providers.dart';
import '../theme.dart';

/// The streak ladder: what has been earned, and what is next.
///
/// A milestone is earned the moment the best streak reaches it and is never
/// taken away, so there is nothing to claim and nothing to miss. The screen is
/// a record rather than a chore.
class StreakScreen extends ConsumerWidget {
  const StreakScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final streak = profile.streak.displayed(DateTime.now());
    final best = profile.streak.best;
    final next = StreakRewards.nextAfter(streak);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.home),
        ),
        title: const Text('Streak Rewards'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            _Summary(streak: streak, best: best, xp: profile.streakXp),
            const SizedBox(height: 20),
            if (next != null) ...[
              Text('NEXT UP', style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 8),
              _NextCard(reward: next, streak: streak),
              const SizedBox(height: 22),
            ],
            Text('THE LADDER', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 10),
            for (final (index, reward) in StreakRewards.all.indexed)
              _Rung(
                reward: reward,
                earned: StreakRewards.isEarned(reward, best),
                isLast: index == StreakRewards.all.length - 1,
              ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.streak, required this.best, required this.xp});

  final int streak;
  final int best;
  final int xp;

  @override
  Widget build(BuildContext context) => AppCard(
    accent: AppColors.streak,
    child: Row(
      children: [
        const Icon(
          Icons.local_fire_department_rounded,
          color: AppColors.streak,
          size: 42,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$streak',
                    style: const TextStyle(
                      fontSize: 34,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      color: AppColors.streak,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    streak == 1 ? 'day streak' : 'day streak',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Best $best · $xp XP earned',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _NextCard extends StatelessWidget {
  const _NextCard({required this.reward, required this.streak});

  final StreakReward reward;
  final int streak;

  @override
  Widget build(BuildContext context) {
    final togo = reward.day - streak;
    // Progress towards this rung from the one below it, so the bar fills
    // steadily instead of restarting from zero each time.
    final floor = StreakRewards.all
        .where((r) => r.day < reward.day)
        .fold<int>(0, (m, r) => r.day > m ? r.day : m);
    final span = reward.day - floor;
    final done = (streak - floor).clamp(0, span);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  reward.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _XpTag(xp: reward.xp, muted: false),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$togo more ${togo == 1 ? 'day' : 'days'} to go.',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: span == 0 ? 1 : done / span),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 7,
                backgroundColor: AppColors.surfaceHigh,
                valueColor: const AlwaysStoppedAnimation(AppColors.streak),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One rung of the ladder, with the dotted spine running through it.
class _Rung extends StatelessWidget {
  const _Rung({
    required this.reward,
    required this.earned,
    required this.isLast,
  });

  final StreakReward reward;
  final bool earned;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colour = earned ? AppColors.streak : AppColors.textMuted;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: earned ? AppColors.streak : AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: colour, width: 2),
                  ),
                  child: earned
                      ? const Icon(
                          Icons.check_rounded,
                          size: 13,
                          color: AppColors.background,
                        )
                      : null,
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: earned
                          ? AppColors.streak.withValues(alpha: 0.45)
                          : AppColors.border,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
              child: AppCard(
                accent: earned ? AppColors.streak : null,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DAY ${reward.day}',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                              color: colour,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            reward.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            reward.blurb,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _XpTag(xp: reward.xp, muted: !earned),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _XpTag extends StatelessWidget {
  const _XpTag({required this.xp, required this.muted});

  final int xp;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colour = muted ? AppColors.textMuted : AppColors.streak;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: muted ? 0.10 : 0.18),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '+$xp XP',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: colour,
        ),
      ),
    );
  }
}
