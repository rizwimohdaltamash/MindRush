import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The streak, celebrated once a day.
///
/// Shown between the final buzzer and the result, and only on the first duel
/// of a day -- the moment the streak actually moves. Every match after that
/// goes straight to the result, because a celebration that fires every time
/// is just a delay.
class StreakFlare extends StatefulWidget {
  const StreakFlare({super.key, required this.days, required this.onDone});

  final int days;
  final VoidCallback onDone;

  /// How long the whole thing takes, start to finish.
  static const Duration duration = Duration(milliseconds: 1900);

  @override
  State<StreakFlare> createState() => _StreakFlareState();
}

class _StreakFlareState extends State<StreakFlare>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: StreakFlare.duration,
    // The flare is the reward, not a transition into one. A phone with
    // system animations off would run it in ninety-five milliseconds, which
    // is not a smaller celebration, it is no celebration.
    animationBehavior: AnimationBehavior.preserve,
  )..forward();

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onDone();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Eased 0 -> 1 over the first [end] of the run, then held.
  double _phase(double start, double end) {
    final t = ((_controller.value - start) / (end - start)).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          final rise = _phase(0, 0.35);
          final count = _phase(0.15, 0.6);
          final label = _phase(0.3, 0.7);
          // Fades out at the end rather than cutting, so the handover to the
          // result screen is a dissolve instead of a flicker.
          final exit = 1 - _phase(0.85, 1.0);

          return Opacity(
            opacity: exit,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Burst(progress: rise, glow: t),
                  const SizedBox(height: 26),
                  Opacity(
                    opacity: count,
                    child: Text(
                      '${(widget.days * count).round()}',
                      style: const TextStyle(
                        fontSize: 76,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -2,
                        color: AppColors.streak,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Opacity(
                    opacity: label,
                    child: Transform.translate(
                      offset: Offset(0, 12 * (1 - label)),
                      child: Column(
                        children: [
                          Text(
                            widget.days == 1 ? 'DAY STREAK' : 'DAY STREAK',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 3,
                              color: AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            widget.days == 1
                                ? 'A streak begins.'
                                : 'Kept alive.',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The flame, arriving with a ring of sparks.
class _Burst extends StatelessWidget {
  const _Burst({required this.progress, required this.glow});

  /// 0 -> 1 as the flame lands.
  final double progress;

  /// The whole run, used for the slow breathing halo.
  final double glow;

  @override
  Widget build(BuildContext context) {
    // Overshoots then settles, so the flame lands rather than fades in.
    final scale = 0.4 + Curves.easeOutBack.transform(progress) * 0.6;
    final halo = 0.45 + 0.25 * math.sin(glow * math.pi * 3);

    return SizedBox(
      width: 190,
      height: 190,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Sparks thrown outward as the flame lands.
          for (var i = 0; i < 8; i++)
            Transform.rotate(
              angle: i * math.pi / 4,
              child: Transform.translate(
                offset: Offset(0, -46 - 34 * progress),
                child: Opacity(
                  opacity: (1 - progress) * 0.9,
                  child: Container(
                    width: 5,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppColors.streak,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.streak.withValues(alpha: 0.10 * progress),
              boxShadow: [
                BoxShadow(
                  color: AppColors.streak.withValues(alpha: halo * progress),
                  blurRadius: 54,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: scale,
            child: const Icon(
              Icons.local_fire_department_rounded,
              size: 104,
              color: AppColors.streak,
            ),
          ),
        ],
      ),
    );
  }
}
