import 'dart:math';

import '../bots/bot_engine.dart';
import '../bots/bot_profile.dart';
import '../bots/opponent_picker.dart';
import '../challenge/friend_duel.dart';
import '../models/game_mode.dart';
import '../questions/question.dart';
import '../questions/question_deck.dart';
import '../rating/rating_engine.dart';
import '../scoring/scoring.dart';
import 'match_result.dart';
import 'opponent_feed.dart';

/// Drives one 60-second duel.
///
/// The engine holds no timer of its own. The UI advances it with
/// [advanceTo] from a Flutter ticker, and tests advance it directly, so match
/// logic is verifiable without waiting a real minute.
class MatchEngine {
  MatchEngine({
    required this.deck,
    required this.opponentFeed,
    this.opponent,
    required this.opponentName,
    required this.opponentAvatarId,
    required this.playerRating,
    this.opponentUid,
    this.opponentPhoto,
  });

  final QuestionDeck deck;
  final OpponentFeed opponentFeed;

  /// Null in a friend challenge: the opponent is a person on another phone,
  /// so there is no local ladder entry to update when the match settles.
  final BotProfile? opponent;
  final String opponentName;
  final int opponentAvatarId;

  /// Set only for a live duel: who, on Firestore, the other side is. It is
  /// carried through to the result so a rematch can be aimed at them.
  final String? opponentUid;
  final String? opponentPhoto;
  final int playerRating;

  GameMode get mode => deck.mode;

  final List<AnswerRecord> _answers = [];
  int _elapsedMs = 0;
  int _questionStartMs = 0;
  int _index = 0;
  int _score = 0;
  MatchResult? _result;

  /// The question on screen right now.
  Question get current => deck.at(_index);

  int get questionIndex => _index;

  int get elapsedMs => _elapsedMs;

  int get remainingMs {
    final left = kMatchDurationMs - _elapsedMs;
    return left < 0 ? 0 : left;
  }

  int get playerScore => _score;

  /// The opponent's score as it stands right now, so the scoreboard ticks up
  /// mid-match the way it would against a real person.
  int get opponentScore => opponentFeed.scoreAt(_elapsedMs);

  bool get isOver => remainingMs == 0;

  List<AnswerRecord> get answers => List.unmodifiable(_answers);

  /// Moves the clock forward. [elapsedMs] is measured from the start of the
  /// match; going backwards is ignored so a jittery ticker cannot rewind play.
  void advanceTo(int elapsedMs) {
    if (elapsedMs > _elapsedMs) _elapsedMs = elapsedMs;
  }

  /// Answers a [NumericQuestion] (Sprint Duels).
  void submitNumber(int value, {required int atMs}) {
    final q = current;
    assert(q is NumericQuestion, 'submitNumber on a ${q.runtimeType}');
    _record(
      atMs: atMs,
      points: (q as NumericQuestion).isCorrect(value) ? Scoring.perfect : 0,
    );
  }

  /// Answers a [ChoiceQuestion] (Fastest Fingers, Ability Duels).
  void submitOption(int optionIndex, {required int atMs}) {
    final q = current;
    assert(q is ChoiceQuestion, 'submitOption on a ${q.runtimeType}');
    _record(
      atMs: atMs,
      points: (q as ChoiceQuestion).isCorrect(optionIndex)
          ? Scoring.perfect
          : 0,
    );
  }

  /// Answers a [PatternRound] (Mind Snap), where partial recall still scores.
  void submitPattern(Set<int> tappedCells, {required int atMs}) {
    final q = current;
    assert(q is PatternRound, 'submitPattern on a ${q.runtimeType}');
    final round = q as PatternRound;
    _record(
      atMs: atMs,
      points: Scoring.roundPoints(
        total: round.litCells.length,
        correct: round.correctlyRecalled(tappedCells),
      ),
    );
  }

  void _record({required int atMs, required int points}) {
    advanceTo(atMs);
    // An answer that lands after the buzzer does not count. The UI stops
    // accepting input at zero, but a tap already in flight can still arrive.
    if (atMs > kMatchDurationMs) return;

    _answers.add(
      AnswerRecord(
        questionIndex: _index,
        atMs: atMs,
        durationMs: atMs - _questionStartMs,
        points: points,
      ),
    );
    _score += points;
    _index++;
    _questionStartMs = atMs;
  }

  /// The match one side stopped playing.
  ///
  /// No rating is applied to either player: the one who walked away has not
  /// been beaten by anybody, and whoever was still answering has not beaten
  /// anybody -- they were racing a phone that had been put down.
  ///
  /// The scores are the real ones as they stood when it was called off, not a
  /// pair of noughts. Somebody who had worked their way to twenty-seven
  /// points deserves to see twenty-seven; it is the rating, not the minute,
  /// that did not happen.
  MatchResult abandon({bool byPlayer = true}) {
    final existing = _result;
    if (existing != null) return existing;

    return _result = MatchResult(
      playerScore: _score,
      opponentScore: opponentScore,
      ratingBefore: playerRating,
      ratingDelta: 0,
      answers: List.unmodifiable(_answers),
      opponentFeed: opponentFeed,
      opponentName: opponentName,
      opponentAvatarId: opponentAvatarId,
      opponentUid: opponentUid,
      opponentPhoto: opponentPhoto,
      shareCode: deck.shareCode,
      abandoned: true,
      abandonedByYou: byPlayer,
    );
  }

  /// Settles the match: computes the rating change, applies the zero-sum
  /// update to the bot, and returns the result. Calling it twice returns the
  /// same result rather than rating the match again.
  MatchResult finish() {
    final existing = _result;
    if (existing != null) return existing;

    _elapsedMs = kMatchDurationMs;
    final opponentScore = opponentFeed.totalScore;
    final playerTimeMs = _answers.isEmpty ? 0 : _answers.last.atMs;

    final delta = RatingEngine.delta(
      myScore: _score,
      oppScore: opponentScore,
      myTimeMs: playerTimeMs,
      oppTimeMs: opponentFeed.totalTimeMs,
    );

    opponent?.applyResult(mode.category, delta);

    return _result = MatchResult(
      playerScore: _score,
      opponentScore: opponentScore,
      ratingBefore: playerRating,
      ratingDelta: delta,
      answers: List.unmodifiable(_answers),
      opponentFeed: opponentFeed,
      opponentName: opponentName,
      opponentAvatarId: opponentAvatarId,
      opponentUid: opponentUid,
      opponentPhoto: opponentPhoto,
      shareCode: deck.shareCode,
    );
  }
}

/// Assembles a match: picks the opponent, rolls its performance, and builds
/// the question deck at the player's difficulty.
///
/// Kept separate from [MatchEngine] so the engine stays a pure state machine
/// with nothing random in it.
class MatchFactory {
  const MatchFactory({required this.roster, required this.random});

  final List<BotProfile> roster;
  final Random random;

  MatchEngine create({
    required GameMode mode,
    required int playerRating,
    int? seed,
  }) {
    final opponent = OpponentPicker.pick(
      roster: roster,
      category: mode.category,
      playerRating: playerRating,
      rng: random,
    );

    return MatchEngine(
      deck: QuestionDeck.forRating(
        seed: seed ?? QuestionDeck.newSeed(random),
        mode: mode,
        rating: playerRating,
      ),
      opponentFeed: BotEngine.simulate(mode, opponent.tier, random),
      opponent: opponent,
      opponentName: opponent.name,
      opponentAvatarId: opponent.avatarId,
      playerRating: playerRating,
    );
  }

  /// A live match against the other person in a room.
  ///
  /// The deck comes from the room, never from [playerRating]: both sides have
  /// to answer the same questions or the two scores are not comparable, and
  /// two friends are rarely the same rating.
  MatchEngine createFriendDuel({
    required FriendDuel friend,
    required int playerRating,
  }) => MatchEngine(
    deck: friend.room.deck,
    opponentFeed: friend.feed,
    opponentName: friend.opponent?.name ?? 'A friend',
    opponentAvatarId: friend.opponent?.avatarId ?? 0,
    opponentUid: friend.opponent?.uid,
    opponentPhoto: friend.opponent?.photo,
    playerRating: playerRating,
  );
}
