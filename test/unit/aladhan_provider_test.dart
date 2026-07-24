/// Tests for the AlAdhan provider's request shape and response parsing.
///
/// The parsing is where this provider can quietly go wrong. Times arrive as
/// local wall-clock strings, so an off-by-one-day error on a late Isha, or a
/// timezone read from the device instead of the response, produces prayer times
/// that look plausible and are hours wrong.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/features/prayer_times/data/datasources/aladhan_prayer_time_provider.dart';
import 'package:prayer_lock/features/prayer_times/data/datasources/prayer_time_provider.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:prayer_lock/features/settings/domain/entities/app_settings.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../support/prayer_fixtures.dart';

/// Serves canned responses, so the tests never touch the network.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.responder);

  final ResponseBody Function(RequestOptions options) responder;

  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body, {int status = 200}) => ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

String _timingsBody({
  String fajr = '04:18 (+03)',
  String sunrise = '05:41 (+03)',
  String dhuhr = '12:17 (+03)',
  String asr = '15:54 (+03)',
  String maghrib = '19:12 (+03)',
  String isha = '20:41 (+03)',
  String timezone = 'Asia/Riyadh',
  String date = '20-07-2026',
}) =>
    '''
{
  "code": 200,
  "status": "OK",
  "data": {
    "timings": {
      "Imsak": "04:08 (+03)",
      "Fajr": "$fajr",
      "Sunrise": "$sunrise",
      "Dhuhr": "$dhuhr",
      "Asr": "$asr",
      "Sunset": "$maghrib",
      "Maghrib": "$maghrib",
      "Isha": "$isha",
      "Midnight": "00:15 (+03)"
    },
    "date": {
      "readable": "20 Jul 2026",
      "gregorian": { "date": "$date" }
    },
    "meta": {
      "latitude": 21.4225,
      "longitude": 39.8262,
      "timezone": "$timezone",
      "method": { "id": 3, "name": "Muslim World League" }
    }
  }
}
''';

AlAdhanPrayerTimeProvider _providerWith(_StubAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.aladhan.com/v1'))
    ..httpClientAdapter = adapter;
  return AlAdhanPrayerTimeProvider(client: dio);
}

void main() {
  tz_data.initializeTimeZones();

  final settings = settingsWith();
  final date = DateTime(2026, 7, 20);

  group('request shape', () {
    test('sends coordinates, method, school and zone', () async {
      final adapter = _StubAdapter((_) => _json(_timingsBody()));
      await _providerWith(adapter).fetch(date: date, settings: settings);

      final query = adapter.lastRequest!.queryParameters;
      expect(query['latitude'], makkah.latitude);
      expect(query['longitude'], makkah.longitude);
      expect(query['timezonestring'], 'Asia/Riyadh');
      // 3 is Muslim World League in AlAdhan's registry.
      expect(query['method'], 3);
      // Shafi is school 0.
      expect(query['school'], 0);
    });

    test('formats the date path as DD-MM-YYYY', () async {
      final adapter = _StubAdapter((_) => _json(_timingsBody()));
      await _providerWith(adapter).fetch(date: date, settings: settings);

      expect(adapter.lastRequest!.path, '/timings/20-07-2026');
    });

    test('maps Hanafi to school 1', () async {
      final adapter = _StubAdapter((_) => _json(_timingsBody()));
      await _providerWith(adapter).fetch(
        date: date,
        settings: settings.copyWith(madhabOverride: Madhab.hanafi),
      );

      expect(adapter.lastRequest!.queryParameters['school'], 1);
    });

    test('omits tune when nothing is adjusted', () async {
      final adapter = _StubAdapter((_) => _json(_timingsBody()));
      await _providerWith(adapter).fetch(date: date, settings: settings);

      expect(adapter.lastRequest!.queryParameters.containsKey('tune'), isFalse);
    });

    test('sends tune in AlAdhan field order when adjusted', () async {
      final adapter = _StubAdapter((_) => _json(_timingsBody()));
      await _providerWith(adapter).fetch(
        date: date,
        settings: settings.copyWith(
          adjustments: {PrayerName.fajr: 2, PrayerName.isha: -3},
        ),
      );

      // Imsak, Fajr, Sunrise, Dhuhr, Asr, Maghrib, Sunset, Isha, Midnight.
      expect(adapter.lastRequest!.queryParameters['tune'], '0,2,0,0,0,0,0,-3,0');
    });

    test('every supported method has an AlAdhan id', () {
      // A missing entry would silently fall back to Muslim World League, so a
      // user who picked Umm al-Qura would get MWL times with no indication.
      for (final method in CalculationMethod.values) {
        expect(
          AlAdhanPrayerTimeProvider.methodIds[method],
          isNotNull,
          reason: '${method.displayName} has no AlAdhan method id',
        );
      }
    });
  });

  group('response parsing', () {
    test('resolves wall-clock times against the response timezone', () async {
      final adapter = _StubAdapter((_) => _json(_timingsBody()));
      final times =
          await _providerWith(adapter).fetch(date: date, settings: settings);

      final riyadh = tz.getLocation('Asia/Riyadh');
      expect(
        times.fajr,
        tz.TZDateTime(riyadh, 2026, 7, 20, 4, 18).toUtc(),
      );
      expect(
        times.dhuhr,
        tz.TZDateTime(riyadh, 2026, 7, 20, 12, 17).toUtc(),
      );
    });

    test('the parsed times reproduce the durations in the design', () async {
      final adapter = _StubAdapter((_) => _json(_timingsBody()));
      final times =
          await _providerWith(adapter).fetch(date: date, settings: settings);

      expect(times.sunrise.difference(times.fajr),
          const Duration(hours: 1, minutes: 23));
      expect(times.asr.difference(times.dhuhr),
          const Duration(hours: 3, minutes: 37));
      expect(times.maghrib.difference(times.asr),
          const Duration(hours: 3, minutes: 18));
      expect(times.isha.difference(times.maghrib),
          const Duration(hours: 1, minutes: 29));
    });

    test('rolls a post-midnight Isha to the following day', () async {
      // Reported as a time of day, "01:12" is numerically before Maghrib. Read
      // literally it would place Isha eighteen hours before Maghrib.
      final adapter = _StubAdapter(
        (_) => _json(_timingsBody(isha: '01:12 (+03)')),
      );
      final times =
          await _providerWith(adapter).fetch(date: date, settings: settings);

      expect(times.isha.isAfter(times.maghrib), isTrue);
      expect(times.isMonotonic, isTrue);

      final riyadh = tz.getLocation('Asia/Riyadh');
      expect(times.isha, tz.TZDateTime(riyadh, 2026, 7, 21, 1, 12).toUtc());
    });

    test('parses times with no zone annotation', () async {
      final adapter = _StubAdapter(
        (_) => _json(_timingsBody(fajr: '04:18', dhuhr: '12:17')),
      );
      final times =
          await _providerWith(adapter).fetch(date: date, settings: settings);

      expect(times.fajr.isBefore(times.dhuhr), isTrue);
    });

    test('parses a named-zone annotation', () async {
      final adapter = _StubAdapter(
        (_) => _json(_timingsBody(fajr: '04:18 (EEST)')),
      );
      await expectLater(
        _providerWith(adapter).fetch(date: date, settings: settings),
        completes,
      );
    });

    test('reports the source as remote', () async {
      final adapter = _StubAdapter((_) => _json(_timingsBody()));
      final times =
          await _providerWith(adapter).fetch(date: date, settings: settings);

      expect(times.source, PrayerTimeSource.remote);
      expect(times.timezone, 'Asia/Riyadh');
    });
  });

  group('failure handling', () {
    test('a 5xx is retryable', () async {
      final adapter = _StubAdapter((_) => _json('{}', status: 503));

      await expectLater(
        _providerWith(adapter).fetch(date: date, settings: settings),
        throwsA(
          isA<PrayerTimeProviderException>()
              .having((e) => e.isRetryable, 'isRetryable', isTrue),
        ),
      );
    });

    test('a 4xx is not retryable', () async {
      // Retrying identical bad input forever is a battery-drain bug.
      final adapter = _StubAdapter((_) => _json('{}', status: 400));

      await expectLater(
        _providerWith(adapter).fetch(date: date, settings: settings),
        throwsA(
          isA<PrayerTimeProviderException>()
              .having((e) => e.isRetryable, 'isRetryable', isFalse),
        ),
      );
    });

    test('a 429 is retryable', () async {
      final adapter = _StubAdapter((_) => _json('{}', status: 429));

      await expectLater(
        _providerWith(adapter).fetch(date: date, settings: settings),
        throwsA(
          isA<PrayerTimeProviderException>()
              .having((e) => e.isRetryable, 'isRetryable', isTrue),
        ),
      );
    });

    test('a missing timing is reported, not silently defaulted', () async {
      final adapter = _StubAdapter(
        (_) => _json('''
{"data": {"timings": {"Fajr": "04:18"}, "meta": {"timezone": "Asia/Riyadh"}}}
'''),
      );

      await expectLater(
        _providerWith(adapter).fetch(date: date, settings: settings),
        throwsA(isA<PrayerTimeProviderException>()),
      );
    });

    test('an unparseable time is reported', () async {
      final adapter = _StubAdapter(
        (_) => _json(_timingsBody(asr: 'not-a-time')),
      );

      await expectLater(
        _providerWith(adapter).fetch(date: date, settings: settings),
        throwsA(isA<PrayerTimeProviderException>()),
      );
    });

    test('an unknown timezone is reported rather than guessed', () async {
      final adapter = _StubAdapter(
        (_) => _json(_timingsBody(timezone: 'Mars/Olympus_Mons')),
      );

      await expectLater(
        _providerWith(adapter).fetch(date: date, settings: settings),
        throwsA(isA<PrayerTimeProviderException>()),
      );
    });

    test('a non-JSON body is reported', () async {
      final adapter = _StubAdapter((_) => _json('"just a string"'));

      await expectLater(
        _providerWith(adapter).fetch(date: date, settings: settings),
        throwsA(isA<PrayerTimeProviderException>()),
      );
    });

    test('no location configured is a non-retryable failure', () async {
      final adapter = _StubAdapter((_) => _json(_timingsBody()));

      await expectLater(
        _providerWith(adapter).fetch(
          date: date,
          settings: const AppSettings(),
        ),
        throwsA(
          isA<PrayerTimeProviderException>()
              .having((e) => e.isRetryable, 'isRetryable', isFalse),
        ),
      );
    });
  });
}
