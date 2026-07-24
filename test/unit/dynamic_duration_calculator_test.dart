/// Tests for dynamic prayer-duration calculation.
///
/// This is the load-bearing computation of the whole feature: it decides how
/// long a phone stays locked. Every duration here must be derived from the
/// schedule — a value that turns out to be a constant would mean the feature
/// silently regressed to the fixed windows it replaced.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_window.dart';
import 'package:prayer_lock/features/prayer_times/domain/usecases/dynamic_duration_calculator.dart';
import 'package:prayer_lock/features/prayer_times/domain/usecases/prayer_time_calculator.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

import '../support/prayer_fixtures.dart';

void main() {
  tz_data.initializeTimeZones();

  final windows = windowsAt();

  group('window boundaries follow the schedule, not a constant', () {
    test('Fajr ends at sunrise', () {
      final fajr = windows.windowFor(PrayerName.fajr);
      expect(fajr.endsAt, windows.sunrise);
      expect(fajr.boundary, WindowBoundary.sunrise);
    });

    test('Dhuhr ends when Asr begins', () {
      expect(
        windows.windowFor(PrayerName.dhuhr).endsAt,
        windows.windowFor(PrayerName.asr).startsAt,
      );
    });

    test('Asr ends when Maghrib begins', () {
      expect(
        windows.windowFor(PrayerName.asr).endsAt,
        windows.windowFor(PrayerName.maghrib).startsAt,
      );
    });

    test('Maghrib ends when Isha begins', () {
      expect(
        windows.windowFor(PrayerName.maghrib).endsAt,
        windows.windowFor(PrayerName.isha).startsAt,
      );
    });

    test('Isha ends at the following day Fajr', () {
      final isha = windows.windowFor(PrayerName.isha);
      expect(isha.endsAt, windows.nextDayFajr);
      expect(isha.boundary, WindowBoundary.nextDayFajr);
      // The Isha window spans midnight, so it must be longer than the gap to
      // the end of the calendar day.
      expect(isha.startsAt.isBefore(isha.endsAt), isTrue);
    });

    test('Fajr does not run on to Dhuhr', () {
      // The morning gap between sunrise and Dhuhr belongs to no prayer. If Fajr
      // ran to Dhuhr, apps would stay blocked for most of the morning.
      final fajr = windows.windowFor(PrayerName.fajr);
      final dhuhr = windows.windowFor(PrayerName.dhuhr);
      expect(fajr.endsAt.isBefore(dhuhr.startsAt), isTrue);
    });
  });

  group('durations are computed', () {
    test('every window has a positive duration', () {
      for (final window in windows.windows) {
        expect(
          window.duration,
          greaterThan(Duration.zero),
          reason: '${window.prayer.displayName} has a non-positive duration',
        );
      }
    });

    test('durations differ between prayers', () {
      // The defining property of the feature. If these were all equal, the
      // windows would be fixed, whatever the code claims.
      final distinct =
          windows.windows.map((w) => w.duration.inMinutes).toSet();
      expect(distinct.length, greaterThan(1));
    });

    test('durations differ across the year at the same location', () {
      final summer = windowsAt(date: DateTime(2026, 7, 20));
      final winter = windowsAt(date: DateTime(2026, 1, 20));

      expect(
        summer.windowFor(PrayerName.fajr).duration,
        isNot(winter.windowFor(PrayerName.fajr).duration),
      );
    });

    test('the day total is the sum of the five windows', () {
      final sum = windows.windows.fold(
        Duration.zero,
        (total, window) => total + window.duration,
      );
      expect(windows.totalDuration, sum);
    });

    test('windows do not overlap', () {
      final ordered = [...windows.windows]
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

      for (var i = 1; i < ordered.length; i++) {
        expect(
          ordered[i].startsAt.isBefore(ordered[i - 1].endsAt),
          isFalse,
          reason: '${ordered[i].prayer.displayName} overlaps '
              '${ordered[i - 1].prayer.displayName}',
        );
      }
    });
  });

  group('window queries', () {
    test('contains is inclusive of the start and exclusive of the end', () {
      final dhuhr = windows.windowFor(PrayerName.dhuhr);
      expect(dhuhr.contains(dhuhr.startsAt), isTrue);
      expect(dhuhr.contains(dhuhr.endsAt), isFalse);
      expect(
        dhuhr.contains(dhuhr.endsAt.subtract(const Duration(milliseconds: 1))),
        isTrue,
      );
    });

    test('windowAt finds the open window and nothing in the morning gap', () {
      final dhuhr = windows.windowFor(PrayerName.dhuhr);
      final inside = dhuhr.startsAt.add(const Duration(minutes: 30));
      expect(windows.windowAt(inside)?.prayer, PrayerName.dhuhr);

      // Between sunrise and Dhuhr no prayer is due.
      final gap = windows.sunrise.add(const Duration(hours: 1));
      expect(windows.windowAt(gap), isNull);
    });

    test('remainingAt counts down and floors at zero', () {
      final asr = windows.windowFor(PrayerName.asr);
      expect(asr.remainingAt(asr.startsAt), asr.duration);
      expect(asr.remainingAt(asr.endsAt), Duration.zero);
      expect(
        asr.remainingAt(asr.endsAt.add(const Duration(hours: 3))),
        Duration.zero,
      );
    });

    test('progress runs from 0 to 1 across the window', () {
      final maghrib = windows.windowFor(PrayerName.maghrib);
      expect(maghrib.progressAt(maghrib.startsAt), 0.0);
      expect(maghrib.progressAt(maghrib.endsAt), 1.0);

      final midpoint = maghrib.startsAt.add(maghrib.duration ~/ 2);
      expect(maghrib.progressAt(midpoint), closeTo(0.5, 0.01));
    });

    test('nextWindowAfter skips windows already open', () {
      final dhuhr = windows.windowFor(PrayerName.dhuhr);
      final inside = dhuhr.startsAt.add(const Duration(minutes: 5));
      expect(windows.nextWindowAfter(inside)?.prayer, PrayerName.asr);
    });
  });

  group('out-of-order input is clamped rather than trusted', () {
    /// A schedule whose Isha lands after the following Fajr, which the
    /// high-latitude fallback rules can genuinely produce in midsummer.
    PrayerSchedule inverted() {
      final base = scheduleAt(
        location: makkah,
        date: DateTime(2026, 7, 20),
        utcOffsetHours: 3,
      );
      return PrayerSchedule(
        prayerDate: base.prayerDate,
        fajr: base.fajr,
        sunrise: base.sunrise,
        dhuhr: base.dhuhr,
        asr: base.asr,
        maghrib: base.maghrib,
        // Two days later: well past the following Fajr.
        isha: base.isha.add(const Duration(days: 2)),
      );
    }

    test('no window ever runs backwards', () {
      final result = DynamicDurationCalculator.fromSchedule(
        schedule: inverted(),
        nextDayFajr: DateTime.utc(2026, 7, 21, 1, 30),
      );

      for (final window in result.windows) {
        expect(
          window.endsAt.isBefore(window.startsAt),
          isFalse,
          reason: '${window.prayer.displayName} runs backwards',
        );
      }
    });

    test('clamping is reported rather than hidden', () {
      final result = DynamicDurationCalculator.fromSchedule(
        schedule: inverted(),
        nextDayFajr: DateTime.utc(2026, 7, 21, 1, 30),
      );
      expect(result.hasClampedWindows, isTrue);
    });

    test('a well-ordered schedule is not reported as clamped', () {
      expect(windows.hasClampedWindows, isFalse);
    });

    test('a collapsed window is empty rather than negative', () {
      final result = DynamicDurationCalculator.fromSchedule(
        schedule: inverted(),
        nextDayFajr: DateTime.utc(2026, 7, 21, 1, 30),
      );
      final isha = result.windowFor(PrayerName.isha);
      expect(isha.duration, Duration.zero);
      expect(isha.isEmpty, isTrue);
      // An empty window can never be the active one, so it cannot hold a lock.
      expect(isha.contains(isha.startsAt), isFalse);
    });
  });

  group('extreme latitudes still produce usable windows', () {
    test('midsummer inside the Arctic Circle yields ordered windows', () {
      final arctic = windowsAt(
        location: tromso,
        date: DateTime(2026, 6, 21),
        utcOffsetHours: 2,
      );

      for (final window in arctic.windows) {
        expect(window.duration.isNegative, isFalse);
      }
      expect(arctic.windowFor(PrayerName.isha).endsAt, arctic.nextDayFajr);
    });

    test('midwinter inside the Arctic Circle yields ordered windows', () {
      final arctic = windowsAt(
        location: tromso,
        date: DateTime(2026, 12, 21),
        utcOffsetHours: 1,
      );

      for (final window in arctic.windows) {
        expect(window.duration.isNegative, isFalse);
      }
    });
  });

  group('duration formatting', () {
    test('renders hours and minutes as the design specifies', () {
      expect(
        formatPrayerDuration(const Duration(hours: 3, minutes: 37)),
        '3 hours 37 minutes',
      );
      expect(
        formatPrayerDuration(const Duration(hours: 1, minutes: 23)),
        '1 hour 23 minutes',
      );
    });

    test('omits a zero component rather than printing "0 minutes"', () {
      expect(formatPrayerDuration(const Duration(hours: 2)), '2 hours');
      expect(formatPrayerDuration(const Duration(minutes: 45)), '45 minutes');
      expect(formatPrayerDuration(const Duration(minutes: 1)), '1 minute');
    });

    test('handles zero and negative durations without crashing', () {
      expect(formatPrayerDuration(Duration.zero), '0 minutes');
      expect(formatPrayerDuration(const Duration(minutes: -5)), '0 minutes');
    });

    test('short form is compact', () {
      expect(
        formatPrayerDurationShort(const Duration(hours: 3, minutes: 37)),
        '3h 37m',
      );
      expect(formatPrayerDurationShort(const Duration(hours: 2)), '2h');
      expect(formatPrayerDurationShort(const Duration(minutes: 20)), '20m');
      expect(formatPrayerDurationShort(Duration.zero), '0m');
    });
  });

  group('serialisation', () {
    test('the JSON projection carries durations and boundaries', () {
      final json = windows.toJson();
      final entries = json['windows'] as List;

      expect(entries, hasLength(5));

      final dhuhr = entries.firstWhere(
        (entry) => (entry as Map)['prayer'] == 'dhuhr',
      ) as Map<String, dynamic>;

      expect(
        dhuhr['durationMinutes'],
        windows.windowFor(PrayerName.dhuhr).duration.inMinutes,
      );
      expect(dhuhr['boundary'], 'asr');
    });
  });
}
