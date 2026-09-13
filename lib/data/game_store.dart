import 'package:hive_ce_flutter/hive_flutter.dart';

import '../core/bots/bot_profile.dart';
import 'player_profile.dart';

/// On-device storage for the profile and the bot roster.
///
/// This is the source of truth. The app never needs a network to start, play,
/// rate a match, or show stats -- which matters for a demo, where venue wifi
/// is the one failure you cannot talk your way out of.
abstract class GameStore {
  PlayerProfile loadProfile();
  Future<void> saveProfile(PlayerProfile profile);

  List<BotProfile> loadRoster();
  Future<void> saveRoster(List<BotProfile> roster);

  Future<void> clear();

  static Future<GameStore> open() => HiveGameStore.open();
}

/// The real store.
///
/// Everything is written as plain JSON maps rather than through Hive type
/// adapters, so there is no code generation step and a schema change is just
/// a defaulted field in `fromJson`.
class HiveGameStore implements GameStore {
  HiveGameStore._(this._profileBox, this._botBox);

  static const String _profileBoxName = 'profile';
  static const String _botBoxName = 'bots';
  static const String _profileKey = 'me';

  final Box<dynamic> _profileBox;
  final Box<dynamic> _botBox;

  static Future<HiveGameStore> open() async {
    await Hive.initFlutter();
    final profileBox = await Hive.openBox<dynamic>(_profileBoxName);
    final botBox = await Hive.openBox<dynamic>(_botBoxName);
    return HiveGameStore._(profileBox, botBox);
  }

  @override
  PlayerProfile loadProfile() {
    final raw = _profileBox.get(_profileKey);
    if (raw is Map) return PlayerProfile.fromJson(raw);
    return PlayerProfile.fresh();
  }

  @override
  Future<void> saveProfile(PlayerProfile profile) =>
      _profileBox.put(_profileKey, profile.toJson());

  /// The bot roster with its accumulated ratings. Any bot missing from
  /// storage is seeded fresh, so adding a tier in a later build just works.
  @override
  List<BotProfile> loadRoster() => [
    for (final bot in BotProfile.seedRoster())
      if (_botBox.get(bot.id) case final Map raw)
        BotProfile.fromJson(raw) ?? bot
      else
        bot,
  ];

  @override
  Future<void> saveRoster(List<BotProfile> roster) =>
      _botBox.putAll({for (final bot in roster) bot.id: bot.toJson()});

  @override
  Future<void> clear() async {
    await _profileBox.clear();
    await _botBox.clear();
  }
}

/// Store for tests and previews. Round-trips through the same JSON as the
/// real one, so a serialisation bug fails here too rather than only on device.
class InMemoryGameStore implements GameStore {
  Map<dynamic, dynamic>? _profile;
  final Map<String, Map<dynamic, dynamic>> _bots = {};

  @override
  PlayerProfile loadProfile() {
    final raw = _profile;
    return raw == null ? PlayerProfile.fresh() : PlayerProfile.fromJson(raw);
  }

  @override
  Future<void> saveProfile(PlayerProfile profile) async {
    _profile = profile.toJson();
  }

  @override
  List<BotProfile> loadRoster() => [
    for (final bot in BotProfile.seedRoster())
      if (_bots[bot.id] case final raw?)
        BotProfile.fromJson(raw) ?? bot
      else
        bot,
  ];

  @override
  Future<void> saveRoster(List<BotProfile> roster) async {
    for (final bot in roster) {
      _bots[bot.id] = bot.toJson();
    }
  }

  @override
  Future<void> clear() async {
    _profile = null;
    _bots.clear();
  }
}
