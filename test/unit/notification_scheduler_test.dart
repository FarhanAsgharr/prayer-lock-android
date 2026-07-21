/// Tests for notification scheduling decisions.
///
/// The scheduling side effect is trivial; deciding *what* to schedule is where
/// the failures live — duplicate adhans, reminders for prayers already passed,
/// and silently exceeding iOS's pending-notification cap.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/core/notifications/notification_service.dart';
import 'package:prayer_lock/core/notifications/prayer_notification_scheduler.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:prayer_lock/features/settings/domain/entities/app_settings.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

/// Makkah: no DST, so assertions test scheduling logic rather than a
/// timezone edge case.
const makkah = PrayerLocation(
  latitude: 21.4225,
  longitude: 39.8262,
  timezone: 'Asia/Riyadh',
  label: 'Makkah',
);

AppSettings settingsWith({
  int reminderMinutes = 15,
  bool adhanEnabled = true,
  bool blockingEnabled = true,
  PrayerLocation? location = makkah,
}) =>
    AppSettings(
      location: location,
      reminderMinutesBefore: reminderMinutes,
      adhanEnabled: adhanEnabled,
      blockingEnabled: blockingEnabled,
    );

void main() {
  setUpAll(tz_data.initializeTimeZones);

  // Fixed instant so the plan is deterministic: 2026-07-20 00:00 UTC, which
  // is 03:00 in Makkah — before Fajr, so a full day is ahead.
  final referenceNow = DateTime.utc(2026, 7, 20, 0, 0);

  final scheduler = PrayerNotificationScheduler(NotificationService());

  group('planning', () {
    test('schedules an adhan for all five prayers', () {
      final planned =
          scheduler.plan(settings: settingsWith(), from: referenceNow);

      final firstDayAdhans = planned
          .where((n) => n.isAdhan && n.date == DateTime(2026, 7, 20))
          .map((n) => n.prayer)
          .toSet();

      expect(firstDayAdhans, equals(PrayerName.values.toSet()));
    });

    test('schedules a reminder before each adhan', () {
      final planned = scheduler.plan(
        settings: settingsWith(reminderMinutes: 15),
        from: referenceNow,
      );

      final fajrAdhan = planned.firstWhere(
        (n) => n.isAdhan && n.prayer == PrayerName.fajr,
      );
      final fajrReminder = planned.firstWhere(
        (n) => !n.isAdhan && n.prayer == PrayerName.fajr,
      );

      expect(
        fajrAdhan.instant.difference(fajrReminder.instant),
        const Duration(minutes: 15),
      );
    });

    test('omits reminders when the lead time is zero', () {
      final planned = scheduler.plan(
        settings: settingsWith(reminderMinutes: 0),
        from: referenceNow,
      );

      expect(planned.every((n) => n.isAdhan), isTrue);
    });

    test('produces nothing without a location', () {
      final planned = scheduler.plan(
        settings: settingsWith(location: null),
        from: referenceNow,
      );

      expect(planned, isEmpty);
    });

    test('never schedules an instant in the past', () {
      // Scheduling a past instant either fires immediately — startling the
      // user with a reminder for a prayer they already prayed — or is
      // rejected outright by the platform.
      final planned =
          scheduler.plan(settings: settingsWith(), from: referenceNow);

      for (final notification in planned) {
        expect(
          notification.instant.isAfter(referenceNow),
          isTrue,
          reason: '${notification.title} was scheduled in the past',
        );
      }
    });

    test('skips prayers already passed today', () {
      // Mid-afternoon in Makkah: Fajr and Dhuhr have gone.
      final afternoon = DateTime.utc(2026, 7, 20, 13, 0);
      final planned =
          scheduler.plan(settings: settingsWith(), from: afternoon);

      final todaysAdhans = planned
          .where((n) => n.isAdhan && n.date == DateTime(2026, 7, 20))
          .map((n) => n.prayer)
          .toSet();

      expect(todaysAdhans.contains(PrayerName.fajr), isFalse);
      expect(todaysAdhans.contains(PrayerName.dhuhr), isFalse);
      expect(todaysAdhans.contains(PrayerName.maghrib), isTrue);
      expect(todaysAdhans.contains(PrayerName.isha), isTrue);
    });

    test('covers multiple days ahead', () {
      // A user who does not open the app for several days must keep receiving
      // reminders.
      final planned =
          scheduler.plan(settings: settingsWith(), from: referenceNow);
      final distinctDays = planned.map((n) => n.date).toSet();

      expect(distinctDays.length, greaterThan(1));
    });

    test('returns notifications in chronological order', () {
      final planned =
          scheduler.plan(settings: settingsWith(), from: referenceNow);
      final instants = planned.map((n) => n.instant).toList();

      expect(instants, orderedEquals(List.of(instants)..sort()));
    });

    test('body text reflects whether blocking is enabled', () {
      final blocking = scheduler
          .plan(settings: settingsWith(blockingEnabled: true), from: referenceNow)
          .firstWhere((n) => n.isAdhan);
      final notBlocking = scheduler
          .plan(
              settings: settingsWith(blockingEnabled: false), from: referenceNow)
          .firstWhere((n) => n.isAdhan);

      expect(blocking.body, contains('lock'));
      expect(notBlocking.body, isNot(contains('lock')));
    });
  });

  group('notification identifiers', () {
    test('are stable for the same prayer and date', () {
      // Stability is what prevents duplicate adhans: rescheduling must
      // overwrite the previous notification, not stack another one.
      final first = NotificationIds.adhan(DateTime(2026, 7, 20), PrayerName.fajr);
      final second =
          NotificationIds.adhan(DateTime(2026, 7, 20), PrayerName.fajr);

      expect(first, equals(second));
    });

    test('differ between prayers on the same day', () {
      final ids = PrayerName.values
          .map((p) => NotificationIds.adhan(DateTime(2026, 7, 20), p))
          .toSet();

      expect(ids.length, PrayerName.values.length);
    });

    test('differ between the adhan and its reminder', () {
      final date = DateTime(2026, 7, 20);
      expect(
        NotificationIds.adhan(date, PrayerName.fajr),
        isNot(NotificationIds.reminder(date, PrayerName.fajr)),
      );
    });

    test('differ between consecutive days', () {
      expect(
        NotificationIds.adhan(DateTime(2026, 7, 20), PrayerName.fajr),
        isNot(NotificationIds.adhan(DateTime(2026, 7, 21), PrayerName.fajr)),
      );
    });

    test('are unique across a full year of prayers', () {
      // A collision would silently overwrite a real notification, so this is
      // checked exhaustively rather than sampled.
      final ids = <int>{};
      var generated = 0;

      for (var day = 0; day < 365; day++) {
        final date = DateTime(2026, 1, 1).add(Duration(days: day));
        for (final prayer in PrayerName.values) {
          ids.add(NotificationIds.adhan(date, prayer));
          ids.add(NotificationIds.reminder(date, prayer));
          generated += 2;
        }
      }

      expect(ids.length, generated, reason: 'notification id collision');
    });

    test('stay inside the reserved prayer band', () {
      // Outside the band lives the ongoing lock-status notice, which must
      // survive a prayer reschedule.
      for (var day = 0; day < 365; day++) {
        final date = DateTime(2026, 1, 1).add(Duration(days: day));
        for (final prayer in PrayerName.values) {
          expect(
            NotificationIds.isPrayerNotification(
              NotificationIds.adhan(date, prayer),
            ),
            isTrue,
          );
        }
      }
    });

    test('the lock status notification is not in the prayer band', () {
      expect(
        NotificationIds.isPrayerNotification(NotificationIds.lockStatus),
        isFalse,
      );
    });
  });

  group('high latitude scheduling', () {
    test('still produces five prayers where twilight never ends', () {
      // Tromsø in July has no true night. The high-latitude fallback must
      // yield real instants, or a user there receives no reminders at all.
      const tromso = PrayerLocation(
        latitude: 69.6492,
        longitude: 18.9553,
        timezone: 'Europe/Oslo',
        label: 'Tromsø',
      );

      final planned = scheduler.plan(
        settings: settingsWith(location: tromso),
        from: DateTime.utc(2026, 7, 20, 0, 0),
      );

      expect(planned, isNotEmpty);
      final adhans = planned.where((n) => n.isAdhan).map((n) => n.prayer);
      expect(adhans.toSet().length, PrayerName.values.length);
    });
  });
}
