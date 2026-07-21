/// Decides whether apps should be locked right now.
///
/// Pure and free of I/O so every rule can be tested without a device. The
/// orchestrator does the acting; this decides. Keeping them apart is what
/// makes the enforcement rules — which are the ones that can genuinely upset
/// someone if wrong — exhaustively testable.
library;

import 'package:flutter/foundation.dart';

import '../../../prayer_times/domain/entities/prayer_day.dart';
import '../../../prayer_times/domain/entities/prayer_enums.dart';
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

  /// Apps should be locked for the current prayer.
  prayerActive,

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
  });

  final bool shouldLock;
  final LockReason reason;
  final PrayerName? prayer;
  final bool isMorningProtection;

  const LockDecision.unlocked(LockReason reason)
      : shouldLock = false,
        reason = reason,
        prayer = null,
        isMorningProtection = false;
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

    // Morning protection takes precedence: after Fajr begins, the gate applies
    // until Fajr is prayed, even though Fajr is also the "current" prayer.
    final fajr = day.entryFor(PrayerName.fajr);
    final morningGateApplies = settings.morningProtectionEnabled &&
        day.requiresMorningProtection(now) &&
        !emergencyUnlockedPrayers.contains(PrayerName.fajr);

    if (morningGateApplies) {
      // The grace period still applies, so an alarm going off at Fajr does not
      // instantly lock a half-asleep user out of their phone.
      if (_isWithinGrace(fajr, now, settings)) {
        return const LockDecision.unlocked(LockReason.withinGracePeriod);
      }
      return const LockDecision(
        shouldLock: true,
        reason: LockReason.morningProtection,
        prayer: PrayerName.fajr,
        isMorningProtection: true,
      );
    }

    // Uses entryInWindow rather than currentPrayer so a fulfilled prayer can
    // be reported as "already prayed" instead of "nothing due" — the same
    // unlocked outcome, but a message the user can actually act on.
    final current = day.entryInWindow(now);
    if (current == null) {
      return const LockDecision.unlocked(LockReason.noPrayerDue);
    }

    if (current.status.isFulfilled) {
      return const LockDecision.unlocked(LockReason.prayerFulfilled);
    }

    if (emergencyUnlockedPrayers.contains(current.prayer)) {
      return const LockDecision.unlocked(LockReason.emergencyUnlocked);
    }

    if (_isWithinGrace(current, now, settings)) {
      return const LockDecision.unlocked(LockReason.withinGracePeriod);
    }

    return LockDecision(
      shouldLock: true,
      reason: LockReason.prayerActive,
      prayer: current.prayer,
    );
  }

  /// Whether the configured grace period after the adhan is still running.
  ///
  /// Exists so a user mid-conversation or mid-commute is not cut off the
  /// instant the adhan sounds.
  static bool _isWithinGrace(
    PrayerEntry entry,
    DateTime now,
    AppSettings settings,
  ) {
    if (settings.lockGracePeriodMinutes <= 0) return false;

    final graceEnds = entry.scheduledAt.add(
      Duration(minutes: settings.lockGracePeriodMinutes),
    );
    return now.isBefore(graceEnds);
  }

  /// When the lock should next engage, so the orchestrator can schedule a
  /// wake-up instead of polling continuously.
  static DateTime? nextLockTransition({
    required AppSettings settings,
    required PrayerDay? day,
    required DateTime now,
  }) {
    if (!settings.blockingEnabled || day == null) return null;

    for (final entry in day.entries) {
      if (entry.status.isFulfilled) continue;

      final engagesAt = entry.scheduledAt.add(
        Duration(minutes: settings.lockGracePeriodMinutes),
      );
      if (engagesAt.isAfter(now)) return engagesAt;
    }

    return null;
  }
}
