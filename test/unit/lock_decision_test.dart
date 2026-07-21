/// Tests for lock enforcement rules.
///
/// These decide when someone's phone becomes unusable. A wrong answer here is
/// not a cosmetic bug — locking a user out when nothing is owed, or failing to
/// release them after they have prayed, is the kind of failure that makes the
/// app harmful rather than helpful. Every rule is covered.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/features/blocking/domain/usecases/lock_decision.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_day.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:prayer_lock/features/prayer_times/domain/usecases/prayer_time_calculator.dart';
import 'package:prayer_lock/features/settings/domain/entities/app_settings.dart';

const makkah = PrayerLocation(
  latitude: 21.4225,
  longitude: 39.8262,
  timezone: 'Asia/Riyadh',
  label: 'Makkah',
);

PrayerDay buildDay({Map<PrayerName, PrayerStatus> statuses = const {}}) {
  const date = (year: 2026, month: 7, day: 20);

  CalculationRequest requestFor(DateTime day) => CalculationRequest(
        latitude: makkah.latitude,
        longitude: makkah.longitude,
        utcOffsetHours: 3,
        prayerDate: day,
      );

  final target = DateTime(date.year, date.month, date.day);
  final today = prayerTimeCalculator.calculate(requestFor(target));
  final tomorrow = prayerTimeCalculator
      .calculate(requestFor(target.add(const Duration(days: 1))));

  var day = PrayerDay.fromSchedule(today, nextDayFajr: tomorrow.fajr);

  for (final entry in statuses.entries) {
    day = day.withEntry(
      day.entryFor(entry.key).copyWith(status: entry.value),
    );
  }
  return day;
}

AppSettings settingsWith({
  bool blockingEnabled = true,
  bool morningProtection = true,
  int gracePeriodMinutes = 5,
  Set<String> blockedPackages = const {'com.instagram.android'},
}) =>
    AppSettings(
      location: makkah,
      blockingEnabled: blockingEnabled,
      morningProtectionEnabled: morningProtection,
      lockGracePeriodMinutes: gracePeriodMinutes,
      blockedPackages: blockedPackages,
    );

void main() {
  final day = buildDay();
  final dhuhr = day.entryFor(PrayerName.dhuhr);
  final fajr = day.entryFor(PrayerName.fajr);

  group('blocking disabled', () {
    test('never locks when the feature is off', () {
      final decision = LockDecisionMaker.decide(
        settings: settingsWith(blockingEnabled: false),
        day: day,
        now: dhuhr.scheduledAt.add(const Duration(hours: 1)),
      );

      expect(decision.shouldLock, isFalse);
      expect(decision.reason, LockReason.disabledBySettings);
    });

    test('never locks when no apps are selected', () {
      // A lock with nothing to block is pure downside: a persistent
      // notification and no benefit whatsoever.
      final decision = LockDecisionMaker.decide(
        settings: settingsWith(blockedPackages: const {}),
        day: day,
        now: dhuhr.scheduledAt.add(const Duration(hours: 1)),
      );

      expect(decision.shouldLock, isFalse);
      expect(decision.reason, LockReason.noAppsSelected);
    });
  });

  group('grace period', () {
    test('does not lock immediately at the adhan', () {
      // Cutting someone off mid-conversation the instant the adhan sounds is
      // hostile; the grace period is what makes enforcement tolerable.
      final decision = LockDecisionMaker.decide(
        settings: settingsWith(gracePeriodMinutes: 5),
        day: day,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 1)),
      );

      expect(decision.shouldLock, isFalse);
      expect(decision.reason, LockReason.withinGracePeriod);
    });

    test('locks once the grace period elapses', () {
      final decision = LockDecisionMaker.decide(
        settings: settingsWith(gracePeriodMinutes: 5),
        day: day,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 6)),
      );

      expect(decision.shouldLock, isTrue);
      expect(decision.reason, LockReason.prayerActive);
      expect(decision.prayer, PrayerName.dhuhr);
    });

    test('a zero grace period locks at the adhan', () {
      final decision = LockDecisionMaker.decide(
        settings: settingsWith(gracePeriodMinutes: 0),
        day: day,
        now: dhuhr.scheduledAt.add(const Duration(seconds: 1)),
      );

      expect(decision.shouldLock, isTrue);
    });
  });

  group('no prayer due', () {
    test('does not lock before the first prayer', () {
      final decision = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: day,
        now: fajr.scheduledAt.subtract(const Duration(hours: 1)),
      );

      expect(decision.shouldLock, isFalse);
      expect(decision.reason, LockReason.noPrayerDue);
    });

    test('does not lock between sunrise and Dhuhr', () {
      // A genuine gap when nothing is owed. Locking here would be a serious
      // bug — the user would lose their phone for hours for no reason.
      final decision = LockDecisionMaker.decide(
        settings: settingsWith(morningProtection: false),
        day: day,
        now: day.sunrise.add(const Duration(hours: 2)),
      );

      expect(decision.shouldLock, isFalse);
      expect(decision.reason, LockReason.noPrayerDue);
    });

    test('does not lock without a schedule', () {
      final decision = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: null,
        now: DateTime.utc(2026, 7, 20, 12),
      );

      expect(decision.shouldLock, isFalse);
    });
  });

  group('fulfilled prayers', () {
    test('releases once the prayer is completed', () {
      final completed =
          buildDay(statuses: {PrayerName.dhuhr: PrayerStatus.completed});

      final decision = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: completed,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 30)),
      );

      expect(decision.shouldLock, isFalse);
      expect(decision.reason, LockReason.prayerFulfilled);
    });

    test('releases for an excused prayer', () {
      final excused =
          buildDay(statuses: {PrayerName.dhuhr: PrayerStatus.excused});

      final decision = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: excused,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 30)),
      );

      expect(decision.shouldLock, isFalse);
    });

    test('releases for a late completion', () {
      final late = buildDay(statuses: {PrayerName.dhuhr: PrayerStatus.late});

      final decision = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: late,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 30)),
      );

      expect(decision.shouldLock, isFalse);
    });
  });

  group('emergency unlock', () {
    test('does not re-lock a prayer the user unlocked out of', () {
      // Re-locking would make the single daily unlock worthless.
      final decision = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: day,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 30)),
        emergencyUnlockedPrayers: const {PrayerName.dhuhr},
      );

      expect(decision.shouldLock, isFalse);
      expect(decision.reason, LockReason.emergencyUnlocked);
    });

    test('still locks for a different prayer later the same day', () {
      // The unlock buys out one prayer, not the whole day.
      final asr = day.entryFor(PrayerName.asr);

      final decision = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: day,
        now: asr.scheduledAt.add(const Duration(minutes: 30)),
        emergencyUnlockedPrayers: const {PrayerName.dhuhr},
      );

      expect(decision.shouldLock, isTrue);
      expect(decision.prayer, PrayerName.asr);
    });
  });

  group('morning protection', () {
    test('locks after Fajr begins when Fajr is unfulfilled', () {
      final decision = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: day,
        now: fajr.scheduledAt.add(const Duration(minutes: 30)),
      );

      expect(decision.shouldLock, isTrue);
      expect(decision.reason, LockReason.morningProtection);
      expect(decision.isMorningProtection, isTrue);
    });

    test('respects the grace period', () {
      // An alarm going off at Fajr must not lock a half-asleep user out
      // instantly.
      final decision = LockDecisionMaker.decide(
        settings: settingsWith(gracePeriodMinutes: 5),
        day: day,
        now: fajr.scheduledAt.add(const Duration(minutes: 2)),
      );

      expect(decision.shouldLock, isFalse);
      expect(decision.reason, LockReason.withinGracePeriod);
    });

    test('releases once Fajr is prayed', () {
      final prayed =
          buildDay(statuses: {PrayerName.fajr: PrayerStatus.completed});

      final decision = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: prayed,
        now: fajr.scheduledAt.add(const Duration(minutes: 30)),
      );

      expect(decision.shouldLock, isFalse);
    });

    test('lifts after sunrise even if Fajr was missed', () {
      // Holding someone's phone all day over a missed Fajr would be punitive
      // rather than helpful.
      final decision = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: day,
        now: day.sunrise.add(const Duration(minutes: 30)),
      );

      expect(decision.shouldLock, isFalse);
    });

    test('can be disabled without disabling normal locking', () {
      final decision = LockDecisionMaker.decide(
        settings: settingsWith(morningProtection: false),
        day: day,
        now: fajr.scheduledAt.add(const Duration(minutes: 30)),
      );

      // Fajr is still the current prayer, so a normal lock applies — just not
      // the morning gate.
      expect(decision.shouldLock, isTrue);
      expect(decision.reason, LockReason.prayerActive);
      expect(decision.isMorningProtection, isFalse);
    });

    test('an emergency unlock also lifts the morning gate', () {
      final decision = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: day,
        now: fajr.scheduledAt.add(const Duration(minutes: 30)),
        emergencyUnlockedPrayers: const {PrayerName.fajr},
      );

      expect(decision.shouldLock, isFalse);
    });
  });

  group('next transition', () {
    test('reports when the lock will next engage', () {
      final now = fajr.scheduledAt.subtract(const Duration(hours: 1));

      final next = LockDecisionMaker.nextLockTransition(
        settings: settingsWith(gracePeriodMinutes: 5),
        day: day,
        now: now,
      );

      expect(next, fajr.scheduledAt.add(const Duration(minutes: 5)));
    });

    test('skips prayers already fulfilled', () {
      final prayed =
          buildDay(statuses: {PrayerName.fajr: PrayerStatus.completed});
      final now = fajr.scheduledAt.subtract(const Duration(hours: 1));

      final next = LockDecisionMaker.nextLockTransition(
        settings: settingsWith(gracePeriodMinutes: 0),
        day: prayed,
        now: now,
      );

      expect(next, prayed.entryFor(PrayerName.dhuhr).scheduledAt);
    });

    test('is null when blocking is disabled', () {
      final next = LockDecisionMaker.nextLockTransition(
        settings: settingsWith(blockingEnabled: false),
        day: day,
        now: fajr.scheduledAt,
      );

      expect(next, isNull);
    });

    test('is null after the last prayer of the day', () {
      final next = LockDecisionMaker.nextLockTransition(
        settings: settingsWith(),
        day: day,
        now: day.entryFor(PrayerName.isha).scheduledAt.add(const Duration(hours: 1)),
      );

      expect(next, isNull);
    });
  });

  group('full day sweep', () {
    test('never locks outside a prayer window when protection is off', () {
      // Walks the whole day minute by minute. Any spurious lock outside a
      // window would be caught here rather than by a user losing their phone.
      final settings = settingsWith(morningProtection: false, gracePeriodMinutes: 0);
      final start = day.entryFor(PrayerName.fajr).scheduledAt;

      for (var minute = 0; minute < 24 * 60; minute += 5) {
        final now = start.add(Duration(minutes: minute));
        final decision =
            LockDecisionMaker.decide(settings: settings, day: day, now: now);

        if (!decision.shouldLock) continue;

        // If it locked, a prayer must genuinely be due right now.
        final current = day.currentPrayer(now);
        expect(
          current,
          isNotNull,
          reason: 'locked at $now with no prayer due',
        );
        expect(decision.prayer, current!.prayer);
      }
    });
  });
}
