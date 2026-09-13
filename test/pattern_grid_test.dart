import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_rush/core/questions/question.dart';
import 'package:mind_rush/ui/theme.dart';
import 'package:mind_rush/ui/widgets/pattern_grid.dart';

/// Reads back the fill colour of the cell at [index].
Color? _cellColour(WidgetTester tester, int index) {
  final container = tester
      .widgetList<AnimatedContainer>(
        find.descendant(
          of: find.byType(PatternGrid),
          matching: find.byType(AnimatedContainer),
        ),
      )
      .elementAt(index);
  return (container.decoration as BoxDecoration?)?.color;
}

void main() {
  const round = PatternRound(
    gridSize: 4,
    litCells: [0, 1, 2, 3, 4, 5],
    flashMs: 1800,
  );

  Widget wrap({required bool revealed, required Set<int> tapped}) =>
      MaterialApp(
        theme: buildTheme(),
        // Constrained the way the duel screen constrains it; unbounded, the
        // square grid overflows the default test surface.
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: PatternGrid(
                round: round,
                revealed: revealed,
                tapped: tapped,
                accent: AppColors.memory,
                onTap: (_) {},
              ),
            ),
          ),
        ),
      );

  testWidgets('while flashing, the lit cells glow and the rest stay dark', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(revealed: true, tapped: const {}));
    await tester.pumpAndSettle();

    expect(_cellColour(tester, 0), isNot(AppColors.surfaceHigh));
    expect(_cellColour(tester, 15), AppColors.surfaceHigh);
  });

  testWidgets('a tap on a cell that was never lit turns red', (tester) async {
    // Cell 9 is not in litCells.
    await tester.pumpWidget(wrap(revealed: false, tapped: const {9}));
    await tester.pumpAndSettle();

    final wrong = _cellColour(tester, 9)!;
    expect(wrong.r, AppColors.loss.r);
    expect(wrong.g, AppColors.loss.g);
    expect(wrong.b, AppColors.loss.b);
  });

  testWidgets('a correct tap uses the mode colour, not red', (tester) async {
    // Cell 2 is in litCells.
    await tester.pumpWidget(wrap(revealed: false, tapped: const {2}));
    await tester.pumpAndSettle();

    final right = _cellColour(tester, 2)!;
    expect(right.r, AppColors.memory.r);
    expect(right.b, AppColors.memory.b);
    expect(
      right.r,
      isNot(AppColors.loss.r),
      reason:
          'showing every tap the same colour hid the one thing the '
          'player wants to know',
    );
  });

  testWidgets('right and wrong taps are visibly different in one round', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(revealed: false, tapped: const {2, 9}));
    await tester.pumpAndSettle();

    expect(_cellColour(tester, 2), isNot(_cellColour(tester, 9)));
  });

  group('how big the board gets', () {
    /// The rendered board, given a screen [across] px wide.
    Future<Size> boardOn(WidgetTester tester, int cells, double across) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: across,
                child: PatternGrid(
                  round: PatternRound(
                    gridSize: cells,
                    litCells: const [0, 1],
                    flashMs: 1800,
                  ),
                  revealed: true,
                  tapped: const {},
                  accent: AppColors.memory,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getSize(
        find.descendant(
          of: find.byType(PatternGrid),
          matching: find.byType(GridView),
        ),
      );
    }

    testWidgets('a cell stays a cell as the board grows', (tester) async {
      // The point of the cap. Filling the width instead would draw a
      // four-by-four with cells half again the size of a six-by-six's, so the
      // same game would feel like a different one round to round.
      final small = await boardOn(tester, 4, 360);
      final large = await boardOn(tester, 6, 360);

      expect(small.width, PatternGrid.sideFor(4, 360));
      expect(large.width, PatternGrid.sideFor(6, 360));
      expect(
        PatternGrid.cellFor(4, 360),
        PatternGrid.cellFor(6, 360),
        reason: 'both should be drawing a full-sized cell on this screen',
      );
    });

    testWidgets('and shrinks rather than overflowing a narrow phone', (
      tester,
    ) async {
      // 260 is narrower than six full cells plus their gaps, so the cap stops
      // applying and the board fits itself to the room it has.
      final board = await boardOn(tester, 6, 260);

      expect(board.width, lessThanOrEqualTo(260));
      expect(PatternGrid.cellFor(6, 260), lessThan(PatternGrid.maxCell));
    });
  });

  testWidgets('nothing is revealed by an untapped cell mid-round', (
    tester,
  ) async {
    // While answering, a lit-but-untapped cell must not give itself away.
    await tester.pumpWidget(wrap(revealed: false, tapped: const {}));
    await tester.pumpAndSettle();

    for (var i = 0; i < round.cellCount; i++) {
      expect(
        _cellColour(tester, i),
        AppColors.surfaceHigh,
        reason: 'cell $i leaked the answer',
      );
    }
  });
}
