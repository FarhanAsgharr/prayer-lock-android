/// Friday-specific and extended prayer statistics.
///
/// Friday is worth counting separately because it behaves differently from
/// every other day: the prayer is a congregation the user has to travel to, at
/// a fixed time they do not control, and missing it is a different kind of miss
/// from sleeping through Fajr. Folding it into the general Dhuhr numbers would
/// hide both facts.
library;

import 'package:flutter/foundation.dart';

import '../../../prayer_times/domain/entities/prayer_enums.dart';

/// One recorded Friday.
@immutable
class FridayRecord {
  const FridayRecord({
    required this.date,
    required this.status,
    required this.wasJumuah,
    this.mosqueName,
    this.blockDuration,
    this.verificationDelay,
  });

  final DateTime date;
  final PrayerStatus status;

  /// Whether it was recorded as a congregation rather than as ordinary Dhuhr.
  ///
  /// A Friday where Smart Jumu'ah was off is still a Friday, but it is not a
  /// Jumu'ah, and the completion rate should not claim otherwise.
  final bool wasJumuah;

  /// The mosque as it was named at the time.
  final String? mosqueName;

  /// How long apps were blocked for it.
  final Duration? blockDuration;

  /// How long after the congregation opened the user confirmed.
  ///
  /// The product brief calls this "average arrival time". It is really time to
  /// *confirmation*, which is the only thing the app can observe — someone may
  /// arrive early and confirm on the way out.
  final Duration? verificationDelay;

  bool get isCompleted => status.isFulfilled;
}

/// Aggregated Friday statistics.
@immutable
class FridayAnalytics {
  const FridayAnalytics({
    required this.totalFridays,
    required this.completedFridays,
    required this.missedFridays,
    required this.currentStreak,
    required this.longestStreak,
    this.averageVerificationDelay,
    this.averageBlockDuration,
    this.mosqueCounts = const {},
  });

  const FridayAnalytics.empty()
      : totalFridays = 0,
        completedFridays = 0,
        missedFridays = 0,
        currentStreak = 0,
        longestStreak = 0,
        averageVerificationDelay = null,
        averageBlockDuration = null,
        mosqueCounts = const {};

  final int totalFridays;
  final int completedFridays;
  final int missedFridays;

  /// Consecutive completed Fridays ending at the most recent one.
  final int currentStreak;
  final int longestStreak;

  /// Mean time from the congregation opening to confirmation.
  final Duration? averageVerificationDelay;

  final Duration? averageBlockDuration;

  /// How many Fridays at each mosque, for "you mostly pray at…".
  final Map<String, int> mosqueCounts;

  /// Fraction of assessed Fridays completed, 0.0–1.0.
  ///
  /// Returns 1.0 when nothing has been assessed: a new user should not be shown
  /// 0% before they have had a Friday.
  double get completionRate =>
      totalFridays == 0 ? 1.0 : completedFridays / totalFridays;

  /// The mosque attended most often, or null when nothing is recorded.
  String? get favouriteMosque {
    if (mosqueCounts.isEmpty) return null;

    var best = mosqueCounts.entries.first;
    for (final entry in mosqueCounts.entries) {
      if (entry.value > best.value) best = entry;
    }
    return best.key;
  }

  /// Build from recorded Fridays, most recent first.
  factory FridayAnalytics.from(List<FridayRecord> records) {
    if (records.isEmpty) return const FridayAnalytics.empty();

    final ordered = [...records]..sort((a, b) => b.date.compareTo(a.date));

    var completed = 0;
    var missed = 0;
    final mosques = <String, int>{};
    final delays = <Duration>[];
    final blocks = <Duration>[];

    for (final record in ordered) {
      if (record.isCompleted) {
        completed++;
        final mosque = record.mosqueName;
        if (mosque != null) {
          mosques[mosque] = (mosques[mosque] ?? 0) + 1;
        }
        final delay = record.verificationDelay;
        if (delay != null) delays.add(delay);
        final block = record.blockDuration;
        if (block != null) blocks.add(block);
      } else if (record.status == PrayerStatus.missed) {
        missed++;
      }
      // Anything still pending is neither completed nor missed — a Friday that
      // has not finished yet must not count against the rate.
    }

    // Current streak: consecutive completions from the most recent Friday
    // backwards. Stops at the first miss.
    var current = 0;
    for (final record in ordered) {
      if (!record.isCompleted) break;
      current++;
    }

    // Longest run anywhere in the history.
    var longest = 0;
    var run = 0;
    for (final record in ordered.reversed) {
      if (record.isCompleted) {
        run++;
        if (run > longest) longest = run;
      } else {
        run = 0;
      }
    }

    return FridayAnalytics(
      totalFridays: completed + missed,
      completedFridays: completed,
      missedFridays: missed,
      currentStreak: current,
      longestStreak: longest,
      averageVerificationDelay: _mean(delays),
      averageBlockDuration: _mean(blocks),
      mosqueCounts: Map.unmodifiable(mosques),
    );
  }

  static Duration? _mean(List<Duration> values) {
    if (values.isEmpty) return null;
    final total = values.fold(0, (sum, d) => sum + d.inSeconds);
    return Duration(seconds: total ~/ values.length);
  }
}

/// Per-prayer performance, for "which prayer do I miss most".
@immutable
class PrayerPerformance {
  const PrayerPerformance({
    required this.prayer,
    required this.completed,
    required this.missed,
    this.averageDelay,
  });

  final PrayerName prayer;
  final int completed;
  final int missed;

  /// Mean minutes between the prayer's start and its confirmation.
  final Duration? averageDelay;

  int get assessed => completed + missed;

  double get completionRate => assessed == 0 ? 1.0 : completed / assessed;
}

/// The extended analytics the dashboard's analytics screen shows.
@immutable
class ExtendedPrayerAnalytics {
  const ExtendedPrayerAnalytics({
    required this.byPrayer,
    this.averageVerificationTime,
    required this.friday,
  });

  const ExtendedPrayerAnalytics.empty()
      : byPrayer = const [],
        averageVerificationTime = null,
        friday = const FridayAnalytics.empty();

  final List<PrayerPerformance> byPrayer;

  /// Mean time from a prayer beginning to the user confirming it, across all
  /// prayers. The product brief's "average verification time".
  final Duration? averageVerificationTime;

  final FridayAnalytics friday;

  /// The prayer missed most often.
  ///
  /// Ranked by *rate*, not by count, so a prayer with three misses out of four
  /// outranks one with five out of a hundred. Prayers with nothing assessed are
  /// excluded — a prayer never yet due is not one the user is failing at.
  PrayerPerformance? get mostMissed {
    final assessed = byPrayer.where((p) => p.assessed > 0).toList();
    if (assessed.isEmpty) return null;

    assessed.sort((a, b) => a.completionRate.compareTo(b.completionRate));
    final worst = assessed.first;
    // Nothing is "most missed" when everything is perfect.
    return worst.completionRate >= 1.0 ? null : worst;
  }

  /// The prayer kept most reliably.
  PrayerPerformance? get bestPrayer {
    final assessed = byPrayer.where((p) => p.assessed > 0).toList();
    if (assessed.isEmpty) return null;

    assessed.sort((a, b) => b.completionRate.compareTo(a.completionRate));
    return assessed.first;
  }

  /// How evenly the user performs across the five prayers, 0.0–1.0.
  ///
  /// Defined as one minus the spread between the best and worst completion
  /// rates. Someone at 90% on every prayer scores higher than someone at 100%
  /// on four and 50% on one, which is the distinction "consistency" is meant to
  /// capture — the second person has a specific problem, not a general one.
  double get consistency {
    final assessed = byPrayer.where((p) => p.assessed > 0).toList();
    if (assessed.length < 2) return 1.0;

    final rates = assessed.map((p) => p.completionRate).toList()..sort();
    return 1.0 - (rates.last - rates.first);
  }

  /// Overall completion across every prayer.
  double get overallCompletionRate {
    final assessed = byPrayer.fold(0, (sum, p) => sum + p.assessed);
    if (assessed == 0) return 1.0;

    final completed = byPrayer.fold(0, (sum, p) => sum + p.completed);
    return completed / assessed;
  }
}
