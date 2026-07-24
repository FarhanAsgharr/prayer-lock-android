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
    DateTime? endsAt,
    bool silence = false,
  }) async {
    if (!isSupported) return false;

    final result = await _invoke<bool>('startLock', {
      'packages': packages,
      'prayerName': prayerName,
      // The native service releases itself at this instant even if the alarm
      // that should have released it never arrives.
      'endsAtEpochMs': endsAt?.millisecondsSinceEpoch,
      'silence': silence,
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

  /// Whether the platform will honour exact alarms.
  ///
  /// Android 12 made this revocable and Android 13 stopped granting it by
  /// default to apps that are not alarm clocks. Without it, a prayer lock can
  /// engage well after the adhan, which the user experiences as the feature
  /// simply not working.
  Future<bool> canScheduleExactAlarms() async {
    if (!Platform.isAndroid) return true;
    return await _invoke<bool>('canScheduleExactAlarms') ?? true;
  }

  Future<void> requestExactAlarmPermission() async {
    if (!Platform.isAndroid) return;
    await _invoke<void>('requestExactAlarmPermission');
  }

  /// Store what the home-screen widget should display, and redraw it.
  ///
  /// Display-only: names the user reads, not the policy that enforces them.
  /// Pushed alongside [syncSchedule] so the widget and the blocking service
  /// can never show different times for the same prayer.
  Future<int> updateWidget(List<WidgetWindow> windows) async {
    if (!Platform.isAndroid) return 0;
    return await _invoke<int>('updateWidget', {
          'windows': [for (final window in windows) window.toPlatform()],
        }) ??
        0;
  }

  /// Redraw the home-screen widget without rewriting its data.
  ///
  /// Cheap enough to call on every tick: the native side returns immediately
  /// when no widget is placed.
  Future<void> refreshWidget() async {
    if (!Platform.isAndroid) return;
    await _invoke<bool>('refreshWidget');
  }

  /// Whether the app is allowed to change Do Not Disturb.
  ///
  /// Notification-policy access cannot be requested with a runtime dialog — the
  /// user has to grant it in Settings — so silencing stays inert until they do.
  /// The settings screen asks this so it can explain itself rather than showing
  /// a switch that quietly does nothing.
  Future<bool> canSilence() async {
    if (!Platform.isAndroid) return false;
    return await _invoke<bool>('canSilence') ?? false;
  }

  /// Open the system screen where notification-policy access is granted.
  Future<void> requestSilencePermission() async {
    if (!Platform.isAndroid) return;
    await _invoke<void>('requestSilencePermission');
  }

  /// Mirror the computed prayer windows and blocking policy to the native side.
  ///
  /// This is what keeps enforcement alive when the Dart isolate is not: after a
  /// reboot, a force-stop, or Android reclaiming the process, native code reads
  /// this mirror and continues locking and releasing on schedule with no
  /// Flutter engine at all.
  ///
  /// Returns the number of windows the platform stored, or 0 where there is no
  /// native scheduler (iOS, tests).
  Future<int> syncSchedule({
    required List<NativePrayerWindow> windows,
    required List<String> packages,
    required bool blockingEnabled,
    required String unlockPolicy,
    required bool blockUntilQaza,
    required bool morningProtection,
  }) async {
    if (!Platform.isAndroid) return 0;

    final result = await _invoke<int>('syncSchedule', {
      'windows': [for (final window in windows) window.toPlatform()],
      'packages': packages,
      'blockingEnabled': blockingEnabled,
      'unlockPolicy': unlockPolicy,
      'blockUntilQaza': blockUntilQaza,
      'morningProtection': morningProtection,
    });
    return result ?? 0;
  }

  /// Erase the native mirror and cancel every armed alarm.
  ///
  /// Called when blocking is switched off or the user's data is deleted —
  /// leaving a mirror behind would let alarms keep firing for a feature the
  /// user has turned off.
  Future<void> clearSchedule() async {
    if (!Platform.isAndroid) return;
    await _invoke<bool>('clearSchedule');
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
