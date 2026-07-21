/// Platform bridge to the native app-restriction layer.
///
/// Android is the only platform with a real implementation today. iOS
/// blocking requires Apple's Family Controls entitlement; until that is
/// granted, every method here degrades to a documented no-op rather than
/// throwing, so the shared UI does not need platform branching everywhere.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/blocking_entities.dart';

/// Raised when the native layer refuses an operation for a reason the UI
/// should explain to the user, such as a missing permission.
class BlockingPlatformException implements Exception {
  const BlockingPlatformException(this.code, this.message);

  final String code;
  final String message;

  /// True when the failure is a missing special permission, which the user
  /// can fix, rather than an internal error, which they cannot.
  bool get isMissingPermission =>
      code == 'MISSING_USAGE_STATS' || code == 'MISSING_OVERLAY';

  @override
  String toString() => 'BlockingPlatformException($code): $message';
}

class BlockingPlatformChannel {
  BlockingPlatformChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'com.prayerlock/blocking';

  final MethodChannel _channel;

  /// Whether native enforcement exists on this platform at all.
  ///
  /// Android always supports it; iOS supports it from iOS 16 via Screen Time,
  /// but only once the user grants Family Controls authorization. The
  /// authorization state is a separate check (`getPermissionStatus`) — this
  /// only reports whether the mechanism exists to be authorized.
  static bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Whether app selection happens through the OS picker rather than an
  /// in-app list.
  ///
  /// iOS forbids enumerating installed apps, so the user selects them through
  /// Apple's `FamilyActivityPicker`, which returns opaque tokens. The blocked-
  /// apps UI branches on this to show a "Choose apps" button instead of a list.
  static bool get usesSystemPicker {
    if (kIsWeb) return false;
    return Platform.isIOS;
  }

  Future<BlockingPermissions> getPermissionStatus() async {
    if (!isSupported) return const BlockingPermissions.none();

    final result = await _invoke<Map<Object?, Object?>>('getPermissionStatus');
    if (result == null) return const BlockingPermissions.none();
    return BlockingPermissions.fromPlatform(result);
  }

  Future<void> requestUsageStatsPermission() =>
      _invokeVoid('requestUsageStatsPermission');

  Future<void> requestOverlayPermission() =>
      _invokeVoid('requestOverlayPermission');

  Future<void> requestDisableBatteryOptimization() =>
      _invokeVoid('requestDisableBatteryOptimization');

  /// Launchable third-party apps, for the blocked-app picker.
  Future<List<InstalledApp>> getInstalledApps() async {
    if (!isSupported) return const [];

    final result = await _invoke<List<Object?>>('getInstalledApps');
    if (result == null) return const [];

    return result
        .whereType<Map<Object?, Object?>>()
        .map(InstalledApp.fromPlatform)
        .toList(growable: false);
  }

  /// Begin restricting [packages] for the named prayer.
  ///
  /// Returns false on platforms without enforcement. Throws
  /// [BlockingPlatformException] when a required permission is missing, so
  /// the caller can route the user into the setup flow rather than reporting
  /// a generic failure.
  Future<bool> startLock({
    required List<String> packages,
    required String prayerName,
  }) async {
    if (!isSupported) return false;

    final result = await _invoke<bool>('startLock', {
      'packages': packages,
      'prayerName': prayerName,
    });
    return result ?? false;
  }

  Future<bool> stopLock() async {
    if (!isSupported) return false;
    return await _invoke<bool>('stopLock') ?? false;
  }

  Future<bool> updateBlockedApps(List<String> packages) async {
    if (!isSupported) return false;
    return await _invoke<bool>('updateBlockedApps', {'packages': packages}) ??
        false;
  }

  /// Present the iOS system app picker.
  ///
  /// Returns the number of apps and categories the user selected. No-op on
  /// Android, where apps are chosen from the in-app list instead.
  Future<int> presentAppPicker() async {
    if (!usesSystemPicker) return 0;
    return await _invoke<int>('presentAppPicker') ?? 0;
  }

  /// Schedule each prayer's blocking window with iOS DeviceActivity.
  ///
  /// This is how iOS enforces blocking while the app is closed — it cannot run
  /// a background timer, so it hands the system a repeating daily window per
  /// prayer. No-op on Android, where the foreground service handles it live.
  ///
  /// Each window is `{name, startHour, startMinute, endHour, endMinute}` in the
  /// device's local wall-clock time, since DeviceActivity schedules by clock
  /// components rather than absolute instants.
  Future<void> scheduleWindows(List<Map<String, dynamic>> windows) async {
    if (!usesSystemPicker) return;
    await _invoke<bool>('scheduleWindows', {'windows': windows});
  }

  /// Cancel all scheduled iOS blocking windows.
  Future<void> cancelSchedule() async {
    if (!usesSystemPicker) return;
    await _invoke<bool>('cancelSchedule');
  }

  // -- internals ---------------------------------------------------------

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw BlockingPlatformException(
        error.code,
        error.message ?? 'Native call "$method" failed.',
      );
    } on MissingPluginException {
      // The native side is absent — expected on iOS and in unit tests.
      // Returning null keeps callers on their documented no-op path.
      return null;
    }
  }

  Future<void> _invokeVoid(String method) async {
    if (!isSupported) return;
    await _invoke<void>(method);
  }
}
