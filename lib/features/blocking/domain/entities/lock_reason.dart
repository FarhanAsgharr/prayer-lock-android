/// Why apps are, or are not, locked.
///
/// Its own file because it is referenced from three layers — the strategies
/// that produce it, the use case that assembles it, and the lock screen that
/// renders it. Leaving it inside the use case made the strategies import their
/// own consumer.
library;

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
