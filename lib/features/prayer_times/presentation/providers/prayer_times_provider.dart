/// Prayer schedule state, derived from settings and the device clock.
///
/// Two paths coexist deliberately:
///
///   * a *synchronous* device computation, used for first paint and as the
///     floor whenever anything else is unavailable. It needs no I/O, so the
///     dashboard never shows a spinner where prayer times should be.
///
///   * an *asynchronous* repository resolution, which prefers cached or
///     remotely fetched times and replaces the synchronous answer once it
///     arrives.
///
/// Both produce the same shape. The synchronous one is never wrong, only
/// potentially less authoritative than the local convention a remote service
/// encodes — which is why it is safe to render immediately.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../../core/storage/storage_providers.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../tracking/presentation/providers/tracking_providers.dart';
import '../../data/datasources/aladhan_prayer_time_provider.dart';
import '../../data/datasources/device_prayer_time_provider.dart';
import '../../data/datasources/prayer_schedule_cache.dart';
import '../../data/datasources/prayer_time_provider.dart';
import '../../data/repositories/prayer_schedule_repository_impl.dart';
import '../../domain/entities/prayer_day.dart';
import '../../domain/entities/prayer_enums.dart';
import '../../domain/entities/prayer_slot.dart';
import '../../domain/entities/prayer_window.dart';
import '../../domain/repositories/prayer_schedule_repository.dart';
import '../../../jumuah/domain/usecases/jumuah_scheduler.dart';
import '../../domain/usecases/dynamic_duration_calculator.dart';
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
double utcOffsetHoursFor(String timezoneName, DateTime date) =>
    utcOffsetHoursAt(timezoneName, date);

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

/// The day's windows computed on-device, with no I/O.
///
/// Resolves the following day's Fajr as well, because Isha's window has no end
/// without it.
DailyPrayerWindows? windowsFor(AppSettings settings, DateTime date) {
  final location = settings.location;
  if (location == null) return null;

  final schedule = scheduleFor(settings, date);
  if (schedule == null) return null;

  final tomorrow = scheduleFor(
    settings,
    DateTime(date.year, date.month, date.day + 1),
  );
  if (tomorrow == null) return null;

  final windows = DynamicDurationCalculator.fromSchedule(
    schedule: schedule,
    nextDayFajr: tomorrow.fajr,
  );

  // Jumu'ah replaces the Dhuhr window on Fridays. A no-op on every other day,
  // and when the feature is off or unconfigured, so this is applied
  // unconditionally rather than behind a weekday check here.
  return JumuahScheduler.applyTo(
    windows: windows,
    settings: settings.jumuah,
    timezone: location.timezone,
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

// -- data layer wiring -----------------------------------------------------

/// The remote authority. Swapping this one line changes the service the whole
/// app fetches from.
final remotePrayerTimeProviderProvider = Provider<PrayerTimeProvider>(
  (ref) => AlAdhanPrayerTimeProvider(),
);

final offlinePrayerTimeProviderProvider = Provider<PrayerTimeProvider>(
  (ref) => const DevicePrayerTimeProvider(),
);

final prayerScheduleCacheProvider = Provider<PrayerScheduleCache>(
  (ref) => PrayerScheduleCache(ref.watch(appDatabaseProvider).raw),
);

final prayerScheduleRepositoryProvider = Provider<PrayerScheduleRepository>(
  (ref) => PrayerScheduleRepositoryImpl(
    cache: ref.watch(prayerScheduleCacheProvider),
    remoteProvider: ref.watch(remotePrayerTimeProviderProvider),
    offlineProvider: ref.watch(offlinePrayerTimeProviderProvider),
    tracking: ref.watch(trackingRepositoryProvider),
    // Read rather than watched: the repository asks for settings at call time,
    // so it always sees the current value without the provider being rebuilt —
    // and rebuilding it would drop the in-flight request coalescing.
    readSettings: () => ref.read(settingsProvider),
  ),
);

/// The authoritative windows for a date, resolved through the repository.
///
/// Keyed by date so yesterday and tomorrow can be inspected without disturbing
/// today's subscription.
final resolvedWindowsProvider =
    FutureProvider.family<ResolvedPrayerDay?, DateTime>((ref, date) async {
  final settings = ref.watch(settingsProvider);
  if (!settings.isReady) return null;

  return ref.watch(prayerScheduleRepositoryProvider).resolveDay(date);
});

/// Today's windows, resolved.
final todayWindowsProvider = Provider<DailyPrayerWindows?>((ref) {
  final settings = ref.watch(settingsProvider);
  final date = ref.watch(localDateProvider);

  final resolved = ref.watch(resolvedWindowsProvider(date)).valueOrNull;
  // Fall back to the device computation while the repository resolves, so the
  // schedule renders on the first frame rather than after a database read.
  return resolved?.windows ?? windowsFor(settings, date);
});

/// Whether the times on screen are awaiting a better source.
final prayerTimesAreStaleProvider = Provider<bool>((ref) {
  final date = ref.watch(localDateProvider);
  final resolved = ref.watch(resolvedWindowsProvider(date)).valueOrNull;
  // Unresolved means the device computation is showing, which is by definition
  // refreshable.
  return resolved?.isStale ?? true;
});

/// Where today's times came from, for the settings and dashboard footers.
final prayerTimeSourceProvider = Provider<PrayerTimeSource>((ref) {
  final date = ref.watch(localDateProvider);
  return ref.watch(resolvedWindowsProvider(date)).valueOrNull?.source ??
      PrayerTimeSource.device;
});

// -- derived day state -----------------------------------------------------

/// Today's prayers, merged with the outcomes recorded in the database.
final prayerDayProvider = Provider<PrayerDay?>((ref) {
  final windows = ref.watch(todayWindowsProvider);
  if (windows == null) return null;

  final base = PrayerDay.fromWindows(windows);

  final date = ref.watch(localDateProvider);
  final tracked = ref.watch(trackedStatusesProvider(date)).valueOrNull;
  if (tracked == null) return base;

  return tracked.entries.fold<PrayerDay>(
    base,
    (day, entry) => day.withEntry(
      day.entryFor(entry.key).copyWith(status: entry.value),
    ),
  );
});

/// Today's day projected into the units the user acts on.
///
/// Everything the dashboard renders reads from here, so switching between
/// separate and combined prayers re-renders the whole screen with no restart
/// and no cache to invalidate.
final prayerSlotsProvider = Provider<List<PrayerSlot>>((ref) {
  final day = ref.watch(prayerDayProvider);
  if (day == null) return const [];

  return day.slots(ref.watch(settingsProvider).prayerGrouping);
});

/// The slot currently owed, if any.
final currentSlotProvider = Provider<PrayerSlot?>((ref) {
  final day = ref.watch(prayerDayProvider);
  final now = ref.watch(nowProvider);
  return day?.lockableSlot(now, ref.watch(settingsProvider).prayerGrouping);
});

/// The slot whose window is open, regardless of whether it is owed.
final activeSlotProvider = Provider<PrayerSlot?>((ref) {
  final day = ref.watch(prayerDayProvider);
  final now = ref.watch(nowProvider);
  return day?.activeSlot(now, ref.watch(settingsProvider).prayerGrouping);
});

/// The next slot to open, and how long until it does.
final nextSlotProvider = Provider<({PrayerSlot slot, Duration until})?>((ref) {
  final day = ref.watch(prayerDayProvider);
  final now = ref.watch(nowProvider);
  if (day == null) return null;

  final grouping = ref.watch(settingsProvider).prayerGrouping;
  final next = day.nextSlot(now, grouping);
  if (next != null) {
    return (slot: next, until: next.window.startsAt.difference(now));
  }

  // Past the final slot: roll over to tomorrow's Fajr, which is never part of
  // a pair, so it is always its own slot.
  final settings = ref.watch(settingsProvider);
  final tomorrowDate = ref.watch(localDateProvider).add(const Duration(days: 1));
  final tomorrow = windowsFor(settings, tomorrowDate);
  if (tomorrow == null) return null;

  final fajrSlot = PrayerSlot.single(
    PrayerEntry(
      window: tomorrow.windowFor(PrayerName.fajr),
      dayEndsAt: tomorrow.nextDayFajr,
    ),
  );
  return (slot: fajrSlot, until: fajrSlot.window.startsAt.difference(now));
});

/// The prayer currently owed, if any.
final currentPrayerProvider = Provider<PrayerEntry?>((ref) {
  final day = ref.watch(prayerDayProvider);
  final now = ref.watch(nowProvider);
  return day?.currentPrayer(now);
});

/// The prayer whose window is open right now — the one whose duration is
/// counting down, regardless of whether it has been verified.
final activePrayerProvider = Provider<PrayerEntry?>((ref) {
  final day = ref.watch(prayerDayProvider);
  final now = ref.watch(nowProvider);
  return day?.activePrayer(now);
});

/// Time left in the active prayer's window, for the countdown.
final activeWindowRemainingProvider = Provider<Duration?>((ref) {
  final entry = ref.watch(activePrayerProvider);
  final now = ref.watch(nowProvider);
  return entry?.window.remainingAt(now);
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
  final tomorrowDate = ref.watch(localDateProvider).add(const Duration(days: 1));
  final tomorrow = windowsFor(settings, tomorrowDate);
  if (tomorrow == null) return null;

  final fajrWindow = tomorrow.windowFor(PrayerName.fajr);
  final fajrEntry = PrayerEntry(
    window: fajrWindow,
    dayEndsAt: tomorrow.nextDayFajr,
  );
  return (entry: fajrEntry, until: fajrWindow.startsAt.difference(now));
});

/// Prayers whose window has closed unfulfilled but which can still be made up.
final outstandingQazaProvider = Provider<List<PrayerEntry>>((ref) {
  final day = ref.watch(prayerDayProvider);
  final now = ref.watch(nowProvider);
  return day?.outstandingQaza(now) ?? const [];
});

/// Whether the Fajr morning-protection gate should be active.
final morningProtectionActiveProvider = Provider<bool>((ref) {
  final settings = ref.watch(settingsProvider);
  if (!settings.morningProtectionEnabled) return false;

  final day = ref.watch(prayerDayProvider);
  final now = ref.watch(nowProvider);
  return day?.requiresMorningProtection(now) ?? false;
});
