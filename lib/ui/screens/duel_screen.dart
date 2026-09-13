import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/challenge/duel_room.dart';
import '../../core/challenge/friend_duel.dart';
import '../../core/match/match_engine.dart';
import '../../core/models/game_mode.dart';
import '../../core/rating/streak_rewards.dart';
import '../../core/questions/question.dart';
import '../../router/app_router.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/answer_feedback.dart';
import '../widgets/keypad.dart';
import '../widgets/pattern_grid.dart';
import '../widgets/streak_flare.dart';

/// One 60-second duel.
///
/// The engine is a plain state machine with no clock of its own; this screen
/// owns the [Ticker] and feeds it elapsed milliseconds. That split is why a
/// full match can be tested in microseconds.
class DuelScreen extends ConsumerStatefulWidget {
  const DuelScreen({super.key, required this.mode, this.seed, this.friend});

  final GameMode mode;
  final int? seed;

  /// Set when this is a live duel out of a lobby. The opponent is then a
  /// person on another phone, and their score arrives as they earn it.
  final FriendDuel? friend;

  /// How long a player may touch nothing at all before the duel asks whether
  /// they are still there.
  ///
  /// Ten seconds is far longer than any question takes and far shorter than a
  /// phone left face-up on a table. It exists because the other side of a
  /// friend duel is a real person waiting out a real minute: somebody who has
  /// walked off should cost them fifteen seconds, not sixty.
  static const Duration idleAfter = Duration(seconds: 10);

  /// And how long they then have to prove it before it is called off.
  static const Duration grace = Duration(seconds: 5);

  @override
  ConsumerState<DuelScreen> createState() => _DuelScreenState();
}

class _DuelScreenState extends ConsumerState<DuelScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final MatchEngine _engine;
  late final Ticker _ticker;

  /// Elapsed match time, taken from the ticker rather than a Stopwatch. A
  /// Stopwatch reads the wall clock, which widget tests cannot advance, so
  /// the whole duel would be untestable end to end.
  int _elapsedMs = 0;

  /// Seconds left on the "get ready" count-in, so the timer never starts
  /// while the player is still reading the screen.
  int _countIn = 3;

  bool _settled = false;
  String _typed = '';
  bool _showingPattern = true;

  /// The beat after a pattern is answered, while the board shows what was
  /// there and what the player actually tapped.
  bool _reviewing = false;

  final Set<int> _tapped = {};

  /// Held so both can be cancelled in [dispose] -- a bare Future.delayed keeps
  /// firing after the screen is gone.
  Timer? _countInTimer;
  Timer? _flashTimer;
  Timer? _reviewTimer;
  Timer? _waitTimer;

  /// Live-duel plumbing; all null or false in an ordinary match against a bot.
  StreamSubscription<DuelRoom>? _roomSubscription;
  bool _awaitingOpponent = false;
  bool _resultShown = false;

  /// Set while the once-a-day streak celebration is on screen.
  int? _flareDays;
  int _reportedScore = -1;

  /// Drives the per-answer verdict flash. Runs 0 -> 1 once per submission.
  late final AnimationController _verdict = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1,
  );
  AnswerVerdict _lastVerdict = AnswerVerdict.perfect;
  int _lastPoints = 0;

  /// Captured once at the start: reading the profile every frame would rebuild
  /// the whole duel on any unrelated profile change mid-match.
  late final String _playerName;
  late final int _playerAvatarId;
  late final String? _playerPhoto;

  /// Runs out [DuelScreen.idleAfter] after the last thing the player touched.
  Timer? _idleTimer;

  /// The five seconds of grace, as an animation rather than a timer: it draws
  /// the countdown and ends the duel with the same value, so the number on
  /// screen and the moment it fires cannot drift apart.
  late final AnimationController _grace =
      AnimationController(
        vsync: this,
        duration: DuelScreen.grace,
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && _asking) unawaited(_abort());
      });

  /// True while the are-you-still-there bar is up.
  bool _asking = false;

  /// Clears the answered board between Mind Snap rounds.
  ///
  /// An animation rather than a timer because the next pattern has to start
  /// on exactly the frame this ends -- a second timer racing it is how a new
  /// board appears over the top of one still leaving.
  late final AnimationController _vanish =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: kMindSnapVanishMs),
      )..addStatusListener((status) {
        // The next pattern arrives on the frame the last one finishes
        // leaving. Hung off the controller rather than a callback on
        // forward(), so the two cannot land in different frames.
        if (status == AnimationStatus.completed && mounted && !_settled) {
          _beginPatternFlash();
        }
      });

  /// The board just answered, held on screen through the review beat.
  ///
  /// Submitting advances the engine straight away, so [MatchEngine.current]
  /// is already the *next* round while the solved one is still being looked
  /// at. Without this the beat revealed the pattern that was coming, marked
  /// up with the previous round's taps, and the counter under it read the
  /// next round's cell count -- which is the part that showed.
  PatternRound? _solved;

  /// What is actually on screen: the board just answered while the beat runs,
  /// and whatever the engine is on the rest of the time.
  Question get _onScreen => (_reviewing ? _solved : null) ?? _engine.current;

  @override
  void initState() {
    super.initState();
    // Watched so that putting the phone away counts as leaving -- see
    // [didChangeAppLifecycleState].
    WidgetsBinding.instance.addObserver(this);
    final profile = ref.read(profileProvider);
    _playerName = profile.displayName;
    _playerAvatarId = profile.avatarId;
    _playerPhoto = profile.photo;
    final friend = widget.friend;
    _engine = friend == null
        ? createMatch(ref, widget.mode, seed: widget.seed)
        : createFriendMatch(ref, friend);
    if (friend != null) _watchOpponent(friend);
    _ticker = createTicker(_onTick);
    _startCountIn();
  }

  void _startCountIn() {
    _countInTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _countIn--);
      if (_countIn > 0) return;

      timer.cancel();
      _countInTimer = null;
      _ticker.start();
      _watchForIdle();
      _beginPatternFlash();
    });
  }

  /// Anything at all counts as being here: a digit, a cell, an option, or a
  /// finger put down on an empty part of the screen. The question is whether
  /// somebody is holding the phone, not whether they are any good at it.
  void _touched() {
    if (_settled) return;
    if (_asking) {
      _grace.stop();
      setState(() => _asking = false);
    }
    _watchForIdle();
  }

  /// Arms the idle check -- but only for a player still on nought.
  ///
  /// Somebody who has scored is playing, however slowly, and slow is a way of
  /// losing rather than a reason to call the duel off. Ending a match for a
  /// player who is behind would hand them a way out of the rating they had
  /// earned: stop answering, get the minute annulled. Nought is different --
  /// there is nothing to annul, and no result worth showing either side.
  void _watchForIdle() {
    _idleTimer?.cancel();
    if (_settled || _engine.playerScore > 0) return;
    _idleTimer = Timer(DuelScreen.idleAfter, _askIfStillThere);
  }

  void _askIfStillThere() {
    // Checked again here as well as when the timer was set: a timer armed on
    // nought can still be in flight when the first answer lands.
    if (!mounted || _settled || _engine.playerScore > 0) return;
    HapticFeedback.mediumImpact();
    setState(() => _asking = true);
    _grace.forward(from: 0);
  }

  /// Ends a duel one side stopped playing.
  ///
  /// Not a loss: being beaten and walking away are different things, and
  /// recording the second as the first would let a player farm a streak by
  /// opening a duel and putting the phone down. Nothing is saved, so this
  /// match leaves no trace beyond the screen that explains it -- and no
  /// rating moves for either player, which is why the phone that gives up
  /// says so out loud rather than reporting a quiet nought.
  ///
  /// [byPlayer] is false when the call came from the other phone.
  Future<void> _abort({bool byPlayer = true}) async {
    if (_resultShown) return;
    _settled = true;
    _resultShown = true;
    _ticker.stop();
    _countInTimer?.cancel();
    _idleTimer?.cancel();
    _flashTimer?.cancel();
    _reviewTimer?.cancel();
    _waitTimer?.cancel();
    HapticFeedback.heavyImpact();

    // Only when this phone is the one that gave up. When the call came from
    // the other side, reporting back would be an echo.
    if (byPlayer) _tellThemIAmOut();

    if (!mounted) return;
    context.pushReplacement(
      AppRoutes.result,
      extra: ResultArgs(_engine.abandon(byPlayer: byPlayer), widget.mode),
    );
  }

  /// Leaving the app mid-duel is leaving the duel.
  ///
  /// The home button, the app switcher and the lock screen all end up here,
  /// and so does swiping the app away -- a phone has to be backgrounded
  /// before it can be swiped out of the switcher, so the message is already
  /// gone by then. The friend on the other phone therefore finds out at the
  /// moment it happens rather than by watching a score that has stopped.
  ///
  /// [AppLifecycleState.inactive] is deliberately not in here. It fires for a
  /// pulled-down notification shade and a half-opened switcher, neither of
  /// which is somebody walking away, and calling a duel off for one would be
  /// worse than the problem this fixes.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached) {
      return;
    }
    // Only in a friend duel. Against a bot there is nobody sitting out the
    // other half of the minute, so taking a call should cost the player their
    // match and nothing more.
    if (widget.friend == null || _settled) return;
    unawaited(_abort());
  }

  /// Tells the other phone that this one is out of the duel.
  ///
  /// Marked aborted rather than simply finished on nought, because the two
  /// mean opposite things to whoever is still playing: a friend who finished
  /// on nought was beaten, and a friend who walked out was never there. Only
  /// the second one calls their duel off as well.
  void _tellThemIAmOut() {
    final friend = widget.friend;
    if (friend == null) return;
    unawaited(
      friend.service.report(
        friend.room.code,
        asHost: friend.asHost,
        score: _engine.playerScore,
        finished: true,
        aborted: true,
      ),
    );
  }

  /// Keeps the opponent's half of the scoreboard moving.
  void _watchOpponent(FriendDuel friend) {
    _roomSubscription = friend.service
        .watch(friend.room.code)
        .listen(
          (DuelRoom room) {
            friend.feed.update(room.opponentOf(friend.myUid));
            if (!mounted) return;
            // Their phone gave up. Neither side is rated for it, so there is
            // nothing to be gained by playing the rest of the minute out
            // against a score that has stopped moving.
            if (friend.feed.hasAborted) {
              unawaited(_abort(byPlayer: false));
              return;
            }
            setState(() {});
            // They may well finish first; this is what lets the result appear the
            // moment the second player is done rather than on a timeout.
            if (_awaitingOpponent && friend.feed.hasFinished) {
              unawaited(_showResult());
            }
          },
          onError: (Object _) {
            // A dropped stream is not worth ending a live match over. The score
            // simply stops moving, and the wait at the end has its own timeout.
          },
        );
  }

  /// Reports this player's own score into the room.
  ///
  /// Skipped when the number has not moved, which is every wrong answer --
  /// that roughly halves the writes over a minute of Fastest Fingers.
  void _report({bool finished = false}) {
    final friend = widget.friend;
    if (friend == null) return;
    final score = _engine.playerScore;
    if (!finished && score == _reportedScore) return;
    _reportedScore = score;
    unawaited(
      friend.service.report(
        friend.room.code,
        asHost: friend.asHost,
        score: score,
        finished: finished,
        timeMs: finished
            ? (_engine.answers.isEmpty ? 0 : _engine.answers.last.atMs)
            : 0,
        // Only on the last report. It is the one thing the other phone cannot
        // work out for itself, and it is what fills in the opponent's half of
        // their speed chart -- which is otherwise a row of single bars.
        durations: finished
            ? [for (final answer in _engine.answers) answer.durationMs]
            : const [],
      ),
    );
  }

  void _onTick(Duration elapsed) {
    _elapsedMs = elapsed.inMilliseconds;
    _engine.advanceTo(_elapsedMs);
    if (_engine.isOver) {
      _settle();
    } else {
      setState(() {});
    }
  }

  Future<void> _settle() async {
    if (_settled) return;
    _settled = true;
    _ticker.stop();
    _idleTimer?.cancel();
    _grace.stop();
    HapticFeedback.mediumImpact();

    final friend = widget.friend;
    if (friend != null) {
      _report(finished: true);
      if (!friend.feed.hasFinished) {
        // Both are on the same sixty-second clock, so this is usually a
        // formality of a second or two. The timeout is for the phone that
        // locked, lost signal, or walked out of the room.
        setState(() => _awaitingOpponent = true);
        _waitTimer = Timer(const Duration(seconds: 12), () {
          unawaited(_showResult());
        });
        return;
      }
    }
    await _showResult();
  }

  /// Settles the match and moves on, exactly once.
  ///
  /// Reachable from three directions at the end of a friend duel -- the
  /// buzzer, the opponent reporting in, and the timeout -- so the guard
  /// matters.
  Future<void> _showResult() async {
    if (_resultShown) return;
    _resultShown = true;
    _waitTimer?.cancel();

    // Read before the match is filed, so the streak can be compared either
    // side of it.
    final before = ref.read(profileProvider).streak;

    final result = _engine.finish();
    await ref.read(profileProvider.notifier).recordMatch(result, widget.mode);

    if (!mounted) return;

    final after = ref.read(profileProvider).streak;
    final milestone = StreakRewards.newlyEarned(
      before: before.best,
      after: after.best,
    ).firstOrNull;

    // Only the first duel of a day moves the streak, and only then is there
    // anything to celebrate. Every match after that goes straight through.
    if (before.lastPlayedDay != after.lastPlayedDay && after.current > 0) {
      setState(() => _flareDays = after.current);
      HapticFeedback.heavyImpact();
      await _flareFinished.future;
      if (!mounted) return;
    }

    context.pushReplacement(
      AppRoutes.result,
      extra: ResultArgs(result, widget.mode, milestone: milestone),
    );
  }

  /// Completed by the celebration when it has played out.
  final Completer<void> _flareFinished = Completer<void>();

  /// Mind Snap shows the pattern, then hides it for the player to reproduce.
  /// Holds the answered board on screen for a moment before moving on.
  ///
  /// The next pattern used to flash on the same frame as the last tap. Showing
  /// the solved board first -- the cells that were lit, and any the player
  /// missed -- is what turns a round into something you can learn from.
  void _reviewRound() {
    // Rewound before the beat starts, not when the clearing does. A finished
    // controller rests at 1, and the board reads its value for the whole
    // hold -- so from the second round on, every cell the player had just
    // tapped was already at nothing on the frame they finished tapping. The
    // board went blank, sat blank, and then the cells popped back to full
    // size as forward(from: 0) rewound it, which is the "blank, then the
    // animation" the player was seeing.
    _vanish.value = 0;
    setState(() => _reviewing = true);
    _reviewTimer?.cancel();
    // Held long enough to read, then cleared. The clearing is the handover:
    // the next pattern arrives on the frame the last one finishes leaving,
    // so there is never a cut from one board straight to another.
    _reviewTimer = Timer(const Duration(milliseconds: kMindSnapReviewMs), () {
      if (mounted && !_settled) _vanish.forward(from: 0);
    });
  }

  void _beginPatternFlash() {
    final question = _engine.current;
    if (question is! PatternRound) return;
    setState(() {
      _showingPattern = true;
      _reviewing = false;
      _tapped.clear();
      _solved = null;
    });
    _flashTimer?.cancel();
    _flashTimer = Timer(Duration(milliseconds: question.flashMs), () {
      if (mounted && !_settled) setState(() => _showingPattern = false);
    });
  }

  void _afterAnswer(int answersBefore) {
    // A tap that arrived after the buzzer is discarded by the engine, and
    // must not be reported back as if it had scored.
    if (_engine.answers.length > answersBefore) {
      final record = _engine.answers.last;
      _lastVerdict = AnswerVerdict.of(record);
      _lastPoints = record.points;
      _lastVerdict.tap();
      // Not in Mind Snap. There the board has already said it, cell by cell,
      // in the same two colours -- and it says it about each tap rather than
      // about the round as a whole. A chip laid over the top of that is the
      // same news a second time, arriving just as the player is reading the
      // answer they actually gave.
      if (!widget.mode.isRoundBased) _verdict.forward(from: 0);
    }
    _typed = '';
    _report();
    if (widget.mode.isRoundBased) {
      _reviewRound();
    } else {
      setState(() {});
    }
  }

  void _submitDigit(String digit) {
    _touched();
    final question = _engine.current as NumericQuestion;
    final next = _typed + digit;
    // Auto-submits once the entry is as long as the answer, which keeps the
    // pace up -- a confirm button costs a tap on every single question.
    if (next.length >= question.answer.toString().length) {
      final before = _engine.answers.length;
      _engine.submitNumber(int.tryParse(next) ?? -1, atMs: _elapsedMs);
      _afterAnswer(before);
    } else {
      setState(() => _typed = next);
    }
  }

  void _submitOption(int index) {
    _touched();
    final before = _engine.answers.length;
    _engine.submitOption(index, atMs: _elapsedMs);
    _afterAnswer(before);
  }

  /// Mind Snap has no submit button: the player taps as many cells as were
  /// lit, right or wrong, and the round settles on the last tap. Asking them
  /// to confirm would cost a tap on every single round, and there is nothing
  /// to confirm -- the count is fixed and they cannot take a tap back.
  void _tapCell(int cell) {
    _touched();
    if (_tapped.contains(cell)) return;
    final round = _engine.current as PatternRound;
    setState(() => _tapped.add(cell));

    // Right and wrong taps feel different, not just look different.
    if (round.litCells.contains(cell)) {
      HapticFeedback.selectionClick();
    } else {
      HapticFeedback.heavyImpact();
    }

    if (_tapped.length >= round.litCells.length) _submitPattern();
  }

  void _submitPattern() {
    final before = _engine.answers.length;
    // Captured before submitting, because submitting moves the engine on.
    _solved = _engine.current as PatternRound;
    _engine.submitPattern(Set.of(_tapped), atMs: _elapsedMs);
    _afterAnswer(before);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countInTimer?.cancel();
    _flashTimer?.cancel();
    _reviewTimer?.cancel();
    _waitTimer?.cancel();
    _idleTimer?.cancel();
    _vanish.dispose();
    _grace.dispose();
    // Nothing is awaiting this once the screen is gone, but leaving a future
    // hanging is how a stuck await becomes a black screen.
    if (!_flareFinished.isCompleted) _flareFinished.complete();
    _roomSubscription?.cancel();
    _verdict.dispose();
    if (_ticker.isActive) _ticker.stop();
    _ticker.dispose();
    super.dispose();
  }

  /// Back to wherever this duel was opened from -- or home, when there is
  /// nothing behind it.
  ///
  /// A guest who cold-started from a tapped invite link has no stack under
  /// them: the lobby replaced the launch route and the duel replaced the
  /// lobby. Popping there pops the last page in the app, which leaves them
  /// staring at the duel they just left.
  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  /// Backing out mid-match abandons it unrated, so ask first. Nothing is at
  /// stake during the count-in, so that leaves freely.
  Future<bool> _confirmQuit() async {
    // Somebody reading a dialog is plainly still here, so the idle watch
    // stands down rather than calling the duel off underneath the question it
    // just asked.
    _idleTimer?.cancel();
    _grace.stop();
    if (_asking) setState(() => _asking = false);

    final quit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Leave the duel?'),
        content: const Text(
          'The match will be abandoned and will not count towards your '
          'rating or streak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep playing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.loss),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    // Staying means the watch starts again from now, not from the last thing
    // they touched before opening this.
    if (quit != true) _watchForIdle();
    return quit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final flareDays = _flareDays;
    if (flareDays != null) {
      return StreakFlare(
        days: flareDays,
        onDone: () {
          if (!_flareFinished.isCompleted) _flareFinished.complete();
        },
      );
    }
    if (_countIn > 0) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || _settled) return;
          // No dialog: this player has answered nothing and has nothing at
          // stake, so there is no decision to put to them. The friend does
          // have something at stake, though -- they are sat in front of the
          // same count-in -- and without this they would play a whole minute
          // against a name that left before the clock started.
          _settled = true;
          _countInTimer?.cancel();
          _tellThemIAmOut();
          _leave();
        },
        child: _CountIn(count: _countIn, mode: widget.mode),
      );
    }
    if (_awaitingOpponent) {
      return _AwaitingOpponent(name: _engine.opponentName, mode: widget.mode);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _settled) return;
        final shouldLeave = await _confirmQuit();
        if (!context.mounted) return;
        if (!shouldLeave) return;
        // Leaving is the same desertion as going quiet, so it ends the same
        // way for the person on the other phone. Without this they play the
        // rest of a minute against a score that has stopped moving, and then
        // wait out a twelve-second timeout for a phone that is not coming
        // back. Set before the pop, so the buzzer cannot settle a match on
        // the way out.
        _settled = true;
        _tellThemIAmOut();
        _leave();
      },
      child: Scaffold(
        body: SafeArea(
          // A finger down anywhere is proof enough that somebody is here --
          // it does not have to be on the right cell. Translucent, so it
          // watches every touch without taking one away from the keypad.
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _touched(),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _Scoreboard(
                    engine: _engine,
                    elapsedMs: _elapsedMs,
                    playerName: _playerName,
                    playerAvatarId: _playerAvatarId,
                    playerPhoto: _playerPhoto,
                  ),
                  // Given room of its own above the play area rather than laid
                  // over it. A warning that covers the board is a warning that
                  // stops you doing the one thing it is asking for.
                  if (_asking) _StillThere(grace: _grace, mode: widget.mode),
                  Expanded(
                    child: AnswerFeedback(
                      progress: _verdict,
                      verdict: _lastVerdict,
                      points: _lastPoints,
                      child: Center(child: _buildQuestion()),
                    ),
                  ),
                  _buildInput(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuestion() {
    final question = _onScreen;
    return switch (question) {
      NumericQuestion q => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            q.prompt,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Container(
            width: 180,
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              _typed.isEmpty ? 'Enter answer' : _typed,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _typed.isEmpty ? AppColors.textMuted : AppColors.text,
              ),
            ),
          ),
        ],
      ),
      ChoiceQuestion q => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            q.prompt,
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
      PatternRound q => AnimatedBuilder(
        animation: _vanish,
        builder: (context, _) => PatternGrid(
          round: q,
          // Only while the pattern is being shown. Turning this on for the
          // beat as well swapped the board on the frame of the last touch:
          // the player's own wrong taps blinked out and the cells they had
          // missed lit up, all at the instant they finished. What they are
          // looking at now stays exactly as they left it, and then it leaves.
          revealed: _showingPattern,
          tapped: _tapped,
          accent: widget.mode.color,
          // Only while the answered board is clearing. The controller rests
          // at 1 once it has finished, which would wipe the pattern that
          // comes next.
          vanish: _reviewing ? _vanish.value : 0,
          // Nothing is tappable while the board is showing an answer or
          // clearing. That is also what makes a finger still resting on the
          // last cell harmless: it is lifted off a board not listening.
          onTap: _showingPattern || _reviewing ? null : _tapCell,
        ),
      ),
    };
  }

  Widget _buildInput() {
    final question = _onScreen;
    return switch (question) {
      NumericQuestion() => Keypad(
        accent: widget.mode.color,
        onDigit: _submitDigit,
        onBackspace: () => setState(
          () => _typed = _typed.isEmpty
              ? ''
              : _typed.substring(0, _typed.length - 1),
        ),
      ),
      ChoiceQuestion q => _OptionButtons(
        question: q,
        accent: widget.mode.color,
        wide: q.options.length == 2,
        onPick: _submitOption,
      ),
      PatternRound q => _TapProgress(
        taken: _tapped.length,
        total: q.litCells.length,
        hits: _tapped.where(q.litCells.contains).length,
        memorising: _showingPattern,
        accent: widget.mode.color,
      ),
    };
  }
}

/// How many of the lit cells the player has reproduced so far. Replaces the
/// submit button, which had nothing to confirm.
class _TapProgress extends StatelessWidget {
  const _TapProgress({
    required this.taken,
    required this.total,
    required this.hits,
    required this.memorising,
    required this.accent,
  });

  final int taken;
  final int total;

  /// Of the taps made so far, how many landed on a lit cell.
  final int hits;
  final bool memorising;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Column(
        children: [
          Text(
            memorising ? 'MEMORISE' : 'TAP $total CELLS',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: memorising ? accent : AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < total; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i < taken ? 20 : 14,
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    // Hits fill first, then misses, so the bar reads as a
                    // score rather than just a count of taps.
                    color: i < hits
                        ? accent
                        : i < taken
                        ? AppColors.loss
                        : AppColors.surfaceHigh,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountIn extends StatelessWidget {
  const _CountIn({required this.count, required this.mode});

  final int count;
  final GameMode mode;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            mode.label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: mode.color),
          ),
          const SizedBox(height: 12),
          TweenAnimationBuilder<double>(
            key: ValueKey(count),
            tween: Tween(begin: 1.8, end: 1.0),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            builder: (context, scale, child) => Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: (2 - scale).clamp(0.0, 1.0),
                child: child,
              ),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 96,
                fontWeight: FontWeight.w800,
                color: mode.color,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(mode.blurb, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    ),
  );
}

/// Two named players and a clock.
///
/// Both sides carry a face and a name, because "YOU vs OPPONENT" is the one
/// place the whole illusion falls down -- the bots have had settled names and
/// avatars all along precisely so this row can read as two people.
class _Scoreboard extends StatelessWidget {
  const _Scoreboard({
    required this.engine,
    required this.elapsedMs,
    required this.playerName,
    required this.playerAvatarId,
    this.playerPhoto,
  });

  final MatchEngine engine;
  final int elapsedMs;
  final String playerName;
  final int playerAvatarId;
  final String? playerPhoto;

  @override
  Widget build(BuildContext context) {
    final seconds = (engine.remainingMs / 1000).ceil();
    final urgent = seconds <= 10;
    final clock =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    // Derived from elapsed time rather than its own controller: the match
    // ticker already rebuilds this every frame, so a second one would only
    // add another thing to keep in sync.
    final beat = urgent ? 0.5 + 0.5 * math.sin(elapsedMs / 110) : 0.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _ScorePill(
            name: playerName,
            avatarId: playerAvatarId,
            photo: playerPhoto,
            score: engine.playerScore,
            color: engine.mode.color,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Transform.scale(
            scale: 1 + beat * 0.12,
            child: Text(
              clock,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: urgent ? AppColors.loss : AppColors.win,
              ),
            ),
          ),
        ),
        Expanded(
          child: _ScorePill(
            name: engine.opponentName,
            avatarId: engine.opponentAvatarId,
            photo: engine.opponentPhoto,
            score: engine.opponentScore,
            color: AppColors.textMuted,
            alignEnd: true,
          ),
        ),
      ],
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({
    required this.name,
    required this.avatarId,
    required this.score,
    required this.color,
    this.photo,
    this.alignEnd = false,
  });

  final String name;
  final int avatarId;
  final String? photo;
  final int score;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final face = AvatarBadge(
      avatarId: avatarId,
      name: name,
      photo: photo,
      size: 26,
    );
    final label = Flexible(
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          letterSpacing: 0.2,
          color: AppColors.text,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: alignEnd
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: alignEnd
              ? [label, const SizedBox(width: 7), face]
              : [face, const SizedBox(width: 7), label],
        ),
        const SizedBox(height: 2),
        PopOnChange(
          value: score,
          child: Text(
            '$score',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _OptionButtons extends StatelessWidget {
  const _OptionButtons({
    required this.question,
    required this.accent,
    required this.wide,
    required this.onPick,
  });

  final ChoiceQuestion question;
  final Color accent;
  final bool wide;
  final void Function(int) onPick;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: wide ? 1.9 : 2.6,
      children: [
        for (var i = 0; i < question.options.length; i++)
          Material(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onPick(i),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withValues(alpha: 0.4)),
                ),
                child: Text(
                  question.options[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: wide ? 30 : 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Shown in the seconds between this player's buzzer and the other phone
/// reporting in, so the result is never computed against half a score.
class _AwaitingOpponent extends StatelessWidget {
  const _AwaitingOpponent({required this.name, required this.mode});

  final String name;
  final GameMode mode;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation(mode.color),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Time. Waiting for $name to finish…',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    ),
  );
}

/// "Still there?" -- and the five seconds it is worth.
///
/// Sits in the layout above the board, not over it: covering the grid would
/// hide the one thing the player has to touch to make it go away. It draws
/// itself from the same controller that ends the duel, so the number counting
/// down and the moment it runs out cannot disagree.
class _StillThere extends StatelessWidget {
  const _StillThere({required this.grace, required this.mode});

  final AnimationController grace;
  final GameMode mode;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: grace,
      builder: (context, _) {
        final t = grace.value;
        final left = (DuelScreen.grace.inSeconds * (1 - t)).ceil().clamp(1, 9);
        // The first tenth of the countdown is spent arriving, so it drops in
        // rather than blinking into existence.
        final enter = Curves.easeOutBack.transform((t / 0.1).clamp(0.0, 1.0));

        return Opacity(
          opacity: (t / 0.06).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -14 * (1 - enter)),
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.loss.withValues(alpha: 0.7),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.timer_outlined,
                        color: AppColors.loss,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Still there?',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              'Answer, or the duel is called off',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '$left',
                        key: const ValueKey('grace-count'),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: AppColors.loss,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: 1 - t,
                      minHeight: 4,
                      backgroundColor: AppColors.surfaceHigh,
                      valueColor: AlwaysStoppedAnimation(AppColors.loss),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
