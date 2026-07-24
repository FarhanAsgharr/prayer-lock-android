/// Offline-first resolution of prayer schedules.
///
/// The resolution order for a single day is:
///
///   1. the local cache, if it holds that day for the current configuration;
///   2. the remote provider, if the user prefers it and the network cooperates;
///   3. the on-device calculator, which cannot fail once a location is set.
///
/// Step 3 is why no feature stops working offline. It is not a degraded mode —
/// it produces a complete, correct schedule — so the difference between online
/// and offline is which authority's rounding conventions apply, not whether the
/// app functions.
///
/// Building a day's *windows* needs two days' times, because Isha runs to the
/// following Fajr. Both are resolved through the same path, so a cached today
/// plus an uncached tomorrow still yields a complete answer.
library;

import 'package:flutter/foundation.dart';

import '../../../../core/network/retry_policy.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../tracking/data/repositories/tracking_repository.dart';
import '../../domain/entities/prayer_day.dart';
import '../../domain/repositories/prayer_schedule_repository.dart';
import '../../domain/usecases/dynamic_duration_calculator.dart';
import '../../domain/usecases/prayer_time_calculator.dart';
import '../datasources/device_prayer_time_provider.dart';
import '../datasources/prayer_schedule_cache.dart';
import '../datasources/prayer_time_provider.dart';

class PrayerScheduleRepositoryImpl implements PrayerScheduleRepository {
  PrayerScheduleRepositoryImpl({
    required ScheduleCacheStore cache,
    required PrayerTimeProvider remoteProvider,
    required AppSettings Function() readSettings,
    PrayerTimeProvider offlineProvider = const DevicePrayerTimeProvider(),
    TrackingRepository? tracking,
    RetryPolicy retryPolicy = const RetryPolicy(),
  })  : _cache = cache,
        _remote = remoteProvider,
        _offline = offlineProvider,
        _readSettings = readSettings,
        _tracking = tracking,
        _retry = retryPolicy;

  final ScheduleCacheStore _cache;
  final PrayerTimeProvider _remote;
  final PrayerTimeProvider _offline;
  final AppSettings Function() _readSettings;
  final TrackingRepository? _tracking;
  final RetryPolicy _retry;

  /// Days kept ahead of today.
  ///
  /// Two weeks covers a normal gap in app usage plus a week of travel, and at
  /// one row per day it is a trivial amount of storage. Longer horizons buy
  /// little: prayer times a month out are not more useful than the on-device
  /// calculation of them.
  static const int defaultHorizonDays = 14;

  /// Remote failures within this window are not retried.
  ///
  /// Without it, a device that is offline for a day would attempt a fetch on
  /// every 30-second orchestrator tick — thousands of failed DNS lookups, each
  /// one waking the radio.
  static const Duration _remoteFailureCooldown = Duration(minutes: 15);

  DateTime? _remoteFailedAt;

  /// In-flight resolutions, keyed by cache row id.
  ///
  /// The orchestrator, the UI and the notification scheduler can all ask for
  /// today within the same frame. Without this they would each start their own
  /// fetch of the same day.
  final Map<String, Future<RawPrayerTimes>> _inFlight = {};

  @override
  Future<ResolvedPrayerDay> resolveDay(DateTime date) async {
    final settings = _readSettings();
    _requireLocation(settings);

    final normalised = DateTime(date.year, date.month, date.day);
    final tomorrow = DateTime(date.year, date.month, date.day + 1);

    final today = await _resolveTimes(normalised, settings);
    final next = await _resolveTimes(tomorrow, settings);

    final windows = DynamicDurationCalculator.fromSchedule(
      schedule: _toSchedule(today),
      nextDayFajr: next.fajr,
    );

    // Persist the durations and the closing boundary now that both days are
    // known, so a later read of this row alone can reconstruct the Isha window.
    await _cache.save(
      times: today,
      settings: settings,
      nextDayFajr: next.fajr,
      durations: {
        for (final window in windows.windows) window.prayer: window.duration,
      },
    );

    return ResolvedPrayerDay(
      windows: windows,
      source: today.source,
      isStale: today.source.shouldRefreshWhenOnline,
    );
  }

  @override
  Future<PrayerDay> prayerDay(DateTime date) async {
    final resolved = await resolveDay(date);
    final base = PrayerDay.fromWindows(resolved.windows);

    final tracking = _tracking;
    if (tracking == null) return base;

    final statuses = await tracking.statusesForDate(date);
    return statuses.entries.fold<PrayerDay>(
      base,
      (day, entry) => day.withEntry(
        day.entryFor(entry.key).copyWith(status: entry.value),
      ),
    );
  }

  @override
  Future<int> prefetch({
    required DateTime from,
    int days = defaultHorizonDays,
    bool force = false,
  }) async {
    final settings = _readSettings();
    _requireLocation(settings);

    final start = DateTime(from.year, from.month, from.day);
    // One extra day so the last day's Isha window has its closing Fajr.
    final span = days + 1;

    final missing = <DateTime>[];
    for (var offset = 0; offset < span; offset++) {
      final date = DateTime(start.year, start.month, start.day + offset);
      if (force) {
        missing.add(date);
        continue;
      }
      final cached = await _cache.read(date: date, settings: settings);
      if (cached == null || cached.shouldRefresh) missing.add(date);
    }

    if (missing.isEmpty) return 0;

    // Try the remote provider for the whole span in one request. A range fetch
    // is a single round trip per month, so it is worth attempting even when
    // only a few days are missing.
    if (_shouldUseRemote(settings)) {
      try {
        final fetched = await _retry.run(
          () => _remote.fetchRange(
            from: missing.first,
            days: missing.length,
            settings: settings,
          ),
          isRetryable: _isRetryable,
        );

        final usable = fetched.where((day) => day.isMonotonic).toList();
        await _cache.saveAll(days: usable, settings: settings);
        _remoteFailedAt = null;

        if (usable.length == fetched.length) return usable.length;
      } on PrayerTimeProviderException catch (error) {
        _noteRemoteFailure(error);
      }
    }

    // Whatever the network could not supply is computed locally, so the cache
    // is complete either way.
    var written = 0;
    for (final date in missing) {
      final cached = await _cache.read(date: date, settings: settings);
      if (cached != null && !cached.shouldRefresh) continue;
      if (cached != null && !_shouldUseRemote(settings)) continue;

      final computed = await _offline.fetch(date: date, settings: settings);
      await _cache.save(times: computed, settings: settings);
      written++;
    }

    return written;
  }

  @override
  Future<void> invalidate() async {
    _inFlight.clear();
    _remoteFailedAt = null;
    await _cache.clear();
  }

  @override
  Future<void> evictExpired({DateTime? today}) async {
    await _cache.evictExpired(today: today ?? DateTime.now());
  }

  // -- resolution ---------------------------------------------------------

  /// One day's times, by whichever route answers.
  Future<RawPrayerTimes> _resolveTimes(
    DateTime date,
    AppSettings settings,
  ) {
    final key = PrayerScheduleCache.rowId(date, settings);

    final existing = _inFlight[key];
    if (existing != null) return existing;

    final future = _resolveUncoalesced(date, settings);
    _inFlight[key] = future;
    // Cleared in a finally rather than on success only: a failed resolution
    // that stayed in the map would be replayed forever.
    return future.whenComplete(() => _inFlight.remove(key));
  }

  Future<RawPrayerTimes> _resolveUncoalesced(
    DateTime date,
    AppSettings settings,
  ) async {
    final cached = await _cache.read(date: date, settings: settings);

    // A remotely sourced cached day is authoritative and final.
    if (cached != null && !cached.shouldRefresh) return cached.times;

    if (_shouldUseRemote(settings)) {
      try {
        final fetched = await _retry.run(
          () => _remote.fetch(date: date, settings: settings),
          isRetryable: _isRetryable,
        );

        // A non-monotonic response would produce backwards windows. The
        // on-device calculation is well-defined at every latitude, so it is
        // strictly better than a response we know to be malformed.
        if (fetched.isMonotonic) {
          _remoteFailedAt = null;
          await _cache.save(times: fetched, settings: settings);
          return fetched;
        }

        debugPrint(
          'Discarding non-monotonic prayer times from ${_remote.id} '
          'for ${date.toIso8601String()}',
        );
      } on PrayerTimeProviderException catch (error) {
        _noteRemoteFailure(error);
      }
    }

    // Any cached day beats recomputing, even one computed on-device: it is the
    // same answer, and reusing it keeps the schedule stable across restarts.
    if (cached != null) return cached.times;

    final computed = await _offline.fetch(date: date, settings: settings);
    await _cache.save(times: computed, settings: settings);
    return computed;
  }

  bool _shouldUseRemote(AppSettings settings) {
    if (!settings.preferRemotePrayerTimes) return false;

    final failedAt = _remoteFailedAt;
    if (failedAt == null) return true;

    return DateTime.now().toUtc().difference(failedAt) > _remoteFailureCooldown;
  }

  void _noteRemoteFailure(PrayerTimeProviderException error) {
    // A permanent failure — unsupported location, bad configuration — starts
    // the same cooldown. Retrying it on the next tick would fail identically.
    _remoteFailedAt = DateTime.now().toUtc();
    debugPrint('Prayer time provider ${_remote.id} failed: ${error.message}');
  }

  static bool _isRetryable(Object error) =>
      error is! PrayerTimeProviderException || error.isRetryable;

  static PrayerSchedule _toSchedule(RawPrayerTimes times) => PrayerSchedule(
        prayerDate: times.date,
        fajr: times.fajr,
        sunrise: times.sunrise,
        dhuhr: times.dhuhr,
        asr: times.asr,
        maghrib: times.maghrib,
        isha: times.isha,
      );

  static void _requireLocation(AppSettings settings) {
    if (settings.location == null) {
      throw StateError(
        'PrayerScheduleRepository was asked for a schedule before a location '
        'was configured. Guard call sites with AppSettings.isReady.',
      );
    }
  }
}
