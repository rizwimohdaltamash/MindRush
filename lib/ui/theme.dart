import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/models/game_mode.dart';
import '../core/players/avatar.dart';

/// The app's palette, taken from the design: a near-black ground with one
/// saturated accent per category so a player can tell at a glance which
/// discipline a screen belongs to.
abstract final class AppColors {
  static const background = Color(0xFF0B0B10);
  static const surface = Color(0xFF15151E);
  static const surfaceHigh = Color(0xFF1E1E2A);
  static const border = Color(0xFF2A2A38);

  static const text = Color(0xFFF2F2F7);
  static const textMuted = Color(0xFF8E8E9E);

  static const math = Color(0xFFF5C518);
  static const memory = Color(0xFF4B9BFF);
  static const logic = Color(0xFFFF4D8D);

  static const win = Color(0xFF35D07F);
  static const loss = Color(0xFFFF5C5C);
  static const streak = Color(0xFFFF8A3D);

  static Color of(Category c) => switch (c) {
    Category.math => math,
    Category.memory => memory,
    Category.logic => logic,
  };
}

extension CategoryVisuals on Category {
  Color get color => AppColors.of(this);

  String get label => switch (this) {
    Category.math => 'MATH',
    Category.memory => 'MEMORY',
    Category.logic => 'LOGIC',
  };

  IconData get icon => switch (this) {
    Category.math => Icons.calculate_rounded,
    Category.memory => Icons.grid_view_rounded,
    Category.logic => Icons.lightbulb_rounded,
  };
}

extension GameModeVisuals on GameMode {
  Color get color => category.color;

  IconData get icon => switch (this) {
    GameMode.sprint => Icons.bolt_rounded,
    GameMode.fastestFingers => Icons.touch_app_rounded,
    GameMode.mindSnap => Icons.grid_view_rounded,
    GameMode.ability => Icons.extension_rounded,
  };

  String get blurb => switch (this) {
    GameMode.sprint => 'Arithmetic against the clock',
    GameMode.fastestFingers => 'Pure reaction speed',
    GameMode.mindSnap => 'Repeat the pattern',
    GameMode.ability => 'Sequences and odd-one-out',
  };

  /// The title as big type on the mode page, where it is the only thing on
  /// the screen. [label] stays the compact form that fits in a list row.
  String get headline => switch (this) {
    GameMode.sprint => 'SPRINT DUELS',
    GameMode.fastestFingers => 'FASTEST FINGERS',
    GameMode.mindSnap => 'MIND SNAP DUELS',
    GameMode.ability => 'ABILITY DUELS',
  };

  /// The question the mode actually settles. Said as a challenge rather than
  /// a description -- the page exists to make you want to press play.
  String get tagline => switch (this) {
    GameMode.sprint => 'WHO ADDS UP FASTER?',
    GameMode.fastestFingers => 'WHO REACTS FIRST?',
    GameMode.mindSnap => 'WHO CAN SNAP FASTER?',
    GameMode.ability => 'WHO SPOTS IT FIRST?',
  };
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    surface: AppColors.background,
    primary: AppColors.math,
    secondary: AppColors.memory,
    error: AppColors.loss,
    onSurface: AppColors.text,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: 'Roboto',
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 44,
        fontWeight: FontWeight.w800,
        color: AppColors.text,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
      bodyMedium: TextStyle(fontSize: 14, color: AppColors.text),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: AppColors.textMuted,
      ),
    ),
  );
}

/// The rounded dark card used throughout the app.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.accent,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  final Widget child;
  final Color? accent;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = accent?.withValues(alpha: 0.45) ?? AppColors.border;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A player's face: their photo if they have set one, otherwise the
/// character they chose.
///
/// Both are drawn to the same disc at the same size, so a row of faces stays
/// a row of faces whether or not anybody has uploaded a photo.
class AvatarBadge extends StatelessWidget {
  const AvatarBadge({
    super.key,
    required this.avatarId,
    required this.name,
    this.size = 40,
    this.photo,
  });

  final int avatarId;
  final String name;
  final double size;

  /// A small square PNG, base64 encoded, as stored on the profile and
  /// published on the player's row. Null for everybody who has not set one.
  final String? photo;

  static const List<Color> _palette = [
    Color(0xFFF5C518),
    Color(0xFF4B9BFF),
    Color(0xFFFF4D8D),
    Color(0xFF35D07F),
    Color(0xFFFF8A3D),
    Color(0xFFB07BFF),
    Color(0xFF23C4C4),
    Color(0xFFE85D75),
    Color(0xFF7BD16A),
    Color(0xFF5C7BFF),
    Color(0xFFFFB03D),
    Color(0xFFDD6BFF),
  ];

  static Color colorFor(int avatarId) =>
      _palette[avatarId.abs() % _palette.length];

  /// Decoded once per build rather than held: the strings are a few tens of
  /// kilobytes and Flutter's image cache keeps the decoded frame, so this is
  /// cheaper than it looks and keeps the widget immutable.
  static Uint8List? bytesOf(String? photo) {
    if (photo == null || photo.isEmpty) return null;
    try {
      return base64Decode(photo);
    } catch (_) {
      // A truncated or hand-edited value must not take a screen down; the
      // character avatar is always there to fall back to.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(avatarId);
    final bytes = bytesOf(photo);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1.5),
      ),
      child: bytes == null
          ? Text(
              Avatars.glyphFor(avatarId),
              style: TextStyle(fontSize: size * 0.52),
            )
          : Image.memory(
              bytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              // Same fallback as a value that would not decode at all.
              errorBuilder: (context, _, _) => Text(
                Avatars.glyphFor(avatarId),
                style: TextStyle(fontSize: size * 0.52),
              ),
            ),
    );
  }
}
