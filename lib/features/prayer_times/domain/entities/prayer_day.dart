/// A day's prayers with their verification/qaza windows and tracked state.
///
/// The calculator produces raw prayer instants; this layer attaches the
/// on-time and qaza windows, the recorded outcome, and the derived "what can
/// the user do now" phase that the entire UI and the lock logic read from.
///
/// The window model (uniform across all five prayers):
///   [start, start+30m)      on-time  — verify -> Verified On Time
///   [start+30m, start+90m)  qaza     — verify -> Qaza Completed
///   >= start+90m            missed   — no action remains
library;

import 'package:flutter/foundation.dart';

import '../usecases/prayer_time_calculator.dart';
import 'prayer_enums.dart';

/// How long after a prayer starts it can still be verified as on time.
const Duration kVerificationWindow = Duration(minutes: 30);

/// How long the qaza window lasts, beginning when the on-time window ends.
const Duration kQazaWindow = Duration(minutes: 60);

/// One prayer on one day: its start, its windows, and its recorded outcome.
@immutable
class PrayerEntry {
  const PrayerEntry({
    required this.prayer,
    required this.scheduledAt,
    this.status = PrayerStatus.pending,
    this.completedAt,
    this.qazaCompletedAt,
  });

  final PrayerName prayer;

  /// When the prayer becomes due — a UTC instant. All windows derive from this.
  final DateTime scheduledAt;

  final PrayerStatus status;

  /// When the prayer was verified on time (null unless [PrayerStatus.completed]).
  final DateTime? completedAt;

  /// When the prayer was verified as qaza (null unless
  /// [PrayerStatus.qazaCompleted]).
  final DateTime? qazaCompletedAt;

  /// End of the on-time window. Verifying at or after this is qaza, not on time.
  DateTime get verificationDeadline => scheduledAt.add(kVerificationWindow);

  /// End of the qaza window. At or after this the prayer is permanently missed.
  DateTime get qazaDeadline =>
      scheduledAt.add(kVerificationWindow + kQazaWindow);

  /// Kept for the tracking/DB layer's `window_ends_at` column: the effective
  /// end of everything actionable is the qaza deadline.
  DateTime get windowEndsAt => qazaDeadline;

  bool isBeforeStart(DateTime now) => now.isBefore(scheduledAt);

  bool isInVerificationWindow(DateTime now) =>
      !now.isBefore(scheduledAt) && now.isBefore(verificationDeadline);

  bool isInQazaWindow(DateTime now) =>
      !now.isBefore(verificationDeadline) && now.isBefore(qazaDeadline);

  bool hasExpired(DateTime now) => !now.isBefore(qazaDeadline);

  /// The verification timestamp, whichever kind, or null if not verified.
  DateTime? get verifiedAt => completedAt ?? qazaCompletedAt;

  /// Minutes between the scheduled instant and verification, or null.
  int? get delayMinutes =>
      verifiedAt?.difference(scheduledAt).inMinutes.clamp(0, 1 << 30);

  /// The time-derived phase at [now].
  ///
  /// A recorded outcome (verified, missed, excused) is authoritative and never
  /// re-derived; only a still-pending prayer's phase is a function of the clock.
  PrayerPhase phaseAt(DateTime now) {
    switch (status) {
      case PrayerStatus.completed:
        return PrayerPhase.verifiedOnTime;
      case PrayerStatus.qazaCompleted:
        return PrayerPhase.qazaCompleted;
      case PrayerStatus.late: // legacy fulfilled — treat as qaza
        return PrayerPhase.qazaCompleted;
      case PrayerStatus.excused:
        return PrayerPhase.excused;
      case PrayerStatus.missed:
        return PrayerPhase.missed;
      case PrayerStatus.pending:
      case PrayerStatus.active: // legacy pending
        if (isBeforeStart(now)) return PrayerPhase.upcoming;
        if (isInVerificationWindow(now)) return PrayerPhase.verifyOnTime;
        if (isInQazaWindow(now)) return PrayerPhase.qazaAvailable;
        return PrayerPhase.missed;
    }
  }

  /// Time left in whichever window is currently open, or null if none is.
  Duration? remainingWindow(DateTime now) {
    final phase = phaseAt(now);
    if (phase == PrayerPhase.verifyOnTime) {
      return verificationDeadline.difference(now);
    }
    if (phase == PrayerPhase.qazaAvailable) {
      return qazaDeadline.difference(now);
    }
    return null;
  }

  PrayerEntry copyWith({
    PrayerStatus? status,
    DateTime? completedAt,
    DateTime? qazaCompletedAt,
  }) =>
      PrayerEntry(
        prayer: prayer,
        scheduledAt: scheduledAt,
        status: status ?? this.status,
        completedAt: completedAt ?? this.completedAt,
        qazaCompletedAt: qazaCompletedAt ?? this.qazaCompletedAt,
      );
}

/// A full day: five prayers with their windows, plus the queries the UI and
/// the lock orchestrator need.
@immutable
class PrayerDay {
  const PrayerDay({
    required this.date,
    required this.entries,
    required this.sunrise,
  });

  final DateTime date;
  final List<PrayerEntry> entries;

  /// Sunrise, retained for display ("Fajr is best prayed before sunrise") even
  /// though the on-time/qaza windows are now uniform 30/90-minute windows.
  final DateTime sunrise;

  factory PrayerDay.fromSchedule(
    PrayerSchedule schedule, {
    Map<PrayerName, PrayerEntry> existing = const {},
  }) {
    final entries = PrayerName.values.map((prayer) {
      final scheduledAt = schedule.prayers[prayer]!;
      // Preserve any recorded outcome across recalculation, so changing a
      // setting never erases a prayer the user already verified.
      final tracked = existing[prayer];

      return PrayerEntry(
        prayer: prayer,
        scheduledAt: scheduledAt,
        status: tracked?.status ?? PrayerStatus.pending,
        completedAt: tracked?.completedAt,
        qazaCompletedAt: tracked?.qazaCompletedAt,
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

  /// The prayer that should currently govern the lock, or null if none.
  ///
  /// With 90-minute qaza windows a previous prayer's qaza can overlap the next
  /// prayer's on-time window, so precedence matters: an on-time window (more
  /// urgent — it is about to expire into qaza) wins over a qaza window, and
  /// within each, the earliest prayer is resolved first.
  PrayerEntry? lockablePrayer(DateTime now) {
    PrayerEntry? onTime;
    PrayerEntry? qaza;

    for (final entry in entries) {
      switch (entry.phaseAt(now)) {
        case PrayerPhase.verifyOnTime:
          onTime ??= entry;
        case PrayerPhase.qazaAvailable:
          qaza ??= entry;
        default:
          break;
      }
    }

    return onTime ?? qaza;
  }

  /// The prayer the user should act on now — the same as [lockablePrayer]. Kept
  /// as a distinct name for the dashboard's "what do I do now" card.
  PrayerEntry? currentPrayer(DateTime now) => lockablePrayer(now);

  /// The next prayer that has not yet begun.
  PrayerEntry? nextPrayer(DateTime now) {
    for (final entry in entries) {
      if (entry.scheduledAt.isAfter(now)) return entry;
    }
    return null;
  }

  int get completedCount =>
      entries.where((entry) => entry.status.isFulfilled).length;

  int get remainingCount => entries.length - completedCount;

  /// Prayers verified specifically as qaza, for the dashboard summary.
  int get qazaCount => entries
      .where((entry) => entry.status == PrayerStatus.qazaCompleted)
      .length;

  /// Whether every prayer whose qaza window has closed was fulfilled.
  ///
  /// The streak spine: a day counts only when nothing was missed. A prayer
  /// still within its windows is not yet judged.
  bool isCleanSoFar(DateTime now) => !entries.any(
        (entry) => entry.hasExpired(now) && !entry.status.isFulfilled,
      );

  bool isComplete(DateTime now) =>
      entries.every((entry) => entry.status.isFulfilled);

  /// Whether Fajr is still owed and verifiable — the morning-protection gate.
  bool requiresMorningProtection(DateTime now) {
    final fajr = entryFor(PrayerName.fajr);
    return fajr.phaseAt(now).isVerifiable;
  }

  PrayerDay withEntry(PrayerEntry updated) => PrayerDay(
        date: date,
        sunrise: sunrise,
        entries: entries
            .map((entry) => entry.prayer == updated.prayer ? updated : entry)
            .toList(growable: false),
      );
}
