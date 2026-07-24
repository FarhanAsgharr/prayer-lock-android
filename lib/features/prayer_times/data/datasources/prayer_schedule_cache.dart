/// Local cache of prayer schedules.
///
/// This is what makes the app work with the network permanently off. A day that
/// has ever been resolved — fetched or computed — is readable forever without
/// touching a provider, and the cache key includes the location and calculation
/// settings so a cached day is never served for a configuration it does not
/// belong to.
library;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../settings/domain/entities/app_settings.dart';
import '../../domain/entities/prayer_enums.dart';
import 'prayer_time_provider.dart';

/// What the repository needs from a cache.
///
/// Extracted so the resolution strategy can be tested without SQLCipher, which
/// needs a device or an emulator to load its native library. The offline-first
/// behaviour — cache hit, remote failure, device fallback — is the part most
/// worth testing and the part a device requirement would keep out of CI.
abstract interface class ScheduleCacheStore {
  Future<void> save({
    required RawPrayerTimes times,
    required AppSettings settings,
    DateTime? nextDayFajr,
    Map<PrayerName, Duration>? durations,
  });

  Future<void> saveAll({
    required List<RawPrayerTimes> days,
    required AppSettings settings,
    Map<String, DateTime> nextDayFajrByDate,
  });

  Future<CachedPrayerDay?> read({
    required DateTime date,
    required AppSettings settings,
  });

  Future<List<CachedPrayerDay>> readRange({
    required DateTime from,
    required int days,
    required AppSettings settings,
  });

  Future<int> evictExpired({required DateTime today});

  Future<void> clear();
}

class PrayerScheduleCache implements ScheduleCacheStore {
  const PrayerScheduleCache(this._database);

  final Database _database;

  static const String _table = 'prayer_schedules';

  /// How much history to keep. Long enough for the statistics screens to
  /// explain a past day's windows, short enough that the table stays small on a
  /// device used for years.
  static const int retentionDays = 120;

  /// Cache identity for a location.
  ///
  /// Rounded to three decimal places — about 110 metres. Finer than that and
  /// ordinary GPS jitter would produce a new key on every fix, so the cache
  /// would miss constantly and the app would refetch all day. Coarser and a
  /// user could move far enough to matter without the key changing.
  static String locationKey(double latitude, double longitude) =>
      '${latitude.toStringAsFixed(3)},${longitude.toStringAsFixed(3)}';

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Row identity: the same day under the same configuration must overwrite
  /// rather than accumulate.
  static String rowId(DateTime date, AppSettings settings) {
    final location = settings.location;
    final key = location == null
        ? 'unset'
        : locationKey(location.latitude, location.longitude);
    return '${dateKey(date)}|$key|${settings.calculationMethod.wireValue}'
        '|${settings.madhab.wireValue}|${settings.highLatitudeRule.wireValue}';
  }

  // -- writes -------------------------------------------------------------

  /// Store one day, replacing any existing row for the same configuration.
  ///
  /// [nextDayFajr] is stored alongside so the Isha window can be reconstructed
  /// from this row alone — otherwise reading a cached day would require the
  /// following day to also be cached, and the last cached day would have no
  /// usable Isha window.
  @override
  Future<void> save({
    required RawPrayerTimes times,
    required AppSettings settings,
    DateTime? nextDayFajr,
    Map<PrayerName, Duration>? durations,
  }) async {
    await _database.insert(
      _table,
      _toRow(
        times: times,
        settings: settings,
        nextDayFajr: nextDayFajr,
        durations: durations,
      ),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Store many days in one transaction.
  ///
  /// A month prefetch is 30 inserts; outside a transaction that is 30 fsyncs on
  /// an encrypted database, which is visibly slow on mid-range hardware.
  @override
  Future<void> saveAll({
    required List<RawPrayerTimes> days,
    required AppSettings settings,
    Map<String, DateTime> nextDayFajrByDate = const {},
  }) async {
    if (days.isEmpty) return;

    await _database.transaction((txn) async {
      final batch = txn.batch();
      for (final times in days) {
        batch.insert(
          _table,
          _toRow(
            times: times,
            settings: settings,
            nextDayFajr: nextDayFajrByDate[dateKey(times.date)],
          ),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Map<String, Object?> _toRow({
    required RawPrayerTimes times,
    required AppSettings settings,
    DateTime? nextDayFajr,
    Map<PrayerName, Duration>? durations,
  }) {
    int? minutes(PrayerName prayer) => durations?[prayer]?.inMinutes;

    return {
      'id': rowId(times.date, settings),
      'prayer_date': dateKey(times.date),
      'latitude': times.latitude,
      'longitude': times.longitude,
      'location_key': locationKey(times.latitude, times.longitude),
      'timezone': times.timezone,
      'method': times.method.wireValue,
      'madhab': settings.madhab.wireValue,
      'high_latitude_rule': settings.highLatitudeRule.wireValue,
      'city': times.city,
      'country': times.country,
      'fajr': times.fajr.millisecondsSinceEpoch,
      'sunrise': times.sunrise.millisecondsSinceEpoch,
      'dhuhr': times.dhuhr.millisecondsSinceEpoch,
      'asr': times.asr.millisecondsSinceEpoch,
      'maghrib': times.maghrib.millisecondsSinceEpoch,
      'isha': times.isha.millisecondsSinceEpoch,
      'fajr_duration_minutes': minutes(PrayerName.fajr),
      'dhuhr_duration_minutes': minutes(PrayerName.dhuhr),
      'asr_duration_minutes': minutes(PrayerName.asr),
      'maghrib_duration_minutes': minutes(PrayerName.maghrib),
      'isha_duration_minutes': minutes(PrayerName.isha),
      'next_day_fajr': nextDayFajr?.millisecondsSinceEpoch,
      'source': times.source.wireValue,
      'fetched_at':
          (times.fetchedAt ?? DateTime.now().toUtc()).millisecondsSinceEpoch,
    };
  }

  // -- reads --------------------------------------------------------------

  /// The cached day for [date] under [settings], or null on a miss.
  @override
  Future<CachedPrayerDay?> read({
    required DateTime date,
    required AppSettings settings,
  }) async {
    final rows = await _database.query(
      _table,
      where: 'id = ?',
      whereArgs: [rowId(date, settings)],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CachedPrayerDay.fromRow(rows.first);
  }

  /// Cached days covering [from] .. [from + days), in date order.
  ///
  /// Days absent from the cache are simply missing from the result; the caller
  /// decides whether to fetch them.
  @override
  Future<List<CachedPrayerDay>> readRange({
    required DateTime from,
    required int days,
    required AppSettings settings,
  }) async {
    final ids = [
      for (var offset = 0; offset < days; offset++)
        rowId(DateTime(from.year, from.month, from.day + offset), settings),
    ];

    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await _database.query(
      _table,
      where: 'id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'prayer_date ASC',
    );

    return rows.map(CachedPrayerDay.fromRow).toList(growable: false);
  }

  /// Whether every day in the range is cached — the prefetch's completion test.
  Future<bool> hasRange({
    required DateTime from,
    required int days,
    required AppSettings settings,
  }) async {
    final cached = await readRange(from: from, days: days, settings: settings);
    return cached.length >= days;
  }

  // -- maintenance --------------------------------------------------------

  /// Drop rows older than [retentionDays] before [today].
  ///
  /// Bounded growth matters here: without it a daily prefetch of two weeks
  /// leaves roughly 5,000 rows a year, each of which is read past on every
  /// range query.
  @override
  @override
  Future<int> evictExpired({required DateTime today}) async {
    final cutoff = DateTime(today.year, today.month, today.day - retentionDays);
    return _database.delete(
      _table,
      where: 'prayer_date < ?',
      whereArgs: [dateKey(cutoff)],
    );
  }

  /// Drop everything. Used when the location or calculation settings change in
  /// a way that invalidates the whole cache, and by "delete my data".
  @override
  @override
  Future<void> clear() => _database.delete(_table);

  Future<int> count() async {
    final result =
        await _database.rawQuery('SELECT COUNT(*) AS count FROM $_table');
    return (result.first['count'] as int?) ?? 0;
  }
}

/// A schedule row read back from the cache.
class CachedPrayerDay {
  const CachedPrayerDay({
    required this.times,
    required this.nextDayFajr,
    required this.fetchedAt,
    required this.originalSource,
  });

  final RawPrayerTimes times;

  /// The following Fajr, if it was known when this row was written.
  final DateTime? nextDayFajr;

  final DateTime fetchedAt;

  /// What produced this row originally, as opposed to the fact that it now
  /// arrives from cache. Drives "these times were computed on-device, we will
  /// refresh them when you are back online".
  final PrayerTimeSource originalSource;

  factory CachedPrayerDay.fromRow(Map<String, Object?> row) {
    DateTime instant(String column) => DateTime.fromMillisecondsSinceEpoch(
          row[column]! as int,
          isUtc: true,
        );

    final source = PrayerTimeSource.fromWire(row['source']! as String);
    final nextFajr = row['next_day_fajr'] as int?;

    return CachedPrayerDay(
      originalSource: source,
      nextDayFajr: nextFajr == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(nextFajr, isUtc: true),
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(
        row['fetched_at']! as int,
        isUtc: true,
      ),
      times: RawPrayerTimes(
        date: DateTime.parse(row['prayer_date']! as String),
        fajr: instant('fajr'),
        sunrise: instant('sunrise'),
        dhuhr: instant('dhuhr'),
        asr: instant('asr'),
        maghrib: instant('maghrib'),
        isha: instant('isha'),
        // Reported as cache so callers can tell a re-read from a fresh fetch;
        // [originalSource] preserves where it first came from.
        source: PrayerTimeSource.cache,
        method: CalculationMethod.fromWire(row['method']! as String),
        latitude: (row['latitude']! as num).toDouble(),
        longitude: (row['longitude']! as num).toDouble(),
        timezone: row['timezone']! as String,
        city: row['city'] as String?,
        country: row['country'] as String?,
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(
          row['fetched_at']! as int,
          isUtc: true,
        ),
      ),
    );
  }

  /// Whether this row should be replaced when the network is available.
  bool get shouldRefresh => originalSource.shouldRefreshWhenOnline;
}
