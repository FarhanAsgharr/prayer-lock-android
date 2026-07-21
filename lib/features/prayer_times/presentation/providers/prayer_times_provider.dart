/// Prayer schedule state, derived from settings and the device clock.
///
/// Everything here is computed on-device. There is no network dependency in
/// this file, which is what makes the offline requirement structural rather
/// than a caching strategy that degrades when the cache misses.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/prayer_day.dart';
import '../../../tracking/presentation/providers/tracking_providers.dart';
import '../../domain/entities/prayer_enums.dart';
import '../../domain/usecases/prayer_time_calculator.dart';

/// Ticks once per second, driving the countdown.
///
/// One shared timer rather than a timer per widget: several widgets show
/// elapsed or remaining time, and independent timers would drift apart
/// visibly and waste wakeups.
final clockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now().toUtc();
  yield* Stream.periodic(
    const Duration(seconds: 1),
    (_) => DateTime.now().toUtc(),
  );
});

/// Current instant, non-async for synchronous reads.
final nowProvider = Provider<DateTime>((ref) {
  return ref.watch(clockProvider).valueOrNull ?? DateTime.now().toUtc();
});

/// Resolves an IANA timezone name to its UTC offset on a given date.
///
/// Uses the timezone package's database rather than the device offset,
/// because the device offset is only correct for *today* — computing next
/// week's schedule across a DST boundary needs the offset on that date.
double utcOffsetHoursFor(String timezoneName, DateTime date) {
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

/// Builds a schedule for an arbitrary date under the given settings.
PrayerSchedule? scheduleFor(AppSettings settings, DateTime date) {
  final location = settings.location;
  if (location == null) return null;

  return prayerTimeCalculator.calculate(
    CalculationRequest(
      latitude: location.latitude,
      longitude: location.longitude,
      utcOffsetHours: utcOffsetHoursFor(location.timezone, date),
      prayerDate: DateTime(date.year, date.month, date.day),
      method: settings.calculationMethod,
      madhab: settings.madhab,
      highLatitudeRule: settings.highLatitudeRule,
      adjustments: settings.adjustments,
    ),
  );
}

/// The local calendar date currently in effect at the user's location.
///
/// Derived from the configured timezone, not the device's — a traveller whose
/// phone has switched zones must still see the schedule for where they set
/// their location.
final localDateProvider = Provider<DateTime>((ref) {
  final settings = ref.watch(settingsProvider);
  final now = ref.watch(nowProvider);

  final timezone = settings.location?.timezone;
  if (timezone == null) return DateTime(now.year, now.month, now.day);

  try {
    final local = tz.TZDateTime.from(now, tz.getLocation(timezone));
    return DateTime(local.year, local.month, local.day);
  } on tz.LocationNotFoundException {
    return DateTime(now.year, now.month, now.day);
  }
});

/// Today's prayers, merged with the outcomes recorded in the database.
///
/// Returns null while the tracked statuses are still loading, so the UI shows
/// its loading state rather than briefly rendering every prayer as unfulfilled
/// — which would flash "missed" at a user who had actually prayed.
final prayerDayProvider = Provider<PrayerDay?>((ref) {
  final settings = ref.watch(settingsProvider);
  final date = ref.watch(localDateProvider);

  final schedule = scheduleFor(settings, date);
  if (schedule == null) return null;

  // Windows are fixed 30/90-minute spans from each prayer's start, so a day is
  // self-contained — no need for the following day's schedule.
  final base = PrayerDay.fromSchedule(schedule);

  final tracked = ref.watch(trackedStatusesProvider(date)).valueOrNull;
  if (tracked == null) return base;

  return tracked.entries.fold<PrayerDay>(
    base,
    (day, entry) => day.withEntry(
      day.entryFor(entry.key).copyWith(status: entry.value),
    ),
  );
});

/// The prayer currently owed, if any.
final currentPrayerProvider = Provider<PrayerEntry?>((ref) {
  final day = ref.watch(prayerDayProvider);
  final now = ref.watch(nowProvider);
  return day?.currentPrayer(now);
});

/// The next prayer to begin, and how long until it does.
final nextPrayerProvider = Provider<({PrayerEntry entry, Duration until})?>((ref) {
  final day = ref.watch(prayerDayProvider);
  final now = ref.watch(nowProvider);
  if (day == null) return null;

  final next = day.nextPrayer(now);
  if (next != null) {
    return (entry: next, until: next.scheduledAt.difference(now));
  }

  // Past Isha: the next prayer is tomorrow's Fajr, and the countdown must
  // roll over rather than showing nothing for several hours.
  final settings = ref.watch(settingsProvider);
  final tomorrow =
      scheduleFor(settings, ref.watch(localDateProvider).add(const Duration(days: 1)));
  if (tomorrow == null) return null;

  final fajrEntry = PrayerEntry(
    prayer: PrayerName.fajr,
    scheduledAt: tomorrow.fajr,
  );
  return (entry: fajrEntry, until: tomorrow.fajr.difference(now));
});

/// Whether the Fajr morning-protection gate should be active.
final morningProtectionActiveProvider = Provider<bool>((ref) {
  final settings = ref.watch(settingsProvider);
  if (!settings.morningProtectionEnabled) return false;

  final day = ref.watch(prayerDayProvider);
  final now = ref.watch(nowProvider);
  return day?.requiresMorningProtection(now) ?? false;
});
