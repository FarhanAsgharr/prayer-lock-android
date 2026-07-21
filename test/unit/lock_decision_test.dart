/// Tests for lock enforcement under the verification / qaza / missed model.
///
/// These decide when someone's phone becomes unusable. Apps lock from a
/// prayer's start and stay locked through both windows — up to 90 minutes —
/// until the prayer is verified or permanently missed. A wrong answer here is
/// not cosmetic: locking when nothing is owed, or failing to release after
/// verification, makes the app harmful.
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
  final schedule = prayerTimeCalculator.calculate(
    CalculationRequest(
      latitude: makkah.latitude,
      longitude: makkah.longitude,
      utcOffsetHours: 3,
      prayerDate: DateTime(2026, 7, 20),
    ),
  );
  var day = PrayerDay.fromSchedule(schedule);
  for (final entry in statuses.entries) {
    day = day.withEntry(day.entryFor(entry.key).copyWith(status: entry.value));
  }
  return day;
}

AppSettings settingsWith({
  bool blockingEnabled = true,
  bool morningProtection = true,
  int gracePeriodMinutes = 0,
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

  group('preconditions', () {
    test('never locks when blocking is disabled', () {
      final d = LockDecisionMaker.decide(
        settings: settingsWith(blockingEnabled: false),
        day: day,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 5)),
      );
      expect(d.shouldLock, isFalse);
      expect(d.reason, LockReason.disabledBySettings);
    });

    test('never locks when no apps are selected', () {
      final d = LockDecisionMaker.decide(
        settings: settingsWith(blockedPackages: const {}),
        day: day,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 5)),
      );
      expect(d.shouldLock, isFalse);
      expect(d.reason, LockReason.noAppsSelected);
    });
  });

  group('locking through the windows', () {
    test('locks from the prayer start (on-time window)', () {
      final d = LockDecisionMaker.decide(
        settings: settingsWith(morningProtection: false),
        day: day,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 5)),
      );
      expect(d.shouldLock, isTrue);
      expect(d.prayer, PrayerName.dhuhr);
    });

    test('stays locked through the qaza window', () {
      // Apps remain locked until verification or the qaza deadline.
      final d = LockDecisionMaker.decide(
        settings: settingsWith(morningProtection: false),
        day: day,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 60)),
      );
      expect(d.shouldLock, isTrue);
      expect(d.prayer, PrayerName.dhuhr);
    });

    test('unlocks once the qaza window closes (permanently missed)', () {
      // "Follow the existing missed-prayer lock policy": nothing more can be
      // done, so the lock lifts rather than trapping the user forever.
      final d = LockDecisionMaker.decide(
        settings: settingsWith(morningProtection: false),
        day: day,
        now: dhuhr.qazaDeadline.add(const Duration(minutes: 1)),
      );
      expect(d.shouldLock, isFalse);
      expect(d.reason, LockReason.noPrayerDue);
    });

    test('does not lock before the prayer starts', () {
      final d = LockDecisionMaker.decide(
        settings: settingsWith(morningProtection: false),
        day: day,
        now: dhuhr.scheduledAt.subtract(const Duration(minutes: 1)),
      );
      expect(d.shouldLock, isFalse);
    });
  });

  group('verification releases the lock', () {
    test('unlocks immediately when verified on time', () {
      final verified =
          buildDay(statuses: {PrayerName.dhuhr: PrayerStatus.completed});
      final d = LockDecisionMaker.decide(
        settings: settingsWith(morningProtection: false),
        day: verified,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 5)),
      );
      expect(d.shouldLock, isFalse);
    });

    test('unlocks immediately when verified as qaza', () {
      final verified =
          buildDay(statuses: {PrayerName.dhuhr: PrayerStatus.qazaCompleted});
      final d = LockDecisionMaker.decide(
        settings: settingsWith(morningProtection: false),
        day: verified,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 45)),
      );
      expect(d.shouldLock, isFalse);
    });

    test('unlocks for an excused prayer', () {
      final excused =
          buildDay(statuses: {PrayerName.dhuhr: PrayerStatus.excused});
      final d = LockDecisionMaker.decide(
        settings: settingsWith(morningProtection: false),
        day: excused,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 5)),
      );
      expect(d.shouldLock, isFalse);
    });
  });

  group('grace period', () {
    test('does not lock during the grace period', () {
      final d = LockDecisionMaker.decide(
        settings: settingsWith(morningProtection: false, gracePeriodMinutes: 5),
        day: day,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 2)),
      );
      expect(d.shouldLock, isFalse);
      expect(d.reason, LockReason.withinGracePeriod);
    });

    test('locks once the grace period elapses', () {
      final d = LockDecisionMaker.decide(
        settings: settingsWith(morningProtection: false, gracePeriodMinutes: 5),
        day: day,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 6)),
      );
      expect(d.shouldLock, isTrue);
    });
  });

  group('emergency unlock', () {
    test('does not re-lock a prayer the user unlocked out of', () {
      final d = LockDecisionMaker.decide(
        settings: settingsWith(morningProtection: false),
        day: day,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 10)),
        emergencyUnlockedPrayers: const {PrayerName.dhuhr},
      );
      expect(d.shouldLock, isFalse);
      expect(d.reason, LockReason.emergencyUnlocked);
    });
  });

  group('morning protection', () {
    test('locks while Fajr is verifiable', () {
      final d = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: day,
        now: fajr.scheduledAt.add(const Duration(minutes: 20)),
      );
      expect(d.shouldLock, isTrue);
      expect(d.reason, LockReason.morningProtection);
      expect(d.isMorningProtection, isTrue);
    });

    test('stays through Fajr qaza', () {
      final d = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: day,
        now: fajr.scheduledAt.add(const Duration(minutes: 45)),
      );
      expect(d.shouldLock, isTrue);
      expect(d.reason, LockReason.morningProtection);
    });

    test('lifts once Fajr is verified', () {
      final prayed =
          buildDay(statuses: {PrayerName.fajr: PrayerStatus.completed});
      final d = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: prayed,
        now: fajr.scheduledAt.add(const Duration(minutes: 20)),
      );
      expect(d.shouldLock, isFalse);
    });

    test('lifts once the Fajr qaza window closes', () {
      final d = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: day,
        now: fajr.qazaDeadline.add(const Duration(minutes: 1)),
      );
      expect(d.shouldLock, isFalse);
    });
  });

  group('full day sweep', () {
    test('only ever locks for a prayer that is genuinely verifiable', () {
      final settings = settingsWith(morningProtection: false);
      final start = fajr.scheduledAt;

      for (var minute = 0; minute < 24 * 60; minute += 3) {
        final now = start.add(Duration(minutes: minute));
        final d =
            LockDecisionMaker.decide(settings: settings, day: day, now: now);
        if (!d.shouldLock) continue;

        // If it locked, the named prayer must be in a verifiable phase.
        final entry = day.entryFor(d.prayer!);
        expect(
          entry.phaseAt(now).isVerifiable,
          isTrue,
          reason: 'locked at $now for a non-verifiable ${d.prayer}',
        );
      }
    });
  });
}
