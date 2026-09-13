import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/game_mode.dart';
import '../../core/players/player_directory.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/challenge.dart';

/// One row of the board -- the player, a bot, or a friend they have duelled,
/// ranked purely on rating.
class _Standing {
  const _Standing({
    required this.name,
    required this.avatarId,
    required this.rating,
    required this.isPlayer,
    this.uid,
    this.photo,
    this.isOnline = false,
  });

  final String name;
  final int avatarId;

  /// Their photograph, when they have set one. Bots never have one.
  final String? photo;
  final int rating;
  final bool isPlayer;

  /// Set only for real people. Bots have no phone to challenge.
  final String? uid;

  /// Beating right now, so a challenge would actually reach them.
  final bool isOnline;

  /// Somebody there is a duel to send to: a real person, on right now, who
  /// is not this player. Bots and the player's own row carry no uid, so both
  /// fall out of this without needing to be named.
  bool get canChallenge => isOnline && uid != null;
}

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key, this.findFor});

  /// Set when the board was opened from a duel's own page to find somebody to
  /// play it with. The challenge then goes out in that mode without asking
  /// again -- they chose it one screen ago.
  final GameMode? findFor;

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  late Category _category = widget.findFor?.category ?? Category.math;

  /// Held in state rather than read from the widget every build, so the
  /// player can put it down without navigating anywhere.
  late GameMode? _findFor = widget.findFor;

  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(
      () => setState(() => _query = _search.text.trim().toLowerCase()),
    );
  }

  @override
  void didUpdateWidget(LeaderboardScreen old) {
    super.didUpdateWidget(old);
    // Arriving from a second duel's page while the tab is already built.
    if (widget.findFor != old.findFor && widget.findFor != null) {
      setState(() {
        _findFor = widget.findFor;
        _category = widget.findFor!.category;
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final roster = ref.watch(rosterProvider);
    // Everyone registered on MindRush, not merely the people this device has
    // happened to duel. Their ratings come off their own phones, so these rows
    // are their real standing.
    final directory =
        ref.watch(directoryProvider).value ?? PlayerDirectory.empty;
    final now = DateTime.now();

    // The bots ship with ordinary first names, and the people playing this
    // have ordinary first names too, so sooner or later somebody picks one
    // that is already on the roster. Two rows reading the same name with
    // different ratings looks like a broken board rather than a coincidence
    // in a list of ten, so the bot stands aside: the person is the one who
    // earned their row, and a bot can be beaten without being listed.
    final realNames = {
      profile.displayName.trim().toLowerCase(),
      for (final player in directory.others) player.name.trim().toLowerCase(),
    }..remove('');

    final standings = <_Standing>[
      _Standing(
        name: profile.displayName,
        avatarId: profile.avatarId,
        photo: profile.photo,
        rating: profile.ratingIn(_category),
        isPlayer: true,
      ),
      for (final bot in roster)
        if (!realNames.contains(bot.name.trim().toLowerCase()))
          _Standing(
            name: bot.name,
            avatarId: bot.avatarId,
            rating: bot.ratingIn(_category),
            isPlayer: false,
          ),
      for (final player in directory.others)
        _Standing(
          name: player.name,
          avatarId: player.avatarId,
          photo: player.photo,
          rating: player.ratingIn(_category),
          isPlayer: false,
          uid: player.uid,
          isOnline: directory.isOnline(player.uid, now: now),
        ),
    ]..sort((a, b) => b.rating.compareTo(a.rating));

    // Ranks are worked out over everybody and only then filtered, so a
    // searched-for player keeps the number they actually hold on the board
    // rather than being renumbered 1 for being the only row left.
    final rows = [
      for (final (index, standing) in standings.indexed)
        if (_query.isEmpty || standing.name.toLowerCase().contains(_query))
          (rank: index + 1, standing: standing),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'Leaderboard',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _SearchField(
                controller: _search,
                // The keyboard is wanted immediately when the player came
                // here to look somebody up, and in the way when they came to
                // read the board.
                autofocus: widget.findFor != null,
              ),
            ),
            if (_findFor != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _ChallengingFor(
                  mode: _findFor!,
                  onClear: () => setState(() => _findFor = null),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final category in Category.values) ...[
                    Expanded(
                      child: _CategoryTab(
                        category: category,
                        selected: category == _category,
                        onTap: () => setState(() => _category = category),
                      ),
                    ),
                    if (category != Category.values.last)
                      const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: rows.isEmpty
                  ? const _NoSuchPlayer()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) => _StandingRow(
                        rank: rows[index].rank,
                        standing: rows[index].standing,
                        accent: _category.color,
                        onChallenge: () => Challenge.challengeDirect(
                          context,
                          ref,
                          uid: rows[index].standing.uid!,
                          name: rows[index].standing.name,
                          mode: _findFor,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? category.color.withValues(alpha: 0.15)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? category.color : AppColors.border),
      ),
      child: Text(
        category.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: selected ? category.color : AppColors.textMuted,
        ),
      ),
    ),
  );
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.rank,
    required this.standing,
    required this.accent,
    required this.onChallenge,
  });

  final int rank;
  final _Standing standing;
  final Color accent;
  final VoidCallback onChallenge;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      accent: standing.isPlayer ? accent : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      // The whole row, not just the bolt. A 22-pixel icon is a small target
      // for a thumb, and everything on the row -- the rank, the face, the
      // name, the rating -- is about the same person the duel would go to.
      // Null when there is nobody to challenge, which leaves the row inert
      // rather than tappable to no effect.
      onTap: standing.canChallenge ? onChallenge : null,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$rank',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: rank <= 3 ? accent : AppColors.textMuted,
              ),
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              AvatarBadge(
                avatarId: standing.avatarId,
                name: standing.name,
                photo: standing.photo,
                size: 34,
              ),
              if (standing.isOnline)
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppColors.win,
                      shape: BoxShape.circle,
                      // Ringed in the card colour so the dot reads as a badge
                      // on the avatar rather than a smudge over it.
                      border: Border.all(color: AppColors.surface, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              standing.isPlayer ? '${standing.name}  (you)' : standing.name,
              style: Theme.of(context).textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (standing.canChallenge) ...[
            // Drawn rather than pressed: the row above is the button now, and
            // a second tap target sitting inside it would swallow the ripple
            // over its own corner of a row that is entirely tappable.
            Tooltip(
              message: 'Challenge ${standing.name}',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.bolt_rounded, color: accent, size: 22),
              ),
            ),
            const SizedBox(width: 2),
          ],
          Text(
            '${standing.rating}',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: standing.isPlayer ? accent : AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

/// Finding one person on a board that is meant to hold everybody.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.autofocus});

  final TextEditingController controller;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    textCapitalization: TextCapitalization.words,
    style: Theme.of(context).textTheme.bodyMedium,
    decoration: InputDecoration(
      hintText: 'Search a player',
      hintStyle: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
      prefixIcon: const Icon(
        Icons.search_rounded,
        color: AppColors.textMuted,
        size: 20,
      ),
      isDense: true,
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.textMuted),
      ),
    ),
  );
}

/// The duel the player already picked, carried onto the board so the bolt
/// does not ask them a question they have answered.
class _ChallengingFor extends StatelessWidget {
  const _ChallengingFor({required this.mode, required this.onClear});

  final GameMode mode;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colour = mode.color;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colour.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(mode.icon, color: colour, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Challenging for ${mode.label}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          IconButton(
            onPressed: onClear,
            visualDensity: VisualDensity.compact,
            tooltip: 'Pick the duel per challenge instead',
            icon: const Icon(
              Icons.close_rounded,
              color: AppColors.textMuted,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

/// A search that matched nobody. Said with the reason, because the usual
/// cause is a friend who has not opened MindRush yet rather than a typo.
class _NoSuchPlayer extends StatelessWidget {
  const _NoSuchPlayer();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 30, 32, 0),
    child: Column(
      children: [
        const Icon(
          Icons.person_search_rounded,
          color: AppColors.textMuted,
          size: 34,
        ),
        const SizedBox(height: 12),
        Text(
          'Nobody by that name',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'Only players who have opened MindRush are on the board. '
          'Send them a link to get them on it.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    ),
  );
}
