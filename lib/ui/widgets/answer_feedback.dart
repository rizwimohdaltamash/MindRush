import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/match/match_result.dart';
import '../theme.dart';

/// How an answer landed.
///
/// Three states rather than two, because Mind Snap awards partial credit --
/// recalling five cells of six is neither a hit nor a miss, and showing it as
/// either would misreport what just happened.
enum AnswerVerdict {
  perfect,
  partial,
  wrong;

  static AnswerVerdict of(AnswerRecord record) {
    if (record.wasCorrect) return AnswerVerdict.perfect;
    return record.scoredPoints ? AnswerVerdict.partial : AnswerVerdict.wrong;
  }

  Color get color => switch (this) {
    AnswerVerdict.perfect => AppColors.win,
    AnswerVerdict.partial => AppColors.streak,
    AnswerVerdict.wrong => AppColors.loss,
  };

  IconData get icon => switch (this) {
    AnswerVerdict.perfect => Icons.check_rounded,
    AnswerVerdict.partial => Icons.adjust_rounded,
    AnswerVerdict.wrong => Icons.close_rounded,
  };

  /// Distinct by feel, not just by colour -- during a sprint the player is
  /// reading the next question, not watching for a flash.
  Future<void> tap() => switch (this) {
    AnswerVerdict.perfect => HapticFeedback.lightImpact(),
    AnswerVerdict.partial => HapticFeedback.selectionClick(),
    AnswerVerdict.wrong => HapticFeedback.heavyImpact(),
  };
}

/// The flash shown over the question area the instant an answer is submitted.
///
/// The question advances immediately -- holding it would wreck the pace of a
/// 60-second race -- so the verdict has to arrive as a fast, non-blocking
/// pulse laid over the next question rather than a screen the player has to
/// dismiss.
class AnswerFeedback extends StatelessWidget {
  const AnswerFeedback({
    super.key,
    required this.progress,
    required this.verdict,
    required this.points,
    required this.child,
  });

  /// Runs 0 -> 1 once per answer.
  final Animation<double> progress;
  final AnswerVerdict verdict;
  final int points;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        final t = progress.value;
        // Nothing to draw between answers.
        final fade = t == 0 || t == 1 ? 0.0 : (1 - t);

        return Stack(
          alignment: Alignment.center,
          children: [
            child,
            if (fade > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: verdict.color.withValues(alpha: fade * 0.8),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: verdict.color.withValues(alpha: fade * 0.22),
                          blurRadius: 28,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (fade > 0)
              Positioned(
                top: 4 + (1 - fade) * 26,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: fade,
                    child: _VerdictChip(verdict: verdict, points: points),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _VerdictChip extends StatelessWidget {
  const _VerdictChip({required this.verdict, required this.points});

  final AnswerVerdict verdict;
  final int points;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: verdict.color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: verdict.color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(verdict.icon, size: 16, color: verdict.color),
          const SizedBox(width: 5),
          Text(
            points > 0 ? '+$points' : 'Missed',
            style: TextStyle(
              color: verdict.color,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

/// Scales its child up briefly whenever [value] changes, so a rising score is
/// noticeable without the player looking away from the question.
class PopOnChange extends StatelessWidget {
  const PopOnChange({super.key, required this.value, required this.child});

  final int value;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    // The key restarts the tween on every change of value.
    key: ValueKey(value),
    tween: Tween(begin: 1.35, end: 1.0),
    duration: const Duration(milliseconds: 280),
    curve: Curves.easeOutBack,
    builder: (context, scale, child) =>
        Transform.scale(scale: scale, child: child),
    child: child,
  );
}
