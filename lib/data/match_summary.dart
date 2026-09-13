import '../core/match/match_result.dart';
import '../core/models/game_mode.dart';

/// A finished match, trimmed to what the stats and profile screens plot.
///
/// The full [MatchResult] holds every answer and the whole bot run, which is
/// far more than is worth keeping on disk for a hundred matches.
class MatchSummary {
  const MatchSummary({
    required this.mode,
    required this.playerScore,
    required this.opponentScore,
    required this.opponentName,
    required this.ratingBefore,
    required this.ratingDelta,
    required this.accuracy,
    required this.averageAnswerMs,
    required this.playedAtMs,
  });

  factory MatchSummary.from(MatchResult result, GameMode mode, DateTime when) =>
      MatchSummary(
        mode: mode,
        playerScore: result.playerScore,
        opponentScore: result.opponentScore,
        opponentName: result.opponentName,
        ratingBefore: result.ratingBefore,
        ratingDelta: result.ratingDelta,
        accuracy: result.accuracy,
        averageAnswerMs: result.averageAnswerMs,
        playedAtMs: when.millisecondsSinceEpoch,
      );

  final GameMode mode;
  final int playerScore;
  final int opponentScore;
  final String opponentName;
  final int ratingBefore;
  final int ratingDelta;
  final double accuracy;
  final int averageAnswerMs;
  final int playedAtMs;

  Category get category => mode.category;

  int get ratingAfter => ratingBefore + ratingDelta;

  bool get won => ratingDelta > 0;

  DateTime get playedAt => DateTime.fromMillisecondsSinceEpoch(playedAtMs);

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'playerScore': playerScore,
    'opponentScore': opponentScore,
    'opponentName': opponentName,
    'ratingBefore': ratingBefore,
    'ratingDelta': ratingDelta,
    'accuracy': accuracy,
    'averageAnswerMs': averageAnswerMs,
    'playedAtMs': playedAtMs,
  };

  /// Returns null for a row this build cannot read -- an unknown mode name
  /// from an older or newer version -- so one bad entry cannot break startup.
  static MatchSummary? fromJson(Map<dynamic, dynamic> json) {
    final mode = GameMode.values
        .where((m) => m.name == json['mode'])
        .firstOrNull;
    if (mode == null) return null;
    return MatchSummary(
      mode: mode,
      playerScore: (json['playerScore'] as num?)?.toInt() ?? 0,
      opponentScore: (json['opponentScore'] as num?)?.toInt() ?? 0,
      opponentName: json['opponentName'] as String? ?? 'Opponent',
      ratingBefore: (json['ratingBefore'] as num?)?.toInt() ?? 0,
      ratingDelta: (json['ratingDelta'] as num?)?.toInt() ?? 0,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0,
      averageAnswerMs: (json['averageAnswerMs'] as num?)?.toInt() ?? 0,
      playedAtMs: (json['playedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}
