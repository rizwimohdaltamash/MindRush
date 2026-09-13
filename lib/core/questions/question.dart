/// One thing the player is asked to do during a match.
///
/// The four modes ask genuinely different things -- type a number, tap the
/// larger of two, repeat a flashed pattern, pick the odd one out -- so this is
/// a sealed hierarchy rather than one struct with unused fields. Exhaustive
/// switches in the UI then guarantee every mode gets a screen.
sealed class Question {
  const Question();

  /// Stable text form, used for deterministic tests and bug reports.
  String get signature;
}

/// Sprint Duels: real arithmetic, answered on a keypad.
final class NumericQuestion extends Question {
  const NumericQuestion({required this.prompt, required this.answer});

  final String prompt;
  final int answer;

  bool isCorrect(int given) => given == answer;

  @override
  String get signature => 'num($prompt=$answer)';
}

/// Fastest Fingers and Ability Duels: pick one option.
final class ChoiceQuestion extends Question {
  const ChoiceQuestion({
    required this.prompt,
    required this.options,
    required this.correctIndex,
  });

  final String prompt;
  final List<String> options;
  final int correctIndex;

  String get correctOption => options[correctIndex];

  bool isCorrect(int index) => index == correctIndex;

  @override
  String get signature => 'choice($prompt|${options.join(",")}|$correctIndex)';
}

/// Mind Snap: a grid flashes, then the player repeats it.
///
/// The number of lit cells grows as the match goes on -- see
/// [mindSnapCellsFor] -- so a run that starts comfortable ends genuinely
/// hard. The grid grows with it to keep the density roughly constant.
final class PatternRound extends Question {
  const PatternRound({
    required this.gridSize,
    required this.litCells,
    required this.flashMs,
  });

  final int gridSize;
  final List<int> litCells;
  final int flashMs;

  int get cellCount => gridSize * gridSize;

  /// How many of the lit cells the player correctly reproduced. Extra taps on
  /// dark cells do not count against them here; the miss count drives scoring.
  int correctlyRecalled(Set<int> tapped) =>
      litCells.where(tapped.contains).length;

  @override
  String get signature => 'pattern($gridSize:${litCells.join("-")})';
}

/// How many cells are lit in round [roundIndex] (zero-based).
///
/// Six for the first six rounds, eight for the next two, twelve from then on.
/// The step up is what makes a sixty-second run escalate rather than settle
/// into a rhythm -- and because [Scoring.roundPoints] works in proportions,
/// a bigger round is still worth the same ten points.
/// The board size for round [roundIndex], zero-based.
///
/// Four rounds on a 4x4, five on a 5x5, then 6x6 for the rest of the minute.
/// The board is the thing the player actually sees getting harder, so the
/// steps are defined here and the pattern size follows from them rather than
/// the other way round.
int mindSnapGridFor(int roundIndex) {
  if (roundIndex < 4) return 4;
  if (roundIndex < 9) return 5;
  return 6;
}

/// How many cells light up in round [roundIndex].
///
/// Tied to the board size so roughly a third of it is ever lit; holding the
/// count fixed while the board grew would make later rounds easier, not
/// harder.
int mindSnapCellsFor(int roundIndex) => switch (mindSnapGridFor(roundIndex)) {
  4 => 6,
  5 => 8,
  _ => 12,
};

/// The opening round size, used where a representative value is needed.
const int kMindSnapCells = 6;

/// The beat between finishing one pattern and the next one flashing.
///
/// Without it the next pattern appeared on the same frame as the final tap,
/// which read as the board being snatched away before you had seen how you
/// did -- and, worse, before the finger that made the last tap had even come
/// off the glass. A full second is long enough to lift a hand, look at what
/// was there against what you tapped, and be ready for the next one.
///
/// It is spent inside the same sixty seconds, so the bot pays it too -- see
/// [BotEngine], which adds it to every round it simulates.
const int kMindSnapReviewMs = 300;

/// How long the answered cells take to shrink away afterwards.
///
/// The beat above ends with a hard cut: one frame the solved board, the next
/// frame a new pattern. Spending this long clearing the board is what turns
/// that into a handover -- the answer leaves, and only then does the next
/// round arrive. It is charged to the bot along with the beat, so the minute
/// holds the same number of rounds for both sides.
const int kMindSnapVanishMs = 250;
