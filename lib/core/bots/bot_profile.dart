import '../models/game_mode.dart';
import '../rating/rating_engine.dart';
import 'bot_tier.dart';

/// A bot opponent.
///
/// Ratings are real and persistent: when a bot wins it gains exactly what the
/// player lost, so the system is zero-sum and no rating is created or
/// destroyed. Every bot starts at 1000 like every player and drifts to its
/// true level over the first few dozen matches, which means the ladder
/// calibrates itself instead of needing hand-tuned rating estimates.
class BotProfile {
  BotProfile({
    required this.id,
    required this.tier,
    required this.name,
    required this.avatarId,
    Map<Category, int>? ratings,
  }) : ratings =
           ratings ??
           {for (final c in Category.values) c: RatingEngine.initial};

  final String id;
  final BotTier tier;

  /// Fixed for the life of the bot, not drawn per match.
  ///
  /// A rotating name would make every duel feel like a new person, but the
  /// leaderboard would then show ten strangers the player has never faced.
  /// Beating Aryan on Tuesday and seeing Aryan two rows above you on
  /// Wednesday is what makes the roster read as a real player base.
  final String name;
  final int avatarId;

  /// One rating per category, exactly like a human profile.
  final Map<Category, int> ratings;

  int ratingIn(Category c) => ratings[c] ?? RatingEngine.initial;

  void applyResult(Category c, int playerDelta) {
    // Zero-sum: the bot moves opposite to the player.
    ratings[c] = RatingEngine.apply(ratingIn(c), -playerDelta);
  }

  /// The ten bots the app ships with, each with a settled identity.
  static List<BotProfile> seedRoster() => [
    for (final (index, tier) in BotTier.values.indexed)
      BotProfile(
        id: 'bot_${tier.name}',
        tier: tier,
        name: BotIdentities.names[index % BotIdentities.names.length],
        avatarId: index % BotIdentities.avatarCount,
      ),
  ];
  //Packages the bot into a text format so it can be saved to the phone's
  //hard drive.
  Map<String, dynamic> toJson() => {
    'id': id,
    'tier': tier.name,
    'name': name,
    'avatarId': avatarId,
    'ratings': {for (final e in ratings.entries) e.key.name: e.value},
  };

  /// Null when the stored tier no longer exists, so a roster change between
  /// versions drops the stale bot instead of crashing the app.
  static BotProfile? fromJson(Map<dynamic, dynamic> json) {
    final tier = BotTier.values
        .where((t) => t.name == json['tier'])
        .firstOrNull;
    final id = json['id'] as String?;
    if (tier == null || id == null) return null;
    final raw = json['ratings'] as Map<dynamic, dynamic>? ?? const {};
    return BotProfile(
      id: id,
      tier: tier,
      name: json['name'] as String? ?? BotIdentities.names.first,
      avatarId: (json['avatarId'] as num?)?.toInt() ?? 0,
      ratings: {
        for (final c in Category.values)
          c: (raw[c.name] as num?)?.toInt() ?? RatingEngine.initial,
      },
    );
  }
}

/// Display identities, kept separate from the ten rated bot slots.
///
/// With only ten bots, ten fixed names would mean the same handful of
/// opponents recurring immediately, which is the fastest way to break the
/// illusion. Drawing a name and avatar per match from a wider pool costs
/// nothing and removes the tell.
abstract final class BotIdentities {
  static const List<String> names = [
    'Aryan',
    'Meera',
    'Rohan',
    'Ishita',
    'Kabir',
    'Ananya',
    'Vivaan',
    'Sana',
    'Arjun',
    'Diya',
    'Reyansh',
    'Aditi',
    'Karan',
    'Nisha',
    'Dev',
    'Tara',
    'Yash',
    'Riya',
    'Manav',
    'Pooja',
    'Aman',
    'Simran',
    'Nikhil',
    'Kavya',
    'Rahul',
    'Sneha',
    'Varun',
    'Priya',
    'Siddharth',
    'Neha',
    'Aditya',
    'Zara',
    'Harsh',
    'Lekha',
    'Om',
    'Naina',
    'Veer',
    'Anika',
    'Raghav',
    'Mira',
  ];

  static const int avatarCount = 24;
}
