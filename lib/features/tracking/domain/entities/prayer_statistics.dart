/// Aggregated prayer statistics.
library;

import 'package:flutter/foundation.dart';

import '../../../prayer_times/domain/entities/prayer_enums.dart';

/// How many recorded prayers were prayed joined, and how many alone.
///
/// Reported separately from [PrayerCounts] rather than folded into it, because
/// combining is orthogonal to the outcome: a combined prayer can be on time,
/// late or missed exactly like any other. Mixing the two would make "completed"
/// ambiguous about whether it meant a prayer or a pair.
@immutable
class CombinedPrayerCounts {
  const CombinedPrayerCounts({this.combined = 0, this.separate = 0});

  /// Prayers recorded while joined with their neighbour.
  final int combined;

  /// Prayers recorded on their own.
  final int separate;

  int get total => combined + separate;

  /// Fraction prayed joined, 0.0–1.0. Zero when nothing is recorded, rather
  /// than dividing by zero.
  double get combinedRate => total == 0 ? 0.0 : combined / total;

  /// Whether the user has ever combined. Drives whether the breakdown is worth
  /// showing at all — it is noise for someone who never combines.
  bool get hasCombined => combined > 0;

  CombinedPrayerCounts operator +(CombinedPrayerCounts other) =>
      CombinedPrayerCounts(
        combined: combined + other.combined,
        separate: separate + other.separate,
      );
}

/// Counts for one period.
@immutable
class PrayerCounts {
  const PrayerCounts({
    this.completed = 0,
    this.qaza = 0,
    this.missed = 0,
    this.excused = 0,
  });

  /// Verified within the on-time window.
  final int completed;

  /// Verified within the qaza (make-up) window. Counted separately from
  /// on-time, as the spec requires, so a make-up is visible as such.
  final int qaza;

  final int missed;
  final int excused;

  /// Prayers whose windows have closed and which therefore count towards a
  /// rate. Excludes excused prayers entirely — inflating the rate because
  /// someone was ill or travelling would make the number meaningless.
  int get assessed => completed + qaza + missed;

  /// Performed at all, on time or as qaza.
  int get fulfilled => completed + qaza;

  int get total => assessed + excused;

  /// Fraction of assessed prayers that were performed, 0.0–1.0.
  ///
  /// Returns 1.0 when nothing has been assessed yet. A new user should not be
  /// shown 0% before they have had the chance to pray anything.
  double get successRate => assessed == 0 ? 1.0 : fulfilled / assessed;

  /// Fraction performed within the on-time window.
  double get onTimeRate => assessed == 0 ? 1.0 : completed / assessed;

  PrayerCounts operator +(PrayerCounts other) => PrayerCounts(
        completed: completed + other.completed,
        qaza: qaza + other.qaza,
        missed: missed + other.missed,
        excused: excused + other.excused,
      );

  static PrayerCounts fromStatuses(Iterable<PrayerStatus> statuses) {
    var completed = 0;
    var qaza = 0;
    var missed = 0;
    var excused = 0;

    for (final status in statuses) {
      switch (status) {
        case PrayerStatus.completed:
          completed++;
        case PrayerStatus.qazaCompleted:
        case PrayerStatus.late: // legacy — fold into qaza
          qaza++;
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
      qaza: qaza,
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
