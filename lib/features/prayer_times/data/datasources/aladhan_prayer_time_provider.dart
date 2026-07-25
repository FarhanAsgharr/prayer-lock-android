/// Prayer times from the AlAdhan web service.
///
/// AlAdhan is used as the *authority* rather than the source of truth: it
/// settles cases where a local convention differs from the pure astronomical
/// calculation, but the app never depends on reaching it. Every response is
/// validated and cached, and the repository falls back to on-device computation
/// whenever this provider cannot answer.
///
/// Two response quirks drive most of the code here:
///
///  1. Times arrive as local wall-clock strings ("04:18 (+03)"), not instants.
///     They are resolved against the IANA zone the response itself reports, so
///     a user whose device clock is in the wrong zone still gets correct times.
///
///  2. Isha is reported as a time-of-day, so a late Isha appears as "01:12" —
///     numerically *before* Maghrib on the same date. Times are therefore
///     rolled forward to keep the sequence ascending, which is what turns
///     "01:12" into the following morning rather than that morning.
library;

import 'package:dio/dio.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../settings/domain/entities/app_settings.dart';
import '../../domain/entities/prayer_enums.dart';
import 'prayer_time_provider.dart';
import '../../domain/strategies/calculation_strategy.dart';

class AlAdhanPrayerTimeProvider implements PrayerTimeProvider {
  AlAdhanPrayerTimeProvider({
    Dio? client,
    String? baseUrl,
    CalculationRegistry? registry,
  })  : _client = client ?? _defaultClient(baseUrl ?? _defaultBaseUrl),
        _baseUrl = baseUrl ?? _defaultBaseUrl,
        _registry = registry ?? CalculationRegistry.standard();

  static const String _defaultBaseUrl = 'https://api.aladhan.com/v1';

  final Dio _client;
  final String _baseUrl;

  /// Where this authority's remote id comes from. Injected so a test can pin
  /// the mapping without reaching through a global.
  final CalculationRegistry _registry;

  static Dio _defaultClient(String baseUrl) => Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          // Statuses are inspected explicitly so a 4xx becomes a typed,
          // non-retryable failure rather than an exception from deep in Dio.
          validateStatus: (status) => status != null && status < 600,
        ),
      );

  @override
  String get id => 'aladhan';

  @override
  String get displayName => 'AlAdhan';

  @override
  bool get requiresNetwork => true;

  /// AlAdhan's high-latitude adjustment identifiers.
  static const Map<HighLatitudeRule, int> _latitudeAdjustmentIds = {
    HighLatitudeRule.middleOfTheNight: 1,
    HighLatitudeRule.seventhOfTheNight: 2,
    HighLatitudeRule.twilightAngle: 3,
  };

  @override
  Future<RawPrayerTimes> fetch({
    required DateTime date,
    required AppSettings settings,
  }) async {
    final location = _requireLocation(settings);
    final normalised = DateTime(date.year, date.month, date.day);

    final response = await _get(
      '/timings/${_pathDate(normalised)}',
      _queryFor(settings, location),
    );

    final data = _asMap(response['data'], 'data');
    return _parseDay(
      data: data,
      settings: settings,
      location: location,
      expectedDate: normalised,
    );
  }

  @override
  Future<List<RawPrayerTimes>> fetchRange({
    required DateTime from,
    required int days,
    required AppSettings settings,
  }) async {
    final location = _requireLocation(settings);
    final start = DateTime(from.year, from.month, from.day);

    // One calendar request per month covered, rather than one per day: a
    // fourteen-day prefetch is then one or two round trips instead of fourteen.
    final wanted = <DateTime>[
      for (var offset = 0; offset < days; offset++)
        DateTime(start.year, start.month, start.day + offset),
    ];

    final months = <String, DateTime>{
      for (final date in wanted) '${date.year}-${date.month}': date,
    };

    final byDate = <String, RawPrayerTimes>{};

    for (final month in months.values) {
      final response = await _get(
        '/calendar/${month.year}/${month.month}',
        _queryFor(settings, location),
      );

      final entries = response['data'];
      if (entries is! List) {
        throw const PrayerTimeProviderException(
          'Calendar response did not contain a list of days.',
          isRetryable: false,
        );
      }

      for (final entry in entries) {
        if (entry is! Map) continue;
        final data = entry.cast<String, dynamic>();

        final gregorian = _gregorianDate(data);
        if (gregorian == null) continue;

        byDate['${gregorian.year}-${gregorian.month}-${gregorian.day}'] =
            _parseDay(
          data: data,
          settings: settings,
          location: location,
          expectedDate: gregorian,
        );
      }
    }

    final result = <RawPrayerTimes>[];
    for (final date in wanted) {
      final match = byDate['${date.year}-${date.month}-${date.day}'];
      // A gap means the service returned a short month. Reporting it is better
      // than silently handing back fewer days than asked for, which the caller
      // would cache as if complete.
      if (match == null) {
        throw PrayerTimeProviderException(
          'No prayer times returned for ${_pathDate(date)}.',
          isRetryable: false,
        );
      }
      result.add(match);
    }

    return result;
  }

  // -- request ------------------------------------------------------------

  PrayerLocation _requireLocation(AppSettings settings) {
    final location = settings.location;
    if (location == null) {
      throw const PrayerTimeProviderException(
        'No location configured.',
        isRetryable: false,
      );
    }
    return location;
  }

  Map<String, dynamic> _queryFor(
    AppSettings settings,
    PrayerLocation location,
  ) {
    final query = <String, dynamic>{
      'latitude': location.latitude,
      'longitude': location.longitude,
      // Pinning the zone stops the service inferring one from the coordinates
      // and disagreeing with what the rest of the app computes against.
      'timezonestring': location.timezone,
      // Resolved through the strategy that also owns this authority's solar
      // angles, so the remote request and the offline fallback can never
      // disagree about which authority the user selected.
      'method': _registry.remoteIdFor(settings.calculationMethod) ?? 3,
      'school': settings.madhab.shadowFactor == 2 ? 1 : 0,
      'latitudeAdjustmentMethod':
          _latitudeAdjustmentIds[settings.highLatitudeRule] ?? 1,
    };

    final tune = _tuneParameter(settings.adjustments);
    if (tune != null) query['tune'] = tune;

    return query;
  }

  /// AlAdhan's `tune` parameter: comma-separated minute offsets in a fixed
  /// order — Imsak, Fajr, Sunrise, Dhuhr, Asr, Maghrib, Sunset, Isha, Midnight.
  ///
  /// Returns null when nothing is adjusted, so the parameter is omitted rather
  /// than sent as a string of zeroes.
  static String? _tuneParameter(Map<PrayerName, int> adjustments) {
    if (adjustments.isEmpty || adjustments.values.every((v) => v == 0)) {
      return null;
    }

    int of(PrayerName prayer) => adjustments[prayer] ?? 0;

    return [
      0, // Imsak
      of(PrayerName.fajr),
      0, // Sunrise
      of(PrayerName.dhuhr),
      of(PrayerName.asr),
      of(PrayerName.maghrib),
      0, // Sunset
      of(PrayerName.isha),
      0, // Midnight
    ].join(',');
  }

  static String _pathDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.year}';

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, dynamic> query,
  ) async {
    late final Response<dynamic> response;
    try {
      response = await _client.get<dynamic>(path, queryParameters: query);
    } on DioException catch (error) {
      // A rejected status may arrive either as a response or as an exception,
      // depending on the injected client's validateStatus. Classifying by
      // status code in both places keeps the retry decision correct however the
      // client is configured.
      final status = error.response?.statusCode;
      if (status != null) {
        throw PrayerTimeProviderException(
          'Prayer time service returned HTTP $status.',
          isRetryable: _statusIsRetryable(status),
          cause: error,
        );
      }

      throw PrayerTimeProviderException(
        'Could not reach $_baseUrl$path: ${error.type.name}',
        // Timeouts and connection failures are transient; a cancelled request
        // or a bad certificate is not going to fix itself on retry.
        isRetryable: error.type != DioExceptionType.cancel &&
            error.type != DioExceptionType.badCertificate,
        cause: error,
      );
    }

    final status = response.statusCode ?? 0;
    if (status >= 400) {
      throw PrayerTimeProviderException(
        'Prayer time service returned HTTP $status.',
        isRetryable: _statusIsRetryable(status),
      );
    }

    final body = response.data;
    if (body is! Map) {
      throw const PrayerTimeProviderException(
        'Prayer time service returned an unexpected body.',
        isRetryable: false,
      );
    }

    return body.cast<String, dynamic>();
  }

  /// Whether an HTTP status is worth retrying.
  ///
  /// 4xx means the request itself is wrong — unsupported coordinates, a bad
  /// method id — and retrying identical bad input wastes battery forever. 429
  /// is the exception: it explicitly means "try again later".
  static bool _statusIsRetryable(int status) => status >= 500 || status == 429;

  // -- parsing ------------------------------------------------------------

  RawPrayerTimes _parseDay({
    required Map<String, dynamic> data,
    required AppSettings settings,
    required PrayerLocation location,
    required DateTime expectedDate,
  }) {
    final timings = _asMap(data['timings'], 'timings');
    final meta = data['meta'] is Map
        ? (data['meta'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};

    // The response's own zone wins over the configured one when present: if the
    // service resolved the coordinates to a different zone, its times are
    // expressed in that zone and reading them in another would shift them.
    final zoneName = (meta['timezone'] as String?) ?? location.timezone;
    final zone = _resolveZone(zoneName);

    // Parsed in chronological order so each can be rolled to the next day when
    // it would otherwise appear before its predecessor.
    var cursor = _instantFor(timings, 'Fajr', expectedDate, zone, null);
    final fajr = cursor;
    final sunrise = cursor = _instantFor(timings, 'Sunrise', expectedDate, zone, cursor);
    final dhuhr = cursor = _instantFor(timings, 'Dhuhr', expectedDate, zone, cursor);
    final asr = cursor = _instantFor(timings, 'Asr', expectedDate, zone, cursor);
    final maghrib = cursor = _instantFor(timings, 'Maghrib', expectedDate, zone, cursor);
    final isha = _instantFor(timings, 'Isha', expectedDate, zone, cursor);

    return RawPrayerTimes(
      date: expectedDate,
      fajr: fajr,
      sunrise: sunrise,
      dhuhr: dhuhr,
      asr: asr,
      maghrib: maghrib,
      isha: isha,
      source: PrayerTimeSource.remote,
      method: settings.calculationMethod,
      latitude: location.latitude,
      longitude: location.longitude,
      timezone: zoneName,
      city: location.label,
      fetchedAt: DateTime.now().toUtc(),
    );
  }

  /// Resolve one timing to a UTC instant, rolling past [notBefore] if needed.
  static DateTime _instantFor(
    Map<String, dynamic> timings,
    String key,
    DateTime date,
    tz.Location zone,
    DateTime? notBefore,
  ) {
    final raw = timings[key];
    if (raw is! String) {
      throw PrayerTimeProviderException(
        'Prayer time response is missing "$key".',
        isRetryable: false,
      );
    }

    final (hour, minute) = _parseClock(raw, key);

    var instant =
        tz.TZDateTime(zone, date.year, date.month, date.day, hour, minute)
            .toUtc();

    // A time-of-day that lands before the previous prayer belongs to the
    // following morning — this is how a 01:12 Isha is placed correctly.
    if (notBefore != null && instant.isBefore(notBefore)) {
      instant = tz.TZDateTime(
        zone,
        date.year,
        date.month,
        date.day + 1,
        hour,
        minute,
      ).toUtc();
    }

    return instant;
  }

  /// Parse "04:18", "04:18 (+03)" or "04:18 (EEST)".
  static (int, int) _parseClock(String value, String key) {
    // Everything from the first space or bracket onward is a zone annotation.
    final clock = value.trim().split(RegExp(r'[\s(]')).first;
    final parts = clock.split(':');

    if (parts.length < 2) {
      throw PrayerTimeProviderException(
        'Could not parse "$key" time "$value".',
        isRetryable: false,
      );
    }

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);

    if (hour == null || minute == null || hour > 47 || minute > 59) {
      throw PrayerTimeProviderException(
        'Could not parse "$key" time "$value".',
        isRetryable: false,
      );
    }

    return (hour, minute);
  }

  static tz.Location _resolveZone(String name) {
    try {
      return tz.getLocation(name);
    } on tz.LocationNotFoundException {
      throw PrayerTimeProviderException(
        'Unknown timezone "$name" in prayer time response.',
        isRetryable: false,
      );
    }
  }

  /// The Gregorian date a calendar entry describes, or null if unreadable.
  static DateTime? _gregorianDate(Map<String, dynamic> data) {
    final date = data['date'];
    if (date is! Map) return null;

    final gregorian = date['gregorian'];
    if (gregorian is! Map) return null;

    // Format is DD-MM-YYYY.
    final text = gregorian['date'];
    if (text is! String) return null;

    final parts = text.split('-');
    if (parts.length != 3) return null;

    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;

    return DateTime(year, month, day);
  }

  static Map<String, dynamic> _asMap(Object? value, String label) {
    if (value is! Map) {
      throw PrayerTimeProviderException(
        'Prayer time response is missing "$label".',
        isRetryable: false,
      );
    }
    return value.cast<String, dynamic>();
  }
}
