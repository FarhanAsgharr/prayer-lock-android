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
  });

  const BlockingPermissions.none()
      : hasUsageStats = false,
        hasOverlay = false,
        batteryOptimizationDisabled = false;

  /// Required to detect which app is in the foreground.
  final bool hasUsageStats;

  /// Required to display the prayer reminder over the blocked app.
  final bool hasOverlay;

  /// Not a permission, but without it the OS may freeze the polling service
  /// and enforcement stops with no visible error.
  final bool batteryOptimizationDisabled;

  factory BlockingPermissions.fromPlatform(Map<Object?, Object?> data) =>
      BlockingPermissions(
        hasUsageStats: data['usageStats'] as bool? ?? false,
        hasOverlay: data['overlay'] as bool? ?? false,
        batteryOptimizationDisabled:
            data['batteryOptimizationDisabled'] as bool? ?? false,
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
        if (!batteryOptimizationDisabled) 'batteryOptimization',
      ];
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
