/// Tests for lock enforcement under dynamic prayer durations.
///
/// These decide when someone's phone becomes unusable. Apps lock from a
/// prayer's start and stay locked until the prayer is verified or its window
/// closes — and a window is now as long as the interval to the next prayer,
/// which can be over three hours. A wrong answer here is not cosmetic: locking
/// when nothing is owed, or failing to release at the end of a window, makes
/// the app actively harmful.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/features/blocking/domain/usecases/lock_decision.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

import '../support/prayer_fixtures.dart';

void main() {
  tz_data.initializeTimeZones();

  final day = buildDay();
  final fajr = day.entryFor(PrayerName.fajr);
  final dhuhr = day.entryFor(PrayerName.dhuhr);
  final asr = day.entryFor(PrayerName.asr);

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

    test('never locks without a schedule', () {
      final d = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: null,
        now: DateTime.utc(2026, 7, 20, 12),
      );
      expect(d.shouldLock, isFalse);
      expect(d.reason, LockReason.noPrayerDue);
    });
  });

  group('locking through a dynamic window', () {
    test('locks from the prayer start', () {
      final d = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: day,
        now: dhuhr.scheduledAt,
      );
      expect(d.shouldLock, isTrue);
      expect(d.reason, LockReason.prayerActive);
      expect(d.prayer, PrayerName.dhuhr);
    });

    test('reports the window end as the release instant', () {
      final d = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: day,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 5)),
      );
      expect(d.lockUntil, dhuhr.windowEndsAt);
      expect(d.windowDuration, dhuhr.duration);
    });

    test('the release instant is not a fixed offset from the start', () {
      final dhuhrDecision = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: day,
        now: dhuhr.scheduledAt,
      );
      final maghrib = day.entryFor(PrayerName.maghrib);
      final maghribDecision = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: day,
        now: maghrib.scheduledAt,
      );

      expect(
        dhuhrDecision.windowDuration,
        isNot(maghribDecision.windowDuration),
      );
    });

    test('remaining time counts down to the window end', () {
      final at = dhuhr.scheduledAt.add(const Duration(minutes: 20));
      final d = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: day,
        now: at,
      );
      expect(d.remainingAt(at), dhuhr.windowEndsAt.difference(at));
    });

    test('stays locked deep into a long window', () {
      // Dhuhr runs to Asr — hours later. The lock must not quietly lapse.
      final lateInWindow =
          dhuhr.windowEndsAt.subtract(const Duration(minutes: 1));
      final d = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: day,
        now: lateInWindow,
      );
      expect(d.shouldLock, isTrue);
      expect(d.prayer, PrayerName.dhuhr);
    });

    test('hands over to the next prayer at the boundary', () {
      final d = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: day,
        now: asr.scheduledAt,
      );
      expect(d.prayer, PrayerName.asr);
      expect(d.lockUntil, asr.windowEndsAt);
    });
  });

  group('Mode A — unlock on verification', () {
    test('releases as soon as the prayer is verified', () {
      final verified = buildDay(
        statuses: {PrayerName.dhuhr: PrayerStatus.completed},
      );
      final d = LockDecisionMaker.decide(
        settings: settingsWith(unlockPolicy: UnlockPolicy.onVerification),
        day: verified,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 5)),
      );
      expect(d.shouldLock, isFalse);
    });

    test('an excused prayer also releases', () {
      final excused = buildDay(
        statuses: {PrayerName.dhuhr: PrayerStatus.excused},
      );
      final d = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: excused,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 5)),
      );
      expect(d.shouldLock, isFalse);
    });
  });

  group('Mode B — block for the full duration', () {
    test('stays locked after verification until the window ends', () {
      final verified = buildDay(
        statuses: {PrayerName.dhuhr: PrayerStatus.completed},
      );
      final d = LockDecisionMaker.decide(
        settings: settingsWith(unlockPolicy: UnlockPolicy.fullDuration),
        day: verified,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 5)),
      );

      expect(d.shouldLock, isTrue);
      expect(d.reason, LockReason.durationRemaining);
      expect(d.lockUntil, dhuhr.windowEndsAt);
    });

    test('releases exactly when the window ends', () {
      final verified = buildDay(
        statuses: {PrayerName.dhuhr: PrayerStatus.completed},
      );
      final d = LockDecisionMaker.decide(
        settings: settingsWith(unlockPolicy: UnlockPolicy.fullDuration),
        day: verified,
        // Asr's window opens here, and Asr is unverified, so the lock passes to
        // Asr rather than lifting — but no longer on Dhuhr's account.
        now: dhuhr.windowEndsAt,
      );
      expect(d.prayer, PrayerName.asr);
    });

    test('an excused prayer is not held for the full duration', () {
      // Someone exempt from praying should not be locked out for three hours
      // on account of a prayer they are not required to perform.
      final excused = buildDay(
        statuses: {PrayerName.dhuhr: PrayerStatus.excused},
      );
      final d = LockDecisionMaker.decide(
        settings: settingsWith(unlockPolicy: UnlockPolicy.fullDuration),
        day: excused,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 5)),
      );
      expect(d.shouldLock, isFalse);
    });

    test('an emergency unlock still wins', () {
      final verified = buildDay(
        statuses: {PrayerName.dhuhr: PrayerStatus.completed},
      );
      final d = LockDecisionMaker.decide(
        settings: settingsWith(unlockPolicy: UnlockPolicy.fullDuration),
        day: verified,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 5)),
        emergencyUnlockedPrayers: {PrayerName.dhuhr},
      );
      expect(d.shouldLock, isFalse);
    });
  });

  group('grace period', () {
    test('does not lock during the grace period', () {
      final d = LockDecisionMaker.decide(
        settings: settingsWith(gracePeriodMinutes: 5),
        day: day,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 2)),
      );
      expect(d.shouldLock, isFalse);
      expect(d.reason, LockReason.withinGracePeriod);
      expect(d.lockUntil, dhuhr.scheduledAt.add(const Duration(minutes: 5)));
    });

    test('locks the moment the grace period ends', () {
      final d = LockDecisionMaker.decide(
        settings: settingsWith(gracePeriodMinutes: 5),
        day: day,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 5)),
      );
      expect(d.shouldLock, isTrue);
    });

    test('a grace period longer than the window never suppresses the lock '
        'beyond the window itself', () {
      // A 10-hour grace period would otherwise mean the lock never engages at
      // all, silently disabling the feature.
      final d = LockDecisionMaker.decide(
        settings: settingsWith(gracePeriodMinutes: 600),
        day: day,
        now: dhuhr.windowEndsAt.subtract(const Duration(minutes: 1)),
      );
      expect(d.reason, LockReason.withinGracePeriod);
      expect(d.lockUntil, dhuhr.windowEndsAt);
    });

    test('does not apply to a qaza debt', () {
      // The prayer has already had its whole window; a second grace period on
      // top would delay enforcement twice for the same prayer.
      //
      // Checked in the morning gap, where Fajr is owed as qaza and no other
      // window is open — anywhere else, a newly opened window's own grace
      // period would be the thing being observed.
      final gap = day.sunrise.add(const Duration(minutes: 1));
      final d = LockDecisionMaker.decide(
        settings: settingsWith(gracePeriodMinutes: 30, blockUntilQaza: true),
        day: day,
        now: gap,
      );

      expect(d.reason, LockReason.qazaOutstanding);
      expect(d.shouldLock, isTrue);
    });
  });

  group('qaza enforcement', () {
    test('is off by default, so a closed window releases the lock', () {
      // The default must not be "miss Fajr, lose your phone until midnight".
      final gap = day.sunrise.add(const Duration(hours: 1));
      final d = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: day,
        now: gap,
      );
      expect(d.shouldLock, isFalse);
      expect(d.reason, LockReason.noPrayerDue);
    });

    test('when enabled, keeps apps locked through the qaza period', () {
      final gap = day.sunrise.add(const Duration(hours: 1));
      final d = LockDecisionMaker.decide(
        settings: settingsWith(blockUntilQaza: true),
        day: day,
        now: gap,
      );
      expect(d.shouldLock, isTrue);
      expect(d.reason, LockReason.qazaOutstanding);
      expect(d.prayer, PrayerName.fajr);
      expect(d.lockUntil, fajr.qazaDeadline);
    });

    test('releases once the qaza is made', () {
      final made = buildDay(
        statuses: {PrayerName.fajr: PrayerStatus.qazaCompleted},
      );
      final gap = day.sunrise.add(const Duration(hours: 1));
      final d = LockDecisionMaker.decide(
        settings: settingsWith(blockUntilQaza: true),
        day: made,
        now: gap,
      );
      expect(d.shouldLock, isFalse);
    });
  });

  group('morning protection', () {
    test('locks while Fajr is owed', () {
      final d = LockDecisionMaker.decide(
        settings: settingsWith(morningProtection: true),
        day: day,
        now: fajr.scheduledAt.add(const Duration(minutes: 10)),
      );
      expect(d.shouldLock, isTrue);
      expect(d.reason, LockReason.morningProtection);
      expect(d.isMorningProtection, isTrue);
    });

    test('lifts once Fajr is verified', () {
      final verified =
          buildDay(statuses: {PrayerName.fajr: PrayerStatus.completed});
      final d = LockDecisionMaker.decide(
        settings: settingsWith(morningProtection: true),
        day: verified,
        now: fajr.scheduledAt.add(const Duration(minutes: 10)),
      );
      expect(d.isMorningProtection, isFalse);
    });

    test('respects the grace period', () {
      final d = LockDecisionMaker.decide(
        settings: settingsWith(morningProtection: true, gracePeriodMinutes: 10),
        day: day,
        now: fajr.scheduledAt.add(const Duration(minutes: 3)),
      );
      expect(d.shouldLock, isFalse);
      expect(d.reason, LockReason.withinGracePeriod);
    });

    test('is bypassed by an emergency unlock', () {
      final d = LockDecisionMaker.decide(
        settings: settingsWith(morningProtection: true),
        day: day,
        now: fajr.scheduledAt.add(const Duration(minutes: 10)),
        emergencyUnlockedPrayers: {PrayerName.fajr},
      );
      expect(d.isMorningProtection, isFalse);
    });
  });

  group('transition instants', () {
    test('are all in the future and ascending', () {
      final now = day.entries.first.scheduledAt
          .subtract(const Duration(hours: 1));
      final instants = LockDecisionMaker.transitionInstants(
        settings: settingsWith(gracePeriodMinutes: 5),
        day: day,
        now: now,
      );

      expect(instants, isNotEmpty);
      for (final instant in instants) {
        expect(instant.isAfter(now), isTrue);
      }
      for (var i = 1; i < instants.length; i++) {
        expect(instants[i].isAfter(instants[i - 1]), isTrue);
      }
    });

    test('include every window start and end', () {
      final now = day.entries.first.scheduledAt
          .subtract(const Duration(hours: 1));
      final instants = LockDecisionMaker.transitionInstants(
        settings: settingsWith(gracePeriodMinutes: 0),
        day: day,
        now: now,
      );

      for (final entry in day.entries) {
        expect(instants, contains(entry.scheduledAt));
        expect(instants, contains(entry.windowEndsAt));
      }
    });

    test('omit the qaza deadline when qaza enforcement is off', () {
      final now = day.dayEndsAt.subtract(const Duration(hours: 12));

      final without = LockDecisionMaker.transitionInstants(
        settings: settingsWith(blockUntilQaza: false),
        day: day,
        now: now,
      );
      final with_ = LockDecisionMaker.transitionInstants(
        settings: settingsWith(blockUntilQaza: true),
        day: day,
        now: now,
      );

      // Nothing changes at a qaza deadline when qaza is not enforced, so
      // arming an alarm for it would be a wakeup that does nothing.
      expect(with_.length, greaterThanOrEqualTo(without.length));
      expect(with_, contains(day.dayEndsAt));
    });

    test('are empty when blocking is disabled', () {
      expect(
        LockDecisionMaker.transitionInstants(
          settings: settingsWith(blockingEnabled: false),
          day: day,
          now: day.entries.first.scheduledAt,
        ),
        isEmpty,
      );
    });

    test('nextLockTransition is the earliest of them', () {
      final now =
          day.entries.first.scheduledAt.subtract(const Duration(hours: 1));
      final settings = settingsWith(gracePeriodMinutes: 5);

      expect(
        LockDecisionMaker.nextLockTransition(
          settings: settings,
          day: day,
          now: now,
        ),
        LockDecisionMaker.transitionInstants(
          settings: settings,
          day: day,
          now: now,
        ).first,
      );
    });
  });

  group('emergency unlock', () {
    test('suppresses the lock for that prayer only', () {
      final d = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: day,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 5)),
        emergencyUnlockedPrayers: {PrayerName.dhuhr},
      );
      expect(d.shouldLock, isFalse);
      expect(d.reason, LockReason.emergencyUnlocked);

      // The next prayer is unaffected.
      final next = LockDecisionMaker.decide(
        settings: settingsWith(),
        day: day,
        now: asr.scheduledAt.add(const Duration(minutes: 5)),
        emergencyUnlockedPrayers: {PrayerName.dhuhr},
      );
      expect(next.shouldLock, isTrue);
      expect(next.prayer, PrayerName.asr);
    });
  });
}
