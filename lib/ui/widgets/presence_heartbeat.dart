import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';

/// Publishes this player to everyone else, for as long as the app is open.
///
/// Wrapped around the whole app rather than one screen, so the green dot does
/// not blink off because someone happens to be sitting on their Profile tab.
///
/// Presence is honest about its own limits: it stops the moment the app is
/// backgrounded, and says so immediately rather than leaving others to wait
/// out the staleness window. An app that is closed cannot be reached anyway,
/// so showing it as online would only ever produce a challenge nobody answers.
///
/// The entry itself stays behind, which is what puts every registered player
/// on the leaderboard whether or not they happen to be holding their phone.
class PresenceHeartbeat extends ConsumerStatefulWidget {
  const PresenceHeartbeat({super.key, required this.child});

  final Widget child;

  /// Comfortably inside [PlayerDirectory.staleAfterMs], so a single failed
  /// write never blinks this player offline.
  static const Duration interval = Duration(seconds: 15);

  @override
  ConsumerState<PresenceHeartbeat> createState() => _PresenceHeartbeatState();
}

class _PresenceHeartbeatState extends ConsumerState<PresenceHeartbeat>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void _start() {
    _timer?.cancel();
    _beat();
    _timer = Timer.periodic(PresenceHeartbeat.interval, (_) => _beat());
  }

  void _beat() {
    final service = ref.read(playerServiceProvider);
    if (service == null) return;
    // A player who has not named themselves yet has nothing to show a friend,
    // and an empty row on the board helps nobody.
    if (ref.read(profileProvider).displayName.trim().isEmpty) return;
    // Only the timestamp goes up. Who they are and how they are rated is
    // written by the store the moment either changes, so a beat every fifteen
    // seconds is not re-uploading a profile that has not moved.
    unawaited(service.beat());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _start();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _timer?.cancel();
        _timer = null;
        unawaited(ref.read(playerServiceProvider)?.leave() ?? Future.value());
      case AppLifecycleState.inactive:
        // A notification shade pulled halfway down is not leaving.
        break;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The connection is made after the app is already on screen, so the first
    // beat cannot be left to the fifteen-second timer -- a player would be
    // invisible to their friends for the whole of that.
    ref.listen(playerServiceProvider, (previous, next) {
      if (previous == null && next != null) _beat();
    });
    return widget.child;
  }
}
