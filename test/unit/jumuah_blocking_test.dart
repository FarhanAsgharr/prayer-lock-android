/// Tests that app blocking follows the Jumu'ah profile on Fridays.
///
/// The behaviour that matters to a user: on a Friday the phone locks when the
/// khutbah starts and releases when the congregation ends — not three hours
/// later at Asr, which is what the ordinary Dhuhr window would do.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/features/blocking/domain/usecases/lock_decision.dart';
import 'package:prayer_lock/features/jumuah/domain/entities/jumuah_profile.dart';
import 'package:prayer_lock/features/jumuah/domain/usecases/jumuah_scheduler.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_day.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:prayer_lock/features/settings/domain/entities/app_settings.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

import '../support/prayer_fixtures.dart';

final _friday = DateTime(2026, 7, 24);
final _thursday = DateTime(2026, 7, 23);
const _timezone = 'Asia/Riyadh';

void main() {
  tz_data.initializeTimeZones();

  AppSettings settingsFor({
    JumuahLocation location = JumuahLocation.homeMosque,
    bool enabled = true,
  }) =>
      settingsWith(gracePeriodMinutes: 0).copyWith(
        jumuah: JumuahSettings(
          enabled: enabled,
          selectedLocation: location,
        ),
      );

  PrayerDay dayFor(DateTime date, AppSettings settings) => PrayerDay.fromWindows(
        JumuahScheduler.applyTo(
          windows: windowsAt(date: date, utcOffsetHours: 3),
          settings: settings.jumuah,
          timezone: _timezone,
        ),
      );

  group('blocking on a Friday', () {
    test('engages when the khutbah begins', () {
      final settings = settingsFor();
      final day = dayFor(_friday, settings);
      final jumuah = day.entryFor(PrayerName.dhuhr);

      final decision = LockDecisionMaker.decide(
        settings: settings,
        day: day,
        now: jumuah.scheduledAt,
      );

      expect(decision.shouldLock, isTrue);
      expect(decision.slotName, "Jumu'ah");
      expect(decision.prayers, [PrayerName.dhuhr]);
    });

    test('releases at the end of the congregation, not at Asr', () {
      final settings = settingsFor();
      final day = dayFor(_friday, settings);
      final jumuah = day.entryFor(PrayerName.dhuhr);

      final decision = LockDecisionMaker.decide(
        settings: settings,
        day: day,
        now: jumuah.scheduledAt,
      );

      expect(decision.lockUntil, jumuah.windowEndsAt);
      expect(decision.windowDuration, const Duration(minutes: 15));

      // The ordinary Dhuhr window on the same day would run to Asr.
      final ordinary = PrayerDay.fromWindows(
        windowsAt(date: _friday, utcOffsetHours: 3),
      ).entryFor(PrayerName.dhuhr);
      expect(
        decision.windowDuration,
        lessThan(ordinary.duration),
      );
    });

    test('nothing is locked after the congregation ends', () {
      final settings = settingsFor();
      final day = dayFor(_friday, settings);
      final jumuah = day.entryFor(PrayerName.dhuhr);

      final decision = LockDecisionMaker.decide(
        settings: settings,
        day: day,
        now: jumuah.windowEndsAt.add(const Duration(minutes: 1)),
      );

      // Qaza enforcement is off by default, so the closed window releases.
      expect(decision.shouldLock, isFalse);
    });

    test('verifying releases the lock', () {
      final settings = settingsFor();
      final day = dayFor(_friday, settings).withEntry(
        dayFor(_friday, settings)
            .entryFor(PrayerName.dhuhr)
            .copyWith(status: PrayerStatus.completed),
      );

      final jumuah = day.entryFor(PrayerName.dhuhr);
      final decision = LockDecisionMaker.decide(
        settings: settings,
        day: day,
        now: jumuah.scheduledAt.add(const Duration(minutes: 5)),
      );

      expect(decision.shouldLock, isFalse);
    });

    test('the University profile locks at its own time', () {
      final settings = settingsFor(location: JumuahLocation.universityMosque);
      final day = dayFor(_friday, settings);
      final jumuah = day.entryFor(PrayerName.dhuhr);

      // 1:15 PM Riyadh, not 2:00 PM.
      final atHomeTime = day.entryFor(PrayerName.dhuhr).scheduledAt;
      expect(jumuah.scheduledAt, atHomeTime);

      final decision = LockDecisionMaker.decide(
        settings: settings,
        day: day,
        now: jumuah.scheduledAt,
      );
      expect(decision.shouldLock, isTrue);
      expect(decision.windowDuration, const Duration(minutes: 15));
    });
  });

  group('other weekdays are unaffected', () {
    test('Thursday blocks for the full Dhuhr window', () {
      final settings = settingsFor();
      final day = dayFor(_thursday, settings);
      final dhuhr = day.entryFor(PrayerName.dhuhr);

      final decision = LockDecisionMaker.decide(
        settings: settings,
        day: day,
        now: dhuhr.scheduledAt,
      );

      expect(decision.shouldLock, isTrue);
      expect(decision.slotName, 'Dhuhr');
      expect(decision.lockUntil, dhuhr.windowEndsAt);
      // Hours, not the fifteen-minute congregation.
      expect(decision.windowDuration!.inMinutes, greaterThan(60));
    });

    test('disabling Smart Jumu\'ah restores the ordinary Friday window', () {
      final settings = settingsFor(enabled: false);
      final day = dayFor(_friday, settings);
      final dhuhr = day.entryFor(PrayerName.dhuhr);

      final decision = LockDecisionMaker.decide(
        settings: settings,
        day: day,
        now: dhuhr.scheduledAt,
      );

      expect(decision.slotName, 'Dhuhr');
      expect(decision.windowDuration!.inMinutes, greaterThan(60));
    });
  });

  group('alarm transitions', () {
    test('Friday arms the congregation start and end', () {
      final settings = settingsFor();
      final day = dayFor(_friday, settings);
      final jumuah = day.entryFor(PrayerName.dhuhr);

      final instants = LockDecisionMaker.transitionInstants(
        settings: settings,
        day: day,
        now: day.entries.first.scheduledAt.subtract(const Duration(hours: 1)),
      );

      expect(instants, contains(jumuah.scheduledAt));
      expect(instants, contains(jumuah.windowEndsAt));
    });

    test('the ordinary Dhuhr start is not armed on a Friday', () {
      final settings = settingsFor();
      final ordinary = PrayerDay.fromWindows(
        windowsAt(date: _friday, utcOffsetHours: 3),
      ).entryFor(PrayerName.dhuhr);

      final instants = LockDecisionMaker.transitionInstants(
        settings: settings,
        day: dayFor(_friday, settings),
        now: DateTime.utc(2026, 7, 24),
      );

      // Waking the device at astronomical Dhuhr would find nothing to do.
      expect(instants, isNot(contains(ordinary.scheduledAt)));
    });
  });
}
