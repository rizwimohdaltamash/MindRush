import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mind_rush/core/bots/bot_engine.dart';
import 'package:mind_rush/core/match/match_result.dart';
import 'package:mind_rush/core/models/game_mode.dart';
import 'package:mind_rush/core/bots/bot_profile.dart';
import 'package:mind_rush/core/challenge/duel_room.dart';
import 'package:mind_rush/core/questions/difficulty.dart';
import 'package:mind_rush/core/players/player_record.dart';
import 'package:mind_rush/data/duel_room_service.dart';
import 'package:mind_rush/data/players_repository.dart';
import 'package:mind_rush/data/game_store.dart';
import 'package:mind_rush/data/match_summary.dart';
import 'package:mind_rush/core/rating/streak.dart';
import 'package:mind_rush/data/player_profile.dart';
import 'package:mind_rush/router/app_router.dart';
import 'package:mind_rush/state/providers.dart';
import 'package:mind_rush/ui/screens/result_screen.dart';
import 'package:mind_rush/ui/screens/welcome_screen.dart';
import 'package:mind_rush/ui/widgets/streak_flare.dart';
import 'package:mind_rush/ui/theme.dart';

import 'support/fake_rooms.dart';
import 'support/test_fonts.dart';

/// Renders each screen to a PNG so the UI can actually be looked at rather
/// than only asserted about. Regenerate with:
///   flutter test test/goldens_test.dart --update-goldens
void main() {
  setUpAll(loadRealFonts);

  Widget app(
    GameStore store,
    GoRouter router, [
    DuelRoomService? rooms,
    PlayerService? presence,
  ]) => ProviderScope(
    overrides: [
      gameStoreProvider.overrideWithValue(store),
      randomProvider.overrideWithValue(Random(7)),
      duelRoomServiceProvider.overrideWithValue(rooms),
      playerServiceProvider.overrideWithValue(presence),
    ],
    child: MaterialApp.router(
      theme: buildTheme(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    ),
  );

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// A player a few days in, so the screens show real numbers rather than
  /// a row of 1000s and empty states.
  GameStore playedStore() {
    final store = InMemoryGameStore();
    var rating = 1000;
    final history = <MatchSummary>[];
    const scores = [120, 160, 140, 190, 170, 210, 200, 230];
    for (var i = 0; i < scores.length; i++) {
      final delta = [6, -4, 8, 5, -3, 9, 6, 7][i];
      history.insert(
        0,
        MatchSummary(
          mode: i.isEven ? GameMode.sprint : GameMode.fastestFingers,
          playerScore: scores[i],
          opponentScore: scores[i] - delta * 3,
          opponentName: const ['Meera', 'Rohan', 'Ishita', 'Kabir'][i % 4],
          ratingBefore: rating,
          ratingDelta: delta,
          accuracy: 0.86 + i * 0.01,
          averageAnswerMs: 2600 - i * 40,
          playedAtMs: DateTime(2026, 8, 28 + i ~/ 2).millisecondsSinceEpoch,
        ),
      );
      rating += delta;
    }
    store.saveProfile(
      PlayerProfile.fresh(name: 'Naman', avatarId: 1).copyWith(
        ratings: {
          Category.math: rating,
          Category.memory: 1042,
          Category.logic: 968,
        },
        streak: StreakState(
          current: 4,
          best: 14,
          lastPlayedDay: StreakCalculator.dayNumber(DateTime.now()),
        ),
        history: history,
      ),
    );

    // Bots that have played a while, so the board is not a column of 1000s.
    const spread = [-96, -74, -51, -28, -9, 14, 33, 58, 77, 96];
    final roster = BotProfile.seedRoster();
    for (final (i, bot) in roster.indexed) {
      bot.ratings[Category.math] = 1000 + spread[i];
      bot.ratings[Category.memory] = 1000 + spread[(i + 3) % spread.length];
      bot.ratings[Category.logic] = 1000 + spread[(i + 6) % spread.length];
    }
    store.saveRoster(roster);
    return store;
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('welcome', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameStoreProvider.overrideWithValue(InMemoryGameStore()),
          randomProvider.overrideWithValue(Random(7)),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          debugShowCheckedModeBanner: false,
          home: const WelcomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await shoot(tester, '00_welcome');
  });

  testWidgets('home', (tester) async {
    phone(tester);
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(app(playedStore(), router));
    await tester.pumpAndSettle();
    await shoot(tester, '01_home');
  });

  /// The waiting line breathes forever, so these two are pumped in fixed
  /// steps rather than settled.
  Future<void> tick(WidgetTester tester, [int frames = 12]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  DuelRoom lobbyRoom({RoomPlayer? guest}) => DuelRoom(
    code: 'mindSnap-849213',
    mode: GameMode.mindSnap,
    seed: 849213,
    difficulty: Difficulty.medium,
    host: const RoomPlayer(uid: 'uid-host', name: 'Naman', avatarId: 1),
    guest: guest,
    status: guest == null ? RoomStatus.waiting : RoomStatus.ready,
  );

  /// Another registered player, online, as the directory reports them.
  GoldenPresence directoryWith({required int lastSeenAtMs}) =>
      GoldenPresence('uid-me', [
        PlayerRecord(
          uid: 'uid-me',
          name: 'Naman',
          avatarId: 0,
          lastSeenAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
        PlayerRecord(
          uid: 'uid-aarav',
          name: 'Aarav',
          avatarId: 4,
          lastSeenAtMs: lastSeenAtMs,
          ratings: const {
            Category.math: 1108,
            Category.memory: 1042,
            Category.logic: 1015,
          },
        ),
      ]);

  testWidgets('settings', (tester) async {
    phone(tester);
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(app(playedStore(), router));
    await tester.pumpAndSettle();
    router.push(AppRoutes.settings);
    await tester.pumpAndSettle();
    await shoot(tester, '19_settings');
  });

  testWidgets('the page for one duel', (tester) async {
    phone(tester);
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(app(playedStore(), router));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-memory')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mode-mindSnap')));
    await tester.pumpAndSettle();
    await shoot(tester, '17_mode_page');
  });

  testWidgets('finding a friend for a duel already chosen', (tester) async {
    phone(tester);
    final router = buildRouter();
    addTearDown(router.dispose);
    final presence = directoryWith(
      lastSeenAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    await tester.pumpWidget(app(playedStore(), router, null, presence));
    await tester.pumpAndSettle();
    router.go(AppRoutes.findFriend(GameMode.mindSnap));
    await tester.pumpAndSettle();
    await shoot(tester, '18_find_a_friend');
  });

  testWidgets('ranks - a friend online', (tester) async {
    phone(tester);
    final router = buildRouter();
    addTearDown(router.dispose);
    final presence = directoryWith(
      lastSeenAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    await tester.pumpWidget(app(playedStore(), router, null, presence));
    await tester.pumpAndSettle();
    router.go(AppRoutes.ranks);
    await tester.pumpAndSettle();
    await shoot(tester, '12_ranks_online');
  });

  testWidgets('an incoming challenge', (tester) async {
    phone(tester);
    final router = buildRouter();
    addTearDown(router.dispose);
    final backend = FakeRoomBackend();
    addTearDown(backend.dispose);
    final me = FakeRooms(backend, 'uid-me');

    await tester.pumpWidget(app(playedStore(), router, me));
    await tester.pumpAndSettle();

    await FakeRooms(backend, 'uid-aarav').create(
      DuelRoom.open(
        mode: GameMode.mindSnap,
        seed: 849213,
        difficulty: Difficulty.medium,
        host: const RoomPlayer(
          uid: 'uid-aarav',
          name: 'Aarav',
          avatarId: 4,
          rating: 1042,
        ),
        invitedUid: 'uid-me',
        invitedName: 'Naman',
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await shoot(tester, '13_challenge_arrives');
  });

  testWidgets('choosing the duel to challenge someone to', (tester) async {
    phone(tester);
    final router = buildRouter();
    addTearDown(router.dispose);
    final backend = FakeRoomBackend();
    addTearDown(backend.dispose);
    final presence = directoryWith(
      lastSeenAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    await tester.pumpWidget(
      app(playedStore(), router, FakeRooms(backend, 'uid-me'), presence),
    );
    await tester.pumpAndSettle();

    // Straight off the online row, which is the short path to a real duel.
    await tester.tap(find.byKey(const ValueKey('online-uid-aarav')));
    await tester.pumpAndSettle();
    await shoot(tester, '16_pick_a_duel');
  });

  testWidgets('streak - the ladder', (tester) async {
    phone(tester);
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(app(playedStore(), router));
    await tester.pumpAndSettle();
    router.go(AppRoutes.streak);
    await tester.pumpAndSettle();
    await shoot(tester, '14_streak_ladder');
  });

  testWidgets('streak - the daily flare', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        debugShowCheckedModeBanner: false,
        home: StreakFlare(days: 7, onDone: () {}),
      ),
    );
    // Caught partway through, where the flame has landed and the number is
    // still counting.
    await tester.pump(const Duration(milliseconds: 750));
    await shoot(tester, '15_streak_flare');
  });

  testWidgets('lobby - waiting for a friend', (tester) async {
    phone(tester);
    final router = buildRouter();
    addTearDown(router.dispose);
    final backend = FakeRoomBackend();
    addTearDown(backend.dispose);
    final host = FakeRooms(backend, 'uid-host');
    await host.create(lobbyRoom());

    await tester.pumpWidget(app(playedStore(), router, host));
    await tester.pumpAndSettle();
    router.go(AppRoutes.lobby('mindSnap-849213'));
    await tick(tester);
    await shoot(tester, '10_lobby_waiting');
  });

  testWidgets('lobby - both players in', (tester) async {
    phone(tester);
    final router = buildRouter();
    addTearDown(router.dispose);
    final backend = FakeRoomBackend();
    addTearDown(backend.dispose);
    // Viewed from the guest's phone, so nobody flips the room to counting and
    // the screenshot holds still on the moment both seats are full.
    final guest = FakeRooms(backend, 'uid-guest');
    await FakeRooms(backend, 'uid-host').create(
      lobbyRoom(
        guest: const RoomPlayer(uid: 'uid-guest', name: 'Aarav', avatarId: 4),
      ),
    );

    await tester.pumpWidget(app(playedStore(), router, guest));
    await tester.pumpAndSettle();
    router.go(AppRoutes.lobby('mindSnap-849213'));
    await tick(tester);
    await shoot(tester, '11_lobby_ready');
  });

  testWidgets('duel - sprint count in', (tester) async {
    phone(tester);
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(app(playedStore(), router));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-math')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mode-sprint')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('play-duel')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await shoot(tester, '02_countin');
  });

  testWidgets('duel - sprint', (tester) async {
    phone(tester);
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(app(playedStore(), router));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-math')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mode-sprint')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('play-duel')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump(const Duration(seconds: 8));
    await shoot(tester, '03_duel_sprint');
  });

  testWidgets('duel - mind snap', (tester) async {
    phone(tester);
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(app(playedStore(), router));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-memory')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mode-mindSnap')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('play-duel')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump(const Duration(milliseconds: 400));
    await shoot(tester, '04_duel_mindsnap');
  });

  testWidgets('duel - ability', (tester) async {
    phone(tester);
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(app(playedStore(), router));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-logic')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mode-ability')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('play-duel')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump(const Duration(seconds: 4));
    await shoot(tester, '05_duel_ability');
  });

  testWidgets('result', (tester) async {
    phone(tester);
    // Built directly so the speed chart has plenty of data to draw.
    final answers = [
      for (var i = 0; i < 18; i++)
        AnswerRecord(
          questionIndex: i,
          atMs: 2300 * (i + 1),
          durationMs: 1900 + (i % 5) * 420,
          points: i % 6 == 0 ? 0 : 10,
        ),
    ];
    final opponentFeed = BotRun([
      for (var i = 0; i < 21; i++)
        BotAnswerEvent(atMs: 2000 * (i + 1), points: i % 8 == 0 ? 0 : 10),
    ]);
    final result = MatchResult(
      playerScore: 150,
      opponentScore: 180,
      ratingBefore: 1034,
      ratingDelta: -5,
      answers: answers,
      opponentFeed: opponentFeed,
      opponentName: 'Ishita',
      opponentAvatarId: 4,
      shareCode: 'sprint-849213',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameStoreProvider.overrideWithValue(playedStore()),
          randomProvider.overrideWithValue(Random(7)),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          debugShowCheckedModeBanner: false,
          home: ResultScreen(result: result, mode: GameMode.sprint),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await shoot(tester, '06_result');
  });

  testWidgets('stats', (tester) async {
    phone(tester);
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(app(playedStore(), router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stats'));
    await tester.pumpAndSettle();
    await shoot(tester, '07_stats');
  });

  testWidgets('leaderboard', (tester) async {
    phone(tester);
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(app(playedStore(), router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ranks'));
    await tester.pumpAndSettle();
    await shoot(tester, '08_leaderboard');
  });

  testWidgets('profile', (tester) async {
    phone(tester);
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(app(playedStore(), router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await shoot(tester, '09_profile');
  });
}

/// Presence fixed in place, so the green dot is in the same state every run.
class GoldenPresence implements PlayerService {
  GoldenPresence(this.myUid, this.entries);

  @override
  final String myUid;

  final List<PlayerRecord> entries;

  @override
  Future<void> beat() async {}

  @override
  Future<void> leave() async {}

  @override
  Future<void> signOut() async {}

  @override
  Stream<List<PlayerRecord>> watch() => Stream.value(entries);
}
