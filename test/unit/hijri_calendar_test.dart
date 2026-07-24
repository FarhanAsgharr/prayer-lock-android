/// Tests for the Hijri calendar and the occasions derived from it.
///
/// Calendar arithmetic is the kind of code that looks right and is off by a
/// day, so these check round-trips and known anchor dates rather than trusting
/// the formulae. The ±1 day caveat against local moon sighting is a *product*
/// caveat, not licence for the arithmetic itself to drift.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/features/islamic_calendar/domain/entities/hijri_date.dart';
import 'package:prayer_lock/features/islamic_calendar/domain/entities/islamic_occasion.dart';
import 'package:prayer_lock/features/islamic_calendar/domain/usecases/ramadan_status.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

import '../support/prayer_fixtures.dart';

void main() {
  tz_data.initializeTimeZones();

  group('calendar arithmetic', () {
    test('the epoch converts to 1 Muharram 1', () {
      // 16 July 622 CE (Julian) is 1 AH by construction. Getting this wrong
      // shifts every date the app ever shows.
      final epoch = HijriDate.fromJdn(1948439);
      expect(epoch.year, 1);
      expect(epoch.month, HijriMonth.muharram);
      expect(epoch.day, 1);
    });

    test('round-trips Gregorian -> Hijri -> Gregorian', () {
      // Every day across four years, including two leap years either side.
      var date = DateTime(2024, 1, 1);
      final end = DateTime(2028, 1, 1);
      var checked = 0;

      while (date.isBefore(end)) {
        final hijri = HijriDate.fromGregorian(date);
        expect(
          hijri.toGregorian(),
          date,
          reason: '$date did not round-trip (via $hijri)',
        );
        date = DateTime(date.year, date.month, date.day + 1);
        checked++;
      }

      expect(checked, greaterThan(1400));
    });

    test('round-trips Hijri -> JDN -> Hijri', () {
      for (var year = 1440; year <= 1460; year++) {
        for (final month in HijriMonth.values) {
          for (final day in [1, 15, 29]) {
            final original = HijriDate(year: year, month: month, day: day);
            expect(HijriDate.fromJdn(original.toJdn()), original);
          }
        }
      }
    });

    test('consecutive days advance by exactly one', () {
      var hijri = HijriDate.fromGregorian(DateTime(2026, 1, 1));
      for (var i = 0; i < 800; i++) {
        final next = hijri.addDays(1);
        expect(next.toJdn() - hijri.toJdn(), 1);
        hijri = next;
      }
    });

    test('months are 29 or 30 days, never anything else', () {
      for (var year = 1445; year <= 1455; year++) {
        for (final month in HijriMonth.values) {
          final first = HijriDate(year: year, month: month, day: 1);
          final nextMonth = month == HijriMonth.dhuAlHijjah
              ? HijriDate(year: year + 1, month: HijriMonth.muharram, day: 1)
              : HijriDate(
                  year: year,
                  month: HijriMonth.fromNumber(month.number + 1),
                  day: 1,
                );

          final length = nextMonth.toJdn() - first.toJdn();
          expect(
            length,
            anyOf(29, 30),
            reason: '${month.displayName} $year was $length days',
          );
        }
      }
    });

    test('a year is 354 or 355 days', () {
      for (var year = 1445; year <= 1465; year++) {
        final start = HijriDate(year: year, month: HijriMonth.muharram, day: 1);
        final next =
            HijriDate(year: year + 1, month: HijriMonth.muharram, day: 1);

        final length = next.toJdn() - start.toJdn();
        expect(length, anyOf(354, 355), reason: 'year $year was $length days');
        expect(length == 355, start.isLeapYear);
      }
    });

    test('a 30-year cycle is exactly 10631 days', () {
      // The defining property of the tabular calendar.
      final start = const HijriDate(year: 1441, month: HijriMonth.muharram, day: 1);
      final end = const HijriDate(year: 1471, month: HijriMonth.muharram, day: 1);
      expect(end.toJdn() - start.toJdn(), 10631);
    });

    test('orders correctly', () {
      final earlier = const HijriDate(year: 1447, month: HijriMonth.rajab, day: 3);
      final later = const HijriDate(year: 1447, month: HijriMonth.ramadan, day: 1);
      expect(earlier.compareTo(later), lessThan(0));
      expect(later.compareTo(earlier), greaterThan(0));
    });

    test('formats readably in both scripts', () {
      final date = const HijriDate(year: 1447, month: HijriMonth.ramadan, day: 12);
      expect(date.format(), '12 Ramadan 1447');
      expect(date.formatArabic(), contains('رمضان'));
      expect(date.formattedYear, '1447 AH');
    });
  });

  group('occasions', () {
    HijriDate at(int year, HijriMonth month, int day) =>
        HijriDate(year: year, month: month, day: day);

    test('Ramadan is detected and numbered', () {
      final day12 = at(1447, HijriMonth.ramadan, 12);
      expect(IslamicOccasions.isRamadan(day12), isTrue);

      final occasions = IslamicOccasions.on(day12);
      expect(occasions.any((o) => o.name == 'Ramadan'), isTrue);
      expect(
        occasions.firstWhere((o) => o.name == 'Ramadan').description,
        contains('Day 12'),
      );
    });

    test('Eid al-Fitr is the 1st of Shawwal', () {
      final eid = at(1447, HijriMonth.shawwal, 1);
      expect(IslamicOccasions.isEid(eid), isTrue);
      expect(IslamicOccasions.eidOn(eid)!.name, 'Eid al-Fitr');

      // Not the 2nd.
      expect(IslamicOccasions.isEid(at(1447, HijriMonth.shawwal, 2)), isFalse);
    });

    test('Eid al-Adha is the 10th of Dhu al-Hijjah', () {
      final eid = at(1447, HijriMonth.dhuAlHijjah, 10);
      expect(IslamicOccasions.eidOn(eid)!.name, 'Eid al-Adha');
    });

    test('Arafah is the 9th of Dhu al-Hijjah', () {
      final names = IslamicOccasions.on(at(1447, HijriMonth.dhuAlHijjah, 9))
          .map((o) => o.name);
      expect(names, contains('Day of Arafah'));
    });

    test('Ashura is the 10th of Muharram', () {
      final names =
          IslamicOccasions.on(at(1447, HijriMonth.muharram, 10)).map((o) => o.name);
      expect(names, contains('Ashura'));
    });

    test('White Days are the 13th to 15th', () {
      for (final day in [13, 14, 15]) {
        final names =
            IslamicOccasions.on(at(1447, HijriMonth.rajab, day)).map((o) => o.name);
        expect(names, contains('White Days'), reason: 'day $day');
      }
      for (final day in [12, 16]) {
        final names =
            IslamicOccasions.on(at(1447, HijriMonth.rajab, day)).map((o) => o.name);
        expect(names, isNot(contains('White Days')), reason: 'day $day');
      }
    });

    test('White Days are not offered during Ramadan', () {
      // The whole month is already fasted; suggesting an extra fast is noise.
      final names = IslamicOccasions.on(at(1447, HijriMonth.ramadan, 14))
          .map((o) => o.name);
      expect(names, isNot(contains('White Days')));
    });

    test('White Days are not offered on a day of Tashriq', () {
      // Fasting is forbidden then, so recommending it would be worse than
      // showing nothing.
      final names = IslamicOccasions.on(at(1447, HijriMonth.dhuAlHijjah, 13))
          .map((o) => o.name);
      expect(names, isNot(contains('White Days')));
    });

    test('Laylatul Qadr is marked on odd nights of the last ten only', () {
      for (final day in [21, 23, 25, 27, 29]) {
        final names = IslamicOccasions.on(at(1447, HijriMonth.ramadan, day))
            .map((o) => o.name);
        expect(names, contains('Laylatul Qadr'), reason: 'night $day');
      }
      for (final day in [20, 22, 24, 19]) {
        final names = IslamicOccasions.on(at(1447, HijriMonth.ramadan, day))
            .map((o) => o.name);
        expect(names, isNot(contains('Laylatul Qadr')), reason: 'night $day');
      }
    });

    test('every occasion is flagged as an estimate', () {
      // The calendar is arithmetic, not a sighting. Claiming certainty would
      // be the actual error.
      for (final occasion in IslamicOccasions.on(
        at(1447, HijriMonth.ramadan, 27),
      )) {
        expect(occasion.isEstimated, isTrue);
      }
    });

    test('Takbeer spans Arafah through Tashriq, and Eid al-Fitr', () {
      for (final day in [9, 10, 11, 12, 13]) {
        expect(
          IslamicOccasions.callsForTakbeer(at(1447, HijriMonth.dhuAlHijjah, day)),
          isTrue,
          reason: 'Dhu al-Hijjah $day',
        );
      }
      expect(
        IslamicOccasions.callsForTakbeer(at(1447, HijriMonth.shawwal, 1)),
        isTrue,
      );
      expect(
        IslamicOccasions.callsForTakbeer(at(1447, HijriMonth.rajab, 5)),
        isFalse,
      );
    });

    test('sacred months are identified', () {
      expect(HijriMonth.muharram.isSacred, isTrue);
      expect(HijriMonth.rajab.isSacred, isTrue);
      expect(HijriMonth.dhuAlQadah.isSacred, isTrue);
      expect(HijriMonth.dhuAlHijjah.isSacred, isTrue);
      expect(HijriMonth.ramadan.isSacred, isFalse);
    });

    test('counts down to the next occurrence', () {
      final beforeRamadan = at(1447, HijriMonth.shaban, 20);
      final days = IslamicOccasions.daysUntil(
        beforeRamadan,
        HijriMonth.ramadan,
        1,
      );

      expect(days, isNotNull);
      expect(days, greaterThan(0));
      expect(days, lessThan(30));
    });

    test('a countdown past the month rolls into next year', () {
      // Standing in Shawwal, the next Ramadan is nearly a year away, not
      // negative.
      final afterRamadan = at(1447, HijriMonth.shawwal, 5);
      final days =
          IslamicOccasions.daysUntil(afterRamadan, HijriMonth.ramadan, 1);

      expect(days, isNotNull);
      expect(days, greaterThan(300));
    });
  });

  group('Ramadan bound to prayer times', () {
    final windows = windowsAt();
    final ramadanDay = const HijriDate(
      year: 1447,
      month: HijriMonth.ramadan,
      day: 12,
    );

    test('Sehri ends at Fajr and Iftar is at Maghrib', () {
      // The Hijri date is an estimate; these instants are not. A user whose
      // local sighting differs by a day still breaks their fast correctly.
      final status = IslamicDayStatus.ramadan(
        hijri: ramadanDay,
        windows: windows,
      );

      expect(status.sehriEndsAt, windows.windowFor(PrayerName.fajr).startsAt);
      expect(status.iftarAt, windows.windowFor(PrayerName.maghrib).startsAt);
      expect(status.taraweehFrom, windows.windowFor(PrayerName.isha).startsAt);
    });

    test('the phase follows the clock', () {
      final fajr = windows.windowFor(PrayerName.fajr).startsAt;
      final maghrib = windows.windowFor(PrayerName.maghrib).startsAt;

      RamadanStatus at(DateTime now) => IslamicDayStatus.ramadanAt(
            hijri: ramadanDay,
            windows: windows,
            now: now,
          );

      expect(
        at(fajr.subtract(const Duration(hours: 1))).phase,
        FastPhase.sehri,
      );
      expect(at(fajr.add(const Duration(hours: 1))).phase, FastPhase.fasting);
      expect(
        at(maghrib.add(const Duration(minutes: 1))).phase,
        FastPhase.afterIftar,
      );
    });

    test('countdowns run out rather than going negative', () {
      final status = IslamicDayStatus.ramadan(
        hijri: ramadanDay,
        windows: windows,
      );

      final afterIftar = status.iftarAt!.add(const Duration(hours: 1));
      expect(status.sehriRemaining(afterIftar), isNull);
      expect(status.iftarRemaining(afterIftar), isNull);

      final beforeFajr =
          status.sehriEndsAt!.subtract(const Duration(minutes: 30));
      expect(status.sehriRemaining(beforeFajr), const Duration(minutes: 30));
    });

    test('the last ten nights are identified', () {
      RamadanStatus onDay(int day) => IslamicDayStatus.ramadan(
            hijri: HijriDate(
              year: 1447,
              month: HijriMonth.ramadan,
              day: day,
            ),
            windows: windows,
          );

      expect(onDay(20).isLastTen, isFalse);
      expect(onDay(21).isLastTen, isTrue);
      expect(onDay(21).isPossibleLaylatulQadr, isTrue);
      expect(onDay(22).isPossibleLaylatulQadr, isFalse);
    });

    test('outside Ramadan everything is inert', () {
      final status = IslamicDayStatus.ramadan(
        hijri: const HijriDate(year: 1447, month: HijriMonth.rajab, day: 5),
        windows: windows,
      );

      expect(status.isRamadan, isFalse);
      expect(status.dayOfRamadan, 0);
      expect(status.sehriEndsAt, isNull);
    });

    test('works before the schedule has resolved', () {
      // The dashboard renders before the repository answers; Ramadan must
      // still be identified, just without countdowns.
      final status =
          IslamicDayStatus.ramadan(hijri: ramadanDay, windows: null);

      expect(status.isRamadan, isTrue);
      expect(status.dayOfRamadan, 12);
      expect(status.iftarAt, isNull);
    });
  });

  group('Eid', () {
    final windows = windowsAt();

    test('the prayer window runs from after sunrise until Dhuhr', () {
      // Unlike the five daily prayers, the Eid prayer has no single moment —
      // mosques hold it anywhere in this range.
      final status = IslamicDayStatus.eid(
        hijri: const HijriDate(year: 1447, month: HijriMonth.shawwal, day: 1),
        windows: windows,
      );

      expect(status.isEid, isTrue);
      expect(status.name, 'Eid al-Fitr');
      expect(status.eidPrayerFrom!.isAfter(windows.sunrise), isTrue);
      expect(
        status.eidPrayerUntil,
        windows.windowFor(PrayerName.dhuhr).startsAt,
      );
      expect(status.callsForTakbeer, isTrue);
    });

    test('an ordinary day counts down to the next Eid', () {
      final status = IslamicDayStatus.eid(
        hijri: const HijriDate(year: 1447, month: HijriMonth.rajab, day: 10),
        windows: windows,
      );

      expect(status.isEid, isFalse);
      expect(status.daysUntilNextEid, isNotNull);
      expect(status.daysUntilNextEid, greaterThan(0));
      expect(status.nextEidName, isNotNull);
    });

    test('Takbeer is flagged on Arafah even though it is not Eid', () {
      final status = IslamicDayStatus.eid(
        hijri: const HijriDate(year: 1447, month: HijriMonth.dhuAlHijjah, day: 9),
        windows: windows,
      );

      expect(status.isEid, isFalse);
      expect(status.callsForTakbeer, isTrue);
    });
  });
}
