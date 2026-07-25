/// On-device astronomical prayer-time calculation.
///
/// This is a deliberate line-by-line port of the server's
/// `app/services/prayer_times.py`. The duplication is the point: the app must
/// compute a full schedule with no network, so the logic cannot live only on
/// the server. Both implementations are validated against the same fixture
/// set (see test/unit/prayer_time_calculator_test.dart and the backend's
/// tests/test_prayer_times.py) so they cannot silently diverge.
///
/// If you change the algorithm here, change it there, and update both fixture
/// sets in the same commit.
library;

import 'dart:math' as math;

import '../entities/prayer_enums.dart';
import '../strategies/calculation_strategy.dart';

/// Sun altitude at sunrise/sunset: the solar disc's upper limb touching the
/// horizon, including atmospheric refraction.
const double _horizonAngle = 0.833;

/// Solar-depression angles defining Fajr and Isha for one authority.
///
/// Some authorities define Isha as a fixed interval after Maghrib rather than
/// a sun angle, because at their latitudes the angle-based definition is
/// unstable in summer.
class MethodParameters {
  const MethodParameters({
    required this.fajrAngle,
    this.ishaAngle,
    this.ishaIntervalMinutes,
    this.maghribAngle = _horizonAngle,
  }) : assert(
          (ishaAngle == null) != (ishaIntervalMinutes == null),
          'Exactly one of ishaAngle or ishaIntervalMinutes must be set',
        );

  final double fajrAngle;
  final double? ishaAngle;
  final int? ishaIntervalMinutes;
  final double maghribAngle;
}

/// Angles for one authority, resolved through [CalculationRegistry].
///
/// Kept as a function so existing call sites read the same, but the table it
/// used to be now lives with the rest of that authority's definition — its
/// remote id included — rather than half here and half in the network layer.
MethodParameters methodParametersFor(
  CalculationMethod method, {
  CalculationRegistry? registry,
}) =>
    (registry ?? _defaultCalculationRegistry).parametersFor(method);

final CalculationRegistry _defaultCalculationRegistry =
    CalculationRegistry.standard();

double _degreesToRadians(double degrees) => degrees * math.pi / 180.0;
double _radiansToDegrees(double radians) => radians * 180.0 / math.pi;

/// Sun declination and equation of time for a Julian Day.
class SolarPosition {
  const SolarPosition({required this.declination, required this.equationOfTime});

  /// Degrees.
  final double declination;

  /// Hours.
  final double equationOfTime;
}

/// Julian Day Number at 00:00 UT on the given civil date.
double julianDay(DateTime date) {
  var year = date.year;
  var month = date.month;
  final day = date.day;

  if (month <= 2) {
    year -= 1;
    month += 12;
  }

  final a = (year / 100).floor();
  // Gregorian calendar correction.
  final b = 2 - a + (a / 4).floor();

  return (365.25 * (year + 4716)).floor() +
      (30.6001 * (month + 1)).floor() +
      day +
      b -
      1524.5;
}

SolarPosition solarPosition(double jd) {
  final d = jd - 2451545.0; // days since the J2000.0 epoch

  // Mean anomaly, mean longitude, and ecliptic longitude of the Sun.
  final meanAnomaly = _degreesToRadians((357.529 + 0.98560028 * d) % 360);
  final meanLongitude = (280.459 + 0.98564736 * d) % 360;
  final eclipticLongitude = _degreesToRadians(
    (meanLongitude +
            1.915 * math.sin(meanAnomaly) +
            0.020 * math.sin(2 * meanAnomaly)) %
        360,
  );

  final obliquity = _degreesToRadians(23.439 - 0.00000036 * d);

  final declination = _radiansToDegrees(
    math.asin(math.sin(obliquity) * math.sin(eclipticLongitude)),
  );

  final rightAscension = _radiansToDegrees(
    math.atan2(
      math.cos(obliquity) * math.sin(eclipticLongitude),
      math.cos(eclipticLongitude),
    ),
  );
  final rightAscensionHours = (rightAscension % 360) / 15.0;

  var equationOfTime = meanLongitude / 15.0 - rightAscensionHours;
  // Fold into [-12, 12) hours; the raw difference can wrap a full day.
  equationOfTime = (equationOfTime + 12) % 24 - 12;

  return SolarPosition(
    declination: declination,
    equationOfTime: equationOfTime,
  );
}

/// Hours between solar noon and the moment the sun reaches [sunAltitude].
///
/// Returns null when the sun never reaches that altitude on this date at this
/// latitude — the high-latitude case that must be handled by a fallback rule
/// rather than allowed to produce a nonsensical time.
double? hourAngle(double sunAltitude, double latitude, double declination) {
  final latRad = _degreesToRadians(latitude);
  final decRad = _degreesToRadians(declination);

  final numerator = -math.sin(_degreesToRadians(sunAltitude)) -
      math.sin(decRad) * math.sin(latRad);
  final denominator = math.cos(decRad) * math.cos(latRad);

  if (denominator == 0) return null;

  final cosine = numerator / denominator;
  if (cosine < -1.0 || cosine > 1.0) return null;

  return _radiansToDegrees(math.acos(cosine)) / 15.0;
}

/// Sun altitude at which the Asr shadow condition is satisfied.
double _asrAltitude(double latitude, double declination, int shadowFactor) {
  // Negative because the angle is measured as a depression in [hourAngle],
  // while the sun is still above the horizon at Asr.
  return -_radiansToDegrees(
    math.atan(
      1.0 /
          (shadowFactor +
              math.tan(_degreesToRadians((latitude - declination).abs()))),
    ),
  );
}

/// One day's prayer instants, as UTC timestamps.
class PrayerSchedule {
  const PrayerSchedule({
    required this.prayerDate,
    required this.fajr,
    required this.sunrise,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
  });

  final DateTime prayerDate;
  final DateTime fajr;
  final DateTime sunrise;
  final DateTime dhuhr;
  final DateTime asr;
  final DateTime maghrib;
  final DateTime isha;

  /// The five obligatory prayers, in order. Sunrise is excluded: it marks the
  /// end of the Fajr window but is not itself a prayer.
  Map<PrayerName, DateTime> get prayers => {
        PrayerName.fajr: fajr,
        PrayerName.dhuhr: dhuhr,
        PrayerName.asr: asr,
        PrayerName.maghrib: maghrib,
        PrayerName.isha: isha,
      };

  /// The first prayer strictly after [moment], or null if the day is done.
  MapEntry<PrayerName, DateTime>? nextPrayerAfter(DateTime moment) {
    final entries = prayers.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    for (final entry in entries) {
      if (entry.value.isAfter(moment)) return entry;
    }
    return null;
  }

  /// The prayer whose window currently contains [moment], if any.
  ///
  /// A prayer's window runs until the next prayer begins. Fajr's window ends
  /// at sunrise, not at Dhuhr — praying Fajr after sunrise is qada, not adaa.
  MapEntry<PrayerName, DateTime>? currentPrayerAt(DateTime moment) {
    final entries = prayers.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    for (var i = entries.length - 1; i >= 0; i--) {
      final entry = entries[i];
      if (!moment.isBefore(entry.value)) {
        final windowEnd = entry.key == PrayerName.fajr
            ? sunrise
            : (i + 1 < entries.length ? entries[i + 1].value : null);
        if (windowEnd == null || moment.isBefore(windowEnd)) return entry;
        return null;
      }
    }
    return null;
  }

  /// End of [prayer]'s permitted window.
  DateTime windowEndFor(PrayerName prayer, {required DateTime nextDayFajr}) {
    return switch (prayer) {
      // Fajr expires at sunrise, not at Dhuhr.
      PrayerName.fajr => sunrise,
      PrayerName.dhuhr => asr,
      PrayerName.asr => maghrib,
      PrayerName.maghrib => isha,
      // Isha runs until the following Fajr.
      PrayerName.isha => nextDayFajr,
    };
  }
}

/// Inputs for one calculation.
class CalculationRequest {
  CalculationRequest({
    required this.latitude,
    required this.longitude,
    required this.utcOffsetHours,
    required this.prayerDate,
    this.method = CalculationMethod.muslimWorldLeague,
    this.madhab = Madhab.shafi,
    this.highLatitudeRule = HighLatitudeRule.middleOfTheNight,
    this.adjustments = const {},
    this.calculationRegistry,
  }) {
    if (latitude < -90.0 || latitude > 90.0) {
      throw ArgumentError('latitude out of range: $latitude');
    }
    if (longitude < -180.0 || longitude > 180.0) {
      throw ArgumentError('longitude out of range: $longitude');
    }
  }

  final double latitude;
  final double longitude;

  /// Offset from UTC in hours at the target date.
  ///
  /// Passed in rather than derived from a timezone name because Dart's core
  /// library has no IANA timezone database; the caller resolves this with the
  /// `timezone` package, which is initialised once at app start.
  final double utcOffsetHours;

  final DateTime prayerDate;
  final CalculationMethod method;
  final Madhab madhab;
  final HighLatitudeRule highLatitudeRule;

  /// Per-prayer manual corrections in minutes, matching local mosque practice.
  final Map<PrayerName, int> adjustments;

  /// The authorities available to this request.
  ///
  /// Injected so a test — or a build shipping a regional authority — can
  /// substitute one without reaching into a global. Null means the standard
  /// set, which is what every production call site wants.
  final CalculationRegistry? calculationRegistry;
}

class PrayerTimeCalculator {
  const PrayerTimeCalculator();

  PrayerSchedule calculate(CalculationRequest request) {
    final params = methodParametersFor(
      request.method,
      registry: request.calculationRegistry,
    );
    final shadowFactor = request.madhab.shadowFactor;

    // Evaluate the sun at local solar noon rather than at midnight; the
    // declination drifts measurably across a day and noon is the midpoint
    // of the interval that matters.
    final jd = julianDay(request.prayerDate) - request.longitude / (15.0 * 24.0);
    final sun = solarPosition(jd + 0.5);

    // Local mean solar noon, expressed in hours of local standard time.
    final dhuhrHours = 12.0 +
        request.utcOffsetHours -
        request.longitude / 15.0 -
        sun.equationOfTime;

    // Maghrib angle: the later of the method's convention and the school's.
    // The Ja'fari (Shia) school delays Maghrib to 4 degrees of depression; a
    // method like Tehran already specifies 4.5. Taking the max keeps Maghrib no
    // earlier than either requires and lets the two coexist without conflict.
    final maghribAngle = math.max(
      params.maghribAngle,
      request.madhab.maghribAngle ?? 0.0,
    );

    final sunriseOffset =
        hourAngle(_horizonAngle, request.latitude, sun.declination);
    final maghribOffset =
        hourAngle(maghribAngle, request.latitude, sun.declination);
    final fajrOffset =
        hourAngle(params.fajrAngle, request.latitude, sun.declination);
    final asrOffset = hourAngle(
      _asrAltitude(request.latitude, sun.declination, shadowFactor),
      request.latitude,
      sun.declination,
    );

    // Sunrise and sunset failing means polar day or night. There is no
    // meaningful astronomical answer, so we fall back to the nearest
    // latitude at which one exists rather than emitting a wrong time.
    if (sunriseOffset == null || maghribOffset == null) {
      return _polarFallback(request);
    }

    final sunriseHours = dhuhrHours - sunriseOffset;
    final maghribHours = dhuhrHours + maghribOffset;
    final asrHours = dhuhrHours + (asrOffset ?? sunriseOffset);

    double ishaHours;
    if (params.ishaIntervalMinutes != null) {
      ishaHours = maghribHours + params.ishaIntervalMinutes! / 60.0;
    } else {
      final ishaOffset =
          hourAngle(params.ishaAngle!, request.latitude, sun.declination);
      ishaHours = ishaOffset != null ? dhuhrHours + ishaOffset : double.nan;
    }

    var fajrHours =
        fajrOffset != null ? dhuhrHours - fajrOffset : double.nan;

    // Night length drives every high-latitude fallback rule.
    final nightLength = (sunriseHours + 24.0) - maghribHours;

    fajrHours = _resolveHighLatitude(
      value: fajrHours,
      boundary: sunriseHours,
      nightLength: nightLength,
      angle: params.fajrAngle,
      rule: request.highLatitudeRule,
      isBeforeBoundary: true,
    );
    ishaHours = _resolveHighLatitude(
      value: ishaHours,
      boundary: maghribHours,
      nightLength: nightLength,
      angle: params.ishaAngle ?? 18.0,
      rule: request.highLatitudeRule,
      isBeforeBoundary: false,
    );

    DateTime toUtc(double hours, PrayerName? prayer) => _hoursToUtc(
          hours,
          request,
          prayer == null ? 0 : (request.adjustments[prayer] ?? 0),
        );

    return PrayerSchedule(
      prayerDate: request.prayerDate,
      fajr: toUtc(fajrHours, PrayerName.fajr),
      sunrise: toUtc(sunriseHours, null),
      dhuhr: toUtc(dhuhrHours, PrayerName.dhuhr),
      asr: toUtc(asrHours, PrayerName.asr),
      maghrib: toUtc(maghribHours, PrayerName.maghrib),
      isha: toUtc(ishaHours, PrayerName.isha),
    );
  }

  /// Clamp Fajr/Isha when the geometric time is absent or implausible.
  ///
  /// Above roughly 48 degrees the sun may never descend far enough for the
  /// angle-based definition to yield a time at all, or it may yield one so
  /// close to sunrise that following it is impractical.
  double _resolveHighLatitude({
    required double value,
    required double boundary,
    required double nightLength,
    required double angle,
    required HighLatitudeRule rule,
    required bool isBeforeBoundary,
  }) {
    final portion = switch (rule) {
      HighLatitudeRule.middleOfTheNight => nightLength / 2.0,
      HighLatitudeRule.seventhOfTheNight => nightLength / 7.0,
      HighLatitudeRule.twilightAngle => nightLength * (angle / 60.0),
    };

    final limit = isBeforeBoundary ? boundary - portion : boundary + portion;

    if (value.isNaN) return limit;

    // Keep whichever time is closer to the boundary — never allow Fajr
    // earlier, or Isha later, than the rule permits.
    return isBeforeBoundary
        ? math.max(value, limit)
        : math.min(value, limit);
  }

  /// Recompute at 48 degrees latitude during polar day or night.
  PrayerSchedule _polarFallback(CalculationRequest request) {
    final substituteLatitude = request.latitude >= 0 ? 48.0 : -48.0;
    return calculate(
      CalculationRequest(
        latitude: substituteLatitude,
        longitude: request.longitude,
        utcOffsetHours: request.utcOffsetHours,
        prayerDate: request.prayerDate,
        method: request.method,
        madhab: request.madhab,
        highLatitudeRule: request.highLatitudeRule,
        adjustments: request.adjustments,
      ),
    );
  }

  /// Convert local-standard-time hours into a UTC instant.
  DateTime _hoursToUtc(
    double hours,
    CalculationRequest request,
    int adjustmentMinutes,
  ) {
    // Local midnight on the target date, expressed as a UTC instant.
    final localMidnightUtc = DateTime.utc(
      request.prayerDate.year,
      request.prayerDate.month,
      request.prayerDate.day,
    ).subtract(
      Duration(milliseconds: (request.utcOffsetHours * 3600000).round()),
    );

    // `hours` may fall outside [0, 24) — Isha after midnight, or Fajr pushed
    // before it — so Duration arithmetic carries the date correctly.
    return localMidnightUtc.add(
      Duration(
        milliseconds: (hours * 3600000).round() + adjustmentMinutes * 60000,
      ),
    );
  }
}

const prayerTimeCalculator = PrayerTimeCalculator();
