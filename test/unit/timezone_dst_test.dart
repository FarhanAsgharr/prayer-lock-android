/// Tests for timezone, DST and travel handling.
///
/// Prayer times are anchored to absolute instants, which is what makes these
/// cases tractable. The bugs that remain are all in the conversions at the
/// edges: computing a future day with today's UTC offset, adding a Duration
/// where a calendar day was meant, or letting a DST transition inside the
/// scheduling horizon shift every subsequent day by an hour.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/features/prayer_times/data/datasources/device_prayer_time_provider.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../support/prayer_fixtures.dart';

void main() {
  tz_data.initializeTimeZones();

  group('UTC offset resolution', () {
    test('reports the offset on the given date, not today', () {
      // British Summer Time runs from late March to late October.
      expect(utcOffsetHoursAt('Europe/London', DateTime(2026, 1, 15)), 0.0);
      expect(utcOffsetHoursAt('Europe/London', DateTime(2026, 7, 15)), 1.0);
    });

    test('handles a half-hour zone', () {
      expect(utcOffsetHoursAt('Asia/Kolkata', DateTime(2026, 7, 15)), 5.5);
    });

    test('handles a three-quarter-hour zone', () {
      expect(utcOffsetHoursAt('Asia/Kathmandu', DateTime(2026, 7, 15)), 5.75);
    });

    test('falls back to UTC for an unknown zone rather than throwing', () {
      // A wrong-but-visible schedule prompts the user to re-pick a location; a
      // crash gives them nothing to act on.
      expect(utcOffsetHoursAt('Nowhere/Nothing', DateTime(2026, 7, 15)), 0.0);
    });

    test('a zone with no DST is stable across the year', () {
      expect(utcOffsetHoursAt('Asia/Riyadh', DateTime(2026, 1, 15)), 3.0);
      expect(utcOffsetHoursAt('Asia/Riyadh', DateTime(2026, 7, 15)), 3.0);
    });
  });

  group('DST transitions', () {
    const provider = DevicePrayerTimeProvider();

    test('a schedule spanning the spring transition stays ordered', () async {
      // BST begins on 29 March 2026.
      final settings = settingsWith(location: london);
      final days = await provider.fetchRange(
        from: DateTime(2026, 3, 27),
        days: 5,
        settings: settings,
      );

      expect(days, hasLength(5));
      for (final day in days) {
        expect(
          day.isMonotonic,
          isTrue,
          reason: '${day.date} is out of order across the DST boundary',
        );
      }
    });

    test('a schedule spanning the autumn transition stays ordered', () async {
      // BST ends on 25 October 2026.
      final settings = settingsWith(location: london);
      final days = await provider.fetchRange(
        from: DateTime(2026, 10, 23),
        days: 5,
        settings: settings,
      );

      for (final day in days) {
        expect(day.isMonotonic, isTrue, reason: '${day.date} is out of order');
      }
    });

    test('consecutive days advance by roughly one day, never by two', () async {
      // The failure this guards against is adding a Duration of 24 hours where
      // a calendar day was meant: across a transition that drifts by an hour,
      // and eventually skips or repeats a date entirely.
      final settings = settingsWith(location: london);
      final days = await provider.fetchRange(
        from: DateTime(2026, 3, 27),
        days: 5,
        settings: settings,
      );

      for (var i = 1; i < days.length; i++) {
        final gap = days[i].dhuhr.difference(days[i - 1].dhuhr);
        expect(gap.inHours, inInclusiveRange(22, 26));
      }
    });

    test('each returned day carries the date that was asked for', () async {
      final settings = settingsWith(location: london);
      final days = await provider.fetchRange(
        from: DateTime(2026, 3, 27),
        days: 5,
        settings: settings,
      );

      for (var i = 0; i < days.length; i++) {
        expect(days[i].date, DateTime(2026, 3, 27 + i));
      }
    });

    test('windows across the spring transition have positive durations',
        () async {
      // The lost hour falls inside the night, which is the Isha window.
      final windows = windowsAt(
        location: london,
        date: DateTime(2026, 3, 28),
        utcOffsetHours: utcOffsetHoursAt('Europe/London', DateTime(2026, 3, 28)),
      );

      for (final window in windows.windows) {
        expect(window.duration, greaterThan(Duration.zero));
      }
    });
  });

  group('travel', () {
    test('the same instant yields different local schedules', () {
      final makkahWindows = windowsAt(
        location: makkah,
        date: DateTime(2026, 7, 20),
        utcOffsetHours: 3,
      );
      final londonWindows = windowsAt(
        location: london,
        date: DateTime(2026, 7, 20),
        utcOffsetHours: 1,
      );

      expect(
        makkahWindows.windowFor(PrayerName.fajr).startsAt,
        isNot(londonWindows.windowFor(PrayerName.fajr).startsAt),
      );
    });

    test('durations differ markedly by latitude', () {
      // London in midsummer has a very short night, so its Isha window is
      // dramatically shorter than Makkah's. A fixed duration would be wrong for
      // one of them by hours.
      final makkahIsha = windowsAt(
        location: makkah,
        date: DateTime(2026, 6, 21),
        utcOffsetHours: 3,
      ).windowFor(PrayerName.isha).duration;

      final londonIsha = windowsAt(
        location: london,
        date: DateTime(2026, 6, 21),
        utcOffsetHours: 1,
      ).windowFor(PrayerName.isha).duration;

      expect(makkahIsha, isNot(londonIsha));
    });

    test('instants are timezone-independent once computed', () {
      // A UTC instant does not move when the device changes zone. This is the
      // property that lets already-armed alarms stay correct after travel.
      final windows = windowsAt();
      final fajr = windows.windowFor(PrayerName.fajr).startsAt;

      expect(fajr.isUtc, isTrue);
      expect(
        tz.TZDateTime.from(fajr, tz.getLocation('Asia/Tokyo'))
            .millisecondsSinceEpoch,
        fajr.millisecondsSinceEpoch,
      );
    });
  });

  group('year boundaries', () {
    const provider = DevicePrayerTimeProvider();

    test('a range spanning new year produces consecutive dates', () async {
      final days = await provider.fetchRange(
        from: DateTime(2026, 12, 30),
        days: 4,
        settings: settingsWith(),
      );

      expect(
        days.map((day) => day.date),
        [
          DateTime(2026, 12, 30),
          DateTime(2026, 12, 31),
          DateTime(2027, 1, 1),
          DateTime(2027, 1, 2),
        ],
      );
    });

    test('a leap day is handled', () async {
      final days = await provider.fetchRange(
        from: DateTime(2028, 2, 28),
        days: 3,
        settings: settingsWith(),
      );

      expect(days[1].date, DateTime(2028, 2, 29));
      expect(days[2].date, DateTime(2028, 3, 1));
    });

    test('windows across new year are well formed', () {
      final windows = windowsAt(date: DateTime(2026, 12, 31));

      for (final window in windows.windows) {
        expect(window.duration, greaterThan(Duration.zero));
      }
      // Isha on 31 December closes at the Fajr of 1 January.
      expect(
        windows.windowFor(PrayerName.isha).endsAt.isAfter(
              DateTime.utc(2026, 12, 31, 20),
            ),
        isTrue,
      );
    });
  });
}
