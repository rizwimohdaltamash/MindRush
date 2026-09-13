import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/match/match_result.dart';
import '../../core/models/game_mode.dart';
import '../../core/rating/streak_rewards.dart';
import '../../router/app_router.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/wiggle_button.dart';
import '../widgets/challenge.dart';
import '../widgets/challenge_inbox.dart';
import '../widgets/staggered_list.dart';

class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({
    super.key,
    required this.result,
    required this.mode,
    this.milestone,
  });

  final MatchResult result;
  final GameMode mode;

  /// A streak rung this match crossed, shown over the result once.
  final StreakReward? milestone;

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  MatchResult get result => widget.result;
  GameMode get mode => widget.mode;

  @override
  void initState() {
    super.initState();
    // The notification prompt goes here, on a win, and only once: a player who
    // has just beaten someone is far likelier to say yes than one who has only
    // seen a splash screen.
    if (result.outcome == MatchOutcome.win) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(profileProvider.notifier).askAboutRemindersOnce();
      });
    }

    // A milestone is worth interrupting for; it happens a handful of times in
    // a player's life, not every match.
    final milestone = widget.milestone;
    if (milestone != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        HapticFeedback.heavyImpact();
        showDialog<void>(
          context: context,
          builder: (context) => _MilestoneDialog(reward: milestone),
        );
      });
    }
  }

  /// Sends the person who just played this match another challenge.
  ///
  /// Only ever reachable against a real opponent: a rematch is a request that
  /// has to arrive on somebody's phone and be accepted there, and a bot has
  /// no phone. The mode is carried through, so neither side is asked which
  /// duel they meant -- they have just played it.
  void _rematch() {
    final uid = result.opponentUid;
    if (uid == null) return;
    Challenge.challengeDirect(
      context,
      ref,
      uid: uid,
      name: result.opponentName,
      mode: mode,
    );
  }

  Color get _outcomeColor => result.abandoned
      ? AppColors.textMuted
      : switch (result.outcome) {
          MatchOutcome.win => AppColors.win,
          MatchOutcome.loss => AppColors.loss,
          MatchOutcome.draw => AppColors.textMuted,
        };

  String get _headline => result.abandoned
      ? 'GAME ABORTED'
      : switch (result.outcome) {
          MatchOutcome.win => 'VICTORY',
          MatchOutcome.loss => 'DEFEAT',
          MatchOutcome.draw => 'DRAW',
        };

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final delta = result.ratingDelta;
    // Wrapped so a rematch can arrive here as well as leave from here. Both
    // players finish a duel on this screen, so this is where the second one
    // has to be asked.
    return ChallengeInbox(
      child: Scaffold(
        body: SafeArea(
          child: StaggeredList(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
            children: [
              Center(
                child: Text(
                  _headline,
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    color: _outcomeColor,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _ScoreBlock(
                      label: 'You',
                      avatarName: profile.displayName,
                      avatarId: profile.avatarId,
                      photo: profile.photo,
                      score: result.playerScore,
                      color: mode.color,
                    ),
                  ),
                  Expanded(
                    child: _ScoreBlock(
                      label: result.opponentName,
                      avatarName: result.opponentName,
                      score: result.opponentScore,
                      color: AppColors.textMuted,
                      avatarId: result.opponentAvatarId,
                      photo: result.opponentPhoto,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (result.abandoned)
                // No rating, no accuracy, no chart. Each would be a statistic
                // about a match that did not happen; saying so once, plainly,
                // is the whole of what there is to report.
                AppCard(
                  accent: AppColors.textMuted,
                  child: Column(
                    children: [
                      const Icon(
                        Icons.timer_off_outlined,
                        color: AppColors.textMuted,
                        size: 30,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        result.abandonedByYou
                            ? 'You stopped answering, so the duel was '
                                  'called off.'
                            : '${result.opponentName} stopped playing, so '
                                  'the duel was called off.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'The scores stand, but nothing was rated for either '
                        'side and nothing was saved.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                )
              else
                AppCard(
                  accent: _outcomeColor,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '${result.ratingBefore}',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          color: AppColors.textMuted,
                          size: 20,
                        ),
                      ),
                      Text(
                        '${result.ratingAfter}',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(color: _outcomeColor),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _outcomeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${delta >= 0 ? '+' : ''}$delta',
                          style: TextStyle(
                            color: _outcomeColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              if (!result.abandoned && result.questionsSlower > 0)
                Center(
                  child: Text(
                    'You were slower in ${result.questionsSlower} '
                    '${result.questionsSlower == 1 ? "question" : "questions"}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              const SizedBox(height: 20),
              if (!result.abandoned)
                Row(
                  children: [
                    Expanded(
                      child: _StatTile(
                        label: 'Answered',
                        value: '${result.questionsAnswered}',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatTile(
                        label: 'Accuracy',
                        value: '${(result.accuracy * 100).round()}%',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatTile(
                        label: 'Avg time',
                        value:
                            '${(result.averageAnswerMs / 1000).toStringAsFixed(1)}s',
                      ),
                    ),
                  ],
                ),
              if (!result.abandoned) ...[
                const SizedBox(height: 24),
                Text(
                  'ANSWER BY ANSWER SPEED',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 12),
                AppCard(
                  child: _SpeedChart(
                    points: result.speedByQuestion,
                    playerColor: mode.color,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: Wiggle(
                  onPressed: () => context.go(AppRoutes.home),
                  builder: (context, press) => FilledButton(
                    onPressed: press,
                    style: FilledButton.styleFrom(
                      backgroundColor: mode.color,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Back to Home'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Against a real person the obvious next move is the same person
              // again -- so it is offered before the generic ones, and it says
              // whose name it is going to.
              if (result.opponentIsReal) ...[
                SizedBox(
                  width: double.infinity,
                  child: Wiggle(
                    onPressed: _rematch,
                    builder: (context, press) => OutlinedButton.icon(
                      key: const ValueKey('rematch'),
                      onPressed: press,
                      icon: const Icon(Icons.replay_rounded, size: 18),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: mode.color,
                        side: BorderSide(
                          color: mode.color.withValues(alpha: 0.7),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      label: Text('Rematch ${result.opponentName}'),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'They get to accept or decline.',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('play-a-friend'),
                  // The board, carrying this duel with it, rather than a share
                  // sheet. A link is for somebody who does not have the game;
                  // straight after a match the interesting question is which
                  // of the people already on it you want next -- and that is a
                  // list with a search box, not a WhatsApp message.
                  onPressed: () => context.go(AppRoutes.findFriend(mode)),
                  icon: const Icon(Icons.groups_rounded, size: 18),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.text,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  label: const Text('Play a friend'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: Wiggle(
                  onPressed: () =>
                      context.pushReplacement(AppRoutes.duel(mode)),
                  builder: (context, press) => TextButton(
                    onPressed: press,
                    child: const Text(
                      'Play again',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreBlock extends StatelessWidget {
  const _ScoreBlock({
    required this.label,
    required this.avatarName,
    required this.score,
    required this.color,
    required this.avatarId,
    this.photo,
  });

  final String label;

  /// The badge shows an initial, which should come from the person's name
  /// even when the label reads "You".
  final String avatarName;
  final int score;
  final Color color;
  final int avatarId;
  final String? photo;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      AvatarBadge(avatarId: avatarId, name: avatarName, photo: photo, size: 34),
      const SizedBox(height: 8),
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 4),
      Text(
        '$score',
        style: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    ],
  );
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
  );
}

/// Paired bars, one column per question: the player's time against the
/// opponent's. Shorter is better, so a player who is winning shows a row of
/// stubs beside taller grey bars.
class _SpeedChart extends StatelessWidget {
  const _SpeedChart({required this.points, required this.playerColor});

  final List<SpeedPoint> points;
  final Color playerColor;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const SizedBox(
        height: 90,
        child: Center(
          child: Text(
            'No answers this match',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
      );
    }

    // Cap the scale so one very slow answer does not flatten everything else.
    final times = [
      for (final p in points) ...[p.playerMs, p.opponentMs],
    ].whereType<int>().toList()..sort();
    final scale = times[(times.length * 0.9).floor().clamp(0, times.length - 1)]
        .clamp(1, 1 << 30);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 90,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final point in points.take(40))
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _Bar(
                          ms: point.playerMs,
                          scale: scale,
                          color: playerColor,
                        ),
                        const SizedBox(width: 1),
                        _Bar(
                          ms: point.opponentMs,
                          scale: scale,
                          color: AppColors.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _LegendDot(color: playerColor, label: 'You'),
            const SizedBox(width: 16),
            _LegendDot(color: AppColors.textMuted, label: 'Opponent'),
          ],
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.ms, required this.scale, required this.color});

  final int? ms;
  final int scale;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final value = ms;
    if (value == null) return const Expanded(child: SizedBox.shrink());
    final fraction = (value / scale).clamp(0.05, 1.0);
    return Expanded(
      child: Container(
        height: 90 * fraction,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.85),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

/// "You hit a seven-day streak. Next stop: fourteen."
class _MilestoneDialog extends ConsumerWidget {
  const _MilestoneDialog({required this.reward});

  final StreakReward reward;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final next = StreakRewards.nextAfter(reward.day);

    return AlertDialog(
      backgroundColor: AppColors.surface,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            color: AppColors.streak,
            size: 54,
          ),
          const SizedBox(height: 12),
          Text(
            '${reward.day}-day streak',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            reward.blurb,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.streak.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '+${reward.xp} XP',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.streak,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            next == null
                ? 'That is the top of the ladder. ${profile.streakXp} XP total.'
                : 'Next up: day ${next.day} for +${next.xp} XP.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            context.push(AppRoutes.streak);
          },
          child: const Text(
            'See the ladder',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.streak,
            foregroundColor: Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text('Nice'),
        ),
      ],
    );
  }
}
