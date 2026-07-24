/// A unit the user acts on: one prayer, or a combined pair.
///
/// This is the layer that makes combined prayers work without duplicating the
/// entire product. Underneath, five prayers are always tracked individually —
/// `PrayerEntry` per prayer, five history rows, five contributions to the
/// streak. On top, the user sees three, four or five *slots* depending on their
/// grouping, and each slot is what gets a card, a lock, a countdown and a
/// verification.
///
/// Keeping the two layers apart is what stops combining from corrupting
/// anything:
///
///   * **History stays comparable.** Someone who prays Dhuhr and Asr together
///     still gets credit for two prayers, and their statistics remain
///     meaningful if they later switch back to five separate prayers.
///
///   * **Switching modes is not destructive.** Grouping is applied when slots
///     are built, so changing it re-renders the day rather than rewriting it.
///
///   * **A slot is never the unit of record.** Nothing persists "Dhuhr+Asr" as
///     a thing that happened; two prayers happened, and they happened together.
library;

import 'package:flutter/foundation.dart';

import '../../../sections/domain/entities/prayer_grouping.dart';
import 'prayer_day.dart';
import 'prayer_enums.dart';
import 'prayer_window.dart';

/// One or two prayers treated as a single unit.
@immutable
class PrayerSlot {
  const PrayerSlot({required this.prayers, this.pair})
      : assert(prayers.length >= 1, 'A slot must contain at least one prayer'),
        assert(
          pair == null || prayers.length == 2,
          'A paired slot must contain exactly two prayers',
        );

  /// The prayers in this slot, in chronological order.
  final List<PrayerEntry> prayers;

  /// The pair this slot represents, or null when it is a single prayer.
  final PrayerPair? pair;

  /// Convenience constructor for a standalone prayer.
  factory PrayerSlot.single(PrayerEntry entry) => PrayerSlot(prayers: [entry]);

  bool get isCombined => pair != null;

  PrayerEntry get first => prayers.first;
  PrayerEntry get last => prayers.last;

  /// Stable identity, used for lock session ids and the native mirror.
  ///
  /// Derived from the constituent prayers rather than from the pair, so a slot
  /// id never depends on a setting that can change mid-session.
  String get id => prayers.map((entry) => entry.prayer.wireValue).join('+');

  /// "Dhuhr + Asr", or just "Asr".
  String get displayName =>
      pair?.displayName ?? prayers.single.prayer.displayName;

  /// The joined window: from the first prayer's start to the last one's end.
  ///
  /// For a combined pair this is exactly the union of the two windows, because
  /// they are adjacent by construction — Dhuhr's window ends where Asr's
  /// begins. There is no gap to account for.
  PrayerWindow get window => PrayerWindow(
        prayer: first.prayer,
        startsAt: first.window.startsAt,
        endsAt: last.window.endsAt,
        boundary: last.window.boundary,
        wasClamped: prayers.any((entry) => entry.window.wasClamped),
      );

  /// How long apps stay blocked for this slot.
  Duration get duration => window.duration;

  /// End of the make-up opportunity — the latest of the constituent deadlines.
  DateTime get qazaDeadline => prayers
      .map((entry) => entry.qazaDeadline)
      .reduce((a, b) => a.isAfter(b) ? a : b);

  DateTime get scheduledAt => window.startsAt;
  DateTime get windowEndsAt => window.endsAt;

  /// Whether every prayer in the slot has been discharged.
  ///
  /// All, not any: a slot with one prayer still owed is still owed. Under
  /// separate verification inside a combined window that is a reachable state,
  /// and treating it as complete would let a user skip a prayer.
  bool get isFulfilled =>
      prayers.every((entry) => entry.status.isFulfilled);

  /// Prayers in this slot that are still owed.
  List<PrayerEntry> get outstanding =>
      prayers.where((entry) => !entry.status.isFulfilled).toList(growable: false);

  /// The time-derived state of the slot.
  ///
  /// A settled outcome wins over the clock, exactly as it does for a single
  /// prayer. Where the constituent outcomes differ — one on time, one as qaza —
  /// the *weaker* is reported, because a slot is only as discharged as its
  /// least-discharged prayer.
  PrayerPhase phaseAt(DateTime now) {
    if (isFulfilled) {
      if (prayers.every((entry) => entry.status == PrayerStatus.excused)) {
        return PrayerPhase.excused;
      }
      final anyQaza = prayers.any(
        (entry) =>
            entry.status == PrayerStatus.qazaCompleted ||
            entry.status == PrayerStatus.late,
      );
      return anyQaza ? PrayerPhase.qazaCompleted : PrayerPhase.verifiedOnTime;
    }

    // Any prayer explicitly recorded missed settles the slot, even if the
    // clock has not yet reached the deadline — a recorded outcome is never
    // re-derived.
    final owed = outstanding;
    if (owed.every((entry) => entry.status == PrayerStatus.missed)) {
      return PrayerPhase.missed;
    }

    if (now.isBefore(window.startsAt)) return PrayerPhase.upcoming;
    if (window.contains(now)) return PrayerPhase.verifyOnTime;
    if (now.isBefore(qazaDeadline)) return PrayerPhase.qazaAvailable;
    return PrayerPhase.missed;
  }

  /// Time left in whichever window is open, or null if none is.
  Duration? remainingWindow(DateTime now) {
    final phase = phaseAt(now);
    if (phase == PrayerPhase.verifyOnTime) return window.endsAt.difference(now);
    if (phase == PrayerPhase.qazaAvailable) return qazaDeadline.difference(now);
    return null;
  }

  bool contains(PrayerName prayer) =>
      prayers.any((entry) => entry.prayer == prayer);

  @override
  bool operator ==(Object other) =>
      other is PrayerSlot &&
      other.id == id &&
      other.window == window &&
      other.isFulfilled == isFulfilled;

  @override
  int get hashCode => Object.hash(id, window, isFulfilled);

  @override
  String toString() => 'PrayerSlot($displayName, ${window.duration})';
}

/// Builds the slots for a day under a grouping.
///
/// Pure and separate from [PrayerDay] so the same day can be projected under a
/// different grouping without rebuilding it — which is what lets the settings
/// screen preview a mode the user has not committed to.
abstract final class PrayerSlotBuilder {
  static List<PrayerSlot> build({
    required PrayerDay day,
    required PrayerGrouping grouping,
  }) {
    final slots = <PrayerSlot>[];
    final consumed = <PrayerName>{};

    for (final entry in day.entries) {
      if (consumed.contains(entry.prayer)) continue;

      final pair = grouping.pairFor(entry.prayer);
      if (pair == null) {
        slots.add(PrayerSlot.single(entry));
        continue;
      }

      // Only the first prayer of a pair opens a slot; the second is absorbed.
      // Guarding on this rather than on position means a grouping naming a
      // pair whose prayers are not both present cannot produce a half-slot.
      if (entry.prayer != pair.first) {
        slots.add(PrayerSlot.single(entry));
        continue;
      }

      final second = day.entries
          .where((candidate) => candidate.prayer == pair.second)
          .firstOrNull;

      if (second == null) {
        slots.add(PrayerSlot.single(entry));
        continue;
      }

      slots.add(PrayerSlot(prayers: [entry, second], pair: pair));
      consumed.addAll([entry.prayer, second.prayer]);
    }

    return List.unmodifiable(slots);
  }
}
