import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/game_mode.dart';
import '../../core/players/avatar.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/brand_mark.dart';
import '../widgets/wiggle_button.dart';

/// First launch: the mark the intro just finished drawing, and one button.
///
/// This screen opens on the exact frame the intro ends on -- same mark, same
/// name, same line, same places, from the shared [BrandStack]. Nothing at the
/// top fades in, because none of it is arriving: it is already there, and the
/// player never sees a swap. All that moves is the button rising into place
/// underneath, and the light around the ring carrying on.
///
/// Google rather than a typed name, because a name on its own is not an
/// identity. An account that lived only on the device meant uninstalling the
/// app orphaned the player's leaderboard row and made a second one the next
/// time they played -- the same person, twice, with their rating split
/// between them. A Google account is the same account on the next install and
/// on the next phone.
///
/// Only the *first* launch needs a network for this. Firebase caches the
/// credential afterwards, so a returning player opens the app offline and
/// keeps everything.
///
/// There is no avatar grid here any more. Picking a face was the first thing
/// the game asked of somebody who had not yet played it, which is a poor
/// trade: a dozen faces to weigh up before a single question. The picker
/// lives in Settings, with the full set, where it can be changed as often as
/// they like.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  String? _failed;

  /// The light around the ring, and the button coming in under it.
  ///
  /// It runs once and stops. This screen is seen for a few seconds, so a loop
  /// would buy nothing a long single pass does not -- and it would keep a
  /// ticker alive behind an account picker, which is a frame budget spent on
  /// a screen nobody is looking at any more.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
    // See the intro: a phone with system animations off would otherwise run
    // this in a tenth of a second, and this screen is the other half of that
    // same piece.
    animationBehavior: AnimationBehavior.preserve,
  )..forward();

  Animation<double> _phase(double from, double to, Curve curve) =>
      CurvedAnimation(parent: _intro, curve: Interval(from, to, curve: curve));

  /// The logo climbing out of the middle of the screen once it has been
  /// handed over. It starts at nought, which is what keeps the handover frame
  /// identical to the intro's last one.
  late final Animation<double> _settle = _phase(0.02, 0.17, Curves.easeOutCubic);

  /// What the three colours of the ring stand for, arriving in order.
  late final List<Animation<double>> _pills = [
    _phase(0.10, 0.22, Curves.easeOutCubic),
    _phase(0.13, 0.25, Curves.easeOutCubic),
    _phase(0.16, 0.28, Curves.easeOutCubic),
  ];

  /// The button and the lines around it. The only thing the player is
  /// actually waiting for, so it does not keep them long.
  late final Animation<double> _form = _phase(0.18, 0.30, Curves.easeOutCubic);

  /// One pass of light across the name, a beat after everything has settled.
  late final Animation<double> _sheen = _phase(0.26, 0.58, Curves.easeInOut);

  /// A spark running the ring. Linear: a light doing laps should not slow
  /// down in the corners.
  late final Animation<double> _orbit = _phase(0.10, 1.0, Curves.linear);

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = null;
    });
    HapticFeedback.selectionClick();

    final user = await ref.read(signInGatewayProvider).prompt();
    if (!mounted) return;

    if (user == null) {
      // Covers both backing out of the account picker and failing to reach
      // Google at all. Said the same way either time, because the player's
      // next move is the same: tap it again.
      setState(() {
        _busy = false;
        _failed = 'Could not sign in. Check your connection and try again.';
      });
      return;
    }

    final notifier = ref.read(profileProvider.notifier);
    await notifier.setAvatar(_avatarFor(user.uid));
    // Setting the name last is what ends onboarding, so it must not happen
    // until the avatar is safely stored.
    await notifier.setName(user.name);
  }

  /// A face, drawn from the account instead of from a grid.
  ///
  /// All that onboarding needs of an avatar is that two players do not both
  /// turn up on the leaderboard as the same circle. The uid is stable across
  /// reinstalls and across phones, so the face is too: a player who wipes the
  /// app and signs back in gets the one they had.
  static int _avatarFor(String uid) {
    var hash = 7;
    for (final unit in uid.codeUnits) {
      hash = (hash * 31 + unit) & 0xffffff;
    }
    return hash % Avatars.count;
  }

  @override
  Widget build(BuildContext context) {
    // How far the logo climbs once it has been handed over. A share of the
    // screen rather than a fixed number, so a tall phone lifts further and a
    // short one does not push the mark off the top.
    final height = MediaQuery.sizeOf(context).height;
    final lift = height * 0.145;

    return Scaffold(
      // Not inside a SafeArea, because the intro is not either, and the two
      // have to centre against the same box for the logo to land in the same
      // place on the frame they swap.
      body: Stack(
        children: [
          Center(
            child: AnimatedBuilder(
              animation: _intro,
              builder: (context, _) => Transform.translate(
                // Dead centre on the handover frame, and only then does it
                // climb. Composing this screen properly and *also* matching
                // the intro are not the same layout, so it does one and then
                // moves to the other in front of the player.
                offset: Offset(0, -lift * _settle.value),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: BrandStack.width,
                      height: BrandStack.height,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          CustomPaint(
                            size: const Size(
                              BrandStack.width,
                              BrandStack.height,
                            ),
                            painter: BrandGlow(_breath),
                          ),
                          CustomPaint(
                            size: const Size(
                              BrandStack.width,
                              BrandStack.height,
                            ),
                            painter: _Comet(_orbit.value),
                          ),
                          const BrandMark(
                            size: BrandStack.markSize,
                            background: false,
                          ),
                        ],
                      ),
                    ),
                    _Sheen(sheen: _sheen.value),
                    const SizedBox(height: BrandStack.underWord),
                    Text(
                      BrandStack.tagline,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(letterSpacing: 2.2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                // Lifted well clear of the bottom edge. Pinned down there,
                // the button was a long way from the logo and the middle of
                // the screen was a hole; the two ends now meet in the middle
                // and the page reads as one composition.
                padding: EdgeInsets.fromLTRB(24, 0, 24, height * 0.13),
                child: AnimatedBuilder(
                  animation: _intro,
                  builder: (context, _) => _signInBlock(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// What the three arcs of the ring actually are.
  ///
  /// The middle of this screen was empty, and the ring above it is three
  /// colours with no explanation. These say what they stand for, which is
  /// both the thing that fills the gap and the only real answer to "what is
  /// this game" -- three kinds of question, one minute.
  Widget _categories(BuildContext context) => FittedBox(
    // Three words, three icons and their padding come to more than a narrow
    // phone has across. Shrinking them to fit beats wrapping to two lines,
    // which would move the button every time this screen was built on a
    // different handset.
    fit: BoxFit.scaleDown,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, category) in Category.values.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: _Pill(category: category, reveal: _pills[index].value),
          ),
      ],
    ),
  );

  /// The glow, breathing twice and landing back where the intro left it.
  ///
  /// Starts at 1, which is exactly the warmth the intro settles on -- so the
  /// first frame of this screen and the last frame of that one are the same
  /// picture.
  double get _breath =>
      1 - 0.25 * (0.5 - 0.5 * math.cos(_intro.value * math.pi * 4));

  Widget _signInBlock(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _categories(context),
      const SizedBox(height: 34),
      Opacity(
        opacity: _form.value,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - _form.value)),
          child: _theButton(context),
        ),
      ),
    ],
  );

  Widget _theButton(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: double.infinity,
        child: Wiggle(
          onPressed: _busy ? null : _start,
          builder: (context, press) => FilledButton(
            onPressed: press,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.math,
              foregroundColor: Colors.black,
              disabledBackgroundColor: AppColors.surfaceHigh,
              disabledForegroundColor: AppColors.textMuted,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Text(
                    'Continue with Google',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Text(
        _failed ??
            'Your name and face come from your Google account. '
                'You can change both in Settings.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _failed == null ? null : AppColors.loss,
        ),
      ),
    ],
  );
}

/// One of the three kinds of question, in its own colour.
///
/// The same three colours as the arcs of the ring above, deliberately: the
/// mark is not decoration, it is a picture of what the game is made of.
class _Pill extends StatelessWidget {
  const _Pill({required this.category, required this.reveal});

  final Category category;
  final double reveal;

  @override
  Widget build(BuildContext context) {
    final colour = category.color;
    return Opacity(
      opacity: reveal.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 14 * (1 - reveal)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: colour.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colour.withValues(alpha: 0.32)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(category.icon, color: colour, size: 16),
              const SizedBox(width: 7),
              Text(
                category.label,
                style: TextStyle(
                  color: colour,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The name, with one pass of light travelling across it.
///
/// The name itself is [BrandWordmark] at full reveal -- the intro has already
/// put it there. This only adds the shine, and falls back to the plain thing
/// at either end of the pass so the two screens match on the handover frame.
class _Sheen extends StatelessWidget {
  const _Sheen({required this.sheen});

  final double sheen;

  @override
  Widget build(BuildContext context) {
    const name = BrandWordmark();
    if (sheen <= 0 || sheen >= 1) return name;

    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (bounds) {
        // A narrow band of brightness travelling left to right.
        final x = bounds.width * (sheen * 2 - 0.5);
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [AppColors.text, Colors.white, AppColors.text],
          stops: [
            ((x - 60) / bounds.width).clamp(0.0, 1.0),
            (x / bounds.width).clamp(0.0, 1.0),
            ((x + 60) / bounds.width).clamp(0.0, 1.0),
          ],
        ).createShader(bounds);
      },
      child: name,
    );
  }
}

/// A spark doing laps of the ring, with a tail behind it.
class _Comet extends CustomPainter {
  const _Comet(this.orbit);

  /// 0 to 1 across [_laps] laps.
  final double orbit;

  static const int _laps = 2;

  /// How many dots make the comet, head included.
  static const int _tail = 10;

  /// Straight from BrandMark: ring radius is 0.315 of the mark's side.
  static const double _ringFraction = 0.315;

  static const List<Color> _palette = [
    AppColors.math,
    AppColors.memory,
    AppColors.logic,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (orbit <= 0 || orbit >= 1) return;

    // In over the first breath, out over the last: a spark that simply
    // stopped would read as a dropped frame.
    final presence =
        (orbit / 0.10).clamp(0.0, 1.0) * ((1 - orbit) / 0.22).clamp(0.0, 1.0);
    if (presence <= 0) return;

    final centre = Offset(size.width / 2, size.height / 2);
    final radius = BrandStack.markSize * _ringFraction;
    final head = -math.pi / 2 + orbit * _laps * 2 * math.pi;

    // A head and a tail behind it, each dot dimmer and smaller than the one
    // in front, which is a comet for the price of ten circles.
    for (var i = 0; i < _tail; i++) {
      final angle = head - i * 0.075;
      final falloff = (1 - i / _tail) * (1 - i / _tail);
      final at = centre + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawCircle(
        at,
        (3.6 - i * 0.26).clamp(0.6, 3.6),
        Paint()
          ..color = _colourAt(angle).withValues(alpha: presence * falloff),
      );
    }
  }

  /// The colour of whichever arc the spark is currently over, so it belongs
  /// to the ring rather than sitting on top of it.
  static Color _colourAt(double angle) {
    final turned = (angle + math.pi / 2) % (2 * math.pi);
    final index = (turned / (2 * math.pi / 3)).floor() % 3;
    return _palette[index];
  }

  @override
  bool shouldRepaint(_Comet old) => old.orbit != orbit;
}
