/// One rung of the bot ladder.
///
/// [speedFactor] multiplies the mode's `baselineMs`, so the same ten tiers
/// work in every mode: below 1.0 is faster than a typical player, above 1.0
/// is slower.
///
/// [formVariance] is the reason bots read as human. A bot that scores 154,
/// 154, 156 every match is obviously a machine no matter what it is called;
/// the giveaway is consistency, not the name. Roughly 22% match-to-match
/// swing makes a bot look like a person having a good or bad day, and it lets
/// even the bottom tier occasionally beat a weak player.
enum BotTier {
  t1('Novice', accuracy: 0.80, speedFactor: 1.17),
  t2('Casual', accuracy: 0.83, speedFactor: 1.11),
  t3('Steady', accuracy: 0.86, speedFactor: 1.05),
  t4('Sharp', accuracy: 0.88, speedFactor: 1.00),
  t5('Quick', accuracy: 0.90, speedFactor: 0.95),
  t6('Keen', accuracy: 0.92, speedFactor: 0.90),
  t7('Expert', accuracy: 0.94, speedFactor: 0.85),
  t8('Elite', accuracy: 0.96, speedFactor: 0.79),
  t9('Master', accuracy: 0.98, speedFactor: 0.73),
  t10('Prodigy', accuracy: 1.00, speedFactor: 0.67);

  const BotTier(
    this.codename, {
    required this.accuracy,
    required this.speedFactor,
  });

  /// Internal only -- never shown to a player.
  final String codename;
  final double accuracy;
  final double speedFactor;

  static const double formVariance = 0.22;
}
