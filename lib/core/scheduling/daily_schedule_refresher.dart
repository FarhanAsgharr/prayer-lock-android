/// Keeps the prayer schedule current as days, locations and clocks change.
///
/// The requirement is "every midnight, download the new day's schedule and
/// recalculate". A literal midnight timer is the wrong mechanism for it: a timer
/// does not survive the process being killed, does not fire while the device is
/// in Doze, and fires at the wrong moment for a user who has travelled. What
/// actually matters is that the schedule is correct whenever the app is in a
/// position to act on it.
///
/// So the refresh is driven by *observations* rather than by a clock:
///
///   * the local calendar date has changed since the last refresh;
///   * the app was resumed and the cached horizon has run down;
///   * the location or calculation settings changed;
///   * the device's UTC offset changed, which means travel or a DST transition.
///
/// Each of these is checked cheaply and often. A day rolls over exactly once
/// per day either way, but this version also copes with the app having been
/// closed for a week, with the user landing in a new timezone, and with a
/// device whose clock was wrong until NTP corrected it.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/prayer_times/data/datasources/device_prayer_time_provider.dart';
import '../../features/prayer_times/domain/repositories/prayer_schedule_repository.dart';
import '../../features/prayer_times/presentation/providers/prayer_times_provider.dart';
import '../../features/settings/domain/entities/app_settings.dart';
import '../../features/settings/presentation/providers/settings_provider.dart';

/// What the refresher observed last time it ran, so it can tell what changed.
@immutable
class ScheduleFingerprint {
  const ScheduleFingerprint({
    required this.localDate,
    required this.locationKey,
    required this.calculationKey,
    required this.utcOffsetHours,
  });

  final DateTime localDate;
  final String locationKey;
  final String calculationKey;
  final double utcOffsetHours;

  static ScheduleFingerprint? of(AppSettings settings, DateTime localDate) {
    final location = settings.location;
    if (location == null) return null;

    return ScheduleFingerprint(
      localDate: DateTime(localDate.year, localDate.month, localDate.day),
      locationKey: '${location.latitude.toStringAsFixed(3)},'
          '${location.longitude.toStringAsFixed(3)},${location.timezone}',
      calculationKey: [
        settings.calculationMethod.wireValue,
        settings.madhab.wireValue,
        settings.highLatitudeRule.wireValue,
        settings.preferRemotePrayerTimes,
        for (final entry in settings.adjustments.entries)
          '${entry.key.wireValue}:${entry.value}',
      ].join('|'),
      utcOffsetHours: utcOffsetHoursAt(location.timezone, localDate),
    );
  }

  /// Whether the *whole cache* is now wrong, as opposed to merely incomplete.
  ///
  /// A location or calculation change invalidates every cached day, because
  /// those days were computed for different inputs. A date change does not:
  /// yesterday's cached times are still correct for yesterday.
  bool invalidatesCache(ScheduleFingerprint previous) =>
      locationKey != previous.locationKey ||
      calculationKey != previous.calculationKey;

  /// Whether anything at all changed.
  bool differsFrom(ScheduleFingerprint previous) =>
      invalidatesCache(previous) ||
      localDate != previous.localDate ||
      utcOffsetHours != previous.utcOffsetHours;

  @override
  bool operator ==(Object other) =>
      other is ScheduleFingerprint &&
      other.localDate == localDate &&
      other.locationKey == locationKey &&
      other.calculationKey == calculationKey &&
      other.utcOffsetHours == utcOffsetHours;

  @override
  int get hashCode =>
      Object.hash(localDate, locationKey, calculationKey, utcOffsetHours);
}

/// Why a refresh ran, for logging and for tests.
enum RefreshTrigger {
  /// First run after launch.
  startup,

  /// The local calendar date rolled over.
  dayChanged,

  /// Location or calculation settings changed.
  settingsChanged,

  /// The UTC offset moved — travel, or a DST transition.
  timezoneShift,

  /// The app was resumed and the cache horizon had run down.
  horizonExhausted,

  /// Explicitly requested by the user.
  manual,
}

@immutable
class RefreshResult {
  const RefreshResult({
    required this.trigger,
    required this.daysWritten,
    required this.cacheInvalidated,
  });

  final RefreshTrigger trigger;
  final int daysWritten;
  final bool cacheInvalidated;
}

final dailyScheduleRefresherProvider = Provider<DailyScheduleRefresher>((ref) {
  final refresher = DailyScheduleRefresher(ref);
  ref.onDispose(refresher.stop);
  return refresher;
});

class DailyScheduleRefresher {
  DailyScheduleRefresher(this._ref);

  final Ref _ref;

  Timer? _ticker;
  ScheduleFingerprint? _lastFingerprint;

  /// Guards against two refreshes overlapping, which would issue duplicate
  /// fetches for the same days.
  bool _isRefreshing = false;

  /// How often to check whether anything has changed.
  ///
  /// This is a comparison of four small values, not a fetch, so it is cheap
  /// enough to run every few minutes. It is what catches midnight without
  /// needing a timer aimed at midnight — which would be wrong for a traveller
  /// and dead after a process kill.
  static const Duration checkInterval = Duration(minutes: 5);

  PrayerScheduleRepository get _repository =>
      _ref.read(prayerScheduleRepositoryProvider);

  /// Begin observing. Called once from the app shell.
  Future<void> start() async {
    _ticker?.cancel();
    _ticker = Timer.periodic(checkInterval, (_) => unawaited(refreshIfNeeded()));

    await refreshIfNeeded(trigger: RefreshTrigger.startup);
  }

  void stop() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// Refresh only if something the schedule depends on has changed.
  Future<RefreshResult?> refreshIfNeeded({RefreshTrigger? trigger}) async {
    if (_isRefreshing) return null;

    final settings = _ref.read(settingsProvider);
    if (!settings.isReady) return null;

    final localDate = _ref.read(localDateProvider);
    final current = ScheduleFingerprint.of(settings, localDate);
    if (current == null) return null;

    final previous = _lastFingerprint;

    // Nothing observable changed and this is not a forced run.
    if (previous != null &&
        !current.differsFrom(previous) &&
        trigger != RefreshTrigger.manual &&
        trigger != RefreshTrigger.startup) {
      return null;
    }

    final resolvedTrigger = trigger ??
        (previous == null
            ? RefreshTrigger.startup
            : current.invalidatesCache(previous)
                ? RefreshTrigger.settingsChanged
                : current.utcOffsetHours != previous.utcOffsetHours
                    ? RefreshTrigger.timezoneShift
                    : RefreshTrigger.dayChanged);

    final invalidates =
        previous != null && current.invalidatesCache(previous);

    return _refresh(
      trigger: resolvedTrigger,
      invalidateCache: invalidates,
      fingerprint: current,
      localDate: localDate,
    );
  }

  /// Force a refresh — the pull-to-refresh gesture and the settings screen's
  /// "update prayer times now".
  Future<RefreshResult?> refreshNow({bool invalidateCache = false}) async {
    final settings = _ref.read(settingsProvider);
    if (!settings.isReady) return null;

    final localDate = _ref.read(localDateProvider);
    final fingerprint = ScheduleFingerprint.of(settings, localDate);
    if (fingerprint == null) return null;

    return _refresh(
      trigger: RefreshTrigger.manual,
      invalidateCache: invalidateCache,
      fingerprint: fingerprint,
      localDate: localDate,
    );
  }

  Future<RefreshResult?> _refresh({
    required RefreshTrigger trigger,
    required bool invalidateCache,
    required ScheduleFingerprint fingerprint,
    required DateTime localDate,
  }) async {
    _isRefreshing = true;

    try {
      if (invalidateCache) {
        // Every cached day was computed for inputs that no longer apply.
        // Serving them would show the user times for a city they have left.
        await _repository.invalidate();
      }

      final written = await _repository.prefetch(from: localDate);

      // Bounded growth: without this the cache accumulates a row per day
      // forever, and every range query reads past all of them.
      await _repository.evictExpired(today: localDate);

      // Recomputed windows mean recomputed notification instants and a stale
      // native mirror, so both are rebuilt from the new schedule.
      _ref.invalidate(resolvedWindowsProvider);

      _lastFingerprint = fingerprint;

      debugPrint(
        'Prayer schedule refreshed (${trigger.name}): '
        '$written day(s) written'
        '${invalidateCache ? ', cache invalidated' : ''}',
      );

      return RefreshResult(
        trigger: trigger,
        daysWritten: written,
        cacheInvalidated: invalidateCache,
      );
    } catch (error, stackTrace) {
      // A failed refresh must never take the app down or stop enforcement.
      // The previously cached days remain valid, and the on-device calculator
      // covers anything they do not.
      debugPrint('Prayer schedule refresh failed: $error\n$stackTrace');
      return null;
    } finally {
      _isRefreshing = false;
    }
  }

  /// The fingerprint last successfully refreshed against. Tests only.
  @visibleForTesting
  ScheduleFingerprint? get lastFingerprint => _lastFingerprint;
}
