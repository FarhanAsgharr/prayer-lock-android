/// Tests for the Smart Jumu'ah system.
///
/// The load-bearing property, asserted from several directions: **Jumu'ah
/// changes Friday and nothing else.** A bug here is invisible for six days a
/// week, which is exactly the kind that ships.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/features/jumuah/data/repositories/jumuah_preference_repository.dart';
import 'package:prayer_lock/features/jumuah/domain/entities/jumuah_profile.dart';
import 'package:prayer_lock/features/jumuah/domain/entities/jumuah_settings.dart';
import 'package:prayer_lock/features/jumuah/domain/entities/mosque_profile.dart';
import 'package:prayer_lock/features/jumuah/domain/usecases/friday_detector.dart';
import 'package:prayer_lock/features/jumuah/domain/usecases/jumuah_manager.dart';
import 'package:prayer_lock/features/jumuah/domain/usecases/jumuah_scheduler.dart';
import 'package:prayer_lock/features/jumuah/domain/usecases/jumuah_verification_controller.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_day.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_slot.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_window.dart';
import 'package:prayer_lock/features/sections/domain/entities/prayer_grouping.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../support/prayer_fixtures.dart';

/// 2026-07-24 is a Friday; 2026-07-23 a Thursday, 2026-07-25 a Saturday.
final _friday = DateTime(2026, 7, 24);
final _thursday = DateTime(2026, 7, 23);
final _saturday = DateTime(2026, 7, 25);

const _timezone = 'Asia/Riyadh';

/// Settings pointing at one of the seeded mosques, optionally overriding it.
JumuahSettings _settings({
  bool enabled = true,
  String? mosqueId = 'home',
  MosqueProfile? override,
}) {
  final mosques = MosqueProfile.defaults();
  return JumuahSettings(
    enabled: enabled,
    selectedMosqueId: mosqueId,
    mosques: override == null
        ? mosques
        : [for (final m in mosques) m.id == override.id ? override : m],
  );
}

/// A seeded mosque with different times.
MosqueProfile _mosque(
  String id, {
  required LocalTimeOfDay startsAt,
  required LocalTimeOfDay endsAt,
}) =>
    MosqueProfile.defaults()
        .firstWhere((m) => m.id == id)
        .copyWith(startsAt: startsAt, endsAt: endsAt);

DailyPrayerWindows _windowsOn(DateTime date) =>
    windowsAt(date: date, utcOffsetHours: 3);

/// The local wall-clock time of a UTC instant at the test timezone.
LocalTimeOfDay _localTime(DateTime instant) {
  final local = tz.TZDateTime.from(instant, tz.getLocation(_timezone));
  return LocalTimeOfDay(local.hour, local.minute);
}

void main() {
  tz_data.initializeTimeZones();

  group('Friday detection', () {
    test('recognises Friday and rejects every other day', () {
      expect(FridayDetector.isFriday(_friday), isTrue);
      for (final other in [
        DateTime(2026, 7, 20), // Monday
        DateTime(2026, 7, 21),
        DateTime(2026, 7, 22),
        _thursday,
        _saturday,
        DateTime(2026, 7, 26), // Sunday
      ]) {
        expect(
          FridayDetector.isFriday(other),
          isFalse,
          reason: '$other was treated as Friday',
        );
      }
    });

    test('resolves the weekday at the user location, not the device', () {
      // 2026-07-24 05:00 UTC is 08:00 Friday in Riyadh (UTC+3) and 19:00
      // Thursday in Honolulu (UTC-10). Reading DateTime.now().weekday would
      // give whichever the device happened to be set to.
      final instant = DateTime.utc(2026, 7, 24, 5);

      expect(FridayDetector.isFridayAt(instant, 'Asia/Riyadh'), isTrue);
      expect(FridayDetector.isFridayAt(instant, 'Pacific/Honolulu'), isFalse);
    });

    test('an unknown zone degrades instead of throwing', () {
      expect(
        () => FridayDetector.isFridayAt(DateTime.utc(2026, 7, 24), 'Mars/Base'),
        returnsNormally,
      );
    });

    test('nextFridayOnOrAfter returns today when today is Friday', () {
      expect(FridayDetector.nextFridayOnOrAfter(_friday), _friday);
      expect(FridayDetector.nextFridayOnOrAfter(_thursday), _friday);
      expect(
        FridayDetector.nextFridayOnOrAfter(_saturday),
        DateTime(2026, 7, 31),
      );
    });

    test('finds exactly one Friday in any seven-day span', () {
      for (var offset = 0; offset < 7; offset++) {
        final from = DateTime(2026, 7, 20 + offset);
        expect(
          FridayDetector.fridaysWithin(from: from, days: 7),
          hasLength(1),
          reason: 'seven days from $from did not contain exactly one Friday',
        );
      }
    });
  });

  group('Jumu\'ah replaces Dhuhr on Fridays only', () {
    test('replaces the Dhuhr window on a Friday', () {
      final result = JumuahScheduler.apply(
        windows: _windowsOn(_friday),
        settings: _settings(),
        timezone: _timezone,
      );

      expect(result.application, JumuahApplication.applied);

      final dhuhr = result.windows.windowFor(PrayerName.dhuhr);
      expect(dhuhr.isJumuah, isTrue);
      expect(dhuhr.displayName, "Jumu'ah");
      expect(_localTime(dhuhr.startsAt), const LocalTimeOfDay(14, 0));
      expect(_localTime(dhuhr.endsAt), const LocalTimeOfDay(14, 15));
    });

    test('leaves every other day untouched', () {
      for (final date in [_thursday, _saturday, DateTime(2026, 7, 22)]) {
        final original = _windowsOn(date);
        final result = JumuahScheduler.apply(
          windows: original,
          settings: _settings(),
          timezone: _timezone,
        );

        expect(result.application, JumuahApplication.notApplied);
        expect(result.windows.windowFor(PrayerName.dhuhr).isJumuah, isFalse);
        expect(
          result.windows.windowFor(PrayerName.dhuhr),
          original.windowFor(PrayerName.dhuhr),
          reason: '$date was modified',
        );
      }
    });

    test('leaves the other four prayers alone on a Friday', () {
      final original = _windowsOn(_friday);
      final result = JumuahScheduler.applyTo(
        windows: original,
        settings: _settings(),
        timezone: _timezone,
      );

      for (final prayer in [
        PrayerName.fajr,
        PrayerName.asr,
        PrayerName.maghrib,
        PrayerName.isha,
      ]) {
        expect(
          result.windowFor(prayer),
          original.windowFor(prayer),
          reason: '${prayer.displayName} changed on a Friday',
        );
      }
    });

    test('does nothing when Smart Jumu\'ah is switched off', () {
      final result = JumuahScheduler.apply(
        windows: _windowsOn(_friday),
        settings: _settings(enabled: false),
        timezone: _timezone,
      );
      expect(result.application, JumuahApplication.notApplied);
    });

    test('does nothing until a mosque has been chosen', () {
      // A half-configured feature must not silently move Dhuhr.
      final result = JumuahScheduler.apply(
        windows: _windowsOn(_friday),
        settings: _settings(mosqueId: null),
        timezone: _timezone,
      );
      expect(result.application, JumuahApplication.notApplied);
    });
  });

  group('mosque profiles', () {
    test('Home Mosque uses 2:00–2:15 PM', () {
      final windows = JumuahScheduler.applyTo(
        windows: _windowsOn(_friday),
        settings: _settings(mosqueId: 'home'),
        timezone: _timezone,
      );
      final dhuhr = windows.windowFor(PrayerName.dhuhr);

      expect(_localTime(dhuhr.startsAt), const LocalTimeOfDay(14, 0));
      expect(_localTime(dhuhr.endsAt), const LocalTimeOfDay(14, 15));
      expect(dhuhr.duration, const Duration(minutes: 15));
    });

    test('University Mosque uses 1:15–1:30 PM', () {
      final windows = JumuahScheduler.applyTo(
        windows: _windowsOn(_friday),
        settings: _settings(mosqueId: 'university'),
        timezone: _timezone,
      );
      final dhuhr = windows.windowFor(PrayerName.dhuhr);

      expect(_localTime(dhuhr.startsAt), const LocalTimeOfDay(13, 15));
      expect(_localTime(dhuhr.endsAt), const LocalTimeOfDay(13, 30));
    });

    test('switching mosque changes the window', () {
      Duration startOf(String mosqueId) {
        final windows = JumuahScheduler.applyTo(
          windows: _windowsOn(_friday),
          settings: _settings(mosqueId: mosqueId),
          timezone: _timezone,
        );
        final start = windows.windowFor(PrayerName.dhuhr).startsAt;
        return Duration(
          minutes: _localTime(start).minutesSinceMidnight,
        );
      }

      expect(
        startOf('home'),
        isNot(startOf('university')),
      );
    });

    test('edited times are honoured', () {
      final custom = _mosque(
        'home',
        startsAt: const LocalTimeOfDay(13, 30),
        endsAt: const LocalTimeOfDay(14, 0),
      );

      final windows = JumuahScheduler.applyTo(
        windows: _windowsOn(_friday),
        settings: _settings(override: custom),
        timezone: _timezone,
      );
      final dhuhr = windows.windowFor(PrayerName.dhuhr);

      expect(_localTime(dhuhr.startsAt), const LocalTimeOfDay(13, 30));
      expect(dhuhr.duration, const Duration(minutes: 30));
    });
  });

  group('a configured time cannot break the schedule', () {
    test('a start before Dhuhr is clamped to Dhuhr', () {
      // Jumu'ah replaces Dhuhr, so it cannot begin before Dhuhr's time enters.
      final tooEarly = _mosque(
        'home',
        startsAt: const LocalTimeOfDay(6, 0),
        endsAt: const LocalTimeOfDay(14, 0),
      );

      final base = _windowsOn(_friday);
      final result = JumuahScheduler.apply(
        windows: base,
        settings: _settings(override: tooEarly),
        timezone: _timezone,
      );

      expect(result.application, JumuahApplication.appliedWithClamping);
      expect(
        result.windows.windowFor(PrayerName.dhuhr).startsAt,
        base.windowFor(PrayerName.dhuhr).startsAt,
      );
    });

    test('an end after Asr is clamped to Asr', () {
      final tooLate = _mosque(
        'home',
        startsAt: const LocalTimeOfDay(14, 0),
        endsAt: const LocalTimeOfDay(23, 59),
      );

      final base = _windowsOn(_friday);
      final result = JumuahScheduler.apply(
        windows: base,
        settings: _settings(override: tooLate),
        timezone: _timezone,
      );

      expect(result.application, JumuahApplication.appliedWithClamping);
      expect(
        result.windows.windowFor(PrayerName.dhuhr).endsAt,
        base.windowFor(PrayerName.dhuhr).endsAt,
      );
    });

    test('a window entirely outside Dhuhr falls back to Dhuhr', () {
      // 6:00–6:30 AM is before Dhuhr on any day; clamping collapses it, so the
      // only correct answer is ordinary Dhuhr.
      final impossible = _mosque(
        'home',
        startsAt: const LocalTimeOfDay(6, 0),
        endsAt: const LocalTimeOfDay(6, 30),
      );

      final base = _windowsOn(_friday);
      final result = JumuahScheduler.apply(
        windows: base,
        settings: _settings(override: impossible),
        timezone: _timezone,
      );

      expect(result.application, JumuahApplication.invalidProfile);
      expect(
        result.windows.windowFor(PrayerName.dhuhr),
        base.windowFor(PrayerName.dhuhr),
      );
    });

    test('an inverted profile is rejected rather than run backwards', () {
      final inverted = _mosque(
        'home',
        startsAt: const LocalTimeOfDay(14, 30),
        endsAt: const LocalTimeOfDay(14, 0),
      );
      expect(inverted.isValid, isFalse);

      final result = JumuahScheduler.apply(
        windows: _windowsOn(_friday),
        settings: _settings(override: inverted),
        timezone: _timezone,
      );
      expect(result.application, JumuahApplication.notApplied);
    });

    test('the replaced window never overlaps Asr', () {
      final windows = JumuahScheduler.applyTo(
        windows: _windowsOn(_friday),
        settings: _settings(),
        timezone: _timezone,
      );

      final dhuhr = windows.windowFor(PrayerName.dhuhr);
      final asr = windows.windowFor(PrayerName.asr);
      expect(dhuhr.endsAt.isAfter(asr.startsAt), isFalse);
    });

    test('an unknown timezone falls back to Dhuhr', () {
      final result = JumuahScheduler.apply(
        windows: _windowsOn(_friday),
        settings: _settings(),
        timezone: 'Mars/Olympus_Mons',
      );
      expect(result.application, JumuahApplication.invalidProfile);
    });
  });

  group('preference memory', () {
    test('a fresh install asks on Friday and not before', () {
      final manager = JumuahManager(
        InMemoryJumuahPreferenceRepository(_settings(mosqueId: null)),
      );

      expect(manager.statusFor(_friday).needsLocationChoice, isTrue);
      // Asking on a Tuesday about a Friday decision is noise.
      expect(manager.statusFor(_thursday).needsLocationChoice, isFalse);
    });

    test('the choice is remembered for every later Friday', () async {
      final repository =
          InMemoryJumuahPreferenceRepository(_settings(mosqueId: null));
      final manager = JumuahManager(repository);

      await manager.chooseMosque('university');

      expect(manager.statusFor(_friday).needsLocationChoice, isFalse);
      expect(manager.statusFor(_friday).mosque?.id, 'university');
      // The following Friday, and the one after.
      for (final later in [DateTime(2026, 7, 31), DateTime(2026, 8, 7)]) {
        expect(manager.statusFor(later).needsLocationChoice, isFalse);
      }
      // Asked once, stored once.
      expect(repository.writeCount, 1);
    });

    test('resetting makes the app ask again', () async {
      final manager = JumuahManager(
        InMemoryJumuahPreferenceRepository(_settings()),
      );

      expect(manager.statusFor(_friday).needsLocationChoice, isFalse);
      await manager.resetSelection();
      expect(manager.statusFor(_friday).needsLocationChoice, isTrue);
    });

    test('changing mosque times keeps the chosen mosque', () async {
      final manager = JumuahManager(
        InMemoryJumuahPreferenceRepository(_settings(mosqueId: 'university')),
      );

      await manager.saveMosque(
        _mosque(
          'home',
          startsAt: const LocalTimeOfDay(13, 0),
          endsAt: const LocalTimeOfDay(13, 15),
        ),
      );

      expect(manager.settings.selectedMosqueId, 'university');
      expect(
        manager.settings.mosqueById('home')!.startsAt,
        const LocalTimeOfDay(13, 0),
      );
    });

    test('disabling keeps the remembered mosque for later', () async {
      final manager = JumuahManager(
        InMemoryJumuahPreferenceRepository(_settings()),
      );

      await manager.setEnabled(false);
      expect(manager.statusFor(_friday).isActive, isFalse);

      await manager.setEnabled(true);
      expect(manager.statusFor(_friday).isActive, isTrue);
      expect(manager.settings.selectedMosqueId, 'home');
    });

    test('survives a JSON round trip, as it must across a restart', () {
      final original = _settings(
        mosqueId: 'university',
        override: _mosque(
          'home',
          startsAt: const LocalTimeOfDay(13, 45),
          endsAt: const LocalTimeOfDay(14, 0),
        ),
      );

      final restored = JumuahSettings.fromJson(original.toJson());
      expect(restored, original);
      expect(restored.selectedMosqueId, 'university');
      expect(
        restored.mosqueById('home')!.startsAt,
        const LocalTimeOfDay(13, 45),
      );
    });

    test('an unchosen mosque round-trips as unchosen', () {
      // Null is meaningful — it is what triggers the prompt — so it must not
      // become Home Mosque on a restart.
      final restored =
          JumuahSettings.fromJson(_settings(mosqueId: null).toJson());
      expect(restored.selectedMosqueId, isNull);
      expect(restored.needsMosqueChoice, isTrue);
    });
  });

  group('slots and blocking', () {
    PrayerDay jumuahDay({String mosqueId = 'home'}) {
      return PrayerDay.fromWindows(
        JumuahScheduler.applyTo(
          windows: _windowsOn(_friday),
          settings: _settings(mosqueId: mosqueId),
          timezone: _timezone,
        ),
      );
    }

    test('the Dhuhr slot is named Jumu\'ah', () {
      final slot = jumuahDay().slotFor(PrayerName.dhuhr, PrayerGrouping.none);
      expect(slot.displayName, "Jumu'ah");
      expect(slot.isJumuah, isTrue);
    });

    test('it still records against Dhuhr, so statistics stay comparable', () {
      // Jumu'ah is the Dhuhr obligation. A sixth prayer would give Friday a
      // different denominator from every other day.
      final day = jumuahDay();
      expect(day.entries, hasLength(5));
      expect(day.entryFor(PrayerName.dhuhr).prayer, PrayerName.dhuhr);
    });

    test('blocking runs for the mosque window, not until Asr', () {
      final slot = jumuahDay().slotFor(PrayerName.dhuhr, PrayerGrouping.none);
      expect(slot.duration, const Duration(minutes: 15));

      final ordinary = PrayerDay.fromWindows(_windowsOn(_friday))
          .slotFor(PrayerName.dhuhr, PrayerGrouping.none);
      expect(slot.duration, lessThan(ordinary.duration));
    });

    test('Jumu\'ah is never absorbed into a combined pair', () {
      // A fifteen-minute congregation cannot swallow Asr, and extending it to
      // Maghrib is not what combining means.
      final slots = jumuahDay().slots(PrayerGrouping.both);

      final jumuah =
          slots.firstWhere((slot) => slot.contains(PrayerName.dhuhr));
      expect(jumuah.isCombined, isFalse);
      expect(jumuah.displayName, "Jumu'ah");

      final asr = slots.firstWhere((slot) => slot.contains(PrayerName.asr));
      expect(asr.isCombined, isFalse);

      // Maghrib+Isha is unaffected.
      final evening =
          slots.firstWhere((slot) => slot.contains(PrayerName.maghrib));
      expect(evening.isCombined, isTrue);
    });

    test('every prayer still appears exactly once', () {
      for (final grouping in PrayerGrouping.values) {
        final covered = jumuahDay()
            .slots(grouping)
            .expand((slot) => slot.prayers)
            .map((entry) => entry.prayer)
            .toList();

        expect(covered.toSet(), PrayerName.values.toSet());
        expect(covered.length, PrayerName.values.length);
      }
    });
  });

  group('verification', () {
    PrayerSlot jumuahSlot() => PrayerDay.fromWindows(
          JumuahScheduler.applyTo(
            windows: _windowsOn(_friday),
            settings: _settings(),
            timezone: _timezone,
          ),
        ).slotFor(PrayerName.dhuhr, PrayerGrouping.none);

    const controller = JumuahVerificationController();

    test('is verifiable inside the window', () {
      final slot = jumuahSlot();
      expect(
        controller.outcomeFor(
          slot: slot,
          now: slot.window.startsAt.add(const Duration(minutes: 5)),
        ),
        JumuahVerificationOutcome.verifiable,
      );
    });

    test('is not yet open before the khutbah', () {
      final slot = jumuahSlot();
      expect(
        controller.outcomeFor(
          slot: slot,
          now: slot.window.startsAt.subtract(const Duration(minutes: 5)),
        ),
        JumuahVerificationOutcome.notYetOpen,
      );
    });

    test('a missed Jumu\'ah is not offered as qaza', () {
      // Jumu'ah has no make-up form; the person prays Dhuhr instead. Offering
      // qaza would tell the user something untrue about their obligation.
      final slot = jumuahSlot();

      expect(
        controller.outcomeFor(
          slot: slot,
          now: slot.window.endsAt.add(const Duration(minutes: 30)),
        ),
        JumuahVerificationOutcome.missedPrayDhuhrInstead,
      );
      expect(controller.offersQaza(slot), isFalse);
    });

    test('an ordinary prayer still offers qaza', () {
      final ordinary = PrayerDay.fromWindows(_windowsOn(_thursday))
          .slotFor(PrayerName.dhuhr, PrayerGrouping.none);
      expect(controller.offersQaza(ordinary), isTrue);
    });

    test('the record captures mosque and block duration', () {
      final slot = jumuahSlot();
      final verifiedAt = slot.window.startsAt.add(const Duration(minutes: 7));

      final record = controller.recordFor(
        slot: slot,
        date: _friday,
        mosque: MosqueProfile.defaults().first,
        verifiedAt: verifiedAt,
      );

      expect(record.mosqueId, 'home');
      expect(record.mosqueName, 'Home Mosque');
      expect(record.blockDuration, const Duration(minutes: 7));
      expect(record.toColumns()['was_jumuah'], 1);
      expect(record.toColumns()['jumuah_location'], 'home');
    });
  });

  group('time of day value object', () {
    test('formats in 12- and 24-hour forms', () {
      expect(const LocalTimeOfDay(14, 0).format(), '2:00 PM');
      expect(const LocalTimeOfDay(13, 15).format(), '1:15 PM');
      expect(const LocalTimeOfDay(0, 5).format(), '12:05 AM');
      expect(const LocalTimeOfDay(14, 0).format(use24Hour: true), '14:00');
    });

    test('orders correctly', () {
      expect(const LocalTimeOfDay(13, 15) < const LocalTimeOfDay(14, 0), isTrue);
      expect(const LocalTimeOfDay(14, 0) > const LocalTimeOfDay(13, 59), isTrue);
    });

    test('adding minutes clamps at end of day rather than wrapping', () {
      // Wrapping would produce a window that runs backwards into the next day.
      expect(
        const LocalTimeOfDay(23, 50).plusMinutes(30),
        const LocalTimeOfDay(23, 59),
      );
      expect(
        const LocalTimeOfDay(14, 0).plusMinutes(15),
        const LocalTimeOfDay(14, 15),
      );
    });
  });
}
