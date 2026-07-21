/// Tests for the verification-window / qaza / missed model.
///
/// This is where the product's correctness lives: whether a prayer is
/// verifiable on time, verifiable as qaza, or permanently missed determines
/// when the phone locks and what the user's history says about them.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_day.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:prayer_lock/features/prayer_times/domain/usecases/prayer_time_calculator.dart';

PrayerDay buildDay({Map<PrayerName, PrayerEntry> existing = const {}}) {
  const date = (year: 2026, month: 7, day: 20);
  final schedule = prayerTimeCalculator.calculate(
    CalculationRequest(
      latitude: 21.4225,
      longitude: 39.8262,
      utcOffsetHours: 3,
      prayerDate: DateTime(date.year, date.month, date.day),
    ),
  );
  return PrayerDay.fromSchedule(schedule, existing: existing);
}

void main() {
  final day = buildDay();
  final dhuhr = day.entryFor(PrayerName.dhuhr);

  group('window boundaries', () {
    test('the on-time window is exactly 30 minutes', () {
      expect(
        dhuhr.verificationDeadline.difference(dhuhr.scheduledAt),
        const Duration(minutes: 30),
      );
    });

    test('the qaza window ends 90 minutes after the prayer starts', () {
      expect(
        dhuhr.qazaDeadline.difference(dhuhr.scheduledAt),
        const Duration(minutes: 90),
      );
    });

    test('every prayer uses the same uniform windows', () {
      for (final entry in day.entries) {
        expect(entry.verificationDeadline,
            entry.scheduledAt.add(const Duration(minutes: 30)));
        expect(entry.qazaDeadline,
            entry.scheduledAt.add(const Duration(minutes: 90)));
      }
    });
  });

  group('phase derivation', () {
    test('is upcoming before the prayer starts', () {
      final before = dhuhr.scheduledAt.subtract(const Duration(minutes: 1));
      expect(dhuhr.phaseAt(before), PrayerPhase.upcoming);
    });

    test('is verifyOnTime within the first 30 minutes', () {
      expect(
        dhuhr.phaseAt(dhuhr.scheduledAt),
        PrayerPhase.verifyOnTime,
      );
      expect(
        dhuhr.phaseAt(dhuhr.scheduledAt.add(const Duration(minutes: 29))),
        PrayerPhase.verifyOnTime,
      );
    });

    test('becomes qazaAvailable exactly at the 30-minute mark', () {
      expect(
        dhuhr.phaseAt(dhuhr.scheduledAt.add(const Duration(minutes: 30))),
        PrayerPhase.qazaAvailable,
      );
      expect(
        dhuhr.phaseAt(dhuhr.scheduledAt.add(const Duration(minutes: 89))),
        PrayerPhase.qazaAvailable,
      );
    });

    test('becomes missed exactly at the 90-minute mark', () {
      expect(
        dhuhr.phaseAt(dhuhr.scheduledAt.add(const Duration(minutes: 90))),
        PrayerPhase.missed,
      );
      expect(
        dhuhr.phaseAt(dhuhr.scheduledAt.add(const Duration(hours: 5))),
        PrayerPhase.missed,
      );
    });

    test('a recorded on-time completion is never re-derived', () {
      final completed =
          dhuhr.copyWith(status: PrayerStatus.completed);
      // Even far in the future, a completed prayer stays verified on time.
      expect(
        completed.phaseAt(dhuhr.scheduledAt.add(const Duration(days: 2))),
        PrayerPhase.verifiedOnTime,
      );
    });

    test('a recorded qaza completion stays qaza', () {
      final qaza = dhuhr.copyWith(status: PrayerStatus.qazaCompleted);
      expect(qaza.phaseAt(DateTime.utc(2030)), PrayerPhase.qazaCompleted);
    });

    test('a recorded miss stays missed even mid-window in a replay', () {
      final missed = dhuhr.copyWith(status: PrayerStatus.missed);
      // A stale replay must not resurrect a missed prayer into verifiable.
      expect(missed.phaseAt(dhuhr.scheduledAt), PrayerPhase.missed);
    });
  });

  group('verifiability', () {
    test('only the on-time and qaza phases are verifiable', () {
      expect(PrayerPhase.verifyOnTime.isVerifiable, isTrue);
      expect(PrayerPhase.qazaAvailable.isVerifiable, isTrue);
      expect(PrayerPhase.upcoming.isVerifiable, isFalse);
      expect(PrayerPhase.verifiedOnTime.isVerifiable, isFalse);
      expect(PrayerPhase.qazaCompleted.isVerifiable, isFalse);
      expect(PrayerPhase.missed.isVerifiable, isFalse);
      expect(PrayerPhase.excused.isVerifiable, isFalse);
    });

    test('excused counts as fulfilled', () {
      expect(PrayerStatus.excused.isFulfilled, isTrue);
    });

    test('qaza counts as fulfilled', () {
      // A make-up prayer keeps the streak — only a true miss breaks it.
      expect(PrayerStatus.qazaCompleted.isFulfilled, isTrue);
    });

    test('missed is not fulfilled', () {
      expect(PrayerStatus.missed.isFulfilled, isFalse);
    });
  });

  group('remaining window countdown', () {
    test('reports on-time remaining during the on-time window', () {
      final at = dhuhr.scheduledAt.add(const Duration(minutes: 10));
      expect(dhuhr.remainingWindow(at), const Duration(minutes: 20));
    });

    test('reports qaza remaining during the qaza window', () {
      final at = dhuhr.scheduledAt.add(const Duration(minutes: 45));
      expect(dhuhr.remainingWindow(at), const Duration(minutes: 45));
    });

    test('is null when no window is open', () {
      expect(dhuhr.remainingWindow(dhuhr.qazaDeadline), isNull);
      expect(
        dhuhr.remainingWindow(dhuhr.scheduledAt.subtract(const Duration(minutes: 1))),
        isNull,
      );
    });
  });

  group('lockable prayer', () {
    test('is the prayer whose on-time window is open', () {
      final at = dhuhr.scheduledAt.add(const Duration(minutes: 5));
      expect(day.lockablePrayer(at)?.prayer, PrayerName.dhuhr);
    });

    test('is the prayer whose qaza window is open', () {
      final at = dhuhr.scheduledAt.add(const Duration(minutes: 45));
      expect(day.lockablePrayer(at)?.prayer, PrayerName.dhuhr);
    });

    test('is null once the prayer is verified', () {
      final at = dhuhr.scheduledAt.add(const Duration(minutes: 5));
      final updated =
          day.withEntry(dhuhr.copyWith(status: PrayerStatus.completed));
      expect(updated.lockablePrayer(at), isNull);
    });

    test('is null once the prayer is missed', () {
      final at = dhuhr.qazaDeadline.add(const Duration(minutes: 1));
      expect(day.lockablePrayer(at), isNull);
    });

    test('prefers an on-time window over an overlapping qaza window', () {
      // Construct an artificial overlap: prayer A in qaza, prayer B on time.
      final start = DateTime.utc(2026, 7, 20, 19, 0);
      final maghrib =
          PrayerEntry(prayer: PrayerName.maghrib, scheduledAt: start);
      // Isha 40 min later: at now = start+45, maghrib is in qaza (30-90),
      // isha is on-time (0-30).
      final isha = PrayerEntry(
        prayer: PrayerName.isha,
        scheduledAt: start.add(const Duration(minutes: 40)),
      );
      final overlapDay = PrayerDay(
        date: DateTime(2026, 7, 20),
        sunrise: start,
        entries: [maghrib, isha],
      );

      final at = start.add(const Duration(minutes: 45));
      // Maghrib qaza and Isha on-time both open; the on-time Isha wins because
      // it is the more urgent (about to slip into qaza itself).
      expect(overlapDay.lockablePrayer(at)?.prayer, PrayerName.isha);
    });
  });

  group('daily aggregates', () {
    test('counts fulfilled across on-time, qaza and excused', () {
      final updated = day
          .withEntry(day.entryFor(PrayerName.fajr).copyWith(
              status: PrayerStatus.completed))
          .withEntry(day.entryFor(PrayerName.dhuhr).copyWith(
              status: PrayerStatus.qazaCompleted))
          .withEntry(day.entryFor(PrayerName.asr).copyWith(
              status: PrayerStatus.excused));

      expect(updated.completedCount, 3);
      expect(updated.qazaCount, 1);
      expect(updated.remainingCount, 2);
    });

    test('a day is clean until a qaza window closes unfulfilled', () {
      final fajr = day.entryFor(PrayerName.fajr);
      final beforeAnyExpiry =
          fajr.scheduledAt.add(const Duration(minutes: 10));
      expect(day.isCleanSoFar(beforeAnyExpiry), isTrue);

      final afterFajrMissed = fajr.qazaDeadline.add(const Duration(minutes: 1));
      expect(day.isCleanSoFar(afterFajrMissed), isFalse);
    });

    test('a day stays clean when the expired prayer was fulfilled', () {
      final fajr = day.entryFor(PrayerName.fajr);
      final updated =
          day.withEntry(fajr.copyWith(status: PrayerStatus.qazaCompleted));
      final afterFajrExpiry = fajr.qazaDeadline.add(const Duration(minutes: 1));
      expect(updated.isCleanSoFar(afterFajrExpiry), isTrue);
    });
  });

  group('morning protection', () {
    test('is active while Fajr is still verifiable', () {
      final fajr = day.entryFor(PrayerName.fajr);
      final duringOnTime = fajr.scheduledAt.add(const Duration(minutes: 10));
      final duringQaza = fajr.scheduledAt.add(const Duration(minutes: 45));

      expect(day.requiresMorningProtection(duringOnTime), isTrue);
      expect(day.requiresMorningProtection(duringQaza), isTrue);
    });

    test('lifts once Fajr is verified', () {
      final fajr = day.entryFor(PrayerName.fajr);
      final updated =
          day.withEntry(fajr.copyWith(status: PrayerStatus.completed));
      final during = fajr.scheduledAt.add(const Duration(minutes: 10));
      expect(updated.requiresMorningProtection(during), isFalse);
    });

    test('lifts once the qaza window closes even if Fajr was missed', () {
      final fajr = day.entryFor(PrayerName.fajr);
      final afterQaza = fajr.qazaDeadline.add(const Duration(minutes: 1));
      expect(day.requiresMorningProtection(afterQaza), isFalse);
    });
  });

  group('state preservation', () {
    test('recalculating a schedule keeps tracked completions', () {
      final completedFajr = buildDay()
          .entryFor(PrayerName.fajr)
          .copyWith(status: PrayerStatus.qazaCompleted);

      final rebuilt = buildDay(existing: {PrayerName.fajr: completedFajr});
      expect(rebuilt.entryFor(PrayerName.fajr).status,
          PrayerStatus.qazaCompleted);
      expect(rebuilt.qazaCount, 1);
    });
  });
}
