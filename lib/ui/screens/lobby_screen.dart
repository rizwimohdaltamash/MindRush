import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/challenge/challenge_link.dart';
import '../../core/challenge/duel_room.dart';
import '../../core/challenge/friend_duel.dart';
import '../../core/challenge/live_opponent.dart';
import '../../core/models/game_mode.dart';
import '../../data/duel_room_service.dart';
import '../../router/app_router.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/challenge.dart';

/// The waiting room for a friend duel.
///
/// Neither side can start alone. The host opens the room and sits here until
/// the link is tapped; the guest lands here from the link and joins. Only when
/// both are present does the host move the room on, and both phones drop into
/// the same minute together.
class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key, required this.code, this.join = false});

  final String code;

  /// True when arriving from a tapped link rather than from having made it.
  final bool join;

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  StreamSubscription<DuelRoom>? _subscription;
  DuelRoom? _room;
  String? _error;

  /// Guards against the stream firing again before the push completes and
  /// launching two duels.
  bool _launched = false;

  /// Created here and handed to the match, so the opponent's score is already
  /// being tracked before the first question appears.
  final LiveOpponentFeed _feed = LiveOpponentFeed();

  /// Watches for the room service turning up, when it is not up yet.
  ProviderSubscription<DuelRoomService?>? _waiting;

  /// Stops that wait being forever.
  Timer? _patience;

  /// How long the cloud is given to arrive before this screen says it cannot
  /// be done.
  ///
  /// Generous on purpose. Nothing here is a network request yet -- it is
  /// waiting on Firebase to start and sign in, which on a cold start is a
  /// second or two of plugin registration before any packet moves.
  static const Duration _patienceFor = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();

    final service = ref.read(duelRoomServiceProvider);
    if (service != null) {
      unawaited(_connect(service));
      return;
    }

    // Not up *yet* is not the same as not available, and this screen used to
    // treat them as the same thing. A guest arriving on a tapped link gets
    // here the instant the app is built, which is before Firebase has
    // finished starting -- so the one player who most needs this screen to
    // work was the one being told to check their connection. It now waits for
    // the service and only gives up when it really does not come.
    _patience = Timer(_patienceFor, () {
      if (mounted && _subscription == null) {
        setState(() => _error = _noConnection);
      }
    });

    _waiting = ref.listenManual<DuelRoomService?>(duelRoomServiceProvider, (
      previous,
      next,
    ) {
      if (next == null || !mounted || _subscription != null) return;
      _patience?.cancel();
      unawaited(_connect(next));
    });
  }

  /// Said plainly rather than worked around. Two people cannot share a minute
  /// without a network, and quietly swapping in a bot would be a lie about
  /// who the player just beat.
  static const String _noConnection =
      'Friend duels need an internet connection.';

  Future<void> _connect(DuelRoomService service) async {
    if (widget.join) {
      final profile = ref.read(profileProvider);
      final failure = await service.join(
        widget.code,
        RoomPlayer(
          uid: service.myUid,
          name: profile.displayName,
          avatarId: profile.avatarId,
          photo: profile.photo,
          // The host already published theirs; this is the other half, so
          // each side can rank the other honestly afterwards.
          rating: profile.ratingIn(_modeOf(widget.code).category),
        ),
      );
      if (failure != null) {
        if (mounted) setState(() => _error = _explain(failure));
        return;
      }
    }
    _subscription = service
        .watch(widget.code)
        .listen(
          (room) => _onRoom(service, room),
          onError: (Object _) {
            if (mounted) setState(() => _error = 'Lost the connection.');
          },
        );
  }

  /// The mode a room code names, read before the document arrives.
  ///
  /// The code is `<mode>-<seed>`, so joining does not have to wait for a
  /// round trip just to know which rating to publish.
  static GameMode _modeOf(String code) =>
      GameMode.values
          .where((m) => m.name == code.split('-').first)
          .firstOrNull ??
      GameMode.sprint;

  static String _explain(RoomError failure) => switch (failure) {
    RoomError.notFound =>
      'That challenge has expired. Ask your friend to send a new one.',
    RoomError.full => 'This duel already has two players in it.',
    RoomError.offline => 'Friend duels need an internet connection.',
    RoomError.unknown => 'Something went wrong opening that duel.',
  };

  void _onRoom(DuelRoomService service, DuelRoom room) {
    if (!mounted) return;

    // A direct challenge that was turned down. Said plainly and once, rather
    // than leaving the challenger watching an empty seat forever.
    if (room.status == RoomStatus.declined) {
      final them = room.invitedName ?? 'They';
      setState(() => _error = '$them declined the challenge.');
      _subscription?.cancel();
      return;
    }

    setState(() => _room = room);
    _feed.update(room.opponentOf(service.myUid));

    // Only the host moves the room on, so the two phones cannot race to do it
    // and write over each other.
    if (room.isHost(service.myUid) &&
        room.isFull &&
        room.status == RoomStatus.ready) {
      unawaited(service.setStatus(widget.code, RoomStatus.counting));
    }

    final started =
        room.status == RoomStatus.counting || room.status == RoomStatus.playing;
    if (!_launched && room.isFull && started) {
      _launched = true;
      HapticFeedback.mediumImpact();
      _subscription?.cancel();
      context.pushReplacement(
        AppRoutes.friendDuel,
        extra: FriendDuel(room: room, service: service, feed: _feed),
      );
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _waiting?.close();
    _patience?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    // Watched, not read: this is null until the cloud is up, and the rows
    // below need rebuilding when it stops being null.
    final service = ref.watch(duelRoomServiceProvider);
    final mine = service == null ? null : room?.me(service.myUid);
    final theirs = service == null ? null : room?.opponentOf(service.myUid);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.go(AppRoutes.home),
        ),
        title: Text(room?.mode.label ?? 'Friend duel'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: _error != null
              ? _Failed(message: _error!)
              : room == null
              ? const Center(child: CircularProgressIndicator())
              : _Waiting(
                  invited: room.invitedUid != null,
                  room: room,
                  mine: mine,
                  theirs: theirs,
                  onResend: () => Challenge.send(
                    ChallengeInvite(
                      mode: room.mode,
                      seed: room.seed,
                      byName: mine?.name ?? '',
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.cloud_off_rounded,
          color: AppColors.textMuted,
          size: 44,
        ),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => context.go(AppRoutes.home),
          child: const Text('Back to Home'),
        ),
      ],
    ),
  );
}

class _Waiting extends StatelessWidget {
  const _Waiting({
    required this.invited,
    required this.room,
    required this.mine,
    required this.theirs,
    required this.onResend,
  });

  /// True when this room was aimed at one person, so there is no link to
  /// resend and the wait is for an answer rather than for a tap.
  final bool invited;

  final DuelRoom room;
  final RoomPlayer? mine;
  final RoomPlayer? theirs;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    final colour = room.mode.color;
    return Column(
      children: [
        const Spacer(),
        _Seat(player: mine, colour: colour, label: 'YOU'),
        const SizedBox(height: 16),
        Text(
          'VS',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(letterSpacing: 2),
        ),
        const SizedBox(height: 16),
        _Seat(player: theirs, colour: colour, label: 'YOUR FRIEND'),
        const SizedBox(height: 28),
        if (theirs == null)
          _Pulse(
            text: invited
                ? 'Waiting for them to accept…'
                : 'Waiting for your friend to join…',
          )
        else
          Text(
            'Both in. Starting…',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: colour),
          ),
        const Spacer(),
        if (theirs == null) ...[
          Text(
            invited
                ? 'The challenge is on their screen now. The match starts the '
                      'moment they accept.'
                : 'The match starts the moment they tap the link. '
                      'Neither of you plays alone.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 14),
          if (!invited)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onResend,
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.text,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                label: const Text('Send the link again'),
              ),
            ),
        ],
      ],
    );
  }
}

/// One side of the lobby: a person, or an empty chair.
class _Seat extends StatelessWidget {
  const _Seat({
    required this.player,
    required this.colour,
    required this.label,
  });

  final RoomPlayer? player;
  final Color colour;
  final String label;

  @override
  Widget build(BuildContext context) {
    final seated = player;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: seated != null
              ? colour.withValues(alpha: 0.6)
              : AppColors.border,
          width: seated != null ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          if (seated != null)
            AvatarBadge(
              avatarId: seated.avatarId,
              name: seated.name,
              photo: seated.photo,
              size: 46,
            )
          else
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.surfaceHigh,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_outline_rounded,
                color: AppColors.textMuted,
                size: 22,
              ),
            ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 3),
                Text(
                  seated?.name ?? 'Empty',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: seated != null
                        ? AppColors.text
                        : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (seated != null)
            Icon(Icons.check_circle_rounded, color: colour, size: 22),
        ],
      ),
    );
  }
}

/// A slow breath on the waiting line, so the screen reads as live rather than
/// stuck.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.text});

  final String text;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(
      begin: 0.45,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
    child: Text(
      widget.text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium,
    ),
  );
}
