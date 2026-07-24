/// Replaces the Dhuhr window with the configured Jumu'ah window on Fridays.
///
/// This is the single point where Friday changes anything about scheduling.
/// Everything downstream — the lock decision, the notification planner, the
/// native alarm mirror, the dashboard — consumes the transformed windows and
/// never asks what day it is. That is what keeps Friday logic out of the rest
/// of the app.
///
/// ## Why Dhuhr's window is *replaced* rather than shortened
///
/// Jumu'ah discharges the Dhuhr obligation for those who attend it. Under the
/// dynamic-duration model Dhuhr normally runs until Asr — often three hours —
/// but a Jumu'ah congregation lasts a well-defined half hour and the user's
/// mosque decides when. Leaving Dhuhr's long window in place and merely
/// relabelling it would keep apps blocked for hours after the khutbah ended.
/// So the whole window becomes the profile's, and the prayer is settled when
/// that window closes.
///
/// ## The two constraints a configured time must respect
///
/// A user can type any time into settings, and two of the possibilities are
/// not merely odd but wrong:
///
///  * **Before zawal.** Jumu'ah replaces Dhuhr, so it cannot begin before Dhuhr
///    does. A profile set to 11:00 in a place where Dhuhr is at 12:17 would
///    schedule a prayer before its time had entered.
///  * **After Asr.** A window that outlived Dhuhr's own would overlap Asr, and
///    two overlapping windows break the "at most one slot is open" invariant
///    the lock decision relies on.
///
/// Both are clamped rather than rejected: a user whose mosque time is briefly
/// out of range should still get a working app, and the settings screen warns
/// them separately. A profile that cannot be clamped into a usable window at
/// all falls back to ordinary Dhuhr, which is always correct.
library;

import 'package:timezone/timezone.dart' as tz;

import '../../../prayer_times/domain/entities/prayer_enums.dart';
import '../../../prayer_times/domain/entities/prayer_window.dart';
import '../entities/jumuah_profile.dart';
import '../entities/jumuah_settings.dart';
import 'friday_detector.dart';

/// The outcome of applying Jumu'ah to a day, for logging and for the UI.
enum JumuahApplication {
  /// Not a Friday, or Jumu'ah is switched off / unconfigured.
  notApplied,

  /// The profile's times were used exactly as configured.
  applied,

  /// Applied, but the window had to be moved to stay inside Dhuhr's.
  appliedWithClamping,

  /// A Friday with Jumu'ah enabled, but the profile could not produce a usable
  /// window. Ordinary Dhuhr is used.
  invalidProfile,
}

/// The result of a transform: the windows to use, and what happened.
class JumuahScheduleResult {
  const JumuahScheduleResult({
    required this.windows,
    required this.application,
  });

  final DailyPrayerWindows windows;
  final JumuahApplication application;

  bool get isJumuahDay =>
      application == JumuahApplication.applied ||
      application == JumuahApplication.appliedWithClamping;
}

abstract final class JumuahScheduler {
  /// The label shown wherever the Dhuhr slot appears on a Friday.
  static const String jumuahLabel = "Jumu'ah";

  /// Apply the user's Jumu'ah profile to [windows] if it is a Friday.
  ///
  /// [timezone] is the IANA zone of the user's configured location. The
  /// profile's wall-clock times are resolved against it, so "2:00 PM" means
  /// 2pm where the user prays — not 2pm on a device that has crossed a border.
  static JumuahScheduleResult apply({
    required DailyPrayerWindows windows,
    required JumuahSettings settings,
    required String timezone,
  }) {
    if (!settings.isActive || !FridayDetector.isFriday(windows.date)) {
      return JumuahScheduleResult(
        windows: windows,
        application: JumuahApplication.notApplied,
      );
    }

    final mosque = settings.activeMosque!;
    final dhuhr = windows.windowFor(PrayerName.dhuhr);

    final start = _resolve(windows.date, mosque.startsAt, timezone);
    final end = _resolve(windows.date, mosque.endsAt, timezone);

    if (start == null || end == null) {
      return JumuahScheduleResult(
        windows: windows,
        application: JumuahApplication.invalidProfile,
      );
    }

    // Constrain to Dhuhr's own window. Jumu'ah cannot begin before Dhuhr's
    // time has entered, nor run past the point Asr begins.
    final clampedStart = start.isBefore(dhuhr.startsAt) ? dhuhr.startsAt : start;
    final clampedEnd = end.isAfter(dhuhr.endsAt) ? dhuhr.endsAt : end;

    // Clamping can collapse the window entirely — a 2pm profile in a place
    // where Asr begins at 1:30pm, say. Ordinary Dhuhr is the safe answer.
    if (!clampedEnd.isAfter(clampedStart)) {
      return JumuahScheduleResult(
        windows: windows,
        application: JumuahApplication.invalidProfile,
      );
    }

    final wasClamped = clampedStart != start || clampedEnd != end;

    final replaced = PrayerWindow(
      prayer: PrayerName.dhuhr,
      startsAt: clampedStart,
      endsAt: clampedEnd,
      // The boundary is still Asr conceptually — Dhuhr's window is what was
      // replaced — but the *time* is the mosque's. Reported as Asr so the UI's
      // "Until …" line stays truthful about what closes the Dhuhr period.
      boundary: dhuhr.boundary,
      wasClamped: dhuhr.wasClamped || wasClamped,
      labelOverride: jumuahLabel,
      isJumuah: true,
    );

    return JumuahScheduleResult(
      windows: DailyPrayerWindows(
        date: windows.date,
        sunrise: windows.sunrise,
        nextDayFajr: windows.nextDayFajr,
        windows: [
          for (final window in windows.windows)
            window.prayer == PrayerName.dhuhr ? replaced : window,
        ],
      ),
      application: wasClamped
          ? JumuahApplication.appliedWithClamping
          : JumuahApplication.applied,
    );
  }

  /// Convenience wrapper for callers that only want the windows.
  static DailyPrayerWindows applyTo({
    required DailyPrayerWindows windows,
    required JumuahSettings settings,
    required String timezone,
  }) =>
      apply(windows: windows, settings: settings, timezone: timezone).windows;

  /// Resolve a wall-clock time on [date] at [timezone] to a UTC instant.
  ///
  /// Returns null for an unknown zone rather than guessing — scheduling a
  /// prayer against the wrong zone is worse than leaving Dhuhr in place.
  static DateTime? _resolve(
    DateTime date,
    LocalTimeOfDay time,
    String timezone,
  ) {
    try {
      return tz.TZDateTime(
        tz.getLocation(timezone),
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ).toUtc();
    } on tz.LocationNotFoundException {
      return null;
    }
  }
}
