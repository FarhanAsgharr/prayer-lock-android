/// Aggregated prayer statistics.
library;

import 'package:flutter/foundation.dart';

import '../../../prayer_times/domain/entities/prayer_enums.dart';

/// Counts for one period.
@immutable
class PrayerCounts {
  const PrayerCounts({
    this.completed = 0,
    this.late = 0,
    this.missed = 0,
    this.excused = 0,
  });

  final int completed;
  final int late;
  final int missed;
  final int excused;

  /// Prayers whose window has closed and which therefore count towards a rate.
  ///
  /// Excludes excused prayers entirely rather than counting them as successes:
  /// inflating someone's rate because they were ill or travelling would make
  /// the number meaningless.
  int get assessed => completed + late + missed;

  int get fulfilled => completed + late;

  int get total => assessed + excused;

  /// Fraction of assessed prayers that were performed, 0.0–1.0.
  ///
  /// Returns 1.0 when nothing has been assessed yet. A new user should not be
  /// shown 0% before they have had the chance to pray anything — that reads as
  /// an accusation on first launch.
  double get successRate => assessed == 0 ? 1.0 : fulfilled / assessed;

  /// Fraction performed within the prayer's own window.
  double get onTimeRate => assessed == 0 ? 1.0 : completed / assessed;

  PrayerCounts operator +(PrayerCounts other) => PrayerCounts(
        completed: completed + other.completed,
        late: late + other.late,
        missed: missed + other.missed,
        excused: excused + other.excused,
      );

  static PrayerCounts fromStatuses(Iterable<PrayerStatus> statuses) {
    var completed = 0;
    var late = 0;
    var missed = 0;
    var excused = 0;

    for (final status in statuses) {
      switch (status) {
        case PrayerStatus.completed:
          completed++;
        case PrayerStatus.late:
          late++;
        case PrayerStatus.missed:
          missed++;
        case PrayerStatus.excused:
          excused++;
        case PrayerStatus.pending:
        case PrayerStatus.active:
          // Still in progress; not yet assessable.
          break;
      }
    }

    return PrayerCounts(
      completed: completed,
      late: late,
      missed: missed,
      excused: excused,
    );
  }
}

/// One day's summary, used by the weekly and monthly charts.
@immutable
class DailySummary {
  const DailySummary({required this.date, required this.counts});

  final DateTime date;
  final PrayerCounts counts;

  /// Whether every prayer that day was fulfilled.
  bool get isPerfect => counts.assessed > 0 && counts.missed == 0;
}

/// Streaks.
@immutable
class StreakSummary {
  const StreakSummary({
    required this.current,
    required this.longest,
    this.lastPerfectDay,
  });

  const StreakSummary.empty()
      : current = 0,
        longest = 0,
        lastPerfectDay = null;

  /// Consecutive complete days ending today or yesterday.
  final int current;

  /// Best run ever recorded.
  final int longest;

  final DateTime? lastPerfectDay;
}

/// The full statistics bundle the dashboard renders.
@immutable
class PrayerStatistics {
  const PrayerStatistics({
    required this.today,
    required this.week,
    required this.month,
    required this.year,
    required this.allTime,
    required this.streak,
    required this.dailyHistory,
    required this.byPrayer,
  });

  const PrayerStatistics.empty()
      : today = const PrayerCounts(),
        week = const PrayerCounts(),
        month = const PrayerCounts(),
        year = const PrayerCounts(),
        allTime = const PrayerCounts(),
        streak = const StreakSummary.empty(),
        dailyHistory = const [],
        byPrayer = const {};

  final PrayerCounts today;
  final PrayerCounts week;
  final PrayerCounts month;
  final PrayerCounts year;
  final PrayerCounts allTime;
  final StreakSummary streak;

  /// Most recent days first, for the charts.
  final List<DailySummary> dailyHistory;

  /// Per-prayer breakdown, which surfaces the pattern that matters most —
  /// almost everyone's weakest prayer is Fajr, and naming it is more useful
  /// than a single overall percentage.
  final Map<PrayerName, PrayerCounts> byPrayer;

  /// The prayer with the lowest success rate, if there is enough data.
  ///
  /// Requires at least five assessed instances so a single missed prayer in a
  /// new install does not get labelled a weakness.
  PrayerName? get weakestPrayer {
    PrayerName? weakest;
    var lowestRate = double.infinity;

    for (final entry in byPrayer.entries) {
      if (entry.value.assessed < 5) continue;
      if (entry.value.successRate < lowestRate) {
        lowestRate = entry.value.successRate;
        weakest = entry.key;
      }
    }

    return weakest;
  }
}
