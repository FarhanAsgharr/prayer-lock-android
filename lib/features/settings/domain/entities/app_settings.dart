/// User preferences governing calculation, notifications and enforcement.
///
/// Persisted locally as the source of truth: the app must be fully
/// configurable offline, and settings changes must take effect immediately
/// without waiting for a server round trip.
library;

import 'package:flutter/foundation.dart';

import '../../../prayer_times/domain/entities/prayer_enums.dart';

@immutable
class PrayerLocation {
  const PrayerLocation({
    required this.latitude,
    required this.longitude,
    required this.timezone,
    this.label,
    this.isAutoDetected = true,
  });

  final double latitude;
  final double longitude;

  /// IANA timezone identifier, e.g. "Asia/Riyadh".
  final String timezone;

  final String? label;
  final bool isAutoDetected;

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'timezone': timezone,
        'label': label,
        'isAutoDetected': isAutoDetected,
      };

  factory PrayerLocation.fromJson(Map<String, dynamic> json) => PrayerLocation(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        timezone: json['timezone'] as String,
        label: json['label'] as String?,
        isAutoDetected: json['isAutoDetected'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      other is PrayerLocation &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.timezone == timezone;

  @override
  int get hashCode => Object.hash(latitude, longitude, timezone);
}

@immutable
class AppSettings {
  const AppSettings({
    this.location,
    this.calculationMethod = CalculationMethod.muslimWorldLeague,
    this.madhab = Madhab.shafi,
    this.highLatitudeRule = HighLatitudeRule.middleOfTheNight,
    this.adjustments = const {},
    this.reminderMinutesBefore = 15,
    this.adhanEnabled = true,
    this.blockingEnabled = true,
    this.lockGracePeriodMinutes = 5,
    this.morningProtectionEnabled = true,
    this.requireAiVerification = true,
    this.maxEmergencyUnlocksPerDay = 1,
    this.blockedPackages = const <String>{},
    this.onboardingComplete = false,
  });

  final PrayerLocation? location;

  final CalculationMethod calculationMethod;
  final Madhab madhab;
  final HighLatitudeRule highLatitudeRule;

  /// Per-prayer manual corrections in minutes, matching local mosque practice.
  final Map<PrayerName, int> adjustments;

  final int reminderMinutesBefore;
  final bool adhanEnabled;

  final bool blockingEnabled;

  /// Delay between the adhan and the lock engaging, so a user mid-conversation
  /// is not cut off without warning.
  final int lockGracePeriodMinutes;

  final bool morningProtectionEnabled;
  final bool requireAiVerification;
  final int maxEmergencyUnlocksPerDay;

  final Set<String> blockedPackages;

  final bool onboardingComplete;

  /// Whether enough is configured to compute a schedule.
  bool get isReady => location != null;

  AppSettings copyWith({
    PrayerLocation? location,
    CalculationMethod? calculationMethod,
    Madhab? madhab,
    HighLatitudeRule? highLatitudeRule,
    Map<PrayerName, int>? adjustments,
    int? reminderMinutesBefore,
    bool? adhanEnabled,
    bool? blockingEnabled,
    int? lockGracePeriodMinutes,
    bool? morningProtectionEnabled,
    bool? requireAiVerification,
    int? maxEmergencyUnlocksPerDay,
    Set<String>? blockedPackages,
    bool? onboardingComplete,
  }) =>
      AppSettings(
        location: location ?? this.location,
        calculationMethod: calculationMethod ?? this.calculationMethod,
        madhab: madhab ?? this.madhab,
        highLatitudeRule: highLatitudeRule ?? this.highLatitudeRule,
        adjustments: adjustments ?? this.adjustments,
        reminderMinutesBefore:
            reminderMinutesBefore ?? this.reminderMinutesBefore,
        adhanEnabled: adhanEnabled ?? this.adhanEnabled,
        blockingEnabled: blockingEnabled ?? this.blockingEnabled,
        lockGracePeriodMinutes:
            lockGracePeriodMinutes ?? this.lockGracePeriodMinutes,
        morningProtectionEnabled:
            morningProtectionEnabled ?? this.morningProtectionEnabled,
        requireAiVerification:
            requireAiVerification ?? this.requireAiVerification,
        maxEmergencyUnlocksPerDay:
            maxEmergencyUnlocksPerDay ?? this.maxEmergencyUnlocksPerDay,
        blockedPackages: blockedPackages ?? this.blockedPackages,
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      );

  Map<String, dynamic> toJson() => {
        'location': location?.toJson(),
        'calculationMethod': calculationMethod.wireValue,
        'madhab': madhab.wireValue,
        'highLatitudeRule': highLatitudeRule.wireValue,
        'adjustments': adjustments.map((k, v) => MapEntry(k.wireValue, v)),
        'reminderMinutesBefore': reminderMinutesBefore,
        'adhanEnabled': adhanEnabled,
        'blockingEnabled': blockingEnabled,
        'lockGracePeriodMinutes': lockGracePeriodMinutes,
        'morningProtectionEnabled': morningProtectionEnabled,
        'requireAiVerification': requireAiVerification,
        'maxEmergencyUnlocksPerDay': maxEmergencyUnlocksPerDay,
        'blockedPackages': blockedPackages.toList(),
        'onboardingComplete': onboardingComplete,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final rawAdjustments =
        (json['adjustments'] as Map?)?.cast<String, dynamic>() ?? const {};

    return AppSettings(
      location: json['location'] == null
          ? null
          : PrayerLocation.fromJson(
              (json['location'] as Map).cast<String, dynamic>()),
      calculationMethod: CalculationMethod.fromWire(
        json['calculationMethod'] as String? ?? 'muslim_world_league',
      ),
      madhab: Madhab.fromWire(json['madhab'] as String? ?? 'shafi'),
      highLatitudeRule: HighLatitudeRule.fromWire(
        json['highLatitudeRule'] as String? ?? 'middle_of_the_night',
      ),
      adjustments: {
        for (final entry in rawAdjustments.entries)
          PrayerName.fromWire(entry.key): (entry.value as num).toInt(),
      },
      reminderMinutesBefore:
          (json['reminderMinutesBefore'] as num?)?.toInt() ?? 15,
      adhanEnabled: json['adhanEnabled'] as bool? ?? true,
      blockingEnabled: json['blockingEnabled'] as bool? ?? true,
      lockGracePeriodMinutes:
          (json['lockGracePeriodMinutes'] as num?)?.toInt() ?? 5,
      morningProtectionEnabled:
          json['morningProtectionEnabled'] as bool? ?? true,
      requireAiVerification: json['requireAiVerification'] as bool? ?? true,
      maxEmergencyUnlocksPerDay:
          (json['maxEmergencyUnlocksPerDay'] as num?)?.toInt() ?? 1,
      blockedPackages:
          ((json['blockedPackages'] as List?) ?? const []).cast<String>().toSet(),
      onboardingComplete: json['onboardingComplete'] as bool? ?? false,
    );
  }
}
