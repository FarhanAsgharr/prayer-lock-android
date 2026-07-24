/// Tests for enforcement under combined prayers.
///
/// The example from the spec is the shape to protect:
///
///   12:17  Dhuhr begins, apps lock
///          ...
///          apps stay locked until Asr is verified, or the combined window ends
///
/// The failure that matters most is a lock that releases in the middle of a
/// joined window — the user would see apps unblock at Asr's start, which is
/// precisely the moment nothing changed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/features/blocking/domain/usecases/lock_decision.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:prayer_lock/features/sections/domain/entities/prayer_grouping.dart';
import 'package:prayer_lock/features/settings/domain/entities/app_settings.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

import '../support/prayer_fixtures.dart';

/// Settings with a grouping applied as an explicit override, so the section's
/// own suggestion cannot interfere with what a test is asserting.
AppSettings combinedSettings({
  PrayerGrouping grouping = PrayerGrouping.both,
  bool combinedVerification = true,
  UnlockPolicy unlockPolicy = UnlockPolicy.onVerification,
  int gracePeriodMinutes = 0,
  bool blockUntilQaza = false,
}) =>
    settingsWith(
      unlockPolicy: unlockPolicy,
      gracePeriodMinutes: gracePeriodMinutes,
      blockUntilQaza: blockUntilQaza,
    ).copyWith(
      prayerGroupingOverride: grouping,
      combinedVerification: combinedVerification,
    );

void main() {
  tz_data.initializeTimeZones();

  final day = buildDay();
  final dhuhr = day.entryFor(PrayerName.dhuhr);
  final asr = day.entryFor(PrayerName.asr);
  final maghrib = day.entryFor(PrayerName.maghrib);

  group('a combined lock covers both prayers', () {
    test('engages at the first prayer of the pair', () {
      final decision = LockDecisionMaker.decide(
        settings: combinedSettings(),
        day: day,
        now: dhuhr.scheduledAt,
      );

      expect(decision.shouldLock, isTrue);
      expect(decision.slotName, 'Dhuhr + Asr');
      expect(decision.prayers, [PrayerName.dhuhr, PrayerName.asr]);
      expect(decision.isCombined, isTrue);
    });

    test('releases at the end of the joined window, not the first prayer', () {
      final decision = LockDecisionMaker.decide(
        settings: combinedSettings(),
        day: day,
        now: dhuhr.scheduledAt,
      );

      // Not Dhuhr's own end, which is where Asr begins.
      expect(decision.lockUntil, asr.windowEndsAt);
      expect(decision.lockUntil, isNot(dhuhr.windowEndsAt));
    });

    test('the reported duration is the sum of both windows', () {
      final decision = LockDecisionMaker.decide(
        settings: combinedSettings(),
        day: day,
        now: dhuhr.scheduledAt,
      );

      expect(decision.windowDuration, dhuhr.duration + asr.duration);
    });

    test('does not release when the second prayer begins', () {
      // The regression this whole design exists to prevent.
      final decision = LockDecisionMaker.decide(
        settings: combinedSettings(),
        day: day,
        now: asr.scheduledAt,
      );

      expect(decision.shouldLock, isTrue);
      expect(decision.slotName, 'Dhuhr + Asr');
    });

    test('stays locked deep into the second prayer', () {
      final decision = LockDecisionMaker.decide(
        settings: combinedSettings(),
        day: day,
        now: asr.windowEndsAt.subtract(const Duration(minutes: 1)),
      );

      expect(decision.shouldLock, isTrue);
      expect(decision.slotName, 'Dhuhr + Asr');
    });

    test('Maghrib and Isha behave the same way', () {
      final decision = LockDecisionMaker.decide(
        settings: combinedSettings(),
        day: day,
        now: maghrib.scheduledAt,
      );

      expect(decision.slotName, 'Maghrib + Isha');
      expect(decision.lockUntil, day.entryFor(PrayerName.isha).windowEndsAt);
    });
  });

  group('releasing a combined lock', () {
    test('one prayer verified is not enough', () {
      final partial = buildDay(
        statuses: {PrayerName.dhuhr: PrayerStatus.completed},
      );

      final decision = LockDecisionMaker.decide(
        settings: combinedSettings(),
        day: partial,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 5)),
      );

      expect(decision.shouldLock, isTrue);
      expect(decision.slotName, 'Dhuhr + Asr');
    });

    test('both prayers verified releases the lock', () {
      final both = buildDay(
        statuses: {
          PrayerName.dhuhr: PrayerStatus.completed,
          PrayerName.asr: PrayerStatus.completed,
        },
      );

      final decision = LockDecisionMaker.decide(
        settings: combinedSettings(),
        day: both,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 5)),
      );

      expect(decision.shouldLock, isFalse);
    });

    test('one excused prayer does not release the pair', () {
      // Exempt from Dhuhr but not Asr: the window must keep holding.
      final one = buildDay(
        statuses: {PrayerName.dhuhr: PrayerStatus.excused},
      );

      final decision = LockDecisionMaker.decide(
        settings: combinedSettings(unlockPolicy: UnlockPolicy.fullDuration),
        day: one,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 5)),
      );

      expect(decision.shouldLock, isTrue);
    });

    test('both excused releases under the full-duration policy', () {
      final both = buildDay(
        statuses: {
          PrayerName.dhuhr: PrayerStatus.excused,
          PrayerName.asr: PrayerStatus.excused,
        },
      );

      final decision = LockDecisionMaker.decide(
        settings: combinedSettings(unlockPolicy: UnlockPolicy.fullDuration),
        day: both,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 5)),
      );

      expect(decision.shouldLock, isFalse);
    });
  });

  group('emergency unlock on a combined slot', () {
    test('exempting either prayer releases the whole slot', () {
      // Otherwise the user spends their single daily unlock and the lock
      // re-engages moments later for the paired prayer.
      for (final spent in [PrayerName.dhuhr, PrayerName.asr]) {
        final decision = LockDecisionMaker.decide(
          settings: combinedSettings(),
          day: day,
          now: dhuhr.scheduledAt.add(const Duration(minutes: 5)),
          emergencyUnlockedPrayers: {spent},
        );

        expect(
          decision.shouldLock,
          isFalse,
          reason: 'unlocking ${spent.displayName} did not release the pair',
        );
        expect(decision.reason, LockReason.emergencyUnlocked);
      }
    });

    test('does not leak into the other pair', () {
      final decision = LockDecisionMaker.decide(
        settings: combinedSettings(),
        day: day,
        now: maghrib.scheduledAt.add(const Duration(minutes: 5)),
        emergencyUnlockedPrayers: {PrayerName.dhuhr},
      );

      expect(decision.shouldLock, isTrue);
      expect(decision.slotName, 'Maghrib + Isha');
    });
  });

  group('grace period on a combined slot', () {
    test('is granted once, at the start of the joined window', () {
      final settings = combinedSettings(gracePeriodMinutes: 10);

      final duringGrace = LockDecisionMaker.decide(
        settings: settings,
        day: day,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 5)),
      );
      expect(duringGrace.shouldLock, isFalse);
      expect(duringGrace.reason, LockReason.withinGracePeriod);

      final afterGrace = LockDecisionMaker.decide(
        settings: settings,
        day: day,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 10)),
      );
      expect(afterGrace.shouldLock, isTrue);
    });

    test('is not re-granted when the second prayer arrives', () {
      // A second grace period mid-window would release a lock that is meant to
      // hold, and the user was already given their warning at Dhuhr.
      final decision = LockDecisionMaker.decide(
        settings: combinedSettings(gracePeriodMinutes: 10),
        day: day,
        now: asr.scheduledAt.add(const Duration(minutes: 2)),
      );

      expect(decision.shouldLock, isTrue);
      expect(decision.reason, isNot(LockReason.withinGracePeriod));
    });
  });

  group('transition instants under combining', () {
    test('a combined pair contributes one start and one end', () {
      final before = day.entries.first.scheduledAt
          .subtract(const Duration(hours: 1));

      final combined = LockDecisionMaker.transitionInstants(
        settings: combinedSettings(),
        day: day,
        now: before,
      );

      // Asr's start is inside the joined window, so arming an alarm for it
      // would wake the device to discover nothing changed.
      expect(combined, isNot(contains(asr.scheduledAt)));
      expect(combined, contains(dhuhr.scheduledAt));
      expect(combined, contains(asr.windowEndsAt));
    });

    test('combining reduces the number of alarms', () {
      final before = day.entries.first.scheduledAt
          .subtract(const Duration(hours: 1));

      final separate = LockDecisionMaker.transitionInstants(
        settings: combinedSettings(grouping: PrayerGrouping.none),
        day: day,
        now: before,
      );
      final combined = LockDecisionMaker.transitionInstants(
        settings: combinedSettings(),
        day: day,
        now: before,
      );

      expect(combined.length, lessThan(separate.length));
    });

    test('every armed instant is still ascending and in the future', () {
      final before = day.entries.first.scheduledAt
          .subtract(const Duration(hours: 1));
      final instants = LockDecisionMaker.transitionInstants(
        settings: combinedSettings(gracePeriodMinutes: 5),
        day: day,
        now: before,
      );

      expect(instants, isNotEmpty);
      for (var i = 1; i < instants.length; i++) {
        expect(instants[i].isAfter(instants[i - 1]), isTrue);
      }
    });
  });

  group('the default grouping changes nothing', () {
    test('separate prayers behave exactly as before', () {
      // Combining must be additive: someone who never enables it must not be
      // able to tell the feature exists.
      final decision = LockDecisionMaker.decide(
        settings: combinedSettings(grouping: PrayerGrouping.none),
        day: day,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 5)),
      );

      expect(decision.slotName, 'Dhuhr');
      expect(decision.prayers, [PrayerName.dhuhr]);
      expect(decision.isCombined, isFalse);
      expect(decision.lockUntil, dhuhr.windowEndsAt);
      expect(decision.windowDuration, dhuhr.duration);
    });

    test('verifying one prayer releases its own lock', () {
      final verified = buildDay(
        statuses: {PrayerName.dhuhr: PrayerStatus.completed},
      );

      final decision = LockDecisionMaker.decide(
        settings: combinedSettings(grouping: PrayerGrouping.none),
        day: verified,
        now: dhuhr.scheduledAt.add(const Duration(minutes: 5)),
      );

      expect(decision.shouldLock, isFalse);
    });
  });

  group('morning protection is unaffected by combining', () {
    test('Fajr is never part of a pair', () {
      final fajr = day.entryFor(PrayerName.fajr);
      final decision = LockDecisionMaker.decide(
        settings: settingsWith(morningProtection: true).copyWith(
          prayerGroupingOverride: PrayerGrouping.both,
        ),
        day: day,
        now: fajr.scheduledAt.add(const Duration(minutes: 10)),
      );

      expect(decision.reason, LockReason.morningProtection);
      expect(decision.prayers, [PrayerName.fajr]);
      expect(decision.slotName, 'Fajr');
    });
  });
}
