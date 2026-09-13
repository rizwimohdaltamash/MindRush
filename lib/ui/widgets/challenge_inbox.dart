import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/challenge/duel_room.dart';
import '../../router/app_router.dart';
import '../../state/providers.dart';
import '../theme.dart';

/// Puts an incoming challenge in front of the player, wherever they are.
///
/// Wrapped round a screen rather than owned by one: a challenge that only
/// arrived while you happened to be looking at Ranks would not be worth
/// having. It sits on the four tabs, and on the result screen -- which is
/// exactly where a rematch lands, because that is where the person sending it
/// is standing too.
///
/// It deliberately does not sit on the duel or the lobby. Being asked to
/// accept a second duel with fifteen seconds left of the first one is not a
/// feature.
class ChallengeInbox extends ConsumerStatefulWidget {
  const ChallengeInbox({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ChallengeInbox> createState() => _ChallengeInboxState();
}

class _ChallengeInboxState extends ConsumerState<ChallengeInbox> {
  bool _asking = false;

  Future<void> _ask(DuelRoom invite) async {
    _asking = true;
    ref.read(answeredChallengesProvider).add(invite.code);
    HapticFeedback.mediumImpact();

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => ChallengeDialog(invite: invite),
    );
    _asking = false;
    if (!mounted) return;

    if (accepted == true) {
      // The same route the WhatsApp link lands on: join, then wait together.
      context.push(AppRoutes.challenge(invite.code));
      return;
    }
    unawaited(
      ref
              .read(duelRoomServiceProvider)
              ?.setStatus(invite.code, RoomStatus.declined) ??
          Future<void>.value(),
    );
  }

  /// True when this inbox is the one the player is actually looking at.
  ///
  /// Two of these are alive at once while the result screen is up -- it is
  /// pushed over the tabs, not instead of them -- and the one underneath has
  /// to stay quiet: its dialog would open on a navigator below the screen in
  /// front, which is to say invisibly.
  ///
  /// It is also what keeps a challenge out of a match. The duel and the lobby
  /// carry no inbox of their own, and while either is on screen the tabs
  /// underneath are not current, so nothing interrupts a minute in progress.
  bool get _inFront => ModalRoute.of(context)?.isCurrent ?? true;

  void _maybeAsk(List<DuelRoom>? invites) {
    if (invites == null || _asking || !mounted || !_inFront) return;
    final uid = ref.read(duelRoomServiceProvider)?.myUid;
    if (uid == null) return;
    final answered = ref.read(answeredChallengesProvider);

    // Checked again here rather than trusted from the snapshot: this also
    // runs on the way back into a screen, and a challenge sent four minutes
    // ago has stopped ringing on the other phone. Asking about it then would
    // send the player into a lobby nobody is waiting in.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final pending = invites
        .where(
          (room) =>
              !answered.contains(room.code) &&
              room.isLiveInviteFor(uid, nowMs: nowMs),
        )
        .firstOrNull;
    if (pending != null) unawaited(_ask(pending));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(invitesProvider, (_, next) => _maybeAsk(next.value));

    // Asked again on the way in, not only when the stream next moves. A
    // challenge that arrived while the player was three screens deep would
    // otherwise sit unanswered until the sender gave up -- Firestore has
    // already delivered that snapshot, and it will not deliver it twice.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeAsk(ref.read(invitesProvider).value),
    );

    return widget.child;
  }
}

/// "Aarav challenges you to Mind Snap." Accept, or say no.
class ChallengeDialog extends StatelessWidget {
  const ChallengeDialog({super.key, required this.invite});

  final DuelRoom invite;

  @override
  Widget build(BuildContext context) {
    final colour = invite.mode.color;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AvatarBadge(
            avatarId: invite.host.avatarId,
            name: invite.host.name,
            photo: invite.host.photo,
            size: 58,
          ),
          const SizedBox(height: 14),
          Text(
            '${invite.host.name} challenges you',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            '${invite.mode.label} · one minute, side by side',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text(
            'Decline',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colour,
            foregroundColor: Colors.black,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Accept'),
        ),
      ],
    );
  }
}
