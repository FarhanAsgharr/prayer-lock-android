/// Prayer times computed on this device, with no network.
///
/// This is the provider that makes the offline requirement structural rather
/// than a caching strategy that degrades on a cache miss. It can answer for any
/// date, past or future, at any location, with no connectivity and no prior
/// fetch — so a user who installs the app on a plane and lands somewhere new
/// still gets a correct schedule.
///
/// It wraps [PrayerTimeCalculator], which is a line-by-line port of the
/// backend's implementation and is pinned against a shared fixture set.
library;

import 'package:timezone/timezone.dart' as tz;

import '../../../settings/domain/entities/app_settings.dart';
import '../../domain/entities/prayer_enums.dart';
import '../../domain/usecases/prayer_time_calculator.dart';
import 'prayer_time_provider.dart';

class DevicePrayerTimeProvider implements PrayerTimeProvider {
  const DevicePrayerTimeProvider({
    PrayerTimeCalculator calculator = prayerTimeCalculator,
  }) : _calculator = calculator;

  final PrayerTimeCalculator _calculator;

  @override
  String get id => 'device';

  @override
  String get displayName => 'On-device calculation';

  @override
  bool get requiresNetwork => false;

  @override
  Future<RawPrayerTimes> fetch({
    required DateTime date,
    required AppSettings settings,
  }) async {
    final location = settings.location;
    if (location == null) {
      throw const PrayerTimeProviderException(
        'No location configured.',
        // Retrying cannot help; the user must set a location.
        isRetryable: false,
      );
    }

    return _computeFor(date: date, settings: settings, location: location);
  }

  @override
  Future<List<RawPrayerTimes>> fetchRange({
    required DateTime from,
    required int days,
    required AppSettings settings,
  }) async {
    final location = settings.location;
    if (location == null) {
      throw const PrayerTimeProviderException(
        'No location configured.',
        isRetryable: false,
      );
    }

    return [
      for (var offset = 0; offset < days; offset++)
        _computeFor(
          date: _addDays(from, offset),
          settings: settings,
          location: location,
        ),
    ];
  }

  RawPrayerTimes _computeFor({
    required DateTime date,
    required AppSettings settings,
    required PrayerLocation location,
  }) {
    final normalised = DateTime(date.year, date.month, date.day);

    final schedule = _calculator.calculate(
      CalculationRequest(
        latitude: location.latitude,
        longitude: location.longitude,
        // Resolved per date, not once: computing next week's schedule across a
        // DST boundary with today's offset would be an hour wrong.
        utcOffsetHours: utcOffsetHoursAt(location.timezone, normalised),
        prayerDate: normalised,
        method: settings.calculationMethod,
        madhab: settings.madhab,
        highLatitudeRule: settings.highLatitudeRule,
        adjustments: settings.adjustments,
      ),
    );

    return RawPrayerTimes(
      date: normalised,
      fajr: schedule.fajr,
      sunrise: schedule.sunrise,
      dhuhr: schedule.dhuhr,
      asr: schedule.asr,
      maghrib: schedule.maghrib,
      isha: schedule.isha,
      source: PrayerTimeSource.device,
      method: settings.calculationMethod,
      latitude: location.latitude,
      longitude: location.longitude,
      timezone: location.timezone,
      city: location.label,
      fetchedAt: DateTime.now().toUtc(),
    );
  }

  /// Calendar-day addition. Duration arithmetic would drift by an hour across
  /// a DST boundary and eventually skip or repeat a date.
  static DateTime _addDays(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);
}

/// UTC offset in hours for [timezoneName] on [date].
///
/// Shared with the notification scheduler and the schedule providers, all of
/// which need the offset *on a given date* rather than today's.
double utcOffsetHoursAt(String timezoneName, DateTime date) {
  try {
    final location = tz.getLocation(timezoneName);
    // Midday avoids landing on the wrong side of a transition, which almost
    // always occurs in the early hours.
    final noon = tz.TZDateTime(location, date.year, date.month, date.day, 12);
    return noon.timeZoneOffset.inMinutes / 60.0;
  } on tz.LocationNotFoundException {
    // An unknown zone must not crash the schedule. UTC produces visibly wrong
    // times, which is preferable to a blank screen and prompts the user to
    // re-select their location.
    return 0.0;
  }
}
