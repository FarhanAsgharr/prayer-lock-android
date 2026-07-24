/// Shared fixtures for the dynamic-duration tests.
///
/// Every test that needs a day of prayer windows builds it here, so a change to
/// how a day is constructed is made once rather than in a dozen files — and so
/// no test accidentally exercises a differently-shaped day from the one the app
/// actually produces.
library;

import 'package:prayer_lock/features/prayer_times/data/datasources/prayer_schedule_cache.dart';
import 'package:prayer_lock/features/prayer_times/data/datasources/prayer_time_provider.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_day.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_window.dart';
import 'package:prayer_lock/features/prayer_times/domain/usecases/dynamic_duration_calculator.dart';
import 'package:prayer_lock/features/prayer_times/domain/usecases/prayer_time_calculator.dart';
import 'package:prayer_lock/features/settings/domain/entities/app_settings.dart';

const makkah = PrayerLocation(
  latitude: 21.4225,
  longitude: 39.8262,
  timezone: 'Asia/Riyadh',
  label: 'Makkah',
);

/// London, for the DST and high-latitude cases Makkah cannot exercise.
const london = PrayerLocation(
  latitude: 51.5074,
  longitude: -0.1278,
  timezone: 'Europe/London',
  label: 'London',
);

/// Tromsø: inside the Arctic Circle, where the sun does not set in midsummer.
const tromso = PrayerLocation(
  latitude: 69.6492,
  longitude: 18.9553,
  timezone: 'Europe/Oslo',
  label: 'Tromsø',
);

/// A raw schedule for [date] at [location].
PrayerSchedule scheduleAt({
  required PrayerLocation location,
  required DateTime date,
  required double utcOffsetHours,
  CalculationMethod method = CalculationMethod.muslimWorldLeague,
  Madhab madhab = Madhab.shafi,
}) =>
    prayerTimeCalculator.calculate(
      CalculationRequest(
        latitude: location.latitude,
        longitude: location.longitude,
        utcOffsetHours: utcOffsetHours,
        prayerDate: DateTime(date.year, date.month, date.day),
        method: method,
        madhab: madhab,
      ),
    );

/// The dynamic windows for [date], resolving the following day's Fajr properly
/// rather than approximating it — the Isha duration depends on it.
DailyPrayerWindows windowsAt({
  PrayerLocation location = makkah,
  DateTime? date,
  double utcOffsetHours = 3,
  CalculationMethod method = CalculationMethod.muslimWorldLeague,
  Madhab madhab = Madhab.shafi,
}) {
  final day = date ?? DateTime(2026, 7, 20);
  final next = DateTime(day.year, day.month, day.day + 1);

  return DynamicDurationCalculator.fromSchedule(
    schedule: scheduleAt(
      location: location,
      date: day,
      utcOffsetHours: utcOffsetHours,
      method: method,
      madhab: madhab,
    ),
    nextDayFajr: scheduleAt(
      location: location,
      date: next,
      utcOffsetHours: utcOffsetHours,
      method: method,
      madhab: madhab,
    ).fajr,
  );
}

/// A [PrayerDay] with optional recorded outcomes merged in.
PrayerDay buildDay({
  PrayerLocation location = makkah,
  DateTime? date,
  double utcOffsetHours = 3,
  Map<PrayerName, PrayerStatus> statuses = const {},
}) {
  var day = PrayerDay.fromWindows(
    windowsAt(
      location: location,
      date: date,
      utcOffsetHours: utcOffsetHours,
    ),
  );

  for (final entry in statuses.entries) {
    day = day.withEntry(day.entryFor(entry.key).copyWith(status: entry.value));
  }

  return day;
}

/// Settings with every knob the lock decision reads made explicit.
AppSettings settingsWith({
  PrayerLocation location = makkah,
  bool blockingEnabled = true,
  bool morningProtection = false,
  int gracePeriodMinutes = 0,
  UnlockPolicy unlockPolicy = UnlockPolicy.onVerification,
  bool blockUntilQaza = false,
  bool preferRemote = true,
  Set<String> blockedPackages = const {'com.instagram.android'},
}) =>
    AppSettings(
      location: location,
      blockingEnabled: blockingEnabled,
      // Off by default in fixtures: the Fajr gate short-circuits the decision
      // before any other rule runs, so leaving it on would silently mask every
      // test that is not about Fajr.
      morningProtectionEnabled: morningProtection,
      lockGracePeriodMinutes: gracePeriodMinutes,
      unlockPolicy: unlockPolicy,
      blockUntilQazaCompleted: blockUntilQaza,
      preferRemotePrayerTimes: preferRemote,
      blockedPackages: blockedPackages,
    );

/// An in-memory [ScheduleCacheStore] for testing resolution without SQLCipher.
class FakeScheduleCache implements ScheduleCacheStore {
  final Map<String, CachedPrayerDay> _rows = {};

  int saveCount = 0;
  int readCount = 0;
  int clearCount = 0;

  /// Rows currently held, for assertions.
  int get length => _rows.length;

  @override
  Future<void> save({
    required RawPrayerTimes times,
    required AppSettings settings,
    DateTime? nextDayFajr,
    Map<PrayerName, Duration>? durations,
  }) async {
    saveCount++;
    _rows[PrayerScheduleCache.rowId(times.date, settings)] = CachedPrayerDay(
      // Round-trips through the cache report themselves as such, mirroring what
      // the real implementation does on read.
      times: times.copyWith(source: PrayerTimeSource.cache),
      nextDayFajr: nextDayFajr,
      fetchedAt: times.fetchedAt ?? DateTime.now().toUtc(),
      originalSource: times.source == PrayerTimeSource.cache
          ? PrayerTimeSource.device
          : times.source,
    );
  }

  @override
  Future<void> saveAll({
    required List<RawPrayerTimes> days,
    required AppSettings settings,
    Map<String, DateTime> nextDayFajrByDate = const {},
  }) async {
    for (final day in days) {
      await save(times: day, settings: settings);
    }
  }

  @override
  Future<CachedPrayerDay?> read({
    required DateTime date,
    required AppSettings settings,
  }) async {
    readCount++;
    return _rows[PrayerScheduleCache.rowId(date, settings)];
  }

  @override
  Future<List<CachedPrayerDay>> readRange({
    required DateTime from,
    required int days,
    required AppSettings settings,
  }) async {
    final result = <CachedPrayerDay>[];
    for (var offset = 0; offset < days; offset++) {
      final date = DateTime(from.year, from.month, from.day + offset);
      final row = _rows[PrayerScheduleCache.rowId(date, settings)];
      if (row != null) result.add(row);
    }
    return result;
  }

  @override
  Future<int> evictExpired({required DateTime today}) async => 0;

  @override
  Future<void> clear() async {
    clearCount++;
    _rows.clear();
  }
}

/// A provider that fails on demand, for the offline-fallback tests.
class FailingPrayerTimeProvider implements PrayerTimeProvider {
  FailingPrayerTimeProvider({
    this.isRetryable = true,
    this.message = 'network unreachable',
  });

  final bool isRetryable;
  final String message;

  int fetchAttempts = 0;

  @override
  String get id => 'failing';

  @override
  String get displayName => 'Failing provider';

  @override
  bool get requiresNetwork => true;

  @override
  Future<RawPrayerTimes> fetch({
    required DateTime date,
    required AppSettings settings,
  }) async {
    fetchAttempts++;
    throw PrayerTimeProviderException(message, isRetryable: isRetryable);
  }

  @override
  Future<List<RawPrayerTimes>> fetchRange({
    required DateTime from,
    required int days,
    required AppSettings settings,
  }) async {
    fetchAttempts++;
    throw PrayerTimeProviderException(message, isRetryable: isRetryable);
  }
}

/// A provider returning times shifted by a fixed offset from the device
/// calculation, so a test can tell which source answered.
class StubRemoteProvider implements PrayerTimeProvider {
  StubRemoteProvider({
    this.shift = const Duration(minutes: 7),
    this.monotonic = true,
  });

  /// How far to move every instant, so remote answers are distinguishable.
  final Duration shift;

  /// When false, returns times deliberately out of order, to exercise the
  /// repository's rejection of malformed responses.
  final bool monotonic;

  int fetchCount = 0;

  @override
  String get id => 'stub-remote';

  @override
  String get displayName => 'Stub remote';

  @override
  bool get requiresNetwork => true;

  @override
  Future<RawPrayerTimes> fetch({
    required DateTime date,
    required AppSettings settings,
  }) async {
    fetchCount++;

    final base = scheduleAt(
      location: settings.location!,
      date: date,
      utcOffsetHours: 3,
    );

    return RawPrayerTimes(
      date: DateTime(date.year, date.month, date.day),
      fajr: base.fajr.add(shift),
      sunrise: base.sunrise.add(shift),
      dhuhr: base.dhuhr.add(shift),
      asr: base.asr.add(shift),
      maghrib: base.maghrib.add(shift),
      // Isha placed before Maghrib makes the sequence non-monotonic.
      isha: monotonic
          ? base.isha.add(shift)
          : base.maghrib.subtract(const Duration(hours: 1)),
      source: PrayerTimeSource.remote,
      method: settings.calculationMethod,
      latitude: settings.location!.latitude,
      longitude: settings.location!.longitude,
      timezone: settings.location!.timezone,
      fetchedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<List<RawPrayerTimes>> fetchRange({
    required DateTime from,
    required int days,
    required AppSettings settings,
  }) async {
    return [
      for (var offset = 0; offset < days; offset++)
        await fetch(
          date: DateTime(from.year, from.month, from.day + offset),
          settings: settings,
        ),
    ];
  }
}
