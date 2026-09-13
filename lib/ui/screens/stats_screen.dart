import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/game_mode.dart';
import '../../data/match_summary.dart';
import '../../state/providers.dart';
import '../theme.dart';

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  Category _category = Category.math;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    // Oldest first, so the chart reads left to right through time.
    final matches = profile.historyFor(_category).reversed.toList();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text('Stats', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final category in Category.values) ...[
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _category = category),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: category == _category
                              ? category.color.withValues(alpha: 0.15)
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: category == _category
                                ? category.color
                                : AppColors.border,
                          ),
                        ),
                        child: Text(
                          category.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                            color: category == _category
                                ? category.color
                                : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (category != Category.values.last)
                    const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: 'Rating',
                    value: '${profile.ratingIn(_category)}',
                    color: _category.color,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Stat(
                    label: 'Win rate',
                    value: matches.isEmpty
                        ? '--'
                        : '${(profile.winRate(_category) * 100).round()}%',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Stat(label: 'Matches', value: '${matches.length}'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'RATING OVER TIME',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 12),
            AppCard(
              child: SizedBox(
                height: 180,
                child: matches.length < 2
                    ? const Center(
                        child: Text(
                          'Play a couple of duels to see your progress',
                          style: TextStyle(color: AppColors.textMuted),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : _RatingChart(matches: matches, color: _category.color),
              ),
            ),
            const SizedBox(height: 24),
            Text('BY MODE', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 12),
            for (final mode in GameMode.values.where(
              (m) => m.category == _category,
            )) ...[
              _ModeStats(
                mode: mode,
                matches: matches.where((m) => m.mode == mode).toList(),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _RatingChart extends StatelessWidget {
  const _RatingChart({required this.matches, required this.color});

  final List<MatchSummary> matches;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (final (index, match) in matches.indexed)
        FlSpot(index.toDouble(), match.ratingAfter.toDouble()),
    ];
    final values = spots.map((s) => s.y);
    final low = values.reduce((a, b) => a < b ? a : b);
    final high = values.reduce((a, b) => a > b ? a : b);
    // Keep a little air above and below so a flat run is not a line glued to
    // the chart edge.
    final padding = ((high - low) * 0.2).clamp(8.0, 60.0);
    final minY = low - padding;
    final maxY = high + padding;

    // Without an explicit interval fl_chart picks its own, which crowds two
    // labels together at the top of a narrow range.
    final interval = ((maxY - minY) / 4).ceilToDouble().clamp(1.0, 1000.0);

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.border, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          bottomTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: interval,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                value.round().toString(),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                ),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: color,
            barWidth: 2.5,
            dotData: FlDotData(show: spots.length <= 20),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
    child: Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: color ?? AppColors.text,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
  );
}

class _ModeStats extends StatelessWidget {
  const _ModeStats({required this.mode, required this.matches});

  final GameMode mode;
  final List<MatchSummary> matches;

  @override
  Widget build(BuildContext context) {
    final played = matches.length;
    final wins = matches.where((m) => m.won).length;
    final bestScore = played == 0
        ? 0
        : matches.map((m) => m.playerScore).reduce((a, b) => a > b ? a : b);

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(mode.icon, color: mode.color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              mode.label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (played == 0)
            Text(
              'Not played yet',
              style: Theme.of(context).textTheme.labelSmall,
            )
          else ...[
            _MiniStat(label: 'played', value: '$played'),
            const SizedBox(width: 14),
            _MiniStat(label: 'won', value: '$wins'),
            const SizedBox(width: 14),
            _MiniStat(label: 'best', value: '$bestScore'),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
      ),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}
