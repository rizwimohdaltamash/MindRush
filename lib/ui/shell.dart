import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart';
import 'widgets/challenge_inbox.dart';

/// The four top-level destinations, wrapped in a bottom bar.
///
/// Duels and results sit outside this shell so the nav bar disappears during
/// a match -- nothing should compete with the clock.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  StatefulNavigationShell get navigationShell => widget.navigationShell;

  static const _destinations = [
    (icon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.show_chart_rounded, label: 'Stats'),
    (icon: Icons.leaderboard_rounded, label: 'Ranks'),
    (icon: Icons.person_rounded, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Everywhere in the tabs, a challenge can arrive and be answered where
      // the player is standing.
      body: ChallengeInbox(child: navigationShell),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              for (final (index, destination) in _destinations.indexed)
                Expanded(
                  child: _NavItem(
                    icon: destination.icon,
                    label: destination.label,
                    selected: index == navigationShell.currentIndex,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      navigationShell.goBranch(
                        index,
                        // Tapping the current tab again returns it to its root.
                        initialLocation: index == navigationShell.currentIndex,
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.text : AppColors.textMuted;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: selected ? 1.12 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              // Built from the theme rather than a bare TextStyle:
              // AnimatedDefaultTextStyle replaces the ambient style outright,
              // so a bare one silently drops the app's font family.
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                fontSize: 10,
                letterSpacing: 0.2,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
