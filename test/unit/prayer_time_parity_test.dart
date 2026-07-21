/// Cross-implementation parity: the Dart engine must agree with the server.
///
/// The app calculates prayer times on-device so it works offline, while the
/// server calculates them to schedule push reminders. If the two drift, a user
/// gets a notification at one time and a lock at another — the single worst
/// failure mode this product has.
///
/// The fixtures are generated from the Python implementation by
/// `backend/scripts/generate_parity_fixtures.py`. Regenerate them whenever
/// either implementation changes, and never edit them by hand.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:prayer_lock/features/prayer_times/domain/usecases/prayer_time_calculator.dart';

/// Maximum permitted disagreement between implementations.
///
/// Zero would be ideal but is unrealistic: Python and Dart differ in
/// floating-point rounding on transcendental functions. One second is far
/// below the one-minute display granularity, so any user-visible time is
/// identical.
const Duration _tolerance = Duration(seconds: 1);

void main() {
  final fixtureFile = File('test/fixtures/prayer_time_parity.json');
  final fixtures =
      jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
  final cases = (fixtures['cases'] as List).cast<Map<String, dynamic>>();

  test('fixture file is populated', () {
    expect(cases, isNotEmpty,
        reason: 'Parity fixtures are missing; regenerate them.');
    expect(cases.length, greaterThanOrEqualTo(60));
  });

  group('parity with the Python backend', () {
    for (final testCase in cases) {
      final city = testCase['city'] as String;
      final date = DateTime.parse(testCase['date'] as String);
      final method =
          CalculationMethod.fromWire(testCase['method'] as String);
      final madhab = Madhab.fromWire(testCase['madhab'] as String);
      final rule =
          HighLatitudeRule.fromWire(testCase['highLatitudeRule'] as String);

      test('$city ${testCase['date']} ${method.wireValue}/${madhab.wireValue}',
          () {
        final schedule = prayerTimeCalculator.calculate(
          CalculationRequest(
            latitude: (testCase['latitude'] as num).toDouble(),
            longitude: (testCase['longitude'] as num).toDouble(),
            utcOffsetHours: (testCase['utcOffsetHours'] as num).toDouble(),
            prayerDate: date,
            method: method,
            madhab: madhab,
            highLatitudeRule: rule,
          ),
        );

        final expected = (testCase['expected'] as Map).cast<String, String>();
        final actual = {
          'fajr': schedule.fajr,
          'sunrise': schedule.sunrise,
          'dhuhr': schedule.dhuhr,
          'asr': schedule.asr,
          'maghrib': schedule.maghrib,
          'isha': schedule.isha,
        };

        for (final entry in actual.entries) {
          final expectedTime = DateTime.parse(expected[entry.key]!).toUtc();
          final difference =
              entry.value.toUtc().difference(expectedTime).abs();

          expect(
            difference,
            lessThanOrEqualTo(_tolerance),
            reason: '${entry.key} disagrees by ${difference.inMilliseconds}ms '
                '(Dart ${entry.value.toIso8601String()} vs '
                'Python ${expectedTime.toIso8601String()})',
          );
        }
      });
    }
  });
}
