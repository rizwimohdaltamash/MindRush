import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Locks the app in portrait mode so the screen doesn't rotate if the user
  // turns their phone sideways.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // The one thing worth waiting for: the local database, where the player's
  // name, ratings and streak live. It opens off the disk in a few
  // milliseconds and it is the source of truth, so the app is genuinely
  // ready once it is here.
  final GameStore local = await GameStore.open();

  // Everything else -- Firebase, signing in, fetching the player's row, the
  // notification plugin -- used to be awaited here too, which meant the app
  // sat on a black screen through three network round trips before it drew
  // anything. On bad wifi that was seconds. It now happens behind the intro,
  // through this stand-in, which keeps anything written in the meantime and
  // replays it the moment the real cloud arrives.
  final cloud = DeferredCloud();
  final monitor = CloudMonitor();
  final store = SyncedGameStore(local, cloud);

  runApp(
    ProviderScope(
      overrides: [
        gameStoreProvider.overrideWithValue(store),
        cloudMonitorProvider.overrideWithValue(monitor),
        photoSourceProvider.overrideWithValue(DevicePhotoSource()),
      ],
      child: CloudBoot(
        cloud: cloud,
        store: store,
        monitor: monitor,
        child: const MindRushApp(),
      ),
    ),
  );
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
  @override
  void initState() {
    super.initState();
    // Deliberately not awaited anywhere: every one of these is a feature the
    // app is expected to run without.
    unawaited(_connect());
    unawaited(_prepareReminders());
  }

  Future<void> _connect() async {
    final players = await _connectPlayers(widget.monitor);
    if (players == null) return;

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

/// Starts Firebase and opens the players collection, or returns null and
/// leaves the app running entirely on local storage.
Future<FirestorePlayers?> _connectPlayers(CloudMonitor monitor) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    _reportCrashes(monitor);
    return await FirestorePlayers.connect(monitor: monitor);
  } catch (error) {
    debugPrint('MindRush: running offline only ($error)');
    return null;
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
  /// Read once, before the splash and the name prompt.
  ///
  /// A guest arriving from WhatsApp without the app installed goes through the
  /// intro and onboarding first, and only then is a router built. Reading the
  /// launch route at that point happens to still work, but it is a fragile
  /// thing to depend on -- so it is captured here, up front, and held.
  late final String _launchRoute =
      widget.launchRoute ??
      WidgetsBinding.instance.platformDispatcher.defaultRouteName;

  late final GoRouter _router = buildRouter(initialLocation: _launchRoute);

  /// The animated intro plays once per launch, then never gets in the way.
  bool _introFinished = false;

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  // Traffic controller to check if the user wrote his name or not and whether the intro is finished or not.
  @override
  Widget build(BuildContext context) {
    // Is the intro finished?
    if (!_introFinished) {
      return MaterialApp(
        title: 'MindRush',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: SplashScreen(
          onFinished: () => setState(() => _introFinished = true),
        ),
      );
    }
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
