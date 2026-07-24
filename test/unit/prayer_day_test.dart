/// Tests for the dynamic-window / qaza / missed model.
///
/// This is where the product's correctness lives: whether a prayer is
/// verifiable on time, verifiable as qaza, or permanently missed determines
/// when the phone locks and what the user's history says about them.
///
/// Under dynamic durations each prayer's window runs to the next boundary, so
/// none of these assertions may reference a fixed number of minutes.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_day.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_window.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

import '../support/prayer_fixtures.dart';

void main() {
  tz_data.initializeTimeZones();

  final day = buildDay();
  final dhuhr = day.entryFor(PrayerName.dhuhr);
  final asr = day.entryFor(PrayerName.asr);

  group('window boundaries', () {
    test('the on-time window runs to the next prayer', () {
      expect(dhuhr.verificationDeadline, asr.scheduledAt);
      expect(dhuhr.windowEndsAt, asr.scheduledAt);
    });

    test('Fajr expires at sunrise, not at Dhuhr', () {
      final fajr = day.entryFor(PrayerName.fajr);
      expect(fajr.windowEndsAt, day.sunrise);
    });

    test('Isha runs to the following Fajr', () {
      final isha = day.entryFor(PrayerName.isha);
      expect(isha.windowEndsAt, day.dayEndsAt);
    });

    test('the qaza opportunity runs to the end of the prayer day', () {
      expect(dhuhr.qazaDeadline, day.dayEndsAt);
      expect(dhuhr.qazaDeadline.isAfter(dhuhr.windowEndsAt), isTrue);
    });

    test('Isha has no same-day qaza room', () {
      // Isha's window already ends at the following Fajr, so there is no space
      // left in the day for a make-up; it becomes a carried-forward debt.
      final isha = day.entryFor(PrayerName.isha);
      expect(isha.qazaDeadline, isha.windowEndsAt);
    });

    test('durations are not uniform across prayers', () {
      final durations =
          day.entries.map((entry) => entry.duration.inMinutes).toSet();
      expect(durations.length, greaterThan(1));
    });
  });

  group('phase derivation', () {
    test('is upcoming before the prayer starts', () {
      final before = dhuhr.scheduledAt.subtract(const Duration(minutes: 1));
      expect(dhuhr.phaseAt(before), PrayerPhase.upcoming);
    });

    test('is verifyOnTime throughout the prayer window', () {
      expect(dhuhr.phaseAt(dhuhr.scheduledAt), PrayerPhase.verifyOnTime);
      expect(
        dhuhr.phaseAt(
          dhuhr.windowEndsAt.subtract(const Duration(minutes: 1)),
        ),
        PrayerPhase.verifyOnTime,
      );
    });

    test('becomes qazaAvailable exactly when the window closes', () {
      expect(dhuhr.phaseAt(dhuhr.windowEndsAt), PrayerPhase.qazaAvailable);
      expect(
        dhuhr.phaseAt(dhuhr.qazaDeadline.subtract(const Duration(minutes: 1))),
        PrayerPhase.qazaAvailable,
      );
    });

    test('becomes missed exactly when the prayer day ends', () {
      expect(dhuhr.phaseAt(dhuhr.qazaDeadline), PrayerPhase.missed);
      expect(
        dhuhr.phaseAt(dhuhr.qazaDeadline.add(const Duration(hours: 5))),
        PrayerPhase.missed,
      );
    });

    test('a recorded on-time completion is never re-derived', () {
      final completed = dhuhr.copyWith(status: PrayerStatus.completed);
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
    test('reports time to the window end during the window', () {
      final at = dhuhr.scheduledAt.add(const Duration(minutes: 10));
      expect(
        dhuhr.remainingWindow(at),
        dhuhr.windowEndsAt.difference(at),
      );
    });

    test('reports time to the day end during the qaza period', () {
      final at = dhuhr.windowEndsAt.add(const Duration(minutes: 10));
      expect(dhuhr.remainingWindow(at), dhuhr.qazaDeadline.difference(at));
    });

    test('is null when no window is open', () {
      expect(dhuhr.remainingWindow(dhuhr.qazaDeadline), isNull);
      expect(
        dhuhr.remainingWindow(
          dhuhr.scheduledAt.subtract(const Duration(minutes: 1)),
        ),
        isNull,
      );
    });
  });

  group('lockable prayer', () {
    test('is the prayer whose window is open', () {
      final at = dhuhr.scheduledAt.add(const Duration(minutes: 5));
      expect(day.lockablePrayer(at)?.prayer, PrayerName.dhuhr);
    });

    test('stops naming a prayer once it is verified', () {
      final at = dhuhr.scheduledAt.add(const Duration(minutes: 5));
      final updated =
          day.withEntry(dhuhr.copyWith(status: PrayerStatus.completed));
      expect(updated.lockablePrayer(at)?.prayer, isNot(PrayerName.dhuhr));
    });

    test('is null only when nothing at all is owed', () {
      // Everything earlier in the day must be discharged too: a qaza window
      // stays open until the prayer day ends, so an unfulfilled Fajr is still
      // owed at Dhuhr.
      var updated = day;
      for (final entry in day.entries) {
        updated = updated.withEntry(
          updated.entryFor(entry.prayer).copyWith(
                status: PrayerStatus.completed,
              ),
        );
      }
      final at = dhuhr.scheduledAt.add(const Duration(minutes: 5));
      expect(updated.lockablePrayer(at), isNull);
    });

    test('is null once the prayer day has ended for that prayer', () {
      final at = dhuhr.qazaDeadline.add(const Duration(minutes: 1));
      expect(day.lockablePrayer(at)?.prayer, isNot(PrayerName.dhuhr));
    });

    test('prefers the open window over an earlier outstanding qaza', () {
      // At a moment inside Asr's window, Dhuhr is already in qaza. The prayer
      // whose window is actually open must win, or the user would be told to
      // pray Dhuhr while Asr is the one that is due.
      final at = asr.scheduledAt.add(const Duration(minutes: 5));
      expect(dhuhr.phaseAt(at), PrayerPhase.qazaAvailable);
      expect(day.lockablePrayer(at)?.prayer, PrayerName.asr);
    });

    test('falls back to the oldest outstanding qaza in the morning gap', () {
      // Between sunrise and Dhuhr no window is open, but Fajr is owed as qaza.
      final gap = day.sunrise.add(const Duration(hours: 1));
      expect(day.activePrayer(gap), isNull);
      expect(day.lockablePrayer(gap)?.prayer, PrayerName.fajr);
    });
  });

  group('active prayer', () {
    test('is the prayer whose window contains the instant', () {
      final at = asr.scheduledAt.add(const Duration(minutes: 30));
      expect(day.activePrayer(at)?.prayer, PrayerName.asr);
    });

    test('remains the active prayer after verification', () {
      // Distinguishes activePrayer from lockablePrayer: under Mode B the window
      // keeps running after the prayer is verified, so the window's owner must
      // still be reported even though nothing is owed for it.
      final at = asr.scheduledAt.add(const Duration(minutes: 30));
      final updated =
          day.withEntry(asr.copyWith(status: PrayerStatus.completed));

      expect(updated.activePrayer(at)?.prayer, PrayerName.asr);
      expect(updated.lockablePrayer(at)?.prayer, isNot(PrayerName.asr));
    });

    test('is null in the morning gap', () {
      expect(day.activePrayer(day.sunrise.add(const Duration(hours: 2))),
          isNull);
    });
  });

  group('qaza and missed collections', () {
    test('outstanding qaza lists prayers past their window, oldest first', () {
      final at = asr.scheduledAt.add(const Duration(minutes: 5));
      final outstanding = day.outstandingQaza(at);

      expect(
        outstanding.map((entry) => entry.prayer),
        containsAll([PrayerName.fajr, PrayerName.dhuhr]),
      );
      expect(outstanding.first.prayer, PrayerName.fajr);
    });

    test('a verified prayer never appears as outstanding', () {
      final at = asr.scheduledAt.add(const Duration(minutes: 5));
      final updated = day.withEntry(
        day.entryFor(PrayerName.fajr).copyWith(status: PrayerStatus.completed),
      );
      expect(
        updated.outstandingQaza(at).map((entry) => entry.prayer),
        isNot(contains(PrayerName.fajr)),
      );
    });

    test('missed lists prayers past their qaza deadline', () {
      final afterDay = day.dayEndsAt.add(const Duration(minutes: 1));
      expect(day.missedPrayers(afterDay), hasLength(5));
      expect(day.outstandingQaza(afterDay), isEmpty);
    });
  });

  group('daily aggregates', () {
    test('counts fulfilled across on-time, qaza and excused', () {
      final updated = day
          .withEntry(day
              .entryFor(PrayerName.fajr)
              .copyWith(status: PrayerStatus.completed))
          .withEntry(day
              .entryFor(PrayerName.dhuhr)
              .copyWith(status: PrayerStatus.qazaCompleted))
          .withEntry(day
              .entryFor(PrayerName.asr)
              .copyWith(status: PrayerStatus.excused));

      expect(updated.completedCount, 3);
      expect(updated.qazaCount, 1);
      expect(updated.remainingCount, 2);
    });

    test('a day is clean until a qaza opportunity closes unfulfilled', () {
      final fajr = day.entryFor(PrayerName.fajr);
      final beforeAnyExpiry = fajr.scheduledAt.add(const Duration(minutes: 10));
      expect(day.isCleanSoFar(beforeAnyExpiry), isTrue);

      final afterQazaClosed =
          fajr.qazaDeadline.add(const Duration(minutes: 1));
      expect(day.isCleanSoFar(afterQazaClosed), isFalse);
    });

    test('a day stays clean when every expired prayer was fulfilled', () {
      // Because the qaza opportunity runs to the end of the prayer day, all
      // five prayers expire at the same instant. A day is therefore judged in
      // one go, at its end — which is the intended behaviour: the user has the
      // whole day to make anything up.
      var updated = day;
      for (final entry in day.entries) {
        updated = updated.withEntry(
          updated.entryFor(entry.prayer).copyWith(
                status: PrayerStatus.qazaCompleted,
              ),
        );
      }

      final afterExpiry = day.dayEndsAt.add(const Duration(minutes: 1));
      expect(updated.isCleanSoFar(afterExpiry), isTrue);
      expect(day.isCleanSoFar(afterExpiry), isFalse);
    });

    test('the total window duration is the sum of the five', () {
      expect(
        day.totalWindowDuration,
        day.entries.fold(Duration.zero, (t, e) => t + e.duration),
      );
    });
  });

  group('morning protection', () {
    test('is active while Fajr is still verifiable', () {
      final fajr = day.entryFor(PrayerName.fajr);
      final duringWindow = fajr.scheduledAt.add(const Duration(minutes: 10));
      final duringQaza = fajr.windowEndsAt.add(const Duration(minutes: 10));

      expect(day.requiresMorningProtection(duringWindow), isTrue);
      expect(day.requiresMorningProtection(duringQaza), isTrue);
    });

    test('lifts once Fajr is verified', () {
      final fajr = day.entryFor(PrayerName.fajr);
      final updated =
          day.withEntry(fajr.copyWith(status: PrayerStatus.completed));
      final during = fajr.scheduledAt.add(const Duration(minutes: 10));
      expect(updated.requiresMorningProtection(during), isFalse);
    });

    test('lifts once the qaza opportunity closes even if Fajr was missed', () {
      final fajr = day.entryFor(PrayerName.fajr);
      final after = fajr.qazaDeadline.add(const Duration(minutes: 1));
      expect(day.requiresMorningProtection(after), isFalse);
    });
  });

  group('state preservation', () {
    test('recalculating a schedule keeps tracked completions', () {
      final completedFajr = buildDay()
          .entryFor(PrayerName.fajr)
          .copyWith(status: PrayerStatus.qazaCompleted);

      final rebuilt = PrayerDay.fromWindows(
        windowsAt(),
        existing: {PrayerName.fajr: completedFajr},
      );

      expect(
        rebuilt.entryFor(PrayerName.fajr).status,
        PrayerStatus.qazaCompleted,
      );
      expect(rebuilt.qazaCount, 1);
    });

    test('withEntry replaces only the named prayer', () {
      final updated =
          day.withEntry(dhuhr.copyWith(status: PrayerStatus.completed));

      expect(updated.entryFor(PrayerName.dhuhr).status,
          PrayerStatus.completed);
      expect(updated.entryFor(PrayerName.asr).status, PrayerStatus.pending);
      // The windows themselves must survive untouched.
      expect(updated.entryFor(PrayerName.asr).window,
          day.entryFor(PrayerName.asr).window);
    });
  });

  group('delay reporting', () {
    test('measures from the prayer start, floored at zero', () {
      final verified = dhuhr.copyWith(
        status: PrayerStatus.completed,
        completedAt: dhuhr.scheduledAt.add(const Duration(minutes: 12)),
      );
      expect(verified.delayMinutes, 12);

      final early = dhuhr.copyWith(
        status: PrayerStatus.completed,
        completedAt: dhuhr.scheduledAt.subtract(const Duration(minutes: 5)),
      );
      expect(early.delayMinutes, 0);
    });

    test('is null when the prayer was never verified', () {
      expect(dhuhr.delayMinutes, isNull);
    });
  });

  group('window boundary labels', () {
    test('each prayer reports what closes it', () {
      expect(day.entryFor(PrayerName.fajr).window.boundary,
          WindowBoundary.sunrise);
      expect(day.entryFor(PrayerName.dhuhr).window.boundary,
          WindowBoundary.asr);
      expect(day.entryFor(PrayerName.asr).window.boundary,
          WindowBoundary.maghrib);
      expect(day.entryFor(PrayerName.maghrib).window.boundary,
          WindowBoundary.isha);
      expect(day.entryFor(PrayerName.isha).window.boundary,
          WindowBoundary.nextDayFajr);
    });
  });
}
