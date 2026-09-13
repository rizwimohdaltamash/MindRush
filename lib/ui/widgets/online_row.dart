import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/players/player_directory.dart';
import '../../state/providers.dart';
import '../theme.dart';
import 'challenge.dart';

/// Who is on MindRush right now, as a row of faces.
///
/// You first, then everyone else who is online, most recently seen first.
/// Tapping a face asks which duel, and only then does a challenge go to their
/// phone -- nobody is asked to accept a match before either side has said what
/// it is.
class OnlineRow extends ConsumerWidget {
  const OnlineRow({super.key});

  static const double height = 96;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final directory =
        ref.watch(directoryProvider).value ?? PlayerDirectory.empty;
    final online = directory.onlineNow(DateTime.now());

    return SizedBox(
      height: height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          _Face(
            name: 'YOU',
            avatarId: profile.avatarId,
            initialFrom: profile.displayName,
            photo: profile.photo,
            ring: AppColors.math,
            showDot: false,
          ),
          for (final player in online)
            _Face(
              key: ValueKey('online-${player.uid}'),
              name: player.name,
              avatarId: player.avatarId,
              initialFrom: player.name,
              photo: player.photo,
              ring: AppColors.win,
              showDot: true,
              onTap: () {
                HapticFeedback.selectionClick();
                Challenge.challengeDirect(
                  context,
                  ref,
                  uid: player.uid,
                  name: player.name,
                );
              },
            ),
          if (online.isEmpty) const _NobodyHere(),
        ],
      ),
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({
    super.key,
    required this.name,
    required this.avatarId,
    required this.initialFrom,
    required this.ring,
    required this.showDot,
    this.photo,
    this.onTap,
  });

  final String name;
  final int avatarId;
  final String initialFrom;
  final String? photo;
  final Color ring;
  final bool showDot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ring, width: 2.5),
                ),
                child: AvatarBadge(
                  avatarId: avatarId,
                  name: initialFrom,
                  photo: photo,
                  size: 54,
                ),
              ),
              if (showDot)
                Positioned(
                  right: 1,
                  top: 1,
                  child: Container(
                    width: 15,
                    height: 15,
                    decoration: BoxDecoration(
                      color: AppColors.win,
                      shape: BoxShape.circle,
                      // Ringed in the page colour so the dot reads as a
                      // badge rather than a smudge on the avatar.
                      border: Border.all(color: AppColors.background, width: 3),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 64,
            child: Text(
              name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Said plainly. An empty row with no explanation reads as a loading bug.
class _NobodyHere extends StatelessWidget {
  const _NobodyHere();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 18),
      child: Text(
        'Nobody else is online.\nShare a link to get someone in.',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    ),
  );
}
