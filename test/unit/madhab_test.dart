/// Tests for how each school of jurisprudence affects the schedule.
///
/// These pin the religiously-significant differences: the Hanafi late Asr, the
/// fact that Ahl-e-Hadith follows the majority (not Hanafi), and the Ja'fari
/// (Shia) delayed Maghrib. Getting any of these wrong produces prayer times
/// that are not merely imprecise but doctrinally incorrect for those users.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:prayer_lock/features/prayer_times/domain/usecases/prayer_time_calculator.dart';

PrayerSchedule scheduleFor(Madhab madhab) => prayerTimeCalculator.calculate(
      CalculationRequest(
        latitude: 24.8607,
        longitude: 67.0011,
        // Karachi is UTC+5 with no DST, so the offset is constant.
        utcOffsetHours: 5,
        prayerDate: DateTime(2026, 7, 20),
        method: CalculationMethod.karachi,
        madhab: madhab,
      ),
    );

double minutesBetween(DateTime a, DateTime b) =>
    (a.difference(b).inSeconds / 60).abs();

void main() {
  group('school wire values match the backend enum', () {
    test('every school has a distinct, expected wire value', () {
      expect(Madhab.shafi.wireValue, 'shafi');
      expect(Madhab.hanafi.wireValue, 'hanafi');
      expect(Madhab.ahleHadith.wireValue, 'ahle_hadith');
      expect(Madhab.jafari.wireValue, 'jafari');
    });

    test('round-trips through fromWire', () {
      for (final madhab in Madhab.values) {
        expect(Madhab.fromWire(madhab.wireValue), madhab);
      }
    });
  });

  group('Asr shadow ratio', () {
    test('Hanafi Asr is significantly later than Shafi', () {
      final shafi = scheduleFor(Madhab.shafi);
      final hanafi = scheduleFor(Madhab.hanafi);

      expect(hanafi.asr.isAfter(shafi.asr), isTrue);
      expect(minutesBetween(hanafi.asr, shafi.asr), greaterThan(45));
    });

    test('Ahl-e-Hadith Asr matches Shafi, not Hanafi', () {
      // They follow the majority ratio-1 position; treating them like Hanafi
      // would push Asr over an hour late.
      expect(scheduleFor(Madhab.ahleHadith).asr, scheduleFor(Madhab.shafi).asr);
    });

    test('Jafari Asr matches Shafi', () {
      expect(scheduleFor(Madhab.jafari).asr, scheduleFor(Madhab.shafi).asr);
    });
  });

  group('Jafari Maghrib', () {
    test('is later than sunset', () {
      // The defining Shia difference. Recording Maghrib at sunset would have
      // these users break their fast and pray 10-15 minutes early each day.
      final shafi = scheduleFor(Madhab.shafi);
      final jafari = scheduleFor(Madhab.jafari);

      expect(jafari.maghrib.isAfter(shafi.maghrib), isTrue);
      final delay = minutesBetween(jafari.maghrib, shafi.maghrib);
      expect(delay, greaterThan(8));
      expect(delay, lessThan(25));
    });

    test('other schools use plain sunset', () {
      final shafi = scheduleFor(Madhab.shafi);
      expect(scheduleFor(Madhab.hanafi).maghrib, shafi.maghrib);
      expect(scheduleFor(Madhab.ahleHadith).maghrib, shafi.maghrib);
    });

    test('only Jafari carries a Maghrib angle', () {
      expect(Madhab.jafari.maghribAngle, 4.0);
      expect(Madhab.shafi.maghribAngle, isNull);
      expect(Madhab.hanafi.maghribAngle, isNull);
      expect(Madhab.ahleHadith.maghribAngle, isNull);
    });
  });

  group('display', () {
    test('every school has a non-empty display name and description', () {
      for (final madhab in Madhab.values) {
        expect(madhab.displayName, isNotEmpty);
        expect(madhab.description, isNotEmpty);
      }
    });

    test('Shia is clearly labelled', () {
      expect(Madhab.jafari.displayName.toLowerCase(), contains('shia'));
    });
  });
}
