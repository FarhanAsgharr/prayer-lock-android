/// Tests for prayer window and status logic.
///
/// This is where the product's correctness actually lives: whether a prayer
/// counts as on time, missed, or still owed determines when the phone locks
/// and what the user's history says about them.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_day.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:prayer_lock/features/prayer_times/domain/usecases/prayer_time_calculator.dart';

/// A schedule for Makkah, which has no DST and moderate day length — so the
/// assertions test the logic rather than an edge case.
PrayerDay buildDay({
  DateTime? date,
  Map<PrayerName, PrayerEntry> existing = const {},
}) {
  final target = date ?? DateTime(2026, 7, 20);

  CalculationRequest requestFor(DateTime day) => CalculationRequest(
        latitude: 21.4225,
        longitude: 39.8262,
        utcOffsetHours: 3,
        prayerDate: day,
      );

  final today = prayerTimeCalculator.calculate(requestFor(target));
  final tomorrow = prayerTimeCalculator
      .calculate(requestFor(target.add(const Duration(days: 1))));

  return PrayerDay.fromSchedule(
    today,
    nextDayFajr: tomorrow.fajr,
    existing: existing,
  );
}

void main() {
  group('prayer windows', () {
    test('Fajr expires at sunrise, not at Dhuhr', () {
      // The single most commonly wrong rule in prayer apps. Fajr prayed after
      // sunrise is qada, not adaa, and treating Dhuhr as the boundary would
      // silently record missed Fajrs as on time.
      final day = buildDay();
      final fajr = day.entryFor(PrayerName.fajr);

      expect(fajr.windowEndsAt, equals(day.sunrise));
      expect(fajr.windowEndsAt.isBefore(day.entryFor(PrayerName.dhuhr).scheduledAt), isTrue);
    });

    test('each prayer window ends when the next begins', () {
      final day = buildDay();

      expect(
        day.entryFor(PrayerName.dhuhr).windowEndsAt,
        equals(day.entryFor(PrayerName.asr).scheduledAt),
      );
      expect(
        day.entryFor(PrayerName.asr).windowEndsAt,
        equals(day.entryFor(PrayerName.maghrib).scheduledAt),
      );
      expect(
        day.entryFor(PrayerName.maghrib).windowEndsAt,
        equals(day.entryFor(PrayerName.isha).scheduledAt),
      );
    });

    test("Isha's window runs into the following day's Fajr", () {
      // Not midnight: Isha remains valid past 00:00 until Fajr begins.
      final day = buildDay();
      final isha = day.entryFor(PrayerName.isha);

      expect(isha.windowEndsAt.isAfter(isha.scheduledAt), isTrue);
      expect(
        isha.windowEndsAt.difference(isha.scheduledAt).inHours,
        greaterThan(6),
      );
    });
  });

  group('status derivation', () {
    test('is pending before the prayer begins', () {
      final day = buildDay();
      final dhuhr = day.entryFor(PrayerName.dhuhr);

      final before = dhuhr.scheduledAt.subtract(const Duration(minutes: 1));
      expect(dhuhr.statusAt(before), PrayerStatus.pending);
    });

    test('is active inside the window', () {
      final day = buildDay();
      final dhuhr = day.entryFor(PrayerName.dhuhr);

      final during = dhuhr.scheduledAt.add(const Duration(minutes: 30));
      expect(dhuhr.statusAt(during), PrayerStatus.active);
    });

    test('becomes missed once the window closes', () {
      // Must be derived from the clock, not stored: a prayer left untouched
      // would otherwise read as "pending" forever.
      final day = buildDay();
      final dhuhr = day.entryFor(PrayerName.dhuhr);

      final after = dhuhr.windowEndsAt.add(const Duration(minutes: 1));
      expect(dhuhr.statusAt(after), PrayerStatus.missed);
    });

    test('a fulfilled status is never overwritten by the clock', () {
      final day = buildDay();
      final completed = day
          .entryFor(PrayerName.dhuhr)
          .copyWith(status: PrayerStatus.completed);

      final longAfter = completed.windowEndsAt.add(const Duration(days: 2));
      expect(completed.statusAt(longAfter), PrayerStatus.completed);
    });

    test('a late completion stays late', () {
      final day = buildDay();
      final late =
          day.entryFor(PrayerName.fajr).copyWith(status: PrayerStatus.late);

      expect(late.statusAt(DateTime.utc(2030)), PrayerStatus.late);
      expect(late.status.isFulfilled, isTrue);
    });

    test('excused counts as fulfilled', () {
      // Travel, illness and menstruation are exemptions, not failures, and
      // must not damage a streak.
      expect(PrayerStatus.excused.isFulfilled, isTrue);
    });
  });

  group('current and next prayer', () {
    test('returns the prayer whose window is open', () {
      final day = buildDay();
      final asr = day.entryFor(PrayerName.asr);

      final during = asr.scheduledAt.add(const Duration(minutes: 5));
      expect(day.currentPrayer(during)?.prayer, PrayerName.asr);
    });

    test('returns nothing in the gap between sunrise and Dhuhr', () {
      // A genuine gap during which nothing is owed. Reporting Dhuhr as active
      // here would lock the user's phone hours before Dhuhr.
      final day = buildDay();
      final midMorning = day.sunrise.add(const Duration(hours: 1));

      expect(day.currentPrayer(midMorning), isNull);
    });

    test('a completed prayer is not reported as current', () {
      final day = buildDay();
      final asr = day.entryFor(PrayerName.asr);
      final updated =
          day.withEntry(asr.copyWith(status: PrayerStatus.completed));

      final during = asr.scheduledAt.add(const Duration(minutes: 5));
      expect(updated.currentPrayer(during), isNull);
    });

    test('next prayer is the next to begin', () {
      final day = buildDay();
      final dhuhr = day.entryFor(PrayerName.dhuhr);

      final before = dhuhr.scheduledAt.subtract(const Duration(minutes: 10));
      expect(day.nextPrayer(before)?.prayer, PrayerName.dhuhr);
    });

    test('there is no next prayer after Isha begins', () {
      final day = buildDay();
      final afterIsha = day
          .entryFor(PrayerName.isha)
          .scheduledAt
          .add(const Duration(minutes: 1));

      expect(day.nextPrayer(afterIsha), isNull);
    });
  });

  group('daily progress', () {
    test('counts completed and remaining', () {
      final day = buildDay();
      expect(day.completedCount, 0);
      expect(day.remainingCount, 5);

      final updated = day.withEntry(
        day.entryFor(PrayerName.fajr).copyWith(status: PrayerStatus.completed),
      );
      expect(updated.completedCount, 1);
      expect(updated.remainingCount, 4);
    });

    test('a day is clean while still in progress', () {
      final day = buildDay();
      final beforeFajr =
          day.entryFor(PrayerName.fajr).scheduledAt.subtract(const Duration(hours: 1));

      expect(day.isCleanSoFar(beforeFajr), isTrue);
    });

    test('a day stops being clean once a window closes unfulfilled', () {
      final day = buildDay();
      final afterFajrExpired = day.sunrise.add(const Duration(minutes: 1));

      expect(day.isCleanSoFar(afterFajrExpired), isFalse);
    });

    test('a day stays clean when the expired prayer was completed', () {
      final day = buildDay();
      final updated = day.withEntry(
        day.entryFor(PrayerName.fajr).copyWith(status: PrayerStatus.completed),
      );

      final afterFajrExpired = day.sunrise.add(const Duration(minutes: 1));
      expect(updated.isCleanSoFar(afterFajrExpired), isTrue);
    });
  });

  group('morning protection', () {
    test('is active while Fajr is due and unfulfilled', () {
      final day = buildDay();
      final duringFajr = day
          .entryFor(PrayerName.fajr)
          .scheduledAt
          .add(const Duration(minutes: 10));

      expect(day.requiresMorningProtection(duringFajr), isTrue);
    });

    test('lifts once Fajr is completed', () {
      final day = buildDay();
      final updated = day.withEntry(
        day.entryFor(PrayerName.fajr).copyWith(status: PrayerStatus.completed),
      );
      final duringFajr = day
          .entryFor(PrayerName.fajr)
          .scheduledAt
          .add(const Duration(minutes: 10));

      expect(updated.requiresMorningProtection(duringFajr), isFalse);
    });

    test('lifts after sunrise even if Fajr was missed', () {
      // Holding someone's phone hostage all day for a missed Fajr would be
      // punitive rather than helpful, so the gate expires with the window.
      final day = buildDay();
      final afterSunrise = day.sunrise.add(const Duration(minutes: 1));

      expect(day.requiresMorningProtection(afterSunrise), isFalse);
    });
  });

  group('state preservation', () {
    test('recalculating a schedule keeps tracked completions', () {
      // A user who changes calculation method at noon must not lose the Fajr
      // they already prayed.
      final original = buildDay();
      final completedFajr = original
          .entryFor(PrayerName.fajr)
          .copyWith(status: PrayerStatus.completed);

      final rebuilt = buildDay(existing: {PrayerName.fajr: completedFajr});

      expect(
        rebuilt.entryFor(PrayerName.fajr).status,
        PrayerStatus.completed,
      );
      expect(rebuilt.completedCount, 1);
    });
  });
}
