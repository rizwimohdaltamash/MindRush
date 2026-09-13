import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/challenge/challenge_link.dart';
import '../../core/challenge/duel_room.dart';
import '../../core/models/game_mode.dart';
import '../../core/questions/difficulty.dart';
import '../../core/questions/question_deck.dart';
import '../../data/error_report.dart';
import '../../router/app_router.dart';
import '../../state/providers.dart';
import '../theme.dart';

/// Inviting a friend to a live duel.
///
/// The link opens a room both phones watch. Nothing starts until both people
/// are in it, so a challenge is never one person playing alone against a copy
/// of someone else's questions.
abstract final class Challenge {
  /// Opens a room for [mode], sends the link, and sits in the lobby.
  static Future<void> start(
    BuildContext context,
    WidgetRef ref,
    GameMode mode,
  ) async {
    if (!_online(context, ref)) return;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      // Without this the sheet is capped at nine sixteenths of the screen and
      // the three steps overflow the bottom.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => _InviteSheet(mode: mode),
    );
    if (confirmed != true || !context.mounted) return;

    final room = await _open(context, ref, mode);
    if (room == null || !context.mounted) return;

    // The lobby first, the share sheet over the top of it. If the sheet is
    // cancelled, refused, or simply slow, the host is already sitting in their
    // own room with a "send the link again" button rather than stranded on
    // home wondering whether anything happened.
    context.push(AppRoutes.lobby(room.code));
    unawaited(
      send(
        ChallengeInvite(
          mode: mode,
          seed: room.seed,
          byName: ref.read(profileProvider).displayName,
        ),
      ),
    );
  }

  /// Challenges one person directly, with no link involved.
  ///
  /// The mode is chosen first and the challenge is only sent afterwards.
  /// Firing one off the instant an avatar is tapped would mean the receiver
  /// is asked to accept a duel before either of them has said what it is.
  ///
  /// [mode] skips the picker for a player who arrived here from that duel's
  /// own page, where they already said which one they wanted. It is never a
  /// way of sending a challenge nobody has chosen: the caller must have been
  /// told, not have guessed.
  static Future<void> challengeDirect(
    BuildContext context,
    WidgetRef ref, {
    required String uid,
    required String name,
    GameMode? mode,
  }) async {
    if (!_online(context, ref)) return;

    final chosen =
        mode ??
        await showModalBottomSheet<GameMode>(
          context: context,
          backgroundColor: AppColors.surface,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          builder: (context) => _ModePicker(name: name),
        );
    if (chosen == null || !context.mounted) return;

    final room = await _open(
      context,
      ref,
      chosen,
      invitedUid: uid,
      invitedName: name,
    );
    if (room == null || !context.mounted) return;
    context.push(AppRoutes.lobby(room.code));
  }

  /// True when friend duels are possible at all; complains and returns false
  /// when they are not.
  static bool _online(BuildContext context, WidgetRef ref) {
    if (ref.read(duelRoomServiceProvider) != null) return true;
    // The one thing in this app that genuinely cannot happen offline, so it
    // says so instead of degrading into something that is not a duel.
    _complain(context, 'Friend duels need an internet connection.');
    return false;
  }

  /// Publishes a room, or complains and returns null.
  static Future<DuelRoom?> _open(
    BuildContext context,
    WidgetRef ref,
    GameMode mode, {
    String? invitedUid,
    String? invitedName,
  }) async {
    final service = ref.read(duelRoomServiceProvider)!;
    final profile = ref.read(profileProvider);
    final room = DuelRoom.open(
      mode: mode,
      seed: QuestionDeck.newSeed(),
      // Fixed by whoever opens the room. Both sides then answer the same
      // questions even when their ratings differ, which is the only way the
      // two scores mean the same thing.
      difficulty: Difficulty.fromRating(profile.ratingIn(mode.category)),
      host: RoomPlayer(
        uid: service.myUid,
        name: profile.displayName,
        avatarId: profile.avatarId,
        photo: profile.photo,
        // Carried so the other phone can put a real person, with a real
        // rating, on its leaderboard afterwards.
        rating: profile.ratingIn(mode.category),
      ),
      invitedUid: invitedUid,
      invitedName: invitedName,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    final failure = await service.create(room);
    if (!context.mounted) return null;
    if (failure != null) {
      _complain(context, 'Could not open the duel. Check your connection.');
      return null;
    }
    return room;
  }

  /// Hands the link to the share sheet, WhatsApp included.
  static Future<void> send(ChallengeInvite invite) async {
    try {
      await SharePlus.instance.share(
        ShareParams(text: invite.shareText, subject: 'MindRush duel'),
      );
    } catch (error, stack) {
      // A share sheet that will not open must not strand the host outside
      // their own lobby: the room already exists, and the link can be sent
      // again from the waiting screen.
      Report.swallowed(error, stack, 'share sheet unavailable');
    }
  }

  static void _complain(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _InviteSheet extends StatelessWidget {
  const _InviteSheet({required this.mode});

  final GameMode mode;

  @override
  Widget build(BuildContext context) {
    final colour = mode.color;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Icon(mode.icon, color: colour, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Challenge a friend',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${mode.label} · one minute, side by side',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 18),
            const _Step(1, 'We send them a link on WhatsApp.'),
            const _Step(2, 'They tap it and join your lobby.'),
            const _Step(
              3,
              'The match starts the moment you are both in — same questions, '
              'same minute, scores moving live.',
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  Navigator.pop(context, true);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: colour,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: const Text('Send the invite'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.number, this.text);

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.surfaceHigh,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    ),
  );
}

/// Which duel to challenge someone to.
///
/// Every mode, grouped by discipline: the challenge is started from a face
/// rather than from a category, so there is nothing to narrow it down by.
class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Challenge $name to',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'They get to accept or decline.',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 16),
          for (final mode in GameMode.values) ...[
            _ModeRow(mode: mode),
            const SizedBox(height: 10),
          ],
        ],
      ),
    ),
  );
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({required this.mode});

  final GameMode mode;

  @override
  Widget build(BuildContext context) {
    final colour = mode.color;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.pop(context, mode);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: colour.withValues(alpha: 0.10),
            border: Border.all(color: colour.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Icon(mode.icon, color: colour, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mode.category.label,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colour, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
