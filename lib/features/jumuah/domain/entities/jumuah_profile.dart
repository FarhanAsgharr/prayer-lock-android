/// Jumu'ah configuration: where the user prays, and when that mosque holds it.
///
/// Jumu'ah is unlike every other prayer this app schedules. The other five are
/// astronomical events — they happen when the sun reaches an angle, and no
/// human decides otherwise. Jumu'ah happens when a particular mosque decides to
/// hold it, which is a wall-clock time set by people and different at every
/// mosque. So it is *configured*, not computed, and the configuration is per
/// location.
///
/// That makes it the one place in the app where a fixed time is correct rather
/// than a bug. It still cannot be arbitrary: Jumu'ah replaces Dhuhr, so it
/// cannot begin before Dhuhr does (before zawal it would not be Dhuhr's time at
/// all) and cannot outlive Dhuhr's window. [JumuahScheduler] enforces both.
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

/// Where the user prays Jumu'ah.
///
/// Two named locations rather than a free list, because the product question is
/// "which of your usual two?" — a person's Jumu'ah is habitual, and asking them
/// to manage a mosque directory every Friday would be worse than useless.
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

/// One mosque's Jumu'ah schedule.
@immutable
class JumuahProfile {
  const JumuahProfile({
    required this.location,
    required this.startsAt,
    required this.endsAt,
  });

  final JumuahLocation location;

  /// When the khutbah begins, in the location's local wall-clock time.
  final LocalTimeOfDay startsAt;

  /// When the verification window closes.
  ///
  /// This is both the verification deadline and the point apps are released,
  /// which is why it is stored as an end time rather than a duration — the
  /// user thinks "2:00 to 2:15", not "2:00 for fifteen minutes".
  final LocalTimeOfDay endsAt;

  String get displayName => location.displayName;

  /// Length of the window. Zero when the times are equal or inverted; the
  /// scheduler treats that as a misconfiguration and falls back to Dhuhr.
  Duration get duration {
    final minutes = endsAt.minutesSinceMidnight - startsAt.minutesSinceMidnight;
    return minutes <= 0 ? Duration.zero : Duration(minutes: minutes);
  }

  /// Whether this profile describes a usable window.
  bool get isValid => endsAt > startsAt;

  /// "2:00 PM – 2:15 PM"
  String get formattedRange => '${startsAt.format()} – ${endsAt.format()}';

  JumuahProfile copyWith({LocalTimeOfDay? startsAt, LocalTimeOfDay? endsAt}) =>
      JumuahProfile(
        location: location,
        startsAt: startsAt ?? this.startsAt,
        endsAt: endsAt ?? this.endsAt,
      );

  /// The shipped defaults, matching the examples in the product brief.
  static const JumuahProfile homeMosqueDefault = JumuahProfile(
    location: JumuahLocation.homeMosque,
    startsAt: LocalTimeOfDay(14, 0),
    endsAt: LocalTimeOfDay(14, 15),
  );

  static const JumuahProfile universityMosqueDefault = JumuahProfile(
    location: JumuahLocation.universityMosque,
    startsAt: LocalTimeOfDay(13, 15),
    endsAt: LocalTimeOfDay(13, 30),
  );

  static JumuahProfile defaultFor(JumuahLocation location) =>
      switch (location) {
        JumuahLocation.homeMosque => homeMosqueDefault,
        JumuahLocation.universityMosque => universityMosqueDefault,
      };

  Map<String, dynamic> toJson() => {
        'location': location.wireValue,
        'startsAt': startsAt.toJson(),
        'endsAt': endsAt.toJson(),
      };

  factory JumuahProfile.fromJson(Map<String, dynamic> json) {
    final location =
        JumuahLocation.fromWire(json['location'] as String? ?? 'home_mosque');
    final fallback = JumuahProfile.defaultFor(location);

    return JumuahProfile(
      location: location,
      startsAt: json['startsAt'] is Map
          ? LocalTimeOfDay.fromJson(
              (json['startsAt'] as Map).cast<String, dynamic>())
          : fallback.startsAt,
      endsAt: json['endsAt'] is Map
          ? LocalTimeOfDay.fromJson(
              (json['endsAt'] as Map).cast<String, dynamic>())
          : fallback.endsAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is JumuahProfile &&
      other.location == location &&
      other.startsAt == startsAt &&
      other.endsAt == endsAt;

  @override
  int get hashCode => Object.hash(location, startsAt, endsAt);
}

/// Everything the Jumu'ah system needs to know about the user's preference.
@immutable
class JumuahSettings {
  const JumuahSettings({
    this.enabled = true,
    this.selectedLocation,
    this.homeMosque = JumuahProfile.homeMosqueDefault,
    this.universityMosque = JumuahProfile.universityMosqueDefault,
  });

  /// Whether Jumu'ah replaces Dhuhr on Fridays at all.
  ///
  /// On by default. Someone who does not attend Jumu'ah — a woman, for whom it
  /// is not obligatory, or anyone travelling or unable to attend — turns it off
  /// and gets ordinary Dhuhr every day.
  final bool enabled;

  /// Where the user prays, or null before they have been asked.
  ///
  /// Null is a meaningful state, not a missing value: it is what triggers the
  /// first-Friday prompt. Defaulting it to Home Mosque would silently answer a
  /// question on the user's behalf and then never ask.
  final JumuahLocation? selectedLocation;

  final JumuahProfile homeMosque;
  final JumuahProfile universityMosque;

  /// Whether the user still needs to be asked where they pray.
  bool get needsLocationChoice => enabled && selectedLocation == null;

  /// The profile in force, or null if no location has been chosen.
  JumuahProfile? get activeProfile {
    final location = selectedLocation;
    if (location == null) return null;
    return profileFor(location);
  }

  JumuahProfile profileFor(JumuahLocation location) => switch (location) {
        JumuahLocation.homeMosque => homeMosque,
        JumuahLocation.universityMosque => universityMosque,
      };

  /// Whether Jumu'ah is fully configured and should take effect on Fridays.
  bool get isActive {
    if (!enabled) return false;
    final profile = activeProfile;
    return profile != null && profile.isValid;
  }

  JumuahSettings withProfile(JumuahProfile profile) => JumuahSettings(
        enabled: enabled,
        selectedLocation: selectedLocation,
        homeMosque: profile.location == JumuahLocation.homeMosque
            ? profile
            : homeMosque,
        universityMosque: profile.location == JumuahLocation.universityMosque
            ? profile
            : universityMosque,
      );

  JumuahSettings copyWith({
    bool? enabled,
    JumuahLocation? selectedLocation,
    JumuahProfile? homeMosque,
    JumuahProfile? universityMosque,
  }) =>
      JumuahSettings(
        enabled: enabled ?? this.enabled,
        selectedLocation: selectedLocation ?? this.selectedLocation,
        homeMosque: homeMosque ?? this.homeMosque,
        universityMosque: universityMosque ?? this.universityMosque,
      );

  /// Forget the chosen location so the user is asked again.
  ///
  /// A distinct operation because [copyWith] cannot express "set this back to
  /// null" — passing null there means "keep the current value".
  JumuahSettings clearSelection() => JumuahSettings(
        enabled: enabled,
        selectedLocation: null,
        homeMosque: homeMosque,
        universityMosque: universityMosque,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'selectedLocation': selectedLocation?.wireValue,
        'homeMosque': homeMosque.toJson(),
        'universityMosque': universityMosque.toJson(),
      };

  factory JumuahSettings.fromJson(Map<String, dynamic> json) {
    JumuahProfile profile(String key, JumuahProfile fallback) =>
        json[key] is Map
            ? JumuahProfile.fromJson((json[key] as Map).cast<String, dynamic>())
            : fallback;

    final selected = json['selectedLocation'] as String?;

    return JumuahSettings(
      enabled: json['enabled'] as bool? ?? true,
      selectedLocation:
          selected == null ? null : JumuahLocation.fromWire(selected),
      homeMosque: profile('homeMosque', JumuahProfile.homeMosqueDefault),
      universityMosque:
          profile('universityMosque', JumuahProfile.universityMosqueDefault),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is JumuahSettings &&
      other.enabled == enabled &&
      other.selectedLocation == selectedLocation &&
      other.homeMosque == homeMosque &&
      other.universityMosque == universityMosque;

  @override
  int get hashCode =>
      Object.hash(enabled, selectedLocation, homeMosque, universityMosque);
}
