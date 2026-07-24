/// Decides whether apps should be locked right now, and until when.
///
/// Pure and free of I/O so every rule can be tested without a device. The
/// orchestrator does the acting; this decides. Keeping them apart is what
/// makes the enforcement rules — which are the ones that can genuinely upset
/// someone if wrong — exhaustively testable.
///
/// Under dynamic durations this function answers two questions, not one:
/// *should* apps be locked, and *until what instant*. The second answer is what
/// lets the platform schedule a single exact alarm to release the lock instead
/// of polling for the end of a three-hour window.
library;

import 'package:flutter/foundation.dart';

import '../../../prayer_times/domain/entities/prayer_day.dart';
import '../../../prayer_times/domain/entities/prayer_enums.dart';
import '../../../prayer_times/domain/entities/prayer_slot.dart';
import '../../../settings/domain/entities/app_settings.dart';

/// Why apps are, or are not, locked.
enum LockReason {
  /// Blocking is switched off entirely.
  disabledBySettings,

  /// No prayer is currently owed.
  noPrayerDue,

  /// The prayer has begun but the grace period has not elapsed.
  withinGracePeriod,

  /// The prayer was already completed or excused.
  prayerFulfilled,

  /// The user spent an emergency unlock for this session.
  emergencyUnlocked,

  /// No apps are selected, so a lock would do nothing.
  noAppsSelected,

  /// Apps should be locked because the prayer's window is open and it has not
  /// been verified.
  prayerActive,

  /// Apps should be locked for the remainder of the computed window even though
  /// the prayer is verified — [UnlockPolicy.fullDuration].
  durationRemaining,

  /// A prayer's window closed unfulfilled and qaza enforcement is switched on.
  qazaOutstanding,

  /// Apps should be locked by the post-Fajr morning gate.
  morningProtection,
}

@immutable
class LockDecision {
  const LockDecision({
    required this.shouldLock,
    required this.reason,
    this.prayer,
    this.isMorningProtection = false,
    this.lockUntil,
    this.windowDuration,
    this.prayers = const [],
    this.slotName,
    this.isJumuah = false,
  });

  /// A decision derived from a slot, so the two can never disagree about which
  /// prayers a lock covers.
  factory LockDecision.forSlot({
    required bool shouldLock,
    required LockReason reason,
    required PrayerSlot slot,
    DateTime? lockUntil,
    bool isMorningProtection = false,
  }) =>
      LockDecision(
        shouldLock: shouldLock,
        reason: reason,
        prayer: slot.first.prayer,
        prayers: slot.prayers.map((entry) => entry.prayer).toList(),
        slotName: slot.displayName,
        lockUntil: lockUntil,
        windowDuration: slot.duration,
        isMorningProtection: isMorningProtection,
        isJumuah: slot.isJumuah,
      );

  final bool shouldLock;
  final LockReason reason;

  /// The prayer that opened the governing slot.
  ///
  /// For a combined slot this is the first of the pair — Dhuhr for Dhuhr+Asr.
  /// Enough to identify the slot, since a pair is uniquely determined by its
  /// first prayer.
  final PrayerName? prayer;

  final bool isMorningProtection;

  /// Every prayer the governing slot covers.
  ///
  /// One prayer normally; two under a combined grouping. Carried so releasing a
  /// lock and recording a verification act on the whole slot rather than on
  /// whichever prayer happened to name it.
  final List<PrayerName> prayers;

  /// The slot's display name — "Dhuhr + Asr" or "Asr".
  final String? slotName;

  /// Whether the governing slot is the Friday congregation.
  ///
  /// Carried on the decision rather than re-derived by each consumer, so the
  /// lock, the notification and the silence behaviour all agree about whether
  /// this is Jumu'ah.
  final bool isJumuah;

  /// The instant the lock is expected to release on its own, if any.
  ///
  /// Drives the exact alarm that ends the block, and the countdown the lock
  /// screen shows. Null when release depends on the user acting rather than on
  /// the clock.
  final DateTime? lockUntil;

  /// The full computed duration of the governing prayer's window, for display.
  final Duration? windowDuration;

  const LockDecision.unlocked(LockReason reason)
      : shouldLock = false,
        reason = reason,
        prayer = null,
        isMorningProtection = false,
        lockUntil = null,
        windowDuration = null,
        prayers = const [],
        slotName = null,
        isJumuah = false;

  /// Whether the governing slot joins two prayers.
  bool get isCombined => prayers.length > 1;

  /// Time left before the lock lifts by itself, or null if it will not.
  Duration? remainingAt(DateTime now) {
    final until = lockUntil;
    if (until == null) return null;
    final remaining = until.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }
}

abstract final class LockDecisionMaker {
  /// Decide the lock state for [now].
  ///
  /// [emergencyUnlockedPrayers] holds prayers the user has bought out of with
  /// an emergency unlock; they must not be re-locked for the same prayer, or
  /// the unlock would be worthless.
  static LockDecision decide({
    required AppSettings settings,
    required PrayerDay? day,
    required DateTime now,
    Set<PrayerName> emergencyUnlockedPrayers = const {},
  }) {
    if (!settings.blockingEnabled) {
      return const LockDecision.unlocked(LockReason.disabledBySettings);
    }

    // A lock with nothing to block is pure downside: the user sees a
    // persistent notification and gains nothing.
    if (settings.blockedPackages.isEmpty) {
      return const LockDecision.unlocked(LockReason.noAppsSelected);
    }

    if (day == null) {
      return const LockDecision.unlocked(LockReason.noPrayerDue);
    }

    // Everything below reasons about *slots*: one prayer normally, a joined
    // pair under a combined grouping. With no grouping every slot holds a
    // single prayer and this reduces exactly to the per-prayer logic.
    final grouping = settings.prayerGrouping;

    // Morning protection takes precedence: while Fajr is still owed and
    // verifiable, the gate applies. Fajr is never part of a pair, so its slot
    // is always the single prayer.
    final fajrSlot = day.slotFor(PrayerName.fajr, grouping);
    final morningGateApplies = settings.morningProtectionEnabled &&
        day.requiresMorningProtection(now) &&
        !emergencyUnlockedPrayers.contains(PrayerName.fajr);

    if (morningGateApplies) {
      // The grace period still applies, so an alarm going off at Fajr does not
      // instantly lock a half-asleep user out of their phone.
      if (_isWithinGrace(fajrSlot, now, settings)) {
        return LockDecision.forSlot(
          shouldLock: false,
          reason: LockReason.withinGracePeriod,
          slot: fajrSlot,
          lockUntil: _graceEnd(fajrSlot, settings),
        );
      }
      return LockDecision.forSlot(
        shouldLock: true,
        reason: LockReason.morningProtection,
        slot: fajrSlot,
        isMorningProtection: true,
        // Fajr's gate cannot outlive Fajr's own make-up opportunity.
        lockUntil: fajrSlot.qazaDeadline,
      );
    }

    // Mode B: the window itself holds the lock, verified or not. Checked before
    // the "is anything owed" path because a verified prayer is no longer owed
    // yet must still block under this policy.
    if (settings.unlockPolicy == UnlockPolicy.fullDuration) {
      final active = day.activeSlot(now, grouping);
      if (active != null &&
          !_isEmergencyUnlocked(active, emergencyUnlockedPrayers) &&
          !_isWithinGrace(active, now, settings) &&
          !_isFullyExcused(active)) {
        return LockDecision.forSlot(
          shouldLock: true,
          reason: active.isFulfilled
              ? LockReason.durationRemaining
              : LockReason.prayerActive,
          slot: active,
          lockUntil: active.windowEndsAt,
        );
      }
    }

    // The slot currently owed: one whose window is open, or whose window has
    // closed but which can still be made up today.
    final current = day.lockableSlot(now, grouping);
    if (current == null) {
      // Nothing is owed. This covers both "no prayer active right now" and
      // "the active window belongs to a slot already verified or missed".
      return const LockDecision.unlocked(LockReason.noPrayerDue);
    }

    // An emergency unlock spent on any prayer in a slot releases the whole
    // slot. The alternative — re-locking for the paired prayer moments later —
    // would make the unlock worthless, which is exactly what it must not be.
    if (_isEmergencyUnlocked(current, emergencyUnlockedPrayers)) {
      return LockDecision.forSlot(
        shouldLock: false,
        reason: LockReason.emergencyUnlocked,
        slot: current,
      );
    }

    if (_isWithinGrace(current, now, settings)) {
      return LockDecision.forSlot(
        shouldLock: false,
        reason: LockReason.withinGracePeriod,
        slot: current,
        lockUntil: _graceEnd(current, settings),
      );
    }

    final phase = current.phaseAt(now);

    // A slot past its window is a make-up debt. Enforcing the block through
    // that period is opt-in: with dynamic durations a missed Fajr would
    // otherwise keep the phone locked from sunrise until the following dawn,
    // which is a punishment few users would accept by default.
    if (phase == PrayerPhase.qazaAvailable &&
        !settings.blockUntilQazaCompleted) {
      return LockDecision.forSlot(
        shouldLock: false,
        reason: LockReason.noPrayerDue,
        slot: current,
      );
    }

    return LockDecision.forSlot(
      shouldLock: true,
      reason: phase == PrayerPhase.qazaAvailable
          ? LockReason.qazaOutstanding
          : LockReason.prayerActive,
      slot: current,
      lockUntil: phase == PrayerPhase.qazaAvailable
          ? current.qazaDeadline
          : current.windowEndsAt,
    );
  }

  /// Whether the user has bought out of any prayer in [slot].
  static bool _isEmergencyUnlocked(
    PrayerSlot slot,
    Set<PrayerName> unlocked,
  ) =>
      slot.prayers.any((entry) => unlocked.contains(entry.prayer));

  /// Whether every prayer in [slot] is marked exempt.
  ///
  /// All, not any: someone exempt from one prayer of a pair still owes the
  /// other, so the window must keep holding.
  static bool _isFullyExcused(PrayerSlot slot) =>
      slot.prayers.every((entry) => entry.status == PrayerStatus.excused);

  /// Whether the configured grace period after the adhan is still running.
  ///
  /// Exists so a user mid-conversation or mid-commute is not cut off the
  /// instant the adhan sounds. Applies only inside the prayer's own window: a
  /// qaza debt has already had its whole window to be discharged, so granting
  /// another grace period on top would just delay enforcement twice.
  static bool _isWithinGrace(
    PrayerSlot slot,
    DateTime now,
    AppSettings settings,
  ) {
    if (settings.lockGracePeriodMinutes <= 0) return false;
    if (!slot.window.contains(now)) return false;

    return now.isBefore(_graceEnd(slot, settings)!);
  }

  /// End of the grace period, clamped to the window: a grace period longer than
  /// the window itself would mean the lock never engages for that slot.
  ///
  /// Measured from the slot's start, not from each constituent prayer. A
  /// combined Dhuhr+Asr slot gets one grace period at Dhuhr, not a second one
  /// when Asr's time arrives — the user was already given their warning, and
  /// re-granting it mid-window would release a lock that is meant to hold.
  static DateTime? _graceEnd(PrayerSlot slot, AppSettings settings) {
    if (settings.lockGracePeriodMinutes <= 0) return slot.scheduledAt;

    final graceEnds = slot.scheduledAt.add(
      Duration(minutes: settings.lockGracePeriodMinutes),
    );
    return graceEnds.isAfter(slot.windowEndsAt)
        ? slot.windowEndsAt
        : graceEnds;
  }

  /// Every instant at which the decision could change, in ascending order.
  ///
  /// The scheduler turns these into exact alarms. Deriving them here rather
  /// than in the scheduler keeps a single definition of "when does something
  /// happen" — a schedule that disagrees with the decision function is how a
  /// lock ends up engaging with no alarm to release it.
  static List<DateTime> transitionInstants({
    required AppSettings settings,
    required PrayerDay? day,
    required DateTime now,
  }) {
    if (!settings.blockingEnabled || day == null) return const [];

    final instants = <DateTime>{};

    // Derived from slots, so a combined pair contributes one start and one end
    // rather than two of each. Arming an alarm at Asr's start inside a joined
    // Dhuhr+Asr window would wake the device to discover that nothing changed.
    for (final slot in day.slots(settings.prayerGrouping)) {
      // Window start, so the lock engages the moment the slot begins.
      instants.add(slot.scheduledAt);

      // End of the grace period, when the lock actually bites.
      final graceEnd = _graceEnd(slot, settings);
      if (graceEnd != null) instants.add(graceEnd);

      // Window end: the release point under every policy, and the moment an
      // unfulfilled slot becomes a make-up debt.
      instants.add(slot.windowEndsAt);

      // End of the make-up opportunity, only meaningful when that enforcement
      // is on — otherwise nothing changes at that instant.
      if (settings.blockUntilQazaCompleted) {
        instants.add(slot.qazaDeadline);
      }
    }

    final future = instants.where((instant) => instant.isAfter(now)).toList()
      ..sort();
    return List.unmodifiable(future);
  }

  /// When the lock should next engage, so the orchestrator can schedule a
  /// wake-up instead of polling continuously.
  static DateTime? nextLockTransition({
    required AppSettings settings,
    required PrayerDay? day,
    required DateTime now,
  }) {
    final instants = transitionInstants(
      settings: settings,
      day: day,
      now: now,
    );
    return instants.isEmpty ? null : instants.first;
  }
}
