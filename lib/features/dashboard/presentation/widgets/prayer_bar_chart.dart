/// A bar chart of daily prayer completion.
///
/// Custom-painted rather than pulled from a charting package: the shapes are
/// simple, and a dependency would drag in far more than this needs while being
/// harder to make match the app's palette and dark mode. Each bar is a stack —
/// on-time, late, and missed — so a glance shows not just how many prayers were
/// prayed but how they were prayed.
library;

import 'package:flutter/material.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../tracking/domain/entities/prayer_statistics.dart';

class PrayerBarChart extends StatelessWidget {
  const PrayerBarChart({
    super.key,
    required this.days,
    this.height = 160,
    this.maxPrayersPerDay = 5,
  });

  /// Days in chronological order (oldest first).
  final List<DailySummary> days;
  final double height;
  final int maxPrayersPerDay;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No prayers recorded yet',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    final theme = Theme.of(context);

    return Semantics(
      label: _semanticSummary(),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final day in days)
                  Expanded(
                    child: _DayBar(
                      day: day,
                      maxPrayers: maxPrayersPerDay,
                      availableHeight: height - 24,
                      labelStyle: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _semanticSummary() {
    final totalFulfilled =
        days.fold(0, (sum, day) => sum + day.counts.fulfilled);
    final totalAssessed =
        days.fold(0, (sum, day) => sum + day.counts.assessed);
    return 'Prayer completion over ${days.length} days: '
        '$totalFulfilled of $totalAssessed prayers fulfilled';
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.day,
    required this.maxPrayers,
    required this.availableHeight,
    required this.labelStyle,
  });

  final DailySummary day;
  final int maxPrayers;
  final double availableHeight;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final counts = day.counts;
    double heightFor(int n) => (n / maxPrayers) * availableHeight;

    // Stacked bottom-to-top: on-time, then late, then missed. Ordering matters
    // visually — the "good" segment sits at the base, so a healthy week reads
    // as solid green columns and a bad one as red-topped stubs.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _segment(heightFor(counts.missed), AppColors.danger, top: true),
                _segment(heightFor(counts.qaza), AppColors.warning),
                _segment(
                  heightFor(counts.completed),
                  AppColors.primary,
                  bottom: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(_weekdayLabel(day.date), style: labelStyle),
        ],
      ),
    );
  }

  Widget _segment(
    double height,
    Color color, {
    bool top = false,
    bool bottom = false,
  }) {
    if (height <= 0) return const SizedBox.shrink();

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(top ? 4 : 0),
          bottom: Radius.circular(bottom ? 4 : 0),
        ),
      ),
    );
  }

  static String _weekdayLabel(DateTime date) {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return labels[(date.weekday - 1) % 7];
  }
}
