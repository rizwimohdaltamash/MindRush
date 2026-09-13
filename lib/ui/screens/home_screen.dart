import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/game_mode.dart';
import '../../core/rating/streak_rewards.dart';
import '../../router/app_router.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/challenge.dart';
import '../widgets/online_row.dart';

/// Home: pick a category, then pick one of its duels.
///
/// The category row is a filter rather than a list of links. Showing every
/// mode at once flattens the three disciplines into one undifferentiated grid;
/// selecting a category first makes the rating for that discipline the thing
/// you are looking at when you choose how to defend it.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Category _selected = Category.math;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final streak = profile.streak.displayed(DateTime.now());
    final modes = GameMode.values
        .where((m) => m.category == _selected)
        .toList();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            Row(
              children: [
                // Both chips are the streak, counted two ways, so both are
                // the way into the ladder that explains them.
                _StatChip(
                  key: const ValueKey('streak-chip'),
                  icon: Icons.local_fire_department_rounded,
                  value: '$streak',
                  color: AppColors.streak,
                  onTap: () => context.push(AppRoutes.streak),
                ),
                const SizedBox(width: 8),
                _StatChip(
                  key: const ValueKey('xp-chip'),
                  icon: Icons.bolt_rounded,
                  value: '${profile.streakXp} XP',
                  color: AppColors.math,
                  onTap: () => context.push(AppRoutes.streak),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => context.go(AppRoutes.profile),
                  child: AvatarBadge(
                    avatarId: profile.avatarId,
                    name: profile.displayName,
                    photo: profile.photo,
                    size: 38,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Everyone reachable right now, you first. Tapping a face is the
            // shortest path in the app to playing a real person.
            Text('ONLINE NOW', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 10),
            const OnlineRow(),
            const SizedBox(height: 18),
            Text('DUELS', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final category in Category.values) ...[
                  Expanded(
                    child: _CategoryTile(
                      // Keyed because the category name also appears as a
                      // chip on every mode card below.
                      key: ValueKey('category-${category.name}'),
                      category: category,
                      rating: profile.ratingIn(category),
                      selected: category == _selected,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selected = category);
                      },
                    ),
                  ),
                  if (category != Category.values.last)
                    const SizedBox(width: 10),
                ],
              ],
            ),
            const SizedBox(height: 22),
            for (final (index, mode) in modes.indexed) ...[
              _SlideIn(
                // Keyed by the category as well as the mode, so choosing a
                // discipline builds new cards rather than reusing the old
                // ones -- which is what makes them arrive instead of simply
                // being different.
                key: ValueKey('slide-${_selected.name}-${mode.name}'),
                order: index,
                child: _ModeCard(
                  key: ValueKey('mode-${mode.name}'),
                  mode: mode,
                ),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 4),
            AppCard(
              accent: AppColors.streak,
              onTap: () => context.push(AppRoutes.streak),
              child: Row(
                children: [
                  const Icon(
                    Icons.local_fire_department_rounded,
                    color: AppColors.streak,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Daily Streak',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          _streakBlurb(profile.streak.best, streak),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '$streak',
                    style: const TextStyle(
                      color: AppColors.streak,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    streak == 1 ? 'day' : 'days',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the streak card says under its title: the next thing to aim at, which
/// is more use than a number the player has already earned.
String _streakBlurb(int best, int streak) {
  if (streak == 0) return 'Play a duel to start one';
  final next = StreakRewards.nextAfter(streak);
  if (next == null) return 'Best $best days';
  final togo = next.day - streak;
  return '$togo ${togo == 1 ? 'day' : 'days'} to +${next.xp} XP';
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    super.key,
    required this.icon,
    required this.value,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap == null
        ? null
        : () {
            HapticFeedback.selectionClick();
            onTap!();
          },
    behavior: HitTestBehavior.opaque,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    ),
  );
}

/// One discipline in the selector.
///
/// The colour is a frame with a dark face inside it, not a filled block. Three
/// solid slabs of colour across the top of the screen is the loudest thing on
/// the page competing with the duels underneath, which is the wrong way round
/// -- this is a filter, and the duels are the point. As an outline the palette
/// is still doing all its work at a fraction of the volume.
///
/// Each tile carries its own rating. The earlier version revealed only the
/// selected one, on the grounds that a rating belongs to the discipline you
/// are about to play; but three numbers side by side is how you see that your
/// memory is a hundred points behind your arithmetic, which is a better reason
/// to tap the other tile than the tile being there.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    super.key,
    required this.category,
    required this.rating,
    required this.selected,
    required this.onTap,
  });

  final Category category;
  final int rating;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colour = category.color;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          // A small lift on selection. Tiles that only change colour read as
          // a filter; one that rises reads as the thing you just picked.
          AnimatedScale(
            scale: selected ? 1.05 : 1,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              width: double.infinity,
              // The frame. Everything inside the padding is the dark face, so
              // the colour reads as a line around the tile rather than as the
              // tile, and picking one thickens the line instead of flooding
              // it.
              padding: EdgeInsets.all(selected ? 3 : 1.5),
              decoration: BoxDecoration(
                color: selected ? colour : colour.withValues(alpha: 0.38),
                borderRadius: BorderRadius.circular(16),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: colour.withValues(alpha: 0.34),
                          blurRadius: 20,
                          spreadRadius: -4,
                        ),
                      ]
                    : null,
              ),
              child: Container(
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      // A breath of the colour on the face of the chosen one,
                      // so selection is legible without the eye having to
                      // measure a border.
                      ? Color.alphaBlend(
                          colour.withValues(alpha: 0.14),
                          AppColors.background,
                        )
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(category.icon, color: colour, size: 21),
                    const SizedBox(height: 3),
                    _Rating(rating: rating, colour: colour, selected: selected),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 240),
            // Built from the theme, never a bare TextStyle:
            // AnimatedDefaultTextStyle replaces the ambient style outright
            // and would silently drop the app's font family.
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: selected ? colour : AppColors.textMuted,
            ),
            child: Text(category.label),
          ),
        ],
      ),
    );
  }
}

/// The rating, arriving.
///
/// It counts up to its value over half a second rather than appearing at it.
/// The number moving is what makes it read as something earned; a number that
/// is simply there reads as a label.
///
/// It runs again whenever there is something to run for -- the tile being
/// picked, or the rating having actually changed since the last time this was
/// on screen. Once, on the first build of the app's life, would be a thing
/// nobody ever sees twice.
class _Rating extends StatefulWidget {
  const _Rating({
    required this.rating,
    required this.colour,
    required this.selected,
  });

  final int rating;
  final Color colour;
  final bool selected;

  @override
  State<_Rating> createState() => _RatingState();
}

class _RatingState extends State<_Rating> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..forward();

  late final Animation<double> _t = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  /// Where the count starts from. The previous rating when there is one, so a
  /// match that moved you from 1004 to 1021 is shown doing exactly that;
  /// otherwise just short of the value, so the first run settles rather than
  /// spinning up from zero like a slot machine.
  late int _from = (widget.rating * 0.955).round();

  @override
  void didUpdateWidget(_Rating old) {
    super.didUpdateWidget(old);
    final ratingMoved = old.rating != widget.rating;
    final justPicked = widget.selected && !old.selected;
    if (!ratingMoved && !justPicked) return;

    _from = ratingMoved ? old.rating : (widget.rating * 0.985).round();
    _controller
      ..reset()
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final from = _from;
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final t = _t.value;
        return Opacity(
          opacity: t,
          child: Text(
            '${from + ((widget.rating - from) * t).round()}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: widget.colour,
              // Tabular, so a rating counting up does not jiggle the tile
              // under it on the way to its value.
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
      },
    );
  }
}

/// A card arriving from the right, a beat after the one above it.
///
/// The duels are the answer to the question the category row just asked, and
/// an answer that slides in reads as a response; the same cards appearing
/// fully formed read as a screen that redrew. The stagger is what stops two
/// or three of them arriving as one block.
class _SlideIn extends StatefulWidget {
  const _SlideIn({super.key, required this.order, required this.child});

  /// Position in the list, which is the only thing the delay is built from.
  final int order;
  final Widget child;

  static const Duration travel = Duration(milliseconds: 380);
  static const Duration between = Duration(milliseconds: 80);

  @override
  State<_SlideIn> createState() => _SlideInState();
}

class _SlideInState extends State<_SlideIn>
    with SingleTickerProviderStateMixin {
  /// One controller covering the wait and the movement, rather than a timer
  /// and then an animation: a pending timer is invisible to a test that
  /// settles the frame, and a card that never arrives is worse than one that
  /// arrives too quickly.
  late final Duration _delay = _SlideIn.between * widget.order;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _delay + _SlideIn.travel,
  )..forward();

  late final Animation<double> _t = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      _delay.inMilliseconds / (_delay + _SlideIn.travel).inMilliseconds,
      1,
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    builder: (context, child) => Opacity(
      opacity: _t.value,
      child: Transform.translate(
        // Comes in from the right, a third of the way across the card. Far
        // enough to be a direction, short enough not to be a journey.
        offset: Offset(120 * (1 - _t.value), 0),
        child: child,
      ),
    ),
    child: widget.child,
  );
}

/// A duel to start.
///
/// Built around one big statement and one obvious action: an oversized title,
/// and a filled play button that is plainly the thing to press. The earlier
/// version was a flat outlined box with a small chevron, which read as a list
/// row rather than an invitation.
class _ModeCard extends ConsumerWidget {
  const _ModeCard({super.key, required this.mode});

  final GameMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colour = mode.color;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          HapticFeedback.selectionClick();
          // The poster, not the count-in: the card is a choice of duel, and
          // who you play it against is the next question, not an assumption.
          context.push(AppRoutes.mode(mode));
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colour.withValues(alpha: 0.45)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colour.withValues(alpha: 0.16),
                AppColors.surface,
                AppColors.surface,
              ],
            ),
          ),
          child: Stack(
            children: [
              // A large, very faint mark filling the empty right-hand side
              // without competing with the title.
              Positioned(
                right: -14,
                top: -10,
                child: Icon(
                  mode.icon,
                  size: 120,
                  color: colour.withValues(alpha: 0.07),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colour.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              mode.category.label,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.9,
                                color: colour,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            mode.label.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 25,
                              height: 1.02,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            mode.blurb,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(letterSpacing: 0.3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Invite sits beside play rather than behind a menu: a
                    // duel with a friend is the reason to open the app twice,
                    // and it was previously buried in a code box on the far
                    // side of the home screen.
                    GestureDetector(
                      key: ValueKey('invite-${mode.name}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Challenge.start(context, ref, mode);
                      },
                      child: Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colour.withValues(alpha: 0.13),
                          border: Border.all(
                            color: colour.withValues(alpha: 0.55),
                          ),
                        ),
                        child: Icon(
                          Icons.person_add_alt_1_rounded,
                          color: colour,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colour,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: colour.withValues(alpha: 0.4),
                            blurRadius: 16,
                            spreadRadius: -3,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: AppColors.background,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
