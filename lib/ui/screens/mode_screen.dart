import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/game_mode.dart';
import '../../router/app_router.dart';
import '../theme.dart';
import '../widgets/challenge.dart';
import '../widgets/wiggle_button.dart';

/// One duel, made the only thing on the screen.
///
/// A mode card on home used to drop straight into a count-in, which gave the
/// choice no weight and no room to say who you want to play. This page holds
/// the title on its own for a moment and then offers the two answers that
/// matter: anyone, or someone in particular.
class ModeScreen extends ConsumerWidget {
  const ModeScreen({super.key, required this.mode});

  final GameMode mode;

  /// Straight into the count-in, replacing this page rather than stacking on
  /// it -- backing out of a match should return home, not to the poster you
  /// just pressed play on.
  void _play(BuildContext context) =>
      context.pushReplacement(AppRoutes.duel(mode));

  /// The board, carrying this duel with it, so nobody is asked which one they
  /// meant a second time.
  void _findFriend(BuildContext context) =>
      context.go(AppRoutes.findFriend(mode));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colour = mode.color;

    return Scaffold(
      body: Stack(
        children: [
          // A very large, very faint mark bleeding off the right edge. It
          // fills the page without competing with the title for attention.
          Positioned(
            right: -80,
            bottom: 190,
            child: Icon(
              mode.icon,
              size: 300,
              color: colour.withValues(alpha: 0.045),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BackButton(onTap: () => context.pop()),
                  const Spacer(flex: 2),
                  Row(
                    children: [
                      _Chip(
                        text: mode.category.label,
                        colour: colour,
                        filled: true,
                      ),
                      const SizedBox(width: 8),
                      const _Chip(text: '1 MIN DUEL', colour: AppColors.text),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // Sized down a little for the longest title so no mode
                  // wraps onto a fourth line.
                  Text(
                    mode.headline,
                    style: TextStyle(
                      fontSize: mode.headline.length > 13 ? 52 : 58,
                      height: 0.98,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.5,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    mode.tagline,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const Spacer(flex: 3),
                  SizedBox(
                    width: double.infinity,
                    child: Wiggle(
                      onPressed: () => _play(context),
                      builder: (context, press) => FilledButton(
                        key: const ValueKey('play-duel'),
                        onPressed: press,
                        style: FilledButton.styleFrom(
                          backgroundColor: colour,
                          foregroundColor: AppColors.background,
                          padding: const EdgeInsets.symmetric(vertical: 17),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'PLAY DUEL',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Wiggle(
                      onPressed: () => _findFriend(context),
                      builder: (context, press) => TextButton(
                        key: const ValueKey('play-a-friend'),
                        onPressed: press,
                        child: Text(
                          'PLAY A FRIEND',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.text,
                              ),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: TextButton(
                      key: const ValueKey('send-a-link'),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        // The way to reach somebody who is not on MindRush
                        // yet, and so not on the board to be searched for.
                        Challenge.start(context, ref, mode);
                      },
                      child: Text(
                        'SEND A LINK INSTEAD',
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(fontSize: 10.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border),
      ),
      child: const Icon(
        Icons.arrow_back_rounded,
        color: AppColors.text,
        size: 20,
      ),
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.colour, this.filled = false});

  final String text;
  final Color colour;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: filled ? colour.withValues(alpha: 0.18) : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      border: filled ? null : Border.all(color: AppColors.border),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.9,
        color: filled ? colour : AppColors.textMuted,
      ),
    ),
  );
}
