import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/players/avatar.dart';
import '../../data/photo_source.dart';
import '../../state/providers.dart';
import '../theme.dart';
import 'profile_screen.dart' show CloudStatusCard;

/// Everything about the player rather than about the game: their face, what
/// the app is allowed to interrupt them for, and the account itself.
///
/// Separate from Profile deliberately. Profile is something to look at -- your
/// ratings, your streak, what you have played. This is where things get
/// changed, and the two want different amounts of care from whoever is
/// holding the phone.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'Settings',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ],
            ),
            const SizedBox(height: 18),

            // ---------------------------------------------------- avatar
            Center(
              child: AvatarBadge(
                avatarId: profile.avatarId,
                name: profile.displayName,
                photo: profile.photo,
                size: 96,
              ),
            ),
            const SizedBox(height: 16),
            const _PhotoButtons(),
            const SizedBox(height: 24),
            Text(
              'CHOOSE A CHARACTER',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 4),
            Text(
              profile.photo == null
                  ? 'Tap one to wear it.'
                  : 'Your photo is showing. Pick one of these to use it '
                        'instead.',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 14),
            for (final (index, family) in Avatars.families.indexed) ...[
              Text(
                family.name,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final (slot, _) in family.glyphs.indexed)
                    _AvatarOption(
                      id: Avatars.idIn(index, slot),
                      selected:
                          Avatars.idIn(index, slot) == profile.avatarId &&
                          profile.photo == null,
                    ),
                ],
              ),
              const SizedBox(height: 18),
            ],

            // --------------------------------------------- notifications
            const SizedBox(height: 6),
            Text(
              'NOTIFICATIONS',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 10),
            AppCard(
              child: Row(
                children: [
                  const Icon(
                    Icons.notifications_active_rounded,
                    color: AppColors.streak,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Daily reminders',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'A nudge when your streak is at risk.',
                          style: Theme.of(
                            context,
                          ).textTheme.labelSmall?.copyWith(letterSpacing: 0.2),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: profile.remindersEnabled,
                    activeThumbColor: AppColors.background,
                    activeTrackColor: AppColors.streak,
                    onChanged: (on) {
                      HapticFeedback.selectionClick();
                      ref.read(profileProvider.notifier).setReminders(on);
                    },
                  ),
                ],
              ),
            ),

            // ---------------------------------------------------- cloud
            const SizedBox(height: 28),
            Text('CLOUD', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 10),
            CloudStatusCard(monitor: ref.watch(cloudMonitorProvider)),

            // -------------------------------------------------- account
            const SizedBox(height: 28),
            Text('ACCOUNT', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 10),
            _DangerButton(
              icon: Icons.logout_rounded,
              label: 'Sign out',
              detail: 'Ends this device\'s account',
              onTap: () => _confirmSignOut(context, ref),
            ),
            const SizedBox(height: 10),
            _DangerButton(
              icon: Icons.restart_alt_rounded,
              label: 'Reset all progress',
              detail: 'Keeps your account, clears your ratings',
              onTap: () => _confirmReset(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  /// Said plainly, because it cannot be undone.
  ///
  /// MindRush signs people in anonymously -- there is no email and no
  /// password, so the account only exists as a credential held on this phone.
  /// Signing out throws that credential away, and nothing can ever sign back
  /// into it. Anything softer than saying so outright would be a lie.
  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Sign out?'),
        content: const Text(
          'Your MindRush account lives on this phone only — there is no '
          'password to sign back in with. Signing out deletes it, along with '
          'your ratings, streak and match history.\n\n'
          'You will start again with a new name.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.loss,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(profileProvider.notifier).signOut();
    // Onboarding is what the app shows a player with no name, so there is
    // nowhere to navigate to: the tree swaps itself back to the welcome
    // screen the moment the profile is empty.
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Reset everything?'),
        content: const Text(
          'Ratings, streak and match history all go back to the start. '
          'Your name and your account stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.loss,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(profileProvider.notifier).resetEverything();
  }
}

/// Camera, gallery, and taking it off again.
class _PhotoButtons extends ConsumerStatefulWidget {
  const _PhotoButtons();

  @override
  ConsumerState<_PhotoButtons> createState() => _PhotoButtonsState();
}

class _PhotoButtonsState extends ConsumerState<_PhotoButtons> {
  /// The picker is a round trip through the system camera, which is slow
  /// enough that a player will press the button twice without this.
  bool _busy = false;

  Future<void> _take(PhotoOrigin origin) async {
    if (_busy) return;
    setState(() => _busy = true);
    final photo = await ref.read(photoSourceProvider).take(origin);
    if (!mounted) return;
    setState(() => _busy = false);

    // Null means they backed out, or the device would not play along. Either
    // way the avatar they already had is the right thing to keep.
    if (photo == null) return;
    HapticFeedback.mediumImpact();
    await ref.read(profileProvider.notifier).setPhoto(photo);
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = ref.watch(profileProvider).photo != null;

    // Wrapped rather than a row: three buttons do not fit across a narrow
    // phone, and a third of "Remove" disappearing off the edge is worse than
    // it moving to a second line.
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: [
        _PhotoButton(
          icon: Icons.photo_camera_rounded,
          label: 'Camera',
          busy: _busy,
          onTap: () => _take(PhotoOrigin.camera),
        ),
        _PhotoButton(
          icon: Icons.image_rounded,
          label: 'Gallery',
          busy: _busy,
          onTap: () => _take(PhotoOrigin.gallery),
        ),
        if (hasPhoto)
          _PhotoButton(
            icon: Icons.close_rounded,
            label: 'Remove',
            busy: _busy,
            onTap: () => ref.read(profileProvider.notifier).setPhoto(null),
          ),
      ],
    );
  }
}

class _PhotoButton extends StatelessWidget {
  const _PhotoButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppColors.text),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 11.5,
                color: AppColors.text,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AvatarOption extends ConsumerWidget {
  const _AvatarOption({required this.id, required this.selected});

  final int id;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
    onTap: () {
      HapticFeedback.selectionClick();
      // Choosing a character is also how a photo is taken off, so the
      // face on screen always matches the thing just tapped.
      ref.read(profileProvider.notifier).setAvatar(id);
    },
    child: AnimatedScale(
      scale: selected ? 1.08 : 1,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutBack,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AvatarBadge.colorFor(id) : Colors.transparent,
            width: 2,
          ),
        ),
        child: AvatarBadge(avatarId: id, name: '', size: 44),
      ),
    ),
  );
}

class _DangerButton extends StatelessWidget {
  const _DangerButton({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppCard(
    onTap: onTap,
    child: Row(
      children: [
        Icon(icon, color: AppColors.loss, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: AppColors.loss),
              ),
              const SizedBox(height: 2),
              Text(detail, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
        const Icon(
          Icons.chevron_right_rounded,
          color: AppColors.textMuted,
          size: 20,
        ),
      ],
    ),
  );
}
