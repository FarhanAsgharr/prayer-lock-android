/// Shared Jumu'ah value types.
///
/// [LocalTimeOfDay] is used throughout the feature. [JumuahLocation] is the
/// superseded two-value model, retained only so settings and history rows
/// written before mosque profiles existed can still be read — see
/// `JumuahSettings.fromJson` for the migration.
library;

import 'package:flutter/foundation.dart';

/// A wall-clock time of day, with no date and no zone.
///
/// Deliberately not `TimeOfDay`: that is a Material widget type, and this lives
/// in the domain layer where a Flutter widget dependency would be wrong. It is
/// also not a `DateTime` — a Jumu'ah that starts "at 2pm" starts at 2pm every
/// Friday regardless of date or daylight saving, and storing an instant would
/// silently drift.
@immutable
class LocalTimeOfDay implements Comparable<LocalTimeOfDay> {
  const LocalTimeOfDay(this.hour, this.minute)
      : assert(hour >= 0 && hour < 24, 'hour must be 0-23'),
        assert(minute >= 0 && minute < 60, 'minute must be 0-59');

  final int hour;
  final int minute;

  int get minutesSinceMidnight => hour * 60 + minute;

  /// This time plus [minutes], clamped to the end of the day.
  ///
  /// Clamped rather than wrapped: a Jumu'ah window that rolled past midnight
  /// into the next day would be a configuration mistake, and silently wrapping
  /// it would produce a window running backwards.
  LocalTimeOfDay plusMinutes(int minutes) {
    final total = (minutesSinceMidnight + minutes).clamp(0, 24 * 60 - 1);
    return LocalTimeOfDay(total ~/ 60, total % 60);
  }

  /// "2:00 PM"
  String format({bool use24Hour = false}) {
    if (use24Hour) {
      return '${hour.toString().padLeft(2, '0')}:'
          '${minute.toString().padLeft(2, '0')}';
    }
    final period = hour < 12 ? 'AM' : 'PM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }

  @override
  int compareTo(LocalTimeOfDay other) =>
      minutesSinceMidnight.compareTo(other.minutesSinceMidnight);

  bool operator <(LocalTimeOfDay other) => compareTo(other) < 0;
  bool operator >(LocalTimeOfDay other) => compareTo(other) > 0;

  Map<String, dynamic> toJson() => {'hour': hour, 'minute': minute};

  factory LocalTimeOfDay.fromJson(Map<String, dynamic> json) => LocalTimeOfDay(
        ((json['hour'] as num?)?.toInt() ?? 0).clamp(0, 23),
        ((json['minute'] as num?)?.toInt() ?? 0).clamp(0, 59),
      );

  @override
  bool operator ==(Object other) =>
      other is LocalTimeOfDay && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => format();
}

/// The superseded two-location model.
///
/// Kept because its wire values appear in stored settings and in the
/// `jumuah_location` history column. New code uses [MosqueProfile].
enum JumuahLocation {
  homeMosque('home_mosque', 'Home Mosque'),
  universityMosque('university_mosque', 'University Mosque');

  const JumuahLocation(this.wireValue, this.displayName);

  final String wireValue;
  final String displayName;

  static JumuahLocation fromWire(String value) =>
      JumuahLocation.values.firstWhere(
        (location) => location.wireValue == value,
        orElse: () => JumuahLocation.homeMosque,
      );
}
