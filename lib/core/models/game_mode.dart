/// The three skill categories. Each carries its own independent rating,
/// so a strong-at-math / weak-at-logic player is matched differently per
/// category.
enum Category { math, memory, logic }

/// A playable duel format.
///
/// [baselineMs] is how long a *typical* player takes per question in this
/// mode. Bot speed is expressed as a multiplier of this baseline rather than
/// an absolute time, so one bot ladder works across every mode. Without it a
/// bot tuned for Sprint (~2.6s per question) would look superhuman in
/// Fastest Fingers, where questions take under a second.
enum GameMode {
  /// Real arithmetic under time pressure. Keypad entry.
  sprint(Category.math, baselineMs: 2600, label: 'Sprint Duels'),

  /// Pure reflex. Trivial comparisons ("which is larger?"), tap to answer.
  /// Roughly 70 questions a match versus Sprint's ~23.
  fastestFingers(Category.math, baselineMs: 850, label: 'Fastest Fingers'),

  /// Pattern recall. Round-based: the grid flashes, then you repeat it.
  /// [baselineMs] covers one whole round, not one tap.
  mindSnap(Category.memory, baselineMs: 4200, label: 'Mind Snap'),

  /// Sequences and odd-one-out reasoning.
  ability(Category.logic, baselineMs: 3000, label: 'Ability Duels');

  const GameMode(
    this.category, {
    required this.baselineMs,
    required this.label,
  });

  final Category category;
  final int baselineMs;
  final String label;

  /// Mind Snap scores a whole round at once; the others score per question.
  bool get isRoundBased => this == GameMode.mindSnap;
}

/// Every duel is exactly one minute.
const int kMatchDurationMs = 60000;
