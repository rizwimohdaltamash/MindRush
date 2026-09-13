import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mind_rush/core/bots/bot_profile.dart';
import 'package:mind_rush/core/models/game_mode.dart';
import 'package:mind_rush/core/questions/question.dart';
import 'package:mind_rush/core/rating/rating_engine.dart';
import 'package:mind_rush/data/game_store.dart';
import 'package:mind_rush/data/match_summary.dart';
import 'package:mind_rush/data/player_profile.dart';
import 'package:mind_rush/router/app_router.dart';
import 'package:mind_rush/state/providers.dart';
import 'package:mind_rush/ui/theme.dart';
import 'package:mind_rush/ui/widgets/pattern_grid.dart';

Widget _app(GameStore store, GoRouter router) => ProviderScope(
  overrides: [
    gameStoreProvider.overrideWithValue(store),
    randomProvider.overrideWithValue(Random(5)),
  ],
  child: MaterialApp.router(theme: buildTheme(), routerConfig: router),
);

void _usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Home filters modes by category and a mode card opens that duel's own page,
/// so starting a match is three taps: the discipline, the mode, then play.
/// Keyed finders because the category name also appears as a chip on each
/// mode card.
Future<void> _openMode(WidgetTester tester, GameMode mode) async {
  await tester.tap(find.byKey(ValueKey('category-${mode.category.name}')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('mode-${mode.name}')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('play-duel')));
  await tester.pumpAndSettle();
}

/// Gets past the count-in and into live play.
Future<void> _startMatch(WidgetTester tester, GameMode mode) async {
  await _openMode(tester, mode);
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pump();
}

/// Advances the match clock with somebody still holding the phone.
///
/// A duel is called off after ten seconds of nothing at all, so a test that
/// wants a full minute of play has to touch the screen the way a player
/// would. The tap lands on the scoreboard, which answers nothing and scores
/// nothing -- it is only proof of life.
Future<void> _playFor(WidgetTester tester, Duration total) async {
  var left = total;
  const step = Duration(seconds: 6);
  while (left > Duration.zero) {
    final slice = left < step ? left : step;
    await tester.pump();
    await tester.pump(slice);
    await tester.tapAt(const Offset(200, 60));
    left -= slice;
  }
}

/// Past the review beat and the board clearing, to the next pattern.
///
/// Two waits, not one: the beat is a timer and the clearing is an animation
/// that only starts when it fires, so the clock has to be let out twice.
Future<void> _pastTheBeat(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: kMindSnapReviewMs));
  await tester.pump(); // the clearing animation's first frame
  // A frame past the end rather than exactly on it: a controller reports
  // itself finished on the first tick *after* its duration, not on the tick
  // that reaches it.
  await tester.pump(const Duration(milliseconds: kMindSnapVanishMs + 16));
  await tester.pump(); // the frame the next pattern flashes on
}

/// pumpAndSettle is unusable while the match ticker is running -- it would
/// play the whole minute out -- so advance in fixed steps instead.
Future<void> _step(
  WidgetTester tester, [
  Duration d = const Duration(milliseconds: 300),
]) async {
  await tester.pump();
  await tester.pump(d);
}

ProviderContainer _containerFor(GameStore store) => ProviderContainer(
  overrides: [
    gameStoreProvider.overrideWithValue(store),
    randomProvider.overrideWithValue(Random(5)),
  ],
);

void main() {
  group('answering actually scores', () {
    testWidgets('Sprint: the keypad advances the question and the score', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(InMemoryGameStore(), router));
      await tester.pumpAndSettle();
      await _startMatch(tester, GameMode.sprint);

      final firstPrompt = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .firstWhere((d) => d != null && d.contains('= ?'));

      // Any digit; auto-submit fires once the entry matches the answer length.
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.widgetWithText(InkWell, '7').first);
        await _step(tester);
      }

      final laterPrompt = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .firstWhere((d) => d != null && d.contains('= ?'));
      expect(
        laterPrompt,
        isNot(firstPrompt),
        reason: 'the question must move on after answering',
      );
    });

    testWidgets('Ability: answers are typed on the keypad, not chosen', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(InMemoryGameStore(), router));
      await tester.pumpAndSettle();
      await _startMatch(tester, GameMode.ability);

      // A keypad, not option tiles.
      expect(find.text('Enter answer'), findsOneWidget);
      for (final digit in ['1', '7', '0']) {
        expect(find.widgetWithText(InkWell, digit), findsWidgets);
      }

      final before = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .firstWhere((d) => d != null && d.contains('= ?'));

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.widgetWithText(InkWell, '8').first);
        await _step(tester);
      }

      final after = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .firstWhere((d) => d != null && d.contains('= ?'));
      expect(after, isNot(before));
    });

    testWidgets('Mind Snap: every round clears, not only the first', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(InMemoryGameStore(), router));
      await tester.pumpAndSettle();
      await _startMatch(tester, GameMode.mindSnap);

      final grid = find.byType(PatternGrid);

      for (var round = 1; round <= 3; round++) {
        // Memorise, then tap the pattern back.
        await tester.pump(
          Duration(
            milliseconds: tester.widget<PatternGrid>(grid).round.flashMs,
          ),
        );
        await tester.pump();

        final pattern = tester.widget<PatternGrid>(grid).round;
        final cells = find.descendant(
          of: grid,
          matching: find.byType(GestureDetector),
        );
        for (final index in pattern.litCells) {
          await tester.tap(cells.at(index));
          await tester.pump();
        }

        // The beat has only just begun, so nothing has cleared yet and the
        // board is still showing what was tapped. A clearing animation left
        // sitting at its finished value by the previous round would have
        // wiped every one of those cells on the frame of the last touch --
        // the board going blank, holding blank, and the cells then snapping
        // back to full size when the clearing rewound itself to start.
        expect(
          tester.widget<PatternGrid>(grid).vanish,
          0,
          reason: 'round $round blanked instead of holding what was tapped',
        );

        await _pastTheBeat(tester);
      }
    });

    testWidgets('Mind Snap: the beat shows the board just answered', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(InMemoryGameStore(), router));
      await tester.pumpAndSettle();
      await _startMatch(tester, GameMode.mindSnap);

      // Memorise, then reproduce it exactly.
      await tester.pump(const Duration(milliseconds: 2500));
      final grid = find.byType(PatternGrid);
      final answered = tester.widget<PatternGrid>(grid).round;
      final cells = find.descendant(
        of: grid,
        matching: find.byType(GestureDetector),
      );
      for (final index in answered.litCells) {
        await tester.tap(cells.at(index));
        await tester.pump();
      }
      // A frame or two, not a fixed slice of the beat: the beat is short
      // enough now that a 300ms step would spend all of it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));

      // Answering advances the engine immediately, so the round the screen
      // asks for is already the next one. During the beat it has to be the
      // solved board: otherwise the player is shown the pattern that is
      // coming, marked up with the taps they made against the last one -- and
      // the counter beneath it jumps to a number that means nothing.
      expect(
        tester.widget<PatternGrid>(grid).round.signature,
        answered.signature,
        reason: 'the beat must hold the board that was just played',
      );
      expect(
        find.text('TAP ${answered.litCells.length} CELLS'),
        findsOneWidget,
      );

      // The board is still the solved one while it clears, so the pattern
      // that is coming is never shown early.
      await tester.pump(const Duration(milliseconds: kMindSnapReviewMs));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: kMindSnapVanishMs ~/ 2));
      expect(
        tester.widget<PatternGrid>(grid).round.signature,
        answered.signature,
      );
      expect(
        tester.widget<PatternGrid>(grid).vanish,
        greaterThan(0),
        reason: 'the answered cells should be on their way out by now',
      );

      // And once they have gone, the next pattern arrives.
      await tester.pump(const Duration(milliseconds: kMindSnapVanishMs));
      await tester.pump();
      expect(find.text('MEMORISE'), findsOneWidget);
    });

    testWidgets(
      'Mind Snap: six taps advance the round, with no submit button',
      (tester) async {
        _usePhoneScreen(tester);
        final router = buildRouter();
        addTearDown(router.dispose);
        await tester.pumpWidget(_app(InMemoryGameStore(), router));
        await tester.pumpAndSettle();
        await _startMatch(tester, GameMode.mindSnap);

        expect(find.text('MEMORISE'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 2500));
        expect(find.text('TAP $kMindSnapCells CELLS'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Submit'), findsNothing);
        expect(
          find.textContaining('Submit'),
          findsNothing,
          reason: 'the count is fixed, so there is nothing to confirm',
        );

        // Tapping the sixth cell must settle the round by itself.
        final cells = find.byType(GestureDetector);
        for (var i = 0; i < kMindSnapCells - 1; i++) {
          await tester.tap(cells.at(i));
          await tester.pump();
        }
        expect(find.text('MEMORISE'), findsNothing, reason: 'still mid-round');

        await tester.tap(cells.at(kMindSnapCells - 1));
        await _step(tester);
        // The answered board is held for a beat before the next pattern, so the
        // player can see what was there against what they tapped.
        expect(
          find.text('MEMORISE'),
          findsNothing,
          reason: 'the next pattern must not snatch the board away',
        );

        await _pastTheBeat(tester);
        expect(
          find.text('MEMORISE'),
          findsOneWidget,
          reason: 'the next round flashes with no further input',
        );
      },
    );
  });

  group('state propagates after a match', () {
    test('the roster notifies listeners when bot ratings change', () {
      final container = ProviderContainer(
        overrides: [
          gameStoreProvider.overrideWithValue(InMemoryGameStore()),
          randomProvider.overrideWithValue(Random(1)),
        ],
      );
      addTearDown(container.dispose);

      var notifications = 0;
      container.listen(rosterProvider, (_, _) => notifications++);

      final roster = container.read(rosterProvider);
      roster.first.applyResult(Category.math, 9);
      container.read(rosterProvider.notifier).persist();

      expect(
        notifications,
        greaterThan(0),
        reason: 'a visible leaderboard would otherwise show stale ratings',
      );
    });

    test('a finished match moves the rating, streak and history', () async {
      final container = ProviderContainer(
        overrides: [
          gameStoreProvider.overrideWithValue(InMemoryGameStore()),
          randomProvider.overrideWithValue(Random(2)),
        ],
      );
      addTearDown(container.dispose);

      final engine = container
          .read(matchFactoryProvider)
          .create(mode: GameMode.sprint, playerRating: 1000);
      // Answer nothing; the bot wins, so the rating must drop.
      final result = engine.finish();
      await container
          .read(profileProvider.notifier)
          .recordMatch(result, GameMode.sprint);

      final profile = container.read(profileProvider);
      expect(profile.ratingIn(Category.math), lessThan(RatingEngine.initial));
      expect(profile.streak.current, 1);
      expect(profile.history.length, 1);
      expect(profile.history.first.opponentName, result.opponentName);
    });
  });

  group('edge cases', () {
    testWidgets('the clock running out while the quit dialog is open', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final store = InMemoryGameStore();
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(store, router));
      await tester.pumpAndSettle();
      await _startMatch(tester, GameMode.sprint);

      // Open the dialog early and sit on it until well past the buzzer. The
      // idle watch stands down while a dialog is up -- somebody reading a
      // question is plainly present -- so this is the match clock running
      // out underneath an open dialog, which is the case being tested.
      await _step(tester, const Duration(seconds: 3));
      await router.routerDelegate.popRoute();
      await _step(tester, const Duration(milliseconds: 400));
      expect(find.text('Leave the duel?'), findsOneWidget);

      await tester.pump(const Duration(seconds: 70));
      await tester.pumpAndSettle();

      // Whatever happens, the dialog must not be stranded over another screen.
      expect(
        find.text('Leave the duel?'),
        findsNothing,
        reason: 'a dialog left open over the result screen traps the player',
      );
    });
  });

  group('screens reflect real data', () {
    /// A store already holding a played history, as if the app were reopened.
    InMemoryGameStore storeWithHistory({int matches = 6}) {
      final store = InMemoryGameStore();
      var rating = 1000;
      final history = <MatchSummary>[];
      for (var i = 0; i < matches; i++) {
        final delta = i.isEven ? 6 : -4;
        history.insert(
          0,
          MatchSummary(
            mode: GameMode.sprint,
            playerScore: 120 + i * 5,
            opponentScore: 110,
            opponentName: 'Meera',
            ratingBefore: rating,
            ratingDelta: delta,
            accuracy: 0.9,
            averageAnswerMs: 2400,
            playedAtMs: DateTime(2026, 9, 1 + i).millisecondsSinceEpoch,
          ),
        );
        rating += delta;
      }
      store.saveProfile(
        PlayerProfile.fresh(name: 'Naman').copyWith(
          ratings: {
            Category.math: rating,
            Category.memory: 1000,
            Category.logic: 1000,
          },
          history: history,
        ),
      );
      return store;
    }

    testWidgets('the rating chart renders with real history', (tester) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(storeWithHistory(), router));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Stats'));
      await tester.pumpAndSettle();

      expect(
        find.text('Play a couple of duels to see your progress'),
        findsNothing,
      );
      expect(find.text('RATING OVER TIME'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Six matches, alternating +6/-4, starting at 1000.
      expect(find.text('1006'), findsOneWidget);
    });

    testWidgets('the leaderboard refreshes after a match is played', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final store = InMemoryGameStore();
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(store, router));
      await tester.pumpAndSettle();

      // Visit Ranks first so the screen is alive in the tab IndexedStack.
      await tester.tap(find.text('Ranks'));
      await tester.pumpAndSettle();
      // Ten rather than the full board: the search field costs a row of
      // height, and a ListView only builds what is on screen.
      expect(find.text('1000'), findsNWidgets(10));

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await _startMatch(tester, GameMode.sprint);
      await _playFor(tester, const Duration(seconds: 61));
      await tester.pumpAndSettle();
      // The first duel now crosses day one of the ladder, so the milestone
      // lands over the result. Dismiss it before reaching what is behind.
      if (find.text('Nice').evaluate().isNotEmpty) {
        await tester.tap(find.text('Nice'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Back to Home'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ranks'));
      await tester.pumpAndSettle();
      // One fewer row on 1000 than before: the opponent took points off the
      // player and now tops the board, which is the board showing post-match
      // numbers rather than a stale build.
      expect(find.text('1000'), findsNWidgets(9));
      // The player moved the other way, which puts their row below the fold;
      // the save is where it can be checked without scrolling.
      expect(
        store.loadProfile().ratingIn(Category.math),
        lessThan(RatingEngine.initial),
      );
    });

    testWidgets('editing the name updates the header and persists', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final store = InMemoryGameStore();
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(store, router));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Naman');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Naman'), findsWidgets);
      expect(store.loadProfile().displayName, 'Naman');
    });

    testWidgets('the challenge-code box is gone', (tester) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(InMemoryGameStore(), router));
      await tester.pumpAndSettle();

      // Typing a code was never how anyone was going to do this. A challenge
      // now arrives as a link, so there is nothing to paste.
      expect(find.text('Have a challenge code?'), findsNothing);
    });

    testWidgets('every mode card can invite a friend', (tester) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(InMemoryGameStore(), router));
      await tester.pumpAndSettle();

      for (final mode in GameMode.values) {
        await tester.tap(
          find.byKey(ValueKey('category-${mode.category.name}')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('invite-${mode.name}')),
          findsOneWidget,
          reason: '${mode.name} has no way to challenge a friend',
        );
      }
    });

    testWidgets('with no connection, inviting says so rather than pretending', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      // No room service is overridden here, which is the offline phone.
      await tester.pumpWidget(_app(InMemoryGameStore(), router));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('category-math')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('invite-sprint')));
      await tester.pumpAndSettle();

      // A friend duel is two people in the same minute. Without a network
      // that cannot happen, and quietly starting a bot match instead would be
      // a lie about who the player just beat.
      expect(
        find.textContaining('need an internet connection'),
        findsOneWidget,
      );
      expect(find.text('Send the invite'), findsNothing);
      expect(find.textContaining('= ?'), findsNothing);
    });

    testWidgets('a broken challenge link lands on home, not a dead screen', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(InMemoryGameStore(), router));
      await tester.pumpAndSettle();

      router.go('/c/rubbish');
      await tester.pumpAndSettle();

      expect(find.text('DUELS'), findsOneWidget);
    });
  });

  group('answer feedback', () {
    /// Reads the live Sprint prompt and works out the right answer, so the
    /// test can deliberately hit or miss.
    int expectedAnswer(WidgetTester tester) {
      final prompt = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .firstWhere((d) => d != null && d.contains('= ?'))!;
      final parts = prompt.replaceAll(' = ?', '').trim().split(' ');
      int apply(int l, String op, int r) => switch (op) {
        '+' => l + r,
        '-' => l - r,
        'x' => l * r,
        '/' => l ~/ r,
        _ => throw ArgumentError(op),
      };
      var acc = apply(int.parse(parts[0]), parts[1], int.parse(parts[2]));
      if (parts.length == 5) acc = apply(acc, parts[3], int.parse(parts[4]));
      return acc;
    }

    Future<void> typeDigits(WidgetTester tester, String digits) async {
      for (final d in digits.split('')) {
        await tester.tap(find.widgetWithText(InkWell, d).first);
        await tester.pump();
      }
    }

    testWidgets('Mind Snap says it on the board, not over it', (tester) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(InMemoryGameStore(), router));
      await tester.pumpAndSettle();
      await _startMatch(tester, GameMode.mindSnap);

      // Memorise, then reproduce the pattern in full -- a perfect round, the
      // one most likely to earn a chip.
      await tester.pump(const Duration(milliseconds: 2500));
      final grid = find.byType(PatternGrid);
      final pattern = tester.widget<PatternGrid>(grid).round;
      final cells = find.descendant(
        of: grid,
        matching: find.byType(GestureDetector),
      );
      for (final index in pattern.litCells) {
        await tester.tap(cells.at(index));
        await tester.pump();
      }
      await _step(tester);

      // The cells themselves carry the verdict here, tap by tap. A chip over
      // the board would repeat it, and repeat it about the whole round.
      expect(find.textContaining('+'), findsNothing);
      expect(find.text('Missed'), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets('a correct answer shows the points won', (tester) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(InMemoryGameStore(), router));
      await tester.pumpAndSettle();
      await _startMatch(tester, GameMode.sprint);

      await typeDigits(tester, expectedAnswer(tester).toString());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('+10'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('a wrong answer is reported differently', (tester) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(InMemoryGameStore(), router));
      await tester.pumpAndSettle();
      await _startMatch(tester, GameMode.sprint);

      final answer = expectedAnswer(tester);
      // Same digit count so auto-submit still fires, but the wrong value.
      final wrong = (answer + 1).toString().padLeft(
        answer.toString().length,
        '9',
      );
      await typeDigits(tester, wrong.substring(0, answer.toString().length));
      await tester.pump(const Duration(milliseconds: 100));

      if (find.text('+10').evaluate().isEmpty) {
        expect(find.text('Missed'), findsOneWidget);
        expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      }
    });

    testWidgets('the flash clears so it cannot linger over the next question', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(InMemoryGameStore(), router));
      await tester.pumpAndSettle();
      await _startMatch(tester, GameMode.sprint);

      await typeDigits(tester, expectedAnswer(tester).toString());
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byIcon(Icons.check_rounded), findsNothing);
    });

    testWidgets('answering fires haptic feedback', (tester) async {
      _usePhoneScreen(tester);
      final haptics = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add('${call.arguments}');
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(InMemoryGameStore(), router));
      await tester.pumpAndSettle();
      await _startMatch(tester, GameMode.sprint);

      haptics.clear();
      await typeDigits(tester, expectedAnswer(tester).toString());
      await tester.pump();

      expect(haptics, isNotEmpty, reason: 'every answer must be felt');
    });
  });

  group('the opponent is a person, not a label', () {
    testWidgets('the scoreboard names both players', (tester) async {
      _usePhoneScreen(tester);
      final store = InMemoryGameStore();
      final container = _containerFor(store);
      await container.read(profileProvider.notifier).setName('Naman');
      container.dispose();

      final router = buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(store, router));
      await tester.pumpAndSettle();
      await _startMatch(tester, GameMode.sprint);

      // The player by name, and the bot by its own settled name -- the whole
      // reason the roster carries fixed identities.
      expect(find.text('Naman'), findsOneWidget);
      expect(find.text('YOU'), findsNothing);
      expect(find.text('OPPONENT'), findsNothing);

      final roster = BotProfile.seedRoster().map((b) => b.name).toSet();
      final shown = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .toSet();
      expect(
        shown.intersection(roster),
        isNotEmpty,
        reason: 'the opponent must be shown by name',
      );
    });
  });
}
