/// The avatars a player can wear.
///
/// Characters rather than the letter of somebody's name: a board of initials
/// on coloured discs is a spreadsheet, and the point of a face is that you
/// pick your friend out of a list without reading it.
///
/// Drawn as glyphs rather than shipped as images. Every one of these is in
/// the system font on both platforms, so the app carries no image assets, no
/// licences and no download -- and a new avatar is one line here.
class AvatarFamily {
  const AvatarFamily(this.name, this.glyphs);

  final String name;
  final List<String> glyphs;
}

abstract final class Avatars {
  static const List<AvatarFamily> families = [
    AvatarFamily('ROBOTS', ['🤖', '👾', '👽', '🛸', '🦾', '🎮', '🎯', '💾']),
    AvatarFamily('ANIMALS', [
      '🦊', '🐼', '🐯', '🦁', '🐵', '🐸', '🐨', '🐺', //
      '🦄', '🐙', '🦉', '🐲', '🦈', '🐧', '🐝', '🦋',
    ]),
    AvatarFamily('HATS', ['🎩', '🧢', '👑', '🥷', '🧙', '🦸', '🎓', '🤠']),
  ];

  /// Every glyph in one list; a player's `avatarId` is an index into it.
  ///
  /// Ids are positional, so families may be added to the end freely -- but
  /// reordering what is already here would change the avatar of everybody who
  /// picked one.
  static final List<String> all = [
    for (final family in families) ...family.glyphs,
  ];

  static int get count => all.length;

  /// Wraps rather than ranging out: an id from a future build with more
  /// avatars still resolves to something rather than crashing this one.
  static String glyphFor(int avatarId) => all[avatarId.abs() % all.length];

  /// Where [avatarId] sits, for a picker that wants to open on the right row.
  static int familyOf(int avatarId) {
    var index = avatarId.abs() % all.length;
    for (final (position, family) in families.indexed) {
      if (index < family.glyphs.length) return position;
      index -= family.glyphs.length;
    }
    return 0;
  }

  /// The id of the glyph at [slot] within [family].
  static int idIn(int family, int slot) {
    var id = 0;
    for (var i = 0; i < family; i++) {
      id += families[i].glyphs.length;
    }
    return id + slot;
  }
}
