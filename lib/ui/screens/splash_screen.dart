import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/brand_mark.dart';

/// The way in: three arcs arrive from three directions, lock into a ring, and
/// the whole mark turns once before the name lands under it.
///
/// It does not fade out at the end. It holds, and the sign-in screen behind
/// it opens with the mark, the name and the line already in exactly the same
/// places -- so the swap is invisible, and all the player sees is the button
/// rising into place under a logo that never moved. Fading one logo out and a
/// second one back in somewhere else is what made this feel like a jump.
///
/// It picks up where the native splash leaves off -- same mark, same
/// background colour -- so the handover from the OS to Flutter has no flash
/// and reads as one continuous piece. On Android 12+ the system owns the very
/// first frame and no Flutter code can run before it, which is why the two
/// have to be designed as a pair rather than as one screen.
///
/// There used to be a shockwave and fourteen sparks here as well. They were
/// dropped, and the whole thing is better for it: an intro is judged on
/// whether it moves smoothly, not on how much is moving, and every extra
/// layer was another thing to composite in the first second of a cold start
/// -- which is the one second in the app's life with the least frame budget
/// to spare. What is left is three arcs, a bolt and one soft glow.
///
/// It runs to the end before the app appears. That is only reasonable because
/// nothing is hiding behind it any more: the local save is already open when
/// this starts, and Firebase, signing in and the notification plugin now wait
/// until it is over rather than competing with it for frames. The intro is
/// the intro, not a loading screen wearing one -- so its length is a decision
/// rather than a symptom.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  static const Duration duration = Duration(milliseconds: 1950);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SplashScreen.duration,
    // Without this, a phone with system animations turned off runs every
    // AnimationController at five per cent of its duration -- so this intro
    // played in about a tenth of a second and looked, correctly, like no
    // animation at all. That setting is there to stop interface chrome
    // getting in somebody's way. This is not chrome; it is the thing on
    // screen, and shortening it does not save anybody any time.
    animationBehavior: AnimationBehavior.preserve,
  );

  Animation<double> _phase(double from, double to, Curve curve) =>
      CurvedAnimation(
        parent: _controller,
        curve: Interval(from, to, curve: curve),
      );

  /// The three arcs coming home along their own bearings.
  ///
  /// easeOutCubic rather than anything springy: they should glide in and stop,
  /// not arrive and wobble. A ring that overshoots reads as three loose parts
  /// rather than one mark.
  late final Animation<double> _fly = _phase(0.0, 0.40, Curves.easeOutCubic);

  /// One full turn of the assembled mark.
  ///
  /// It starts while the arcs are still travelling, which is what makes the
  /// join feel like one movement rather than two: the pieces curve in rather
  /// than sliding in straight, because the whole group is already turning as
  /// they land. easeInOutCubic winds up and winds down, and a whole turn is
  /// what puts the bolt back upright at the end of it.
  late final Animation<double> _turn = _phase(0.02, 0.68, Curves.easeInOutCubic);

  /// The bolt, arriving as the ring closes and riding the rest of the turn.
  late final Animation<double> _bolt = _phase(0.34, 0.48, Curves.easeOutCubic);

  /// A glow that swells under the mark as it locks together and then holds,
  /// so the ring sits in light rather than on flat black.
  late final Animation<double> _glow = _phase(0.30, 0.58, Curves.easeOut);

  /// The name, and the line under it.
  late final Animation<double> _word = _phase(0.48, 0.66, Curves.easeOutCubic);
  late final Animation<double> _tag = _phase(0.58, 0.72, Curves.easeOut);

  /// How far out the arcs begin, as a fraction of the mark's side.
  static const double _apart = 1.15;

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
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  // Smaller than the art it holds. The arcs start well
                  // outside the ring, and they are allowed to spill past this
                  // box rather than it reserving a screen of empty space
                  // under the mark that the name then sits below.
                  width: BrandStack.width,
                  height: BrandStack.height,
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      CustomPaint(
                        size: const Size(BrandStack.width, BrandStack.height),
                        painter: BrandGlow(_glow.value),
                      ),
                      // No fade. The three arcs are at full strength on the
                      // very first frame Flutter draws, because Android is
                      // showing its own still picture of the mark right up
                      // until that frame -- and a frame that starts empty
                      // makes the icon blink out of existence before the
                      // animation begins. The pieces are simply already
                      // there, out on their bearings, and the first thing
                      // that happens is that they move.
                      Transform.rotate(
                        angle: _turn.value * 2 * math.pi,
                        child: BrandMark(
                          size: BrandStack.markSize,
                          spread: _apart * (1 - _fly.value),
                          boltOpacity: _bolt.value,
                          background: false,
                        ),
                      ),
                    ],
                  ),
                ),
                BrandWordmark(reveal: _word.value),
                const SizedBox(height: BrandStack.underWord),
                Opacity(
                  opacity: _tag.value,
                  child: Text(
                    BrandStack.tagline,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(letterSpacing: 2.2),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
