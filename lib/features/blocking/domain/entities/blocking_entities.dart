/// Domain types for app restriction.
library;

import 'package:flutter/foundation.dart';

/// An app installed on the device that the user may choose to restrict.
@immutable
class InstalledApp {
  const InstalledApp({required this.packageIdentifier, required this.appName});

  /// Android package name, or iOS bundle identifier.
  final String packageIdentifier;
  final String appName;

  factory InstalledApp.fromPlatform(Map<Object?, Object?> data) => InstalledApp(
        packageIdentifier: data['packageName']! as String,
        appName: data['appName']! as String,
      );

  @override
  bool operator ==(Object other) =>
      other is InstalledApp && other.packageIdentifier == packageIdentifier;

  @override
  int get hashCode => packageIdentifier.hashCode;
}

/// The special permissions blocking depends on.
///
/// Every one is required for enforcement to work at all. The app checks these
/// rather than assuming, because without them blocking silently does nothing
/// and the user believes they are protected when they are not.
@immutable
class BlockingPermissions {
  const BlockingPermissions({
    required this.hasUsageStats,
    required this.hasOverlay,
    required this.batteryOptimizationDisabled,
    this.canScheduleExactAlarms = true,
  });

  const BlockingPermissions.none()
      : hasUsageStats = false,
        hasOverlay = false,
        batteryOptimizationDisabled = false,
        canScheduleExactAlarms = true;

  /// Required to detect which app is in the foreground.
  final bool hasUsageStats;

  /// Required to display the prayer reminder over the blocked app.
  final bool hasOverlay;

  /// Not a permission, but without it the OS may freeze the polling service
  /// and enforcement stops with no visible error.
  final bool batteryOptimizationDisabled;

  /// Whether exact alarms are permitted.
  ///
  /// Without them the lock still engages, but late — Doze may defer the alarm
  /// by many minutes. Defaults to true so platforms without the concept are not
  /// reported as missing something that does not exist there.
  final bool canScheduleExactAlarms;

  factory BlockingPermissions.fromPlatform(Map<Object?, Object?> data) =>
      BlockingPermissions(
        hasUsageStats: data['usageStats'] as bool? ?? false,
        hasOverlay: data['overlay'] as bool? ?? false,
        batteryOptimizationDisabled:
            data['batteryOptimizationDisabled'] as bool? ?? false,
        canScheduleExactAlarms: data['exactAlarms'] as bool? ?? true,
      );

  /// Whether a lock can actually be enforced right now.
  ///
  /// Battery optimisation is excluded deliberately: it degrades reliability
  /// but does not prevent enforcement outright, so requiring it would block
  /// users on OEMs where the setting cannot be changed.
  bool get canEnforce => hasUsageStats && hasOverlay;

  /// Permissions still missing, in the order the setup flow should request
  /// them — most important first.
  List<String> get missing => [
        if (!hasUsageStats) 'usageStats',
        if (!hasOverlay) 'overlay',
        if (!canScheduleExactAlarms) 'exactAlarms',
        if (!batteryOptimizationDisabled) 'batteryOptimization',
      ];
}

/// One prayer window as the native scheduler needs it.
///
/// A deliberately flat, primitive-only projection: it crosses a method channel
/// and is stored by native code that has no access to the domain model. Keeping
/// it separate from [PrayerWindow] means the domain type can change shape
/// without silently altering what the platform receives.
@immutable
class NativePrayerWindow {
  const NativePrayerWindow({
    required this.prayer,
    required this.startsAt,
    required this.engagesAt,
    required this.endsAt,
    required this.qazaEndsAt,
    required this.fulfilled,
  });

  /// Wire value of the prayer name, e.g. "dhuhr".
  final String prayer;

  final DateTime startsAt;

  /// When the lock engages — the start plus the grace period.
  final DateTime engagesAt;

  final DateTime endsAt;

  /// End of the same-day qaza opportunity.
  final DateTime qazaEndsAt;

  /// Whether the prayer has already been verified or excused.
  final bool fulfilled;

  Map<String, dynamic> toPlatform() => {
        'prayer': prayer,
        'startsAt': startsAt.millisecondsSinceEpoch,
        'engagesAt': engagesAt.millisecondsSinceEpoch,
        'endsAt': endsAt.millisecondsSinceEpoch,
        'qazaEndsAt': qazaEndsAt.millisecondsSinceEpoch,
        'fulfilled': fulfilled,
      };
}

/// Why a lock ended. Recorded for the history screen and for analytics.
enum LockEndReason {
  verified('verified'),
  emergencyUnlock('emergency_unlock'),
  windowExpired('window_expired'),
  userDisabled('user_disabled');

  const LockEndReason(this.wireValue);
  final String wireValue;
}
