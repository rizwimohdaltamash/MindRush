// ignore_for_file: avoid_print -- dev-only content preview, not shipped.
import 'package:mind_rush/core/models/game_mode.dart';
import 'package:mind_rush/core/questions/difficulty.dart';
import 'package:mind_rush/core/questions/question.dart';
import 'package:mind_rush/core/questions/question_deck.dart';

String render(Question q) => switch (q) {
      NumericQuestion() => '${q.prompt.padRight(20)} -> ${q.answer}',
      ChoiceQuestion() =>
        '${q.prompt.padRight(28)} ${q.options.join(" | ").padRight(34)} -> ${q.correctOption}',
      PatternRound() =>
        '${q.gridSize}x${q.gridSize} grid, flash ${q.flashMs}ms, lit ${q.litCells}',
    };

void main() {
  for (final (mode, diff) in [
    (GameMode.sprint, Difficulty.easy),
    (GameMode.sprint, Difficulty.brutal),
    (GameMode.fastestFingers, Difficulty.brutal),
    (GameMode.ability, Difficulty.light),
    (GameMode.ability, Difficulty.brutal),
    (GameMode.mindSnap, Difficulty.hard),
  ]) {
    final deck = QuestionDeck(seed: 2024, mode: mode, difficulty: diff);
    print('\n${mode.label} -- ${diff.name}   [${deck.shareCode}]');
    for (var i = 0; i < 6; i++) {
      print('   ${render(deck.at(i))}');
    }
  }
}
