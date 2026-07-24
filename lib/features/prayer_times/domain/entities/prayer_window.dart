/// Dynamic prayer windows: the interval each prayer actually occupies.
///
/// A prayer's window runs from its own start to the start of whatever ends it —
/// sunrise for Fajr, the next prayer for Dhuhr/Asr/Maghrib, and the *following
/// day's* Fajr for Isha. Those boundaries move every day with the sun, so the
/// duration of each window is a computed property of the schedule and never a
/// configured constant.
///
///   Fajr     04:18 -> Sunrise  05:41   1h 23m
///   Dhuhr    12:17 -> Asr      15:54   3h 37m
///   Asr      15:54 -> Maghrib  19:12   3h 18m
///   Maghrib  19:12 -> Isha     20:41   1h 29m
///   Isha     20:41 -> Fajr (next day)  computed
///
/// Note the gap between sunrise and Dhuhr: the windows are deliberately *not*
/// contiguous. Fajr expires at sunrise rather than running on to Dhuhr, because
/// praying Fajr after sunrise is qada, not adaa. Treating the morning as one
/// unbroken Fajr window would both be wrong and would keep apps blocked for
/// six hours.
library;

import 'package:flutter/foundation.dart';

import 'prayer_enums.dart';

/// What closes a prayer's window, for display ("End: Sunrise").
enum WindowBoundary {
  sunrise('Sunrise'),
  dhuhr('Dhuhr'),
  asr('Asr'),
  maghrib('Maghrib'),
  isha('Isha'),
  nextDayFajr('Next day Fajr');

  const WindowBoundary(this.displayName);

  final String displayName;
}

/// The boundary that closes each prayer's window. Fixed by fiqh, not by
/// configuration — which is why it is a constant map rather than a setting.
const Map<PrayerName, WindowBoundary> kWindowBoundaries = {
  PrayerName.fajr: WindowBoundary.sunrise,
  PrayerName.dhuhr: WindowBoundary.asr,
  PrayerName.asr: WindowBoundary.maghrib,
  PrayerName.maghrib: WindowBoundary.isha,
  PrayerName.isha: WindowBoundary.nextDayFajr,
};

/// One prayer's computed window.
@immutable
class PrayerWindow {
  const PrayerWindow({
    required this.prayer,
    required this.startsAt,
    required this.endsAt,
    required this.boundary,
    this.wasClamped = false,
    this.labelOverride,
    this.isJumuah = false,
  });

  final PrayerName prayer;

  /// A name to show instead of the prayer's own.
  ///
  /// Exists for Jumu'ah, which *is* Dhuhr — the same obligation, the same
  /// history row, the same contribution to the streak — but is called something
  /// else and held at a different time. Carrying the name on the window rather
  /// than branching on the weekday at each call site means the dashboard,
  /// notifications, lock screen and native mirror all say "Jumu'ah" on Fridays
  /// without any of them knowing what a Friday is.
  final String? labelOverride;

  /// Whether this window was replaced by a Jumu'ah profile.
  ///
  /// Distinct from [labelOverride] being set, because the flag is what the
  /// history layer records and the label is only presentation.
  final bool isJumuah;

  /// What to call this window. Never empty.
  String get displayName => labelOverride ?? prayer.displayName;

  /// Inclusive start, as a UTC instant.
  final DateTime startsAt;

  /// Exclusive end, as a UTC instant. Never earlier than [startsAt].
  final DateTime endsAt;

  /// What defines [endsAt], for the "End: Sunrise" line in the UI.
  final WindowBoundary boundary;

  /// Whether the raw astronomical times were out of order here and had to be
  /// clamped to keep the window non-negative.
  ///
  /// Surfaced rather than hidden: at extreme latitudes the high-latitude
  /// fallback rules can push Isha past the following Fajr, and a window silently
  /// running backwards would produce a lock that never releases.
  final bool wasClamped;

  /// How long apps stay blocked for this prayer, in Mode B.
  Duration get duration => endsAt.difference(startsAt);

  /// A window with no time in it. Nothing is ever owed during one.
  bool get isEmpty => !endsAt.isAfter(startsAt);

  bool contains(DateTime instant) =>
      !instant.isBefore(startsAt) && instant.isBefore(endsAt);

  bool hasEnded(DateTime instant) => !instant.isBefore(endsAt);

  bool hasStarted(DateTime instant) => !instant.isBefore(startsAt);

  /// Time left before the window closes, or [Duration.zero] once it has.
  Duration remainingAt(DateTime instant) {
    final remaining = endsAt.difference(instant);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Fraction of the window elapsed at [instant], in [0, 1].
  ///
  /// Used by the progress ring on the lock screen. Zero-length windows report
  /// 1.0 rather than dividing by zero.
  double progressAt(DateTime instant) {
    final total = duration.inMilliseconds;
    if (total <= 0) return 1.0;
    final elapsed = instant.difference(startsAt).inMilliseconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) =>
      other is PrayerWindow &&
      other.prayer == prayer &&
      other.startsAt == startsAt &&
      other.endsAt == endsAt;

  @override
  int get hashCode => Object.hash(prayer, startsAt, endsAt);

  @override
  String toString() =>
      'PrayerWindow(${prayer.wireValue}, $startsAt -> $endsAt, $duration)';
}

/// The five windows for one local calendar day.
@immutable
class DailyPrayerWindows {
  const DailyPrayerWindows({
    required this.date,
    required this.windows,
    required this.sunrise,
    required this.nextDayFajr,
  });

  /// The local calendar date these windows belong to, at midnight, no offset.
  final DateTime date;

  /// One window per prayer, in chronological order of start.
  final List<PrayerWindow> windows;

  /// Retained for display and because it closes the Fajr window.
  final DateTime sunrise;

  /// The instant that closes the Isha window.
  final DateTime nextDayFajr;

  PrayerWindow windowFor(PrayerName prayer) =>
      windows.firstWhere((window) => window.prayer == prayer);

  /// The window containing [instant], or null when no prayer is due — which is
  /// the normal state between sunrise and Dhuhr.
  PrayerWindow? windowAt(DateTime instant) {
    for (final window in windows) {
      if (window.contains(instant)) return window;
    }
    return null;
  }

  /// The first window that has not yet opened at [instant].
  PrayerWindow? nextWindowAfter(DateTime instant) {
    for (final window in windows) {
      if (window.startsAt.isAfter(instant)) return window;
    }
    return null;
  }

  /// Total time the day's windows cover. Purely informational — shown in
  /// settings so the user can see what "block for the full duration" costs
  /// before switching to Mode B.
  Duration get totalDuration => windows.fold(
        Duration.zero,
        (total, window) => total + window.duration,
      );

  /// Whether any window needed clamping, i.e. the raw times were out of order.
  bool get hasClampedWindows => windows.any((window) => window.wasClamped);

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'sunrise': sunrise.toIso8601String(),
        'nextDayFajr': nextDayFajr.toIso8601String(),
        'windows': [
          for (final window in windows)
            {
              'prayer': window.prayer.wireValue,
              'startsAt': window.startsAt.toIso8601String(),
              'endsAt': window.endsAt.toIso8601String(),
              'durationMinutes': window.duration.inMinutes,
              'boundary': window.boundary.name,
            },
        ],
      };
}
