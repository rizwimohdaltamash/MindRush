import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/brand_mark.dart';

/// The way in: the mark assembles, the bolt strikes it, and the name arrives.
///
/// It picks up where the native splash leaves off -- same mark, same
/// background colour -- so the handover from the OS to Flutter has no flash
/// and reads as one continuous piece. On Android 12+ the system owns the very
/// first frame and no Flutter code can run before it, which is why the two
/// have to be designed as a pair rather than as one screen.
///
/// It runs to the end before the app appears. That is only reasonable because
/// nothing is hiding behind it any more: the local save is already open when
/// this starts, and Firebase, signing in and the notification plugin now
/// connect after the app is up. The intro is the intro, not a loading screen
/// wearing one -- so its length is a decision rather than a symptom.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  static const Duration duration = Duration(milliseconds: 1750);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SplashScreen.duration,
  );

  Animation<double> _phase(double from, double to, Curve curve) =>
      CurvedAnimation(
        parent: _controller,
        curve: Interval(from, to, curve: curve),
      );

  /// The three arcs draw themselves round the ring.
  late final Animation<double> _sweep = _phase(0.0, 0.30, Curves.easeOutCubic);

  /// The mark arrives small and settles, turning as it comes.
  late final Animation<double> _rise = _phase(0.0, 0.34, Curves.easeOutBack);

  /// The bolt does not fade in. It lands.
  late final Animation<double> _bolt = _phase(0.24, 0.36, Curves.easeOutExpo);

  /// What the strike throws off: a ring of light and a scatter of sparks in
  /// the three category colours.
  late final Animation<double> _shock = _phase(0.26, 0.62, Curves.easeOutCubic);
  late final Animation<double> _sparks = _phase(
    0.27,
    0.80,
    Curves.easeOutCubic,
  );

  /// A glow that swells under the mark on the strike and then holds, so the
  /// ring sits in light rather than on a flat black.
  late final Animation<double> _glow = _phase(0.10, 0.45, Curves.easeOut);

  /// The name, and the line under it.
  late final Animation<double> _word = _phase(0.40, 0.66, Curves.easeOutCubic);
  late final Animation<double> _sheen = _phase(0.48, 0.82, Curves.easeInOut);
  late final Animation<double> _tag = _phase(0.58, 0.80, Curves.easeOut);

  /// And the whole thing lifts away rather than cutting, so the first screen
  /// of the app is arrived at instead of jumped to.
  late final Animation<double> _exit = _phase(0.86, 1.0, Curves.easeInCubic);

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(() {
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final exit = _exit.value;
          return Opacity(
            opacity: 1 - exit,
            child: Transform.translate(
              offset: Offset(0, -26 * exit),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      // Narrower than the art it holds: the shockwave is
                      // allowed to spill past this box rather than reserving
                      // dead space under the mark that the wordmark then has
                      // to sit below.
                      width: 300,
                      height: 168,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          // Glow, shockwave and sparks all live in one
                          // painter: they are lit by the same moment and it
                          // keeps the layer count down.
                          CustomPaint(
                            size: const Size(300, 300),
                            painter: _Strike(
                              glow: _glow.value,
                              shock: _shock.value,
                              sparks: _sparks.value,
                            ),
                          ),
                          Transform.rotate(
                            // A quarter-turn's worth of settle, unwinding as
                            // it arrives. The ring is a circle, so the turn
                            // reads as momentum rather than as crookedness.
                            angle: (1 - _rise.value) * -0.5,
                            child: Transform.scale(
                              // Overshoots slightly on the way in; easeOutBack
                              // does the settling.
                              scale: 0.55 + 0.45 * _rise.value,
                              child: BrandMark(
                                size: 128,
                                sweep: _sweep.value,
                                boltOpacity: _bolt.value,
                                background: false,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _Wordmark(reveal: _word.value, sheen: _sheen.value),
                    const SizedBox(height: 8),
                    Opacity(
                      opacity: _tag.value,
                      child: Transform.translate(
                        offset: Offset(0, 8 * (1 - _tag.value)),
                        child: Text(
                          'SIXTY SECONDS. ONE WINNER.',
                          style: Theme.of(
                            context,
                          ).textTheme.labelSmall?.copyWith(letterSpacing: 2.2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The name, rising into place with a single pass of light across it.
///
/// The sheen is what stops the wordmark being a label that merely appeared:
/// it is one gradient sweep, and it costs one shader.
class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.reveal, required this.sheen});

  final double reveal;
  final double sheen;

  @override
  Widget build(BuildContext context) {
    const name = Text(
      'MindRush',
      style: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.6,
        color: AppColors.text,
      ),
    );

    return Opacity(
      opacity: reveal,
      child: Transform.translate(
        offset: Offset(0, 16 * (1 - reveal)),
        child: sheen <= 0 || sheen >= 1
            ? name
            : ShaderMask(
                blendMode: BlendMode.srcATop,
                shaderCallback: (bounds) {
                  // A narrow band of brightness travelling left to right.
                  final x = bounds.width * (sheen * 2 - 0.5);
                  return LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: const [
                      AppColors.text,
                      Colors.white,
                      AppColors.text,
                    ],
                    stops: [
                      ((x - 60) / bounds.width).clamp(0.0, 1.0),
                      (x / bounds.width).clamp(0.0, 1.0),
                      ((x + 60) / bounds.width).clamp(0.0, 1.0),
                    ],
                  ).createShader(bounds);
                },
                child: name,
              ),
      ),
    );
  }
}

/// What the bolt landing throws off.
class _Strike extends CustomPainter {
  const _Strike({
    required this.glow,
    required this.shock,
    required this.sparks,
  });

  final double glow;
  final double shock;
  final double sparks;

  /// Fixed rather than random: the intro should look the same every launch,
  /// and a screenshot of it should be reproducible.
  static const List<double> _angles = [
    0.18, 0.62, 1.05, 1.48, 1.96, 2.42, 2.88, 3.34,
    3.78, 4.22, 4.68, 5.12, 5.58, 6.02, //
  ];

  static const List<Color> _palette = [
    AppColors.math,
    AppColors.memory,
    AppColors.logic,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);

    if (glow > 0) {
      final radius = 60 + 70 * glow;
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              AppColors.math.withValues(alpha: 0.16 * glow),
              AppColors.memory.withValues(alpha: 0.06 * glow),
              Colors.transparent,
            ],
            stops: const [0.0, 0.45, 1.0],
          ).createShader(Rect.fromCircle(center: centre, radius: radius)),
      );
    }

    if (shock > 0 && shock < 1) {
      // Two rings, the second a beat behind, so the strike has depth rather
      // than being one hoop.
      for (final (index, delay) in [0.0, 0.22].indexed) {
        final t = ((shock - delay) / (1 - delay)).clamp(0.0, 1.0);
        if (t <= 0 || t >= 1) continue;
        final fade = (1 - t) * (1 - t);
        canvas.drawCircle(
          centre,
          58 + 92 * t,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (3.5 - index) * fade
            ..color = (index == 0 ? AppColors.text : AppColors.math).withValues(
              alpha: 0.5 * fade,
            ),
        );
      }
    }

    if (sparks > 0 && sparks < 1) {
      final fade = (1 - sparks) * (1 - sparks);
      for (final (index, angle) in _angles.indexed) {
        // Alternating lengths, so the scatter is not a perfect wheel.
        final reach = 62 + (index.isEven ? 74 : 52) * sparks;
        final at = centre + Offset(math.cos(angle), math.sin(angle)) * reach;
        canvas.drawCircle(
          at,
          (index.isEven ? 3.0 : 2.2) * fade,
          Paint()..color = _palette[index % 3].withValues(alpha: 0.9 * fade),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_Strike old) =>
      old.glow != glow || old.shock != shock || old.sparks != sparks;
}
