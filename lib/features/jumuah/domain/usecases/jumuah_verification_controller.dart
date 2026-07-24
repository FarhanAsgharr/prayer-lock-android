/// Decides what verifying a Jumu'ah slot means and records it.
///
/// Verification itself is unchanged — the same camera, the same vision check,
/// the same `PrayerStatus.completed` written against `PrayerName.dhuhr`,
/// because Jumu'ah *is* the Dhuhr obligation and must count identically in
/// history, statistics and the streak. Recording it as a sixth prayer would
/// give Friday a different denominator from every other day.
///
/// What differs is narrower and worth isolating:
///
///  * **There is no qaza.** A missed Jumu'ah is not made up as Jumu'ah; the
///    person prays Dhuhr instead. Offering "pray it as qaza" would tell the
///    user something untrue about their obligation, so the qaza path is closed
///    for a Jumu'ah slot and the UI says what to do instead.
///
///  * **The mosque is part of the record.** Which congregation the user
///    attended is worth keeping, and is what the Friday history screen shows.
library;

import '../../../prayer_times/domain/entities/prayer_slot.dart';
import '../entities/mosque_profile.dart';

/// What the app should do when the user acts on a Jumu'ah slot.
enum JumuahVerificationOutcome {
  /// Inside the window — verifying records Jumu'ah as completed.
  verifiable,

  /// The window has closed. Jumu'ah cannot be made up; Dhuhr is prayed instead.
  missedPrayDhuhrInstead,

  /// Already recorded.
  alreadyRecorded,

  /// The window has not opened yet.
  notYetOpen,
}

/// The record written when a Jumu'ah is confirmed.
class JumuahRecord {
  const JumuahRecord({
    required this.date,
    required this.mosqueId,
    required this.mosqueName,
    required this.verifiedAt,
    required this.blockDuration,
  });

  final DateTime date;
  /// The mosque attended, by id and by name at the time.
  final String mosqueId;
  final String mosqueName;
  final DateTime verifiedAt;

  /// How long apps were blocked for this congregation, for the history screen.
  final Duration blockDuration;

  Map<String, Object?> toColumns() => {
        'was_jumuah': 1,
        'jumuah_location': mosqueId,
        'jumuah_mosque_name': mosqueName,
        'jumuah_block_seconds': blockDuration.inSeconds,
      };
}

class JumuahVerificationController {
  const JumuahVerificationController();

  /// What acting on [slot] at [now] should do.
  ///
  /// Pure: the caller performs the write. Keeping the decision separate is what
  /// lets every branch — including "missed, pray Dhuhr" — be asserted without a
  /// camera or a database.
  JumuahVerificationOutcome outcomeFor({
    required PrayerSlot slot,
    required DateTime now,
  }) {
    if (!slot.isJumuah) {
      // Not a Jumuah slot; the caller should use the ordinary path.
      return JumuahVerificationOutcome.verifiable;
    }

    if (slot.isFulfilled) return JumuahVerificationOutcome.alreadyRecorded;
    if (now.isBefore(slot.window.startsAt)) {
      return JumuahVerificationOutcome.notYetOpen;
    }
    if (slot.window.contains(now)) return JumuahVerificationOutcome.verifiable;

    // Past the window. Deliberately *not* qazaAvailable: Jumu'ah has no
    // make-up form.
    return JumuahVerificationOutcome.missedPrayDhuhrInstead;
  }

  /// Whether the qaza affordance should be offered for this slot.
  ///
  /// Always false for Jumu'ah, which is the point.
  bool offersQaza(PrayerSlot slot) => !slot.isJumuah;

  /// The record to persist alongside the ordinary prayer-history write.
  JumuahRecord recordFor({
    required PrayerSlot slot,
    required DateTime date,
    required MosqueProfile mosque,
    required DateTime verifiedAt,
  }) =>
      JumuahRecord(
        date: date,
        mosqueId: mosque.id,
        mosqueName: mosque.displayName,
        verifiedAt: verifiedAt,
        // Measured from the window opening to the moment of verification —
        // what the user actually lost, not the configured length.
        blockDuration: verifiedAt.isAfter(slot.window.startsAt)
            ? verifiedAt.difference(slot.window.startsAt)
            : Duration.zero,
      );

  /// What to tell a user whose Jumu'ah window has closed.
  String missedMessage() =>
      'Jumu\'ah cannot be made up. Pray Dhuhr instead — it is still owed today.';
}
