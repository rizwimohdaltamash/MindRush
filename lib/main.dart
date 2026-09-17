import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/challenge/challenge_link.dart';
import 'data/cloud_sync.dart';
import 'data/deferred_cloud.dart';
import 'data/photo_source.dart';
import 'data/duel_room_service.dart';
import 'data/cloud_status.dart';
import 'data/error_report.dart';
import 'data/players_repository.dart';
import 'data/game_store.dart';
import 'firebase_options.dart';
import 'notifications/local_scheduler.dart';
import 'router/app_router.dart';
import 'state/providers.dart';
import 'ui/screens/splash_screen.dart';
import 'ui/screens/welcome_screen.dart';
import 'ui/widgets/presence_heartbeat.dart';
import 'ui/theme.dart';

/// Nothing is awaited here, and that is the whole point.
///
/// Tapping the icon used to put the still launcher mark on screen for a
/// couple of seconds before the intro began. That gap was not the phone being
/// slow: it was this function. The OS holds its own splash until Flutter
/// draws its first frame, and Flutter cannot draw a first frame until [main]
/// reaches [runApp] -- so every await here was time the player spent looking
/// at a photograph of the logo instead of the animation of it.
///
/// Opening the local save is a plugin channel call for the documents
/// directory and two boxes read off the disk; the orientation lock is another
/// channel round trip. Neither is slow on its own, and together, on a cold
/// start with the engine still warming up, they were most of that gap. Both
/// now happen underneath the intro rather than in front of it.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Locks the app in portrait mode so the screen doesn't rotate if the user
  // turns their phone sideways. Fire and forget: a frame or two in landscape
  // on a phone nobody is holding sideways is not worth a millisecond of the
  // launch.
  unawaited(
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
  );

  runApp(const Boot());
}

/// The first thing Flutter draws, and what it draws while getting ready.
///
/// The intro plays immediately. Behind it the local save opens -- the
/// database holding the player's name, ratings and streak, and the source of
/// truth for all of it -- and the app proper is built once both the animation
/// has finished and the save is in hand.
///
/// In practice the save wins that race by well over a second, so the intro is
/// never waited on and never cut short. Holding for whichever finishes last
/// is what makes that a fact rather than a hope.
class Boot extends StatefulWidget {
  const Boot({super.key});

  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  SyncedGameStore? _store;
  DeferredCloud? _cloud;
  CloudMonitor? _monitor;

  /// The animated intro plays once per launch, then never gets in the way.
  bool _introFinished = false;

  /// Where the app was asked to open, read on the first frame of the first
  /// widget there is.
  ///
  /// This has to happen here rather than in [MindRushApp], because
  /// [MindRushApp] is not built until the intro is over and the save is open
  /// -- a couple of seconds in, by which point a tapped invite is old news.
  /// A guest arriving from WhatsApp is the whole reason any of this exists,
  /// so the one thing that carries them is read before anything else runs.
  String? _launchRoute;

  @override
  void initState() {
    super.initState();
    _launchRoute = WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    unawaited(_openTheSave());
  }

  Future<void> _openTheSave() async {
    final local = await GameStore.open();
    if (!mounted) return;

    // Firebase, signing in, fetching the player's row, the notification
    // plugin -- none of it is waited for. It happens through this stand-in,
    // which keeps anything written in the meantime and replays it the moment
    // the real cloud arrives.
    final cloud = DeferredCloud();
    final monitor = CloudMonitor();
    setState(() {
      _cloud = cloud;
      _monitor = monitor;
      _store = SyncedGameStore(local, cloud);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    if (!_introFinished || store == null) {
      return MaterialApp(
        title: 'MindRush',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: SplashScreen(
          onFinished: () => setState(() => _introFinished = true),
        ),
      );
    }

    return ProviderScope(
      overrides: [
        gameStoreProvider.overrideWithValue(store),
        cloudMonitorProvider.overrideWithValue(_monitor!),
        photoSourceProvider.overrideWithValue(DevicePhotoSource()),
      ],
      child: CloudBoot(
        cloud: _cloud!,
        store: store,
        monitor: _monitor!,
        child: MindRushApp(launchRoute: _launchRoute),
      ),
    );
  }
}

/// Connects everything that could not be waited for, then switches it on.
///
/// It is a widget rather than a few more lines in [main] so that it can reach
/// the providers: the app is already running by the time any of this
/// finishes, so the connection has to be handed to a tree that exists rather
/// than baked into one that does not yet.
class CloudBoot extends ConsumerStatefulWidget {
  const CloudBoot({
    super.key,
    required this.cloud,
    required this.store,
    required this.monitor,
    required this.child,
  });

  final DeferredCloud cloud;
  final SyncedGameStore store;
  final CloudMonitor monitor;
  final Widget child;

  @override
  ConsumerState<CloudBoot> createState() => _CloudBootState();
}

class _CloudBootState extends ConsumerState<CloudBoot> {
  StreamSubscription<User?>? _authSub;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    // Deliberately not awaited anywhere: every one of these is a feature the
    // app is expected to run without.
    unawaited(_afterTheIntro());
  }

  /// Holds everything heavy back until the first real screen has settled.
  ///
  /// Starting Firebase is a platform-channel round trip and a pile of plugin
  /// registration, and the notification plugin loads the whole timezone
  /// database. Both used to run underneath the intro -- which is the one
  /// moment in the app's life with the least frame budget to spare, because
  /// the engine is still warming up and every shader is being compiled for
  /// the first time. Dropped frames there are the ones a player actually
  /// notices, since there is nothing on screen but movement.
  ///
  /// [Boot] only builds this once the intro is over, so most of that is
  /// already avoided; the beat on top of it is for the screen underneath to
  /// draw before anything lands on the platform thread.
  ///
  /// Nothing is lost by waiting: the local save is open, so the app is fully
  /// playable, and the cloud connects a moment later than it used to -- by
  /// which point the player is still reading the home screen.
  Future<void> _afterTheIntro() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    unawaited(_watchForSignIn());
    unawaited(_prepareReminders());
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  /// Starts Firebase, then connects the cloud whenever there is somebody to
  /// connect it for.
  ///
  /// Listened for rather than done once at launch, because signing in happens
  /// on the welcome screen -- which is drawn after this runs. A returning
  /// player's cached credential arrives on the first event and connects
  /// immediately; a brand new one connects the moment they finish with the
  /// account picker.
  Future<void> _watchForSignIn() async {
    if (!await _startFirebase(widget.monitor)) return;
    if (!mounted) return;
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) unawaited(_connect());
    });
  }

  Future<void> _connect() async {
    if (_connecting || !mounted) return;
    _connecting = true;
    final players = await FirestorePlayers.connect(monitor: widget.monitor);
    if (players == null) {
      _connecting = false;
      return;
    }

    // The catch-up that used to happen before the first frame: adopt the
    // cloud's copy if it is newer than this device's, then send ours up.
    await widget.store.catchUp(await players.fetch());
    await widget.cloud.attach(players);

    final rooms = await FirestoreDuelRooms.connect();
    if (!mounted) return;
    ref.read(runtimeProvider.notifier).arrived(players: players, rooms: rooms);
  }

  Future<void> _prepareReminders() async {
    // Loading the timezone database and initialising the plugin costs a
    // couple of hundred milliseconds, which is a couple of hundred
    // milliseconds nobody should spend looking at nothing.
    final scheduler = await LocalNotificationScheduler.create();
    if (scheduler == null || !mounted) return;
    ref.read(runtimeProvider.notifier).arrived(scheduler: scheduler);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// True for the failures that mean "no signal" rather than "bug".
///
/// Filtered out deliberately. A phone on a train fails every write it
/// attempts, and reporting each one would bury the one real fault in a
/// thousand copies of "the wifi went" -- which is not a thing anybody can fix
/// and not a thing this app treats as broken.
bool isJustTheNetwork(Object error) =>
    error is FirebaseException &&
    const {
      'unavailable',
      'deadline-exceeded',
      'network-request-failed',
      'aborted',
    }.contains(error.code);

/// Starts Firebase and wires up crash reporting.
///
/// False leaves the app running entirely on local storage, which is a
/// complete game -- what is missing is the leaderboard and friend duels.
Future<bool> _startFirebase(CloudMonitor monitor) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    _reportCrashes(monitor);
    return true;
  } catch (error) {
    debugPrint('MindRush: running offline only ($error)');
    return false;
  }
}

/// Sends anything that gets past the app to Crashlytics.
///
/// This runs a moment after launch rather than before the first frame,
/// because Firebase itself does -- that is what keeps the intro instant. It
/// costs less than it sounds: the Android SDK installs its own handler when
/// the process starts, so a hard crash is captured whether or not this has
/// run yet. What is wired here is the Dart half, which cannot exist until
/// Firebase does.
void _reportCrashes(CloudMonitor monitor) {
  final crashlytics = FirebaseCrashlytics.instance;

  FlutterError.onError = (details) {
    // Still printed, and still red-screened in debug: reporting a crash is an
    // addition to seeing it, not a replacement for it.
    FlutterError.presentError(details);
    crashlytics.recordFlutterError(details, fatal: true);
  };

  // Errors thrown outside the framework's own call stack -- a failed future
  // nobody awaited, a callback from the platform -- which FlutterError never
  // sees.
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    crashlytics.recordError(error, stack, fatal: true);
    return true;
  };

  // Everything this app catches and survives -- a refused write, a camera
  // that would not open, a reminder that would not schedule. Without this,
  // the failures most likely to be happening in the field would be the ones
  // Crashlytics never heard about, because the app is at its quietest exactly
  // when something is most wrong with it. Recorded as non-fatal, which is
  // what they are: the game carried on.
  Report.sink = (error, stack, reason) {
    if (isJustTheNetwork(error)) return;
    unawaited(
      crashlytics.recordError(error, stack, reason: reason, fatal: false),
    );
  };

  // Which phone a report came from. The account is anonymous, so this is a
  // random id and nothing about a person -- but with two test devices it is
  // the difference between a report you can place and one you cannot.
  //
  // Listened for rather than read now: signing in happens after this runs.
  String? tagged;
  monitor.addListener(() {
    final uid = monitor.value.uid;
    if (uid == null || uid == tagged) return;
    tagged = uid;
    unawaited(crashlytics.setUserIdentifier(uid));
  });
}

class MindRushApp extends ConsumerStatefulWidget {
  const MindRushApp({super.key, this.launchRoute});

  /// Where the app was asked to open, if it was launched by a tapped link.
  /// Injectable so the install-then-name-then-lobby path is testable; in the
  /// real app it comes from the platform.
  final String? launchRoute;

  @override
  ConsumerState<MindRushApp> createState() => _MindRushAppState();
}

class _MindRushAppState extends ConsumerState<MindRushApp> {
  /// Where the app was asked to open, if it was a tapped invite link.
  ///
  /// [Boot] reads it from the platform on the very first frame and passes it
  /// in, because by the time this widget exists the answer is two seconds
  /// stale and has had a Google account picker in front of it. Falling back
  /// to the platform here covers the case where nobody passed one.
  String? _launchRoute;

  late final GoRouter _router = buildRouter(initialLocation: _launchRoute);

  @override
  void initState() {
    super.initState();
    _launchRoute = _challengeIn(
      widget.launchRoute ??
          WidgetsBinding.instance.platformDispatcher.defaultRouteName,
    );
  }

  /// [route] if it is a challenge link, and null for anything else.
  ///
  /// A challenge is the only reason this app should ever open anywhere but
  /// home. Everything else the platform might hand over -- '/', a leftover
  /// from the last session, whatever an account picker returns -- is not a
  /// destination the player chose, and treating it as one is how signing in
  /// landed somebody on the settings screen.
  static String? _challengeIn(String? route) {
    if (route == null) return null;
    final uri = Uri.tryParse(route);
    if (uri == null) return null;
    return ChallengeInvite.parse(uri) == null ? null : route;
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  // Traffic controller to check whether the user has an account yet. The
  // intro is behind us by the time this builds: it belongs to [Boot], which
  // plays it before there is a store to build this tree around.
  @override
  Widget build(BuildContext context) {
    // Is it a brand new player
    final needsName = ref.watch(
      profileProvider.select((p) => p.needsOnboarding),
    );

    if (needsName) {
      return MaterialApp(
        title: 'MindRush',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const WelcomeScreen(),
      );
    }
    // Let them play
    return PresenceHeartbeat(
      child: MaterialApp.router(
        title: 'MindRush',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        routerConfig: _router,
      ),
    );
  }
}
