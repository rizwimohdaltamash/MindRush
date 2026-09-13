import '../core/models/game_mode.dart';
import '../core/rating/rating_engine.dart';
import '../core/rating/streak.dart';
import '../core/rating/streak_rewards.dart';
import 'match_summary.dart';

/// Everything the app knows about the person playing.
///
/// Immutable: every change produces a new profile, which keeps the Riverpod
/// notifier honest about when the UI needs to rebuild.
class PlayerProfile {
  const PlayerProfile({
    required this.displayName,
    required this.avatarId,
    required this.ratings,
    required this.streak,
    required this.history,
    this.photo,
    this.remindersEnabled = true,
    this.askedAboutReminders = false,
    this.updatedAtMs = 0,
  });

  factory PlayerProfile.fresh({String name = '', int avatarId = 0}) =>
      PlayerProfile(
        displayName: name,
        avatarId: avatarId,
        ratings: {for (final c in Category.values) c: RatingEngine.initial},
        streak: const StreakState(),
        history: const [],
      );

  final String displayName;
  final int avatarId;
  final Map<Category, int> ratings;
  final StreakState streak;

  /// Most recent first, capped at [historyLimit].
  final List<MatchSummary> history;

  /// A small square PNG, base64 encoded: the player's own photograph, used
  /// in place of their chosen character.
  ///
  /// Kept inline rather than in a file or a storage bucket. At this size it
  /// is a few tens of kilobytes -- small enough to sit on the player's row
  /// and travel with it, which is what lets a friend see a real face on the
  /// leaderboard without the app needing file hosting at all.
  final String? photo;

  /// Whether the daily reminders are wanted. On unless the player says
  /// otherwise: a streak game that never reminds you is a streak you lose.
  final bool remindersEnabled;

  /// Whether the notification prompt has already been shown once.
  final bool askedAboutReminders;

  /// When this profile last changed, in epoch milliseconds.
  ///
  /// The tiebreaker when the same account has been played on two devices:
  /// without it a sync can only guess which copy is newer, and guessing
  /// eventually eats somebody's progress.
  final int updatedAtMs;

  static const int historyLimit = 100;

  int ratingIn(Category c) => ratings[c] ?? RatingEngine.initial;

  /// True until the player has told us what to call them. Having a name is the
  /// only thing the app needs before it can be played -- no account, no
  /// network.
  bool get needsOnboarding => displayName.trim().isEmpty;

  /// XP earned from streak milestones.
  ///
  /// Derived from [StreakState.best] rather than stored, so it cannot drift
  /// out of step with the streak that earned it.
  int get streakXp => StreakRewards.xpFor(streak.best);

  /// Shown on the profile header. Rises one level per 100 rating points
  /// gained across all three categories.
  int get level {
    final total = Category.values.fold(0, (s, c) => s + ratingIn(c));
    final gained = total - RatingEngine.initial * Category.values.length;
    return 1 + (gained / 100).floor().clamp(0, 999);
  }

  List<MatchSummary> historyFor(Category c) =>
      history.where((m) => m.category == c).toList();

  double winRate(Category c) {
    final games = historyFor(c);
    if (games.isEmpty) return 0;
    return games.where((m) => m.won).length / games.length;
  }

  PlayerProfile copyWith({
    String? displayName,
    int? avatarId,
    Map<Category, int>? ratings,
    StreakState? streak,
    List<MatchSummary>? history,
    String? photo,

    /// Taking a photo off cannot be said by passing null, which means "leave
    /// it alone" everywhere else in this method.
    bool clearPhoto = false,
    bool? remindersEnabled,
    bool? askedAboutReminders,
    int? updatedAtMs,
  }) => PlayerProfile(
    displayName: displayName ?? this.displayName,
    avatarId: avatarId ?? this.avatarId,
    ratings: ratings ?? this.ratings,
    streak: streak ?? this.streak,
    history: history ?? this.history,
    photo: clearPhoto ? null : photo ?? this.photo,
    remindersEnabled: remindersEnabled ?? this.remindersEnabled,
    askedAboutReminders: askedAboutReminders ?? this.askedAboutReminders,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );

  /// Stamps the profile as changed now. Called by the store on every save.
  PlayerProfile touched(DateTime when) =>
      copyWith(updatedAtMs: when.millisecondsSinceEpoch);

  /// Applies a finished match: new rating for that category, the streak
  /// advanced, and the summary pushed onto the front of the history.
  PlayerProfile withMatch(MatchSummary summary, DateTime when) {
    final category = summary.category;
    return copyWith(
      ratings: {
        ...ratings,
        category: RatingEngine.apply(ratingIn(category), summary.ratingDelta),
      },
      streak: StreakCalculator.register(streak, when),
      history: [summary, ...history].take(historyLimit).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'displayName': displayName,
    'avatarId': avatarId,
    'ratings': {for (final e in ratings.entries) e.key.name: e.value},
    'streak': {
      'current': streak.current,
      'best': streak.best,
      'lastPlayedDay': streak.lastPlayedDay,
    },
    'history': history.map((m) => m.toJson()).toList(),
    'photo': photo,
    'remindersEnabled': remindersEnabled,
    'askedAboutReminders': askedAboutReminders,
    'updatedAtMs': updatedAtMs,
  };

  static PlayerProfile fromJson(Map<dynamic, dynamic> json) {
    final rawRatings = json['ratings'] as Map<dynamic, dynamic>? ?? const {};
    final rawStreak = json['streak'] as Map<dynamic, dynamic>? ?? const {};
    final rawHistory = json['history'] as List<dynamic>? ?? const [];

    return PlayerProfile(
      displayName: json['displayName'] as String? ?? '',
      avatarId: (json['avatarId'] as num?)?.toInt() ?? 0,
      ratings: {
        for (final c in Category.values)
          c: (rawRatings[c.name] as num?)?.toInt() ?? RatingEngine.initial,
      },
      streak: StreakState(
        current: (rawStreak['current'] as num?)?.toInt() ?? 0,
        best: (rawStreak['best'] as num?)?.toInt() ?? 0,
        lastPlayedDay: (rawStreak['lastPlayedDay'] as num?)?.toInt(),
      ),
      history: [
        for (final row in rawHistory)
          if (row is Map) ?MatchSummary.fromJson(row),
      ],
      photo: json['photo'] as String?,
      // Absent on every save written before the toggle existed, and those
      // players had reminders.
      remindersEnabled: json['remindersEnabled'] as bool? ?? true,
      askedAboutReminders: json['askedAboutReminders'] as bool? ?? false,
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}
