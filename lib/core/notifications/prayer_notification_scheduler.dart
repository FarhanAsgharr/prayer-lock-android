/// Decides which prayer notifications should exist, and keeps them current.
///
/// Scheduling horizon is seven days. That number balances two failure modes:
/// too short and a user who does not open the app for a few days stops getting
/// reminders; too long and we exceed iOS's hard limit of 64 pending
/// notifications. Seven days x 5 prayers x 2 notifications = 70, which is over
/// that limit, so iOS uses a shorter horizon — see [_horizonDaysFor].
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../features/prayer_times/domain/entities/prayer_day.dart'
    show kVerificationWindow;
import '../../features/prayer_times/domain/entities/prayer_enums.dart';
import '../../features/prayer_times/domain/usecases/prayer_time_calculator.dart';
import '../../features/settings/domain/entities/app_settings.dart';
import 'notification_service.dart';

/// One notification the scheduler intends to exist.
@immutable
class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.instant,
    required this.title,
    required this.body,
    required this.isAdhan,
    required this.prayer,
    required this.date,
  });

  final int id;
  final DateTime instant;
  final String title;
  final String body;
  final bool isAdhan;
  final PrayerName prayer;
  final DateTime date;
}

class PrayerNotificationScheduler {
  PrayerNotificationScheduler(this._service);

  final NotificationService _service;

  /// iOS silently drops anything beyond 64 pending notifications, and drops
  /// the *newest* — so exceeding the cap loses the far future first, which is
  /// invisible until a user notices reminders stopped.
  static const int _iosPendingLimit = 60;

  static int _horizonDaysFor(int notificationsPerDay) {
    if (!Platform.isIOS) return 7;
    // Stay under the cap with headroom for the lock-status notice.
    return (_iosPendingLimit / notificationsPerDay).floor().clamp(1, 7);
  }

  /// Rebuild the full schedule from settings.
  ///
  /// Cancels prayer notifications first so a settings change never leaves a
  /// stale reminder from the previous configuration. The lock-status
  /// notification is outside the prayer id band and survives.
  Future<List<PlannedNotification>> reschedule({
    required AppSettings settings,
    DateTime? from,
  }) async {
    await _service.cancelScheduledPrayerNotifications();

    if (settings.location == null) return const [];

    final planned = plan(settings: settings, from: from);
    final scheduled = <PlannedNotification>[];

    for (final notification in planned) {
      final succeeded = await _service.scheduleAt(
        id: notification.id,
        instant: notification.instant,
        title: notification.title,
        body: notification.body,
        channel: notification.isAdhan
            ? NotificationChannels.adhan
            : NotificationChannels.reminder,
        payload: '${notification.prayer.wireValue}'
            '|${notification.date.toIso8601String()}',
        useAdhanSound: notification.isAdhan && settings.adhanEnabled,
      );

      // Continue past a rejection rather than aborting. The caller compares
      // the returned list against the plan to detect partial scheduling.
      if (succeeded) scheduled.add(notification);
    }

    if (scheduled.length != planned.length) {
      debugPrint(
        'Only ${scheduled.length} of ${planned.length} prayer notifications '
        'could be scheduled.',
      );
    }

    return scheduled;
  }

  /// Compute the notifications that should exist, without scheduling them.
  ///
  /// Pure and separately testable: the scheduling side effect is trivial, but
  /// deciding *what* to schedule is where the bugs live.
  @visibleForTesting
  List<PlannedNotification> plan({
    required AppSettings settings,
    DateTime? from,
  }) {
    final location = settings.location;
    if (location == null) return const [];

    final now = (from ?? DateTime.now()).toUtc();
    final wantsReminder = settings.reminderMinutesBefore > 0;
    final perDay = wantsReminder ? 10 : 5;
    final horizonDays = _horizonDaysFor(perDay);

    final planned = <PlannedNotification>[];

    for (var dayOffset = 0; dayOffset < horizonDays; dayOffset++) {
      final date = _dateAt(now, location.timezone, dayOffset);

      final schedule = prayerTimeCalculator.calculate(
        CalculationRequest(
          latitude: location.latitude,
          longitude: location.longitude,
          utcOffsetHours: _utcOffsetHours(location.timezone, date),
          prayerDate: date,
          method: settings.calculationMethod,
          madhab: settings.madhab,
          highLatitudeRule: settings.highLatitudeRule,
          adjustments: settings.adjustments,
        ),
      );

      for (final entry in schedule.prayers.entries) {
        final prayer = entry.key;
        final instant = entry.value;

        // Past instants are skipped rather than scheduled: the platform would
        // either reject them or fire immediately.
        if (!instant.isAfter(now)) continue;

        planned.add(
          PlannedNotification(
            id: NotificationIds.adhan(date, prayer),
            instant: instant,
            title: "It's time for ${prayer.displayName}",
            body: settings.blockingEnabled
                ? 'Apps are locked. Verify within 30 minutes to unlock.'
                : 'May Allah accept your prayer.',
            isAdhan: true,
            prayer: prayer,
            date: date,
          ),
        );

        // A notice at the moment the on-time window closes and qaza begins, so
        // a user who has not yet verified knows they have slipped to qaza. It
        // is cancelled on verification (see NotificationSync) so it never fires
        // for a prayer already completed on time.
        final qazaStart = instant.add(kVerificationWindow);
        if (qazaStart.isAfter(now)) {
          planned.add(
            PlannedNotification(
              id: NotificationIds.qazaTransition(date, prayer),
              instant: qazaStart,
              title: '${prayer.displayName} on-time window ended',
              body: 'You can still pray ${prayer.displayName} as qaza for the '
                  'next hour.',
              isAdhan: false,
              prayer: prayer,
              date: date,
            ),
          );
        }

        if (!wantsReminder) continue;

        final reminderInstant = instant.subtract(
          Duration(minutes: settings.reminderMinutesBefore),
        );
        if (!reminderInstant.isAfter(now)) continue;

        planned.add(
          PlannedNotification(
            id: NotificationIds.reminder(date, prayer),
            instant: reminderInstant,
            title: '${prayer.displayName} in '
                '${settings.reminderMinutesBefore} minutes',
            body: 'Prepare for prayer.',
            isAdhan: false,
            prayer: prayer,
            date: date,
          ),
        );
      }
    }

    planned.sort((a, b) => a.instant.compareTo(b.instant));
    return planned;
  }

  /// The local calendar date [dayOffset] days from [now] at [timezoneName].
  static DateTime _dateAt(DateTime now, String timezoneName, int dayOffset) {
    final offset = _utcOffsetHours(timezoneName, now);
    final local = now.add(Duration(minutes: (offset * 60).round()));
    final base = DateTime(local.year, local.month, local.day);
    return base.add(Duration(days: dayOffset));
  }

  static double _utcOffsetHours(String timezoneName, DateTime date) {
    try {
      final location = tz.getLocation(timezoneName);
      final noon = tz.TZDateTime(location, date.year, date.month, date.day, 12);
      return noon.timeZoneOffset.inMinutes / 60.0;
    } on tz.LocationNotFoundException {
      // An unknown zone must not prevent scheduling entirely. UTC produces
      // visibly wrong times, which prompts the user to re-pick their location
      // rather than silently receiving nothing at all.
      return 0.0;
    }
  }
}
