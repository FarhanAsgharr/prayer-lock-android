/// Turns a day's prayer instants into the windows apps are blocked for.
///
/// Pure, synchronous, and free of I/O — every rule that decides how long a
/// phone stays locked is testable without a device, a network, or a clock.
///
/// The one genuinely hard part is ordering. The astronomical calculator can, at
/// high latitudes and under some high-latitude fallback rules, return times that
/// are not in ascending order: Isha pushed past the following Fajr in midsummer,
/// or Asr landing before Dhuhr. A window built naively from those would run
/// backwards, and a backwards window means a lock whose end is in the past —
/// which either never engages or never releases. So the boundaries are forced
/// monotonic first, and anything that had to move is flagged rather than
/// silently corrected.
library;

import '../entities/prayer_enums.dart';
import '../entities/prayer_window.dart';
import 'prayer_time_calculator.dart';

/// Computes [DailyPrayerWindows] from prayer instants.
abstract final class DynamicDurationCalculator {
  /// Build the day's windows from [schedule] and the following day's Fajr.
  ///
  /// [nextDayFajr] is required rather than optional: Isha's window has no
  /// defined end without it, and defaulting to midnight or to a fixed number of
  /// hours would reintroduce exactly the hardcoded duration this replaces.
  static DailyPrayerWindows fromSchedule({
    required PrayerSchedule schedule,
    required DateTime nextDayFajr,
  }) {
    // The boundary instants in the order they must occur. Every window start
    // and every window end is drawn from this sequence.
    final ordered = _forceAscending([
      schedule.fajr,
      schedule.sunrise,
      schedule.dhuhr,
      schedule.asr,
      schedule.maghrib,
      schedule.isha,
      nextDayFajr,
    ]);

    final fajr = ordered[0];
    final sunrise = ordered[1];
    final dhuhr = ordered[2];
    final asr = ordered[3];
    final maghrib = ordered[4];
    final isha = ordered[5];
    final followingFajr = ordered[6];

    // True when any boundary had to be moved, i.e. the raw times were not in
    // ascending order. Applied to every window rather than tracked per index,
    // because a single displaced boundary distorts the two windows either side
    // of it and there is no honest way to say only one of them is affected.
    final clamped = !_isAscending([
      schedule.fajr,
      schedule.sunrise,
      schedule.dhuhr,
      schedule.asr,
      schedule.maghrib,
      schedule.isha,
      nextDayFajr,
    ]);

    PrayerWindow window(PrayerName prayer, DateTime start, DateTime end) =>
        PrayerWindow(
          prayer: prayer,
          startsAt: start,
          endsAt: end,
          boundary: kWindowBoundaries[prayer]!,
          wasClamped: clamped,
        );

    return DailyPrayerWindows(
      date: DateTime(
        schedule.prayerDate.year,
        schedule.prayerDate.month,
        schedule.prayerDate.day,
      ),
      sunrise: sunrise,
      nextDayFajr: followingFajr,
      windows: [
        // Fajr ends at sunrise, not at Dhuhr. See prayer_window.dart.
        window(PrayerName.fajr, fajr, sunrise),
        window(PrayerName.dhuhr, dhuhr, asr),
        window(PrayerName.asr, asr, maghrib),
        window(PrayerName.maghrib, maghrib, isha),
        window(PrayerName.isha, isha, followingFajr),
      ],
    );
  }

  /// Raise each instant to at least its predecessor, preserving order.
  ///
  /// Clamping upward rather than downward is deliberate: pulling a boundary
  /// *earlier* would end a window before the prayer it belongs to had begun,
  /// whereas raising it merely collapses the offending window to zero length,
  /// which the lock logic already treats as "nothing owed".
  static List<DateTime> _forceAscending(List<DateTime> instants) {
    final result = <DateTime>[instants.first];
    for (var i = 1; i < instants.length; i++) {
      final previous = result[i - 1];
      final current = instants[i];
      result.add(current.isBefore(previous) ? previous : current);
    }
    return result;
  }

  static bool _isAscending(List<DateTime> instants) {
    for (var i = 1; i < instants.length; i++) {
      if (instants[i].isBefore(instants[i - 1])) return false;
    }
    return true;
  }
}

/// Human-readable duration, e.g. "3 hours 37 minutes".
///
/// Lives here rather than in a widget because the same string appears in
/// notifications, which are built off the UI thread and have no BuildContext.
String formatPrayerDuration(Duration duration) {
  if (duration.isNegative || duration == Duration.zero) return '0 minutes';

  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);

  final parts = <String>[
    if (hours > 0) '$hours ${hours == 1 ? 'hour' : 'hours'}',
    if (minutes > 0) '$minutes ${minutes == 1 ? 'minute' : 'minutes'}',
  ];

  // A window shorter than a minute still needs to say something.
  if (parts.isEmpty) return '${duration.inSeconds} seconds';

  return parts.join(' ');
}

/// Compact duration for tight layouts, e.g. "3h 37m".
String formatPrayerDurationShort(Duration duration) {
  if (duration.isNegative || duration == Duration.zero) return '0m';

  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);

  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}
