/// A day's prayers with their tracked completion state.
///
/// The calculator produces raw instants; this layer attaches status, window
/// boundaries and the derived "what should the user do right now" answer that
/// the entire UI is built from.
library;

import 'package:flutter/foundation.dart';

import '../usecases/prayer_time_calculator.dart';
import 'prayer_enums.dart';

/// One prayer on one day, with its window and current status.
@immutable
class PrayerEntry {
  const PrayerEntry({
    required this.prayer,
    required this.scheduledAt,
    required this.windowEndsAt,
    this.status = PrayerStatus.pending,
    this.completedAt,
  });

  final PrayerName prayer;

  /// When the prayer becomes due, as a UTC instant.
  final DateTime scheduledAt;

  /// When the window closes. For Fajr this is sunrise, not Dhuhr.
  final DateTime windowEndsAt;

  final PrayerStatus status;
  final DateTime? completedAt;

  /// How late the prayer was performed, or null if not yet performed.
  Duration? get delay => completedAt?.difference(scheduledAt);

  bool isDue(DateTime now) =>
      !now.isBefore(scheduledAt) && now.isBefore(windowEndsAt);

  bool hasExpired(DateTime now) => !now.isBefore(windowEndsAt);

  /// Status recomputed against the clock.
  ///
  /// Stored status is authoritative once a prayer is fulfilled; before that,
  /// the correct status is a function of time and must be derived rather than
  /// cached, or a prayer would stay "pending" forever after its window closed.
  PrayerStatus statusAt(DateTime now) {
    if (status.isFulfilled) return status;
    if (isDue(now)) return PrayerStatus.active;
    if (hasExpired(now)) return PrayerStatus.missed;
    return PrayerStatus.pending;
  }

  PrayerEntry copyWith({PrayerStatus? status, DateTime? completedAt}) =>
      PrayerEntry(
        prayer: prayer,
        scheduledAt: scheduledAt,
        windowEndsAt: windowEndsAt,
        status: status ?? this.status,
        completedAt: completedAt ?? this.completedAt,
      );
}

/// A full day: five prayers, sunrise, and the queries the UI needs.
@immutable
class PrayerDay {
  const PrayerDay({
    required this.date,
    required this.entries,
    required this.sunrise,
  });

  final DateTime date;
  final List<PrayerEntry> entries;
  final DateTime sunrise;

  /// Build from a calculated schedule.
  ///
  /// [nextDayFajr] is required because Isha's window runs until the following
  /// Fajr, which is not part of this day's schedule. Passing it explicitly
  /// avoids the common bug of ending Isha at midnight, which is wrong.
  factory PrayerDay.fromSchedule(
    PrayerSchedule schedule, {
    required DateTime nextDayFajr,
    Map<PrayerName, PrayerEntry> existing = const {},
  }) {
    final entries = PrayerName.values.map((prayer) {
      final scheduledAt = schedule.prayers[prayer]!;
      final windowEndsAt =
          schedule.windowEndFor(prayer, nextDayFajr: nextDayFajr);

      // Preserve any tracked completion state across recalculation, so
      // changing a setting never erases a prayer the user already performed.
      final tracked = existing[prayer];

      return PrayerEntry(
        prayer: prayer,
        scheduledAt: scheduledAt,
        windowEndsAt: windowEndsAt,
        status: tracked?.status ?? PrayerStatus.pending,
        completedAt: tracked?.completedAt,
      );
    }).toList(growable: false);

    return PrayerDay(
      date: schedule.prayerDate,
      entries: entries,
      sunrise: schedule.sunrise,
    );
  }

  PrayerEntry entryFor(PrayerName prayer) =>
      entries.firstWhere((entry) => entry.prayer == prayer);

  /// The prayer currently *owed*, if any.
  ///
  /// Excludes prayers already fulfilled, because the dashboard uses this to
  /// answer "what should I do now" and showing a completed prayer as current
  /// would be wrong.
  ///
  /// Returns null between Fajr's expiry at sunrise and Dhuhr — a genuine gap
  /// during which no prayer is owed, which the UI must represent honestly
  /// rather than pretending Dhuhr is already active.
  PrayerEntry? currentPrayer(DateTime now) {
    final entry = entryInWindow(now);
    return entry != null && !entry.status.isFulfilled ? entry : null;
  }

  /// The prayer whose window contains [now], fulfilled or not.
  ///
  /// Distinct from [currentPrayer]: enforcement needs to tell "you have
  /// already prayed this one" apart from "nothing is owed right now", and
  /// those are different messages to show the user.
  PrayerEntry? entryInWindow(DateTime now) {
    for (final entry in entries) {
      if (entry.isDue(now)) return entry;
    }
    return null;
  }

  /// The next prayer that has not yet begun.
  PrayerEntry? nextPrayer(DateTime now) {
    for (final entry in entries) {
      if (entry.scheduledAt.isAfter(now)) return entry;
    }
    return null;
  }

  /// Time until the next prayer begins, or null if the day's prayers have all
  /// started.
  Duration? timeUntilNextPrayer(DateTime now) =>
      nextPrayer(now)?.scheduledAt.difference(now);

  int get completedCount =>
      entries.where((entry) => entry.status.isFulfilled).length;

  int get remainingCount => entries.length - completedCount;

  /// Whether every prayer whose window has closed was fulfilled.
  ///
  /// Used for streak calculation: a day counts only when nothing was missed,
  /// and a day still in progress cannot yet be judged.
  bool isCleanSoFar(DateTime now) => !entries.any(
        (entry) => entry.hasExpired(now) && !entry.status.isFulfilled,
      );

  bool isComplete(DateTime now) =>
      entries.every((entry) => entry.status.isFulfilled);

  /// Whether Fajr is due or missed and unfulfilled — the morning-protection
  /// gate condition.
  bool requiresMorningProtection(DateTime now) {
    final fajr = entryFor(PrayerName.fajr);
    if (fajr.status.isFulfilled) return false;
    // Only between Fajr and its expiry at sunrise; after sunrise the gate
    // lifts, because holding someone's phone hostage all day is punitive.
    return fajr.isDue(now);
  }

  PrayerDay withEntry(PrayerEntry updated) => PrayerDay(
        date: date,
        sunrise: sunrise,
        entries: entries
            .map((entry) => entry.prayer == updated.prayer ? updated : entry)
            .toList(growable: false),
      );
}
