/// A day's prayers with their dynamic windows, and the tracked outcome of each.
///
/// [DynamicDurationCalculator] produces the raw windows; this layer attaches the
/// recorded outcome and the derived "what can the user do now" phase that the
/// entire UI and the lock logic read from.
///
/// The window model, per prayer:
///   [start, end)              on-time  — verify -> Verified On Time
///   [end, dayEndsAt)          qaza     — verify -> Qaza Completed
///   >= dayEndsAt              missed   — becomes an outstanding qaza debt
///
/// where `end` is the next boundary (sunrise for Fajr, the next prayer
/// otherwise, the following Fajr for Isha) and `dayEndsAt` is the following
/// Fajr — the end of the prayer day.
///
/// Nothing here is a fixed number of minutes. Every boundary moves with the sun.
library;

import 'package:flutter/foundation.dart';

import '../../../sections/domain/entities/prayer_grouping.dart';
import '../usecases/dynamic_duration_calculator.dart';
import '../usecases/prayer_time_calculator.dart';
import 'prayer_enums.dart';
import 'prayer_slot.dart';
import 'prayer_window.dart';

/// One prayer on one day: its window, and its recorded outcome.
@immutable
class PrayerEntry {
  const PrayerEntry({
    required this.window,
    required this.dayEndsAt,
    this.status = PrayerStatus.pending,
    this.completedAt,
    this.qazaCompletedAt,
  });

  /// The computed window this prayer occupies.
  final PrayerWindow window;

  /// End of the prayer day — the following Fajr. Bounds the qaza opportunity:
  /// after this the prayer is a debt carried forward, not something that can
  /// still be made up "today".
  final DateTime dayEndsAt;

  final PrayerStatus status;

  /// When the prayer was verified on time (null unless [PrayerStatus.completed]).
  final DateTime? completedAt;

  /// When the prayer was verified as qaza (null unless
  /// [PrayerStatus.qazaCompleted]).
  final DateTime? qazaCompletedAt;

  PrayerName get prayer => window.prayer;

  /// When the prayer becomes due — a UTC instant.
  DateTime get scheduledAt => window.startsAt;

  /// When the prayer's own window closes. This is the dynamic duration boundary.
  DateTime get windowEndsAt => window.endsAt;

  /// How long apps stay blocked for this prayer under [UnlockPolicy.fullDuration].
  Duration get duration => window.duration;

  /// End of the on-time window. Verifying at or after this is qaza, not on time.
  ///
  /// Under dynamic durations this *is* the window end — there is no separate
  /// fixed grace band. Kept under the old name because the tracking schema and
  /// the backend both persist it under that column.
  DateTime get verificationDeadline => window.endsAt;

  /// End of the qaza opportunity for today.
  DateTime get qazaDeadline => dayEndsAt.isAfter(window.endsAt)
      ? dayEndsAt
      // Isha's window already runs to the following Fajr, so it has no
      // same-day qaza room; missing it produces a carried-forward debt instead.
      : window.endsAt;

  bool isBeforeStart(DateTime now) => now.isBefore(window.startsAt);

  bool isInVerificationWindow(DateTime now) => window.contains(now);

  bool isInQazaWindow(DateTime now) =>
      window.hasEnded(now) && now.isBefore(qazaDeadline);

  bool hasExpired(DateTime now) => !now.isBefore(qazaDeadline);

  /// The verification timestamp, whichever kind, or null if not verified.
  DateTime? get verifiedAt => completedAt ?? qazaCompletedAt;

  /// Minutes between the scheduled instant and verification, or null.
  int? get delayMinutes =>
      verifiedAt?.difference(window.startsAt).inMinutes.clamp(0, 1 << 30);

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
      return window.endsAt.difference(now);
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
        window: window,
        dayEndsAt: dayEndsAt,
        status: status ?? this.status,
        completedAt: completedAt ?? this.completedAt,
        qazaCompletedAt: qazaCompletedAt ?? this.qazaCompletedAt,
      );
}

/// A full day: five prayers with their dynamic windows, plus the queries the UI
/// and the lock orchestrator need.
@immutable
class PrayerDay {
  const PrayerDay({
    required this.date,
    required this.entries,
    required this.sunrise,
    required this.dayEndsAt,
  });

  final DateTime date;
  final List<PrayerEntry> entries;

  /// Sunrise — both a display value and the boundary that closes Fajr.
  final DateTime sunrise;

  /// The following Fajr: the end of the prayer day, and of Isha's window.
  final DateTime dayEndsAt;

  /// Build a day from a schedule and the following day's Fajr.
  ///
  /// [nextDayFajr] is required because Isha's duration is undefined without it.
  /// Any previously recorded outcome in [existing] is carried across, so
  /// changing a calculation method never erases a prayer the user has already
  /// verified.
  factory PrayerDay.fromSchedule(
    PrayerSchedule schedule, {
    required DateTime nextDayFajr,
    Map<PrayerName, PrayerEntry> existing = const {},
  }) {
    final daily = DynamicDurationCalculator.fromSchedule(
      schedule: schedule,
      nextDayFajr: nextDayFajr,
    );
    return PrayerDay.fromWindows(daily, existing: existing);
  }

  factory PrayerDay.fromWindows(
    DailyPrayerWindows daily, {
    Map<PrayerName, PrayerEntry> existing = const {},
  }) {
    final entries = daily.windows.map((window) {
      final tracked = existing[window.prayer];

      return PrayerEntry(
        window: window,
        dayEndsAt: daily.nextDayFajr,
        status: tracked?.status ?? PrayerStatus.pending,
        completedAt: tracked?.completedAt,
        qazaCompletedAt: tracked?.qazaCompletedAt,
      );
    }).toList(growable: false);

    return PrayerDay(
      date: daily.date,
      entries: entries,
      sunrise: daily.sunrise,
      dayEndsAt: daily.nextDayFajr,
    );
  }

  PrayerEntry entryFor(PrayerName prayer) =>
      entries.firstWhere((entry) => entry.prayer == prayer);

  /// The day projected into the units the user acts on.
  ///
  /// Under [PrayerGrouping.none] this is five single-prayer slots and every
  /// slot query below reduces to the per-prayer one. Under a grouping it is
  /// three or four, with combined pairs sharing one window, one lock and one
  /// verification.
  ///
  /// A projection, not a mutation: the underlying five entries are unchanged,
  /// so changing the grouping re-renders the day rather than rewriting it.
  List<PrayerSlot> slots(PrayerGrouping grouping) =>
      PrayerSlotBuilder.build(day: this, grouping: grouping);

  /// The slot containing [prayer] under [grouping].
  PrayerSlot slotFor(PrayerName prayer, PrayerGrouping grouping) =>
      slots(grouping).firstWhere((slot) => slot.contains(prayer));

  /// The slot that should currently govern the lock, or null if none.
  ///
  /// Same precedence as [lockablePrayer]: an open window outranks an older
  /// outstanding make-up, and among make-ups the earliest is resolved first.
  PrayerSlot? lockableSlot(DateTime now, PrayerGrouping grouping) {
    PrayerSlot? onTime;
    PrayerSlot? qaza;

    for (final slot in slots(grouping)) {
      switch (slot.phaseAt(now)) {
        case PrayerPhase.verifyOnTime:
          onTime ??= slot;
        case PrayerPhase.qazaAvailable:
          qaza ??= slot;
        default:
          break;
      }
    }

    return onTime ?? qaza;
  }

  /// The slot whose window contains [now], regardless of whether it is owed.
  PrayerSlot? activeSlot(DateTime now, PrayerGrouping grouping) {
    for (final slot in slots(grouping)) {
      if (slot.window.contains(now)) return slot;
    }
    return null;
  }

  /// The next slot that has not yet opened.
  PrayerSlot? nextSlot(DateTime now, PrayerGrouping grouping) {
    for (final slot in slots(grouping)) {
      if (slot.window.startsAt.isAfter(now)) return slot;
    }
    return null;
  }

  /// Total time the day's five windows span, for the settings preview.
  Duration get totalWindowDuration => entries.fold(
        Duration.zero,
        (total, entry) => total + entry.duration,
      );

  /// The prayer that should currently govern the lock, or null if none.
  ///
  /// Windows are non-overlapping, so at most one prayer is inside its own
  /// window at any instant. Qaza windows *do* overlap later prayers, so
  /// precedence matters: a prayer inside its own window wins over an older
  /// prayer awaiting qaza, and among qaza candidates the earliest is resolved
  /// first — a user should clear the oldest debt before the newest.
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

  /// The prayer whose window contains [now], ignoring qaza. This is the one
  /// whose duration is counting down.
  PrayerEntry? activePrayer(DateTime now) {
    for (final entry in entries) {
      if (entry.window.contains(now)) return entry;
    }
    return null;
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

  /// Prayers whose window closed unfulfilled but which can still be made up
  /// today, oldest first.
  List<PrayerEntry> outstandingQaza(DateTime now) => entries
      .where((entry) => entry.phaseAt(now) == PrayerPhase.qazaAvailable)
      .toList(growable: false);

  /// Prayers permanently missed — the qaza opportunity has closed too.
  List<PrayerEntry> missedPrayers(DateTime now) => entries
      .where((entry) => entry.phaseAt(now) == PrayerPhase.missed)
      .toList(growable: false);

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
        dayEndsAt: dayEndsAt,
        entries: entries
            .map((entry) => entry.prayer == updated.prayer ? updated : entry)
            .toList(growable: false),
      );
}
