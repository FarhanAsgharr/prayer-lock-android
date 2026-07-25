/// Local notification delivery.
///
/// Prayer reminders are scheduled as absolute instants, not as "in N hours".
/// This matters more than it appears: a prayer time is a fixed moment at a
/// fixed location, so changing the device's timezone does not change when
/// Fajr occurs in Makkah. Anchoring to absolute instants means a traveller's
/// already-scheduled reminders stay correct without rescheduling, and only a
/// *location* change requires recalculation.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../features/prayer_times/domain/entities/prayer_enums.dart';
import '../../core/utils/app_log.dart';

/// Channels are declared once and reused. Android caches channel settings at
/// creation time, so importance and sound cannot be changed later without a
/// new channel id — hence the version suffixes.
abstract final class NotificationChannels {
  /// Pre-prayer reminder. Default importance: it should be noticed, not
  /// alarming.
  static const AndroidNotificationChannel reminder =
      AndroidNotificationChannel(
    'prayer_reminder_v1',
    'Prayer reminders',
    description: 'Reminds you shortly before each prayer begins.',
    importance: Importance.defaultImportance,
  );

  /// The adhan at prayer time. High importance so it surfaces as a heads-up
  /// notification and can sound while the phone is idle.
  static const AndroidNotificationChannel adhan = AndroidNotificationChannel(
    'prayer_adhan_v1',
    'Adhan',
    description: 'Announces the start of each prayer.',
    importance: Importance.high,
    playSound: true,
  );

  /// Silent channel for the ongoing "apps are locked" notice. Low importance
  /// so it never makes a sound — it is a status indicator, not an alert.
  static const AndroidNotificationChannel lockStatus =
      AndroidNotificationChannel(
    'prayer_lock_status_v1',
    'Prayer lock status',
    description: 'Shows while apps are restricted during prayer.',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
  );
}

/// Result of requesting notification permission.
enum NotificationPermissionStatus { granted, denied, notRequired }

class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  bool _initialised = false;

  /// Whether `res/raw/adhan` exists in the Android build.
  ///
  /// Checked at runtime rather than assumed. Passing a raw-resource sound that
  /// is absent makes the platform throw `invalid_sound`, and because scheduling
  /// is a loop, that single throw aborts every remaining notification — the
  /// user silently ends up with almost no reminders at all.
  bool _adhanResourceAvailable = false;

  bool get adhanResourceAvailable => _adhanResourceAvailable;

  /// Route taken when the user taps a notification.
  ///
  /// Set by the app shell; kept as a callback rather than a direct router
  /// dependency so this service stays usable from a background isolate where
  /// no router exists.
  void Function(String? payload)? onNotificationTapped;

  Future<void> initialise() async {
    if (_initialised) return;

    const androidSettings =
        AndroidInitializationSettings('@drawable/ic_notification');

    const darwinSettings = DarwinInitializationSettings(
      // Permissions are requested explicitly later, after the user has been
      // told why. A cold permission prompt on first launch gets denied.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
      ),
      onDidReceiveNotificationResponse: (response) =>
          onNotificationTapped?.call(response.payload),
    );

    await _createChannels();
    _adhanResourceAvailable = await _detectAdhanResource();
    _initialised = true;
  }

  /// Ask the native side whether the adhan raw resource is present.
  ///
  /// Returns false on any failure, including iOS and unit tests where the
  /// channel is unimplemented — falling back to the system notification sound
  /// is always safe, whereas assuming the resource exists is not.
  Future<bool> _detectAdhanResource() async {
    if (!Platform.isAndroid) return false;

    try {
      const channel = MethodChannel('com.prayerlock/blocking');
      return await channel.invokeMethod<bool>('hasAdhanSound') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> _createChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    for (final channel in [
      NotificationChannels.reminder,
      NotificationChannels.adhan,
      NotificationChannels.lockStatus,
    ]) {
      await android.createNotificationChannel(channel);
    }
  }

  /// Request permission to post notifications.
  ///
  /// Android 13+ requires a runtime grant; earlier versions do not.
  Future<NotificationPermissionStatus> requestPermission() async {
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return NotificationPermissionStatus.notRequired;

      final granted = await android.requestNotificationsPermission();
      // Null means the platform did not need to ask — pre-Android 13.
      if (granted == null) return NotificationPermissionStatus.notRequired;
      return granted
          ? NotificationPermissionStatus.granted
          : NotificationPermissionStatus.denied;
    }

    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return (granted ?? false)
          ? NotificationPermissionStatus.granted
          : NotificationPermissionStatus.denied;
    }

    return NotificationPermissionStatus.notRequired;
  }

  /// Whether exact alarms may be scheduled.
  ///
  /// Android 12+ can revoke this independently of notification permission.
  /// Without it the OS silently downgrades to inexact delivery, which can drift
  /// by many minutes — unusable for a prayer time.
  Future<bool> canScheduleExactAlarms() async {
    if (!Platform.isAndroid) return true;

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.canScheduleExactNotifications() ?? true;
  }

  Future<void> requestExactAlarmPermission() async {
    if (!Platform.isAndroid) return;

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestExactAlarmsPermission();
  }

  /// Schedule a single notification at an absolute instant.
  ///
  /// Silently skips instants already in the past: scheduling one would either
  /// fire immediately (startling the user with a reminder for a prayer they
  /// already prayed) or be rejected by the platform.
  ///
  /// Returns false if the platform refused this notification. Failures are
  /// reported rather than thrown so that one bad notification cannot abort a
  /// whole week's schedule.
  Future<bool> scheduleAt({
    required int id,
    required DateTime instant,
    required String title,
    required String body,
    required AndroidNotificationChannel channel,
    String? payload,
    bool useAdhanSound = false,
  }) async {
    final scheduledFor = tz.TZDateTime.from(instant, tz.local);
    if (!scheduledFor.isAfter(tz.TZDateTime.now(tz.local))) return false;

    // Only reference the custom sound when it genuinely exists, otherwise the
    // platform rejects the whole notification.
    final useCustomSound =
        useAdhanSound && channel.playSound && _adhanResourceAvailable;

    try {
      await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduledFor,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          priority: channel.importance == Importance.high
              ? Priority.high
              : Priority.defaultPriority,
          // Full-screen intent is deliberately not used. It would let the
          // reminder take over the device, which Play treats as a restricted
          // capability and which users experience as hostile.
          category: AndroidNotificationCategory.reminder,
          playSound: channel.playSound,
          sound: useCustomSound
              ? const RawResourceAndroidNotificationSound('adhan')
              : null,
          audioAttributesUsage: useAdhanSound
              // Alarm usage so the adhan sounds even in Do Not Disturb, which
              // is the behaviour users expect from a call to prayer.
              ? AudioAttributesUsage.alarm
              : AudioAttributesUsage.notification,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: channel.playSound,
          sound: useCustomSound ? 'adhan.caf' : null,
          interruptionLevel: channel.importance == Importance.high
              ? InterruptionLevel.timeSensitive
              : InterruptionLevel.active,
        ),
      ),
      // Exact delivery, and permitted to fire in Doze. A prayer reminder that
      // arrives twenty minutes late has failed at its only job.
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      // Absolute time, not wall-clock. A prayer occurs at a fixed instant at a
      // fixed location, so a device timezone change must not shift an already
      // scheduled adhan — which wallClockTime would do.
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
      );
      return true;
    } on PlatformException catch (error) {
      // Report and continue. One rejected notification — an unavailable sound,
      // a revoked exact-alarm permission — must never cost the user their
      // entire week of reminders.
      logDiagnostic('Could not schedule notification $id: ${error.code}');
      return false;
    } on ArgumentError catch (error) {
      logDiagnostic('Invalid notification $id: $error');
      return false;
    }
  }

  Future<void> cancel(int id) => _plugin.cancel(id);

  Future<void> cancelAll() => _plugin.cancelAll();

  /// Cancel only the notifications this app scheduled for prayers.
  ///
  /// Used before a full reschedule. Cancelling everything would also remove
  /// the ongoing lock-status notification, which must survive.
  Future<void> cancelScheduledPrayerNotifications() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      if (NotificationIds.isPrayerNotification(request.id)) {
        await _plugin.cancel(request.id);
      }
    }
  }

  /// Cancel the "qaza now available" notice for a prayer once it has been
  /// verified, so it never fires for a prayer already completed on time.
  Future<void> cancelQazaNotice(DateTime date, PrayerName prayer) =>
      _plugin.cancel(NotificationIds.qazaTransition(date, prayer));

  Future<List<PendingNotificationRequest>> pending() =>
      _plugin.pendingNotificationRequests();

  /// The notification that launched the app, if any.
  Future<NotificationAppLaunchDetails?> launchDetails() =>
      _plugin.getNotificationAppLaunchDetails();
}

/// Deterministic notification identifiers.
///
/// Derived from the date and prayer rather than allocated sequentially, so
/// rescheduling the same prayer overwrites its previous notification instead
/// of stacking a duplicate. Duplicate adhans are one of the most complained-
/// about failures in prayer apps.
abstract final class NotificationIds {
  /// Reserved band for prayer notifications. Anything outside it (such as the
  /// lock-status notice) is left alone by a prayer reschedule.
  static const int _prayerBandStart = 100000;
  static const int _prayerBandEnd = 999999;

  static const int lockStatus = 4711;

  static bool isPrayerNotification(int id) =>
      id >= _prayerBandStart && id <= _prayerBandEnd;

  /// Stable id for a prayer's adhan on a given date.
  static int adhan(DateTime date, PrayerName prayer) =>
      _base(date, prayer) + 0;

  /// Stable id for a prayer's pre-reminder on a given date.
  ///
  /// [rung] distinguishes the steps of the reminder ladder (15, 10 and 5
  /// minutes before), which must not collide or the later one silently replaces
  /// the earlier.
  static int reminder(DateTime date, PrayerName prayer, {int rung = 0}) =>
      _base(date, prayer) + 1 + rung.clamp(0, maxReminderRungs - 1);

  /// How many distinct pre-prayer reminders a single prayer may have.
  static const int maxReminderRungs = 4;

  /// Stable id for the "on-time window ended, qaza now available" notice.
  static int qazaTransition(DateTime date, PrayerName prayer) =>
      _base(date, prayer) + 1 + maxReminderRungs;

  /// Stable id for the "this prayer's window is about to close" warning.
  static int windowEnding(DateTime date, PrayerName prayer) =>
      _base(date, prayer) + 2 + maxReminderRungs;

  /// Stable id for the "apps unlocked, the window has ended" notice.
  static int windowEnded(DateTime date, PrayerName prayer) =>
      _base(date, prayer) + 3 + maxReminderRungs;

  /// Slots reserved per prayer per day. Must exceed the highest offset used
  /// above, or two notification kinds share an id and one is lost.
  static const int _slotsPerPrayer = 4 + maxReminderRungs;

  static int _base(DateTime date, PrayerName prayer) {
    // day-of-year (1-366) and prayer index pack into a small, collision-free
    // space. Eight slots per prayer across five prayers is 40 per day;
    // 366 * 40 = 14,640 stays well inside the reserved band.
    final dayOfYear = date.difference(DateTime(date.year, 1, 1)).inDays + 1;
    final prayerIndex = PrayerName.values.indexOf(prayer);
    return _prayerBandStart +
        (dayOfYear * _slotsPerPrayer * PrayerName.values.length) +
        (prayerIndex * _slotsPerPrayer);
  }
}

/// Debug helper: lists what is currently scheduled.
@visibleForTesting
String describePending(List<PendingNotificationRequest> requests) {
  final lines = requests.map(
    (request) => '#${request.id} ${request.title} — ${request.body}',
  );
  return lines.join('\n');
}
