/// Decides whether a given day is Friday.
///
/// Trivial-looking, and deliberately its own component, because getting it
/// wrong is invisible until a Friday arrives and the feature does not fire.
/// Two traps:
///
///  1. **Which clock?** `DateTime.now().weekday` reads the *device* timezone. A
///     traveller whose phone has switched zones, or anyone near the
///     international date line, can have a device weekday that differs from the
///     weekday where they actually pray. Friday is resolved against the
///     location the user configured, exactly as [localDateProvider] resolves
///     the calendar date, so the whole app agrees about what day it is.
///
///  2. **Which Friday?** Jumu'ah is tied to the *civil* Friday, not to the
///     Islamic day that begins at Maghrib. Thursday evening after sunset is
///     Islamically Friday, but nobody holds Jumu'ah then. Using the civil date
///     is correct here and would be wrong for, say, the start of Ramadan.
library;

import 'package:timezone/timezone.dart' as tz;

/// Friday, as `DateTime.weekday` numbers it. Named rather than inlined so no
/// call site has to remember whether the week starts on Sunday or Monday.
const int kFridayWeekday = DateTime.friday;

abstract final class FridayDetector {
  /// Whether [date] is a Friday.
  ///
  /// [date] is expected to already be a local calendar date — the value
  /// `localDateProvider` produces — so no conversion happens here. Passing a
  /// UTC instant instead would reintroduce exactly the timezone bug this
  /// exists to prevent, which is why [isFridayAt] is the API for instants.
  static bool isFriday(DateTime date) => date.weekday == kFridayWeekday;

  /// Whether [instant] falls on a Friday at [timezoneName].
  ///
  /// Use this when what you hold is a moment in time rather than a calendar
  /// date — an alarm firing, a notification being planned.
  static bool isFridayAt(DateTime instant, String timezoneName) {
    return localDateAt(instant, timezoneName).weekday == kFridayWeekday;
  }

  /// The local calendar date at [timezoneName] for [instant].
  ///
  /// Falls back to the device's own reckoning when the zone is unknown, which
  /// produces a visibly wrong day rather than a crash — and prompts the user to
  /// re-pick their location.
  static DateTime localDateAt(DateTime instant, String timezoneName) {
    try {
      final local =
          tz.TZDateTime.from(instant, tz.getLocation(timezoneName));
      return DateTime(local.year, local.month, local.day);
    } on tz.LocationNotFoundException {
      final local = instant.toLocal();
      return DateTime(local.year, local.month, local.day);
    }
  }

  /// The next Friday on or after [date].
  ///
  /// Returns [date] itself when it is already a Friday, so "when is the next
  /// Jumu'ah" answers "today" on a Friday morning rather than pointing a week
  /// ahead.
  static DateTime nextFridayOnOrAfter(DateTime date) {
    final normalised = DateTime(date.year, date.month, date.day);
    final daysAhead = (kFridayWeekday - normalised.weekday + 7) % 7;
    return DateTime(
      normalised.year,
      normalised.month,
      normalised.day + daysAhead,
    );
  }

  /// The Fridays within [days] days starting at [from], in order.
  ///
  /// Used by the notification scheduler, which plans a week at a time and must
  /// know which of those days get Jumu'ah notices instead of Dhuhr ones.
  static List<DateTime> fridaysWithin({
    required DateTime from,
    required int days,
  }) {
    final result = <DateTime>[];
    for (var offset = 0; offset < days; offset++) {
      // Calendar-day arithmetic, not Duration: adding 24 hours across a DST
      // boundary drifts and would eventually skip or repeat a day.
      final date = DateTime(from.year, from.month, from.day + offset);
      if (isFriday(date)) result.add(date);
    }
    return List.unmodifiable(result);
  }
}
