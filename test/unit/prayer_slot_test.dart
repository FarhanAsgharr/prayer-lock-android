/// Tests for the combined prayer engine.
///
/// The invariant that everything else depends on: **combining changes
/// presentation and enforcement, never the obligation.** Five prayers are still
/// tracked, still recorded individually, and still counted individually. A slot
/// is a view over them, not a replacement for them.
///
/// If that invariant breaks, a user who combines gets a different denominator
/// from a user who does not, and their statistics, streak and history stop
/// meaning the same thing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_window.dart';
import 'package:prayer_lock/features/sections/domain/entities/prayer_grouping.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

import '../support/prayer_fixtures.dart';

void main() {
  tz_data.initializeTimeZones();

  final day = buildDay();

  group('grouping arithmetic', () {
    test('none combines nothing', () {
      expect(PrayerGrouping.none.pairs, isEmpty);
      expect(PrayerGrouping.none.combinesAnything, isFalse);
      expect(PrayerGrouping.none.slotCount, 5);
    });

    test('each grouping reports the right slot count', () {
      expect(PrayerGrouping.dhuhrAsr.slotCount, 4);
      expect(PrayerGrouping.maghribIsha.slotCount, 4);
      expect(PrayerGrouping.both.slotCount, 3);
    });

    test('pairFor finds the pair a prayer belongs to', () {
      expect(
        PrayerGrouping.both.pairFor(PrayerName.asr),
        PrayerPair.dhuhrAsr,
      );
      expect(
        PrayerGrouping.both.pairFor(PrayerName.isha),
        PrayerPair.maghribIsha,
      );
      // Fajr is never combined — sunrise separates it from Dhuhr by hours.
      expect(PrayerGrouping.both.pairFor(PrayerName.fajr), isNull);
    });

    test('toggling reaches every grouping and never an invalid one', () {
      // The two switches in the UI are independent, so every sequence of
      // toggles must land on a representable value.
      var grouping = PrayerGrouping.none;

      grouping = grouping.toggle(PrayerPair.dhuhrAsr, enabled: true);
      expect(grouping, PrayerGrouping.dhuhrAsr);

      grouping = grouping.toggle(PrayerPair.maghribIsha, enabled: true);
      expect(grouping, PrayerGrouping.both);

      grouping = grouping.toggle(PrayerPair.dhuhrAsr, enabled: false);
      expect(grouping, PrayerGrouping.maghribIsha);

      grouping = grouping.toggle(PrayerPair.maghribIsha, enabled: false);
      expect(grouping, PrayerGrouping.none);
    });

    test('toggling is idempotent', () {
      expect(
        PrayerGrouping.both.toggle(PrayerPair.dhuhrAsr, enabled: true),
        PrayerGrouping.both,
      );
      expect(
        PrayerGrouping.none.toggle(PrayerPair.dhuhrAsr, enabled: false),
        PrayerGrouping.none,
      );
    });

    test('wire values round-trip', () {
      for (final grouping in PrayerGrouping.values) {
        expect(PrayerGrouping.fromWire(grouping.wireValue), grouping);
      }
      expect(PrayerGrouping.fromWire('nonsense'), PrayerGrouping.none);
    });
  });

  group('slot construction', () {
    test('no grouping yields five single-prayer slots', () {
      final slots = day.slots(PrayerGrouping.none);

      expect(slots, hasLength(5));
      expect(slots.every((slot) => !slot.isCombined), isTrue);
      expect(
        slots.map((slot) => slot.displayName),
        ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'],
      );
    });

    test('combining both pairs yields three slots', () {
      final slots = day.slots(PrayerGrouping.both);

      expect(slots, hasLength(3));
      expect(
        slots.map((slot) => slot.displayName),
        ['Fajr', 'Dhuhr + Asr', 'Maghrib + Isha'],
      );
    });

    test('combining one pair leaves the other separate', () {
      final slots = day.slots(PrayerGrouping.dhuhrAsr);

      expect(
        slots.map((slot) => slot.displayName),
        ['Fajr', 'Dhuhr + Asr', 'Maghrib', 'Isha'],
      );
    });

    test('slots are chronological', () {
      final slots = day.slots(PrayerGrouping.both);
      for (var i = 1; i < slots.length; i++) {
        expect(
          slots[i].window.startsAt.isAfter(slots[i - 1].window.startsAt),
          isTrue,
        );
      }
    });

    test('every prayer appears in exactly one slot, whatever the grouping', () {
      // The invariant: combining is a partition of the five prayers, never a
      // filter. A prayer dropped here would be one the user is never shown and
      // never asked to pray.
      for (final grouping in PrayerGrouping.values) {
        final covered = day
            .slots(grouping)
            .expand((slot) => slot.prayers)
            .map((entry) => entry.prayer)
            .toList();

        expect(
          covered.toSet(),
          PrayerName.values.toSet(),
          reason: '${grouping.wireValue} does not cover every prayer',
        );
        expect(
          covered.length,
          PrayerName.values.length,
          reason: '${grouping.wireValue} duplicates a prayer',
        );
      }
    });

    test('slotFor finds the slot containing a prayer', () {
      final slot = day.slotFor(PrayerName.asr, PrayerGrouping.both);
      expect(slot.displayName, 'Dhuhr + Asr');
      expect(slot.contains(PrayerName.dhuhr), isTrue);
    });
  });

  group('combined windows', () {
    test('a combined window spans both prayers', () {
      final combined = day.slotFor(PrayerName.dhuhr, PrayerGrouping.both);
      final dhuhr = day.entryFor(PrayerName.dhuhr);
      final asr = day.entryFor(PrayerName.asr);

      expect(combined.window.startsAt, dhuhr.scheduledAt);
      expect(combined.window.endsAt, asr.windowEndsAt);
    });

    test('its duration is the sum of the two', () {
      final combined = day.slotFor(PrayerName.dhuhr, PrayerGrouping.both);
      final dhuhr = day.entryFor(PrayerName.dhuhr);
      final asr = day.entryFor(PrayerName.asr);

      expect(combined.duration, dhuhr.duration + asr.duration);
    });

    test('it takes the later prayer boundary', () {
      // Dhuhr+Asr ends at Maghrib, not at Asr.
      final combined = day.slotFor(PrayerName.dhuhr, PrayerGrouping.both);
      expect(combined.window.boundary, WindowBoundary.maghrib);

      final evening = day.slotFor(PrayerName.maghrib, PrayerGrouping.both);
      expect(evening.window.boundary, WindowBoundary.nextDayFajr);
    });

    test('combined slots still do not overlap', () {
      final slots = day.slots(PrayerGrouping.both);
      for (var i = 1; i < slots.length; i++) {
        expect(
          slots[i].window.startsAt.isBefore(slots[i - 1].window.endsAt),
          isFalse,
        );
      }
    });

    test('total blocked time is unchanged by combining', () {
      // Combining joins windows that were already adjacent, so it changes how
      // many locks there are, not how long the phone is blocked.
      Duration total(PrayerGrouping grouping) => day
          .slots(grouping)
          .fold(Duration.zero, (sum, slot) => sum + slot.duration);

      expect(total(PrayerGrouping.both), total(PrayerGrouping.none));
    });
  });

  group('combined slot phase', () {
    test('is open across the whole joined window', () {
      final combined = day.slotFor(PrayerName.dhuhr, PrayerGrouping.both);
      final asr = day.entryFor(PrayerName.asr);

      // Deep inside Asr's half of the window, the slot is still open.
      final lateInAsr = asr.windowEndsAt.subtract(const Duration(minutes: 5));
      expect(combined.phaseAt(lateInAsr), PrayerPhase.verifyOnTime);
    });

    test('is owed while either prayer is owed', () {
      // Under separate verification inside a joined window, one prayer can be
      // discharged and the other not. Treating that as complete would let the
      // user skip a prayer.
      final partial = buildDay(
        statuses: {PrayerName.dhuhr: PrayerStatus.completed},
      );
      final slot = partial.slotFor(PrayerName.dhuhr, PrayerGrouping.both);

      expect(slot.isFulfilled, isFalse);
      expect(slot.outstanding.single.prayer, PrayerName.asr);
    });

    test('is fulfilled only when both prayers are', () {
      final both = buildDay(
        statuses: {
          PrayerName.dhuhr: PrayerStatus.completed,
          PrayerName.asr: PrayerStatus.completed,
        },
      );
      final slot = both.slotFor(PrayerName.dhuhr, PrayerGrouping.both);

      expect(slot.isFulfilled, isTrue);
      expect(slot.phaseAt(slot.window.startsAt), PrayerPhase.verifiedOnTime);
    });

    test('reports the weaker of two settled outcomes', () {
      // On time plus qaza is a qaza slot: a slot is only as discharged as its
      // least-discharged prayer.
      final mixed = buildDay(
        statuses: {
          PrayerName.dhuhr: PrayerStatus.qazaCompleted,
          PrayerName.asr: PrayerStatus.completed,
        },
      );
      final slot = mixed.slotFor(PrayerName.dhuhr, PrayerGrouping.both);
      expect(slot.phaseAt(slot.window.startsAt), PrayerPhase.qazaCompleted);
    });

    test('is excused only when both prayers are excused', () {
      final one = buildDay(
        statuses: {PrayerName.dhuhr: PrayerStatus.excused},
      );
      expect(
        one.slotFor(PrayerName.dhuhr, PrayerGrouping.both).isFulfilled,
        isFalse,
      );

      final bothExcused = buildDay(
        statuses: {
          PrayerName.dhuhr: PrayerStatus.excused,
          PrayerName.asr: PrayerStatus.excused,
        },
      );
      final slot = bothExcused.slotFor(PrayerName.dhuhr, PrayerGrouping.both);
      expect(slot.phaseAt(slot.window.startsAt), PrayerPhase.excused);
    });

    test('the make-up deadline is the later of the two', () {
      final combined = day.slotFor(PrayerName.dhuhr, PrayerGrouping.both);
      final asr = day.entryFor(PrayerName.asr);
      expect(combined.qazaDeadline, asr.qazaDeadline);
    });
  });

  group('slot queries on the day', () {
    test('lockableSlot prefers an open window over an older make-up', () {
      final maghrib = day.entryFor(PrayerName.maghrib);
      final at = maghrib.scheduledAt.add(const Duration(minutes: 5));

      final slot = day.lockableSlot(at, PrayerGrouping.both);
      expect(slot?.displayName, 'Maghrib + Isha');
    });

    test('activeSlot ignores whether the slot is owed', () {
      final verified = buildDay(
        statuses: {
          PrayerName.dhuhr: PrayerStatus.completed,
          PrayerName.asr: PrayerStatus.completed,
        },
      );
      final dhuhr = day.entryFor(PrayerName.dhuhr);
      final at = dhuhr.scheduledAt.add(const Duration(minutes: 30));

      expect(
        verified.activeSlot(at, PrayerGrouping.both)?.displayName,
        'Dhuhr + Asr',
      );
      expect(verified.lockableSlot(at, PrayerGrouping.both)?.displayName,
          isNot('Dhuhr + Asr'));
    });

    test('nextSlot skips a slot already open', () {
      final dhuhr = day.entryFor(PrayerName.dhuhr);
      final at = dhuhr.scheduledAt.add(const Duration(minutes: 5));

      expect(
        day.nextSlot(at, PrayerGrouping.both)?.displayName,
        'Maghrib + Isha',
      );
    });

    test('slot identity is stable and distinct', () {
      final slots = day.slots(PrayerGrouping.both);
      final ids = slots.map((slot) => slot.id).toList();

      expect(ids.toSet().length, ids.length);
      expect(ids, contains('dhuhr+asr'));
      expect(ids, contains('fajr'));
    });
  });

  group('switching modes is non-destructive', () {
    test('the underlying entries are untouched', () {
      // Grouping is applied when slots are built, so changing it re-renders the
      // day rather than rewriting it.
      final before = day.entries.map((entry) => entry.window).toList();
      day.slots(PrayerGrouping.both);
      final after = day.entries.map((entry) => entry.window).toList();

      expect(after, before);
      expect(day.entries, hasLength(5));
    });

    test('recorded outcomes survive a mode change', () {
      final recorded = buildDay(
        statuses: {PrayerName.dhuhr: PrayerStatus.completed},
      );

      for (final grouping in PrayerGrouping.values) {
        final slot = recorded.slotFor(PrayerName.dhuhr, grouping);
        expect(
          slot.prayers
              .firstWhere((entry) => entry.prayer == PrayerName.dhuhr)
              .status,
          PrayerStatus.completed,
        );
      }
    });

    test('the day still counts five prayers whatever the grouping', () {
      // The denominator that makes statistics comparable between users who
      // combine and users who do not.
      final recorded = buildDay(
        statuses: {
          PrayerName.dhuhr: PrayerStatus.completed,
          PrayerName.asr: PrayerStatus.completed,
        },
      );

      expect(recorded.entries, hasLength(5));
      expect(recorded.completedCount, 2);
      expect(recorded.remainingCount, 3);
    });
  });
}
