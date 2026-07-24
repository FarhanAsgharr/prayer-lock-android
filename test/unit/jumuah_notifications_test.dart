/// Tests that Jumu'ah notifications fire on Fridays and only on Fridays.
///
/// The spec is explicit: these must not appear on Monday through Thursday,
/// Saturday or Sunday. That is asserted directly by planning a full week and
/// checking every non-Friday day is untouched.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/core/notifications/notification_service.dart';
import 'package:prayer_lock/core/notifications/prayer_notification_scheduler.dart';
import 'package:prayer_lock/features/jumuah/domain/entities/jumuah_profile.dart';
import 'package:prayer_lock/features/jumuah/domain/usecases/friday_detector.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:prayer_lock/features/settings/domain/entities/app_settings.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

import '../support/prayer_fixtures.dart';

void main() {
  tz_data.initializeTimeZones();

  // Monday 2026-07-20, 00:00 UTC — 03:00 in Makkah, so a full week lies ahead
  // and exactly one Friday (2026-07-24) falls inside the horizon.
  final referenceNow = DateTime.utc(2026, 7, 20, 0, 0);
  final friday = DateTime(2026, 7, 24);

  final scheduler = PrayerNotificationScheduler(NotificationService());

  AppSettings settingsWithJumuah({
    bool enabled = true,
    JumuahLocation? location = JumuahLocation.homeMosque,
    JumuahProfile? home,
  }) =>
      settingsWith().copyWith(
        jumuah: JumuahSettings(
          enabled: enabled,
          selectedLocation: location,
          homeMosque: home ?? JumuahProfile.homeMosqueDefault,
        ),
      );

  List<PlannedNotification> planWith(AppSettings settings) =>
      scheduler.plan(settings: settings, from: referenceNow);

  /// Notifications whose wording is Jumu'ah-specific.
  Iterable<PlannedNotification> jumuahNotices(
    List<PlannedNotification> planned,
  ) =>
      planned.where((n) => n.title.contains("Jumu'ah"));

  group('Friday only', () {
    test('Jumu\'ah notices exist, and every one falls on a Friday', () {
      final planned = planWith(settingsWithJumuah());
      final notices = jumuahNotices(planned).toList();

      expect(notices, isNotEmpty);
      for (final notice in notices) {
        expect(
          FridayDetector.isFriday(notice.date),
          isTrue,
          reason: '"${notice.title}" was planned for ${notice.date}',
        );
      }
    });

    test('no Jumu\'ah notice lands on any other weekday', () {
      final planned = planWith(settingsWithJumuah());

      for (final notice in planned) {
        if (FridayDetector.isFriday(notice.date)) continue;
        expect(
          notice.title.contains("Jumu'ah"),
          isFalse,
          reason: '${notice.date} carried a Jumu\'ah notice',
        );
      }
    });

    test('non-Friday days still get ordinary Dhuhr notices', () {
      // Suppressing Dhuhr on other days would be a regression, not a feature.
      final planned = planWith(settingsWithJumuah());

      final dhuhrOnOtherDays = planned.where(
        (n) =>
            n.prayer == PrayerName.dhuhr &&
            !FridayDetector.isFriday(n.date) &&
            n.isAdhan,
      );

      expect(dhuhrOnOtherDays, isNotEmpty);
      for (final notice in dhuhrOnOtherDays) {
        expect(notice.title, contains('Dhuhr'));
      }
    });

    test('Friday itself no longer announces Dhuhr', () {
      final planned = planWith(settingsWithJumuah());

      final fridayDhuhrAdhan = planned.where(
        (n) => n.date == friday && n.prayer == PrayerName.dhuhr && n.isAdhan,
      );

      expect(fridayDhuhrAdhan, hasLength(1));
      expect(fridayDhuhrAdhan.single.title, contains("Jumu'ah"));
      expect(fridayDhuhrAdhan.single.title, isNot(contains('Dhuhr')));
    });
  });

  group('the full Friday notification set', () {
    test('covers reminders, start, ending and end', () {
      final planned = planWith(settingsWithJumuah())
          .where((n) => n.date == friday && n.prayer == PrayerName.dhuhr)
          .toList();

      final kinds = planned.map((n) => n.kind).toSet();
      expect(kinds, contains(PrayerNotificationKind.reminder));
      expect(kinds, contains(PrayerNotificationKind.adhan));
      expect(kinds, contains(PrayerNotificationKind.windowEnded));
    });

    test('the start notice says apps are locked, with the closing time', () {
      final started = planWith(settingsWithJumuah()).firstWhere(
        (n) =>
            n.date == friday &&
            n.prayer == PrayerName.dhuhr &&
            n.kind == PrayerNotificationKind.adhan,
      );

      expect(started.title, "Jumu'ah has started");
      expect(started.body, contains('locked'));
      expect(started.body, contains('2:15 PM'));
    });

    test('reminders name the mosque the user chose', () {
      final reminders = planWith(
        settingsWithJumuah(location: JumuahLocation.universityMosque),
      ).where(
        (n) =>
            n.date == friday &&
            n.prayer == PrayerName.dhuhr &&
            n.kind == PrayerNotificationKind.reminder,
      );

      expect(reminders, isNotEmpty);
      expect(
        reminders.any((n) => n.body.contains('University Mosque')),
        isTrue,
      );
    });

    test('the closing notice does not offer qaza', () {
      // Jumu'ah has no make-up form; telling the user otherwise would be wrong.
      final ended = planWith(settingsWithJumuah()).firstWhere(
        (n) =>
            n.date == friday &&
            n.prayer == PrayerName.dhuhr &&
            n.kind == PrayerNotificationKind.windowEnded,
      );

      expect(ended.title, "Jumu'ah has ended");
      expect(ended.body.toLowerCase(), isNot(contains('qaza')));
      expect(ended.body, contains('Dhuhr'));
    });

    test('a short window still gets a closing warning', () {
      // The default fifteen-minute window is shorter than the ordinary
      // fifteen-minute warning lead, so a naive implementation would drop the
      // warning entirely.
      final ending = planWith(settingsWithJumuah()).where(
        (n) =>
            n.date == friday &&
            n.prayer == PrayerName.dhuhr &&
            n.kind == PrayerNotificationKind.windowEnding,
      );

      expect(ending, hasLength(1));
      expect(ending.single.title, "Jumu'ah time is ending");
    });
  });

  group('disabled or unconfigured', () {
    test('no Jumu\'ah notices when Smart Jumu\'ah is off', () {
      final planned = planWith(settingsWithJumuah(enabled: false));
      expect(jumuahNotices(planned), isEmpty);
    });

    test('no Jumu\'ah notices before a mosque is chosen', () {
      final planned = planWith(settingsWithJumuah(location: null));
      expect(jumuahNotices(planned), isEmpty);
    });

    test('Friday still gets ordinary Dhuhr notices when disabled', () {
      final planned = planWith(settingsWithJumuah(enabled: false)).where(
        (n) => n.date == friday && n.prayer == PrayerName.dhuhr && n.isAdhan,
      );

      expect(planned, hasLength(1));
      expect(planned.single.title, contains('Dhuhr'));
    });
  });

  group('scheduling safety', () {
    test('ids stay unique across a week containing a Friday', () {
      final ids = planWith(settingsWithJumuah()).map((n) => n.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every planned instant is in the future and ordered', () {
      final planned = planWith(settingsWithJumuah());

      for (final notice in planned) {
        expect(notice.instant.isAfter(referenceNow), isTrue);
      }
      final instants = planned.map((n) => n.instant).toList();
      expect(instants, orderedEquals(List.of(instants)..sort()));
    });

    test('Friday reminders precede the khutbah', () {
      final planned = planWith(settingsWithJumuah());

      final start = planned
          .firstWhere(
            (n) =>
                n.date == friday &&
                n.prayer == PrayerName.dhuhr &&
                n.kind == PrayerNotificationKind.adhan,
          )
          .instant;

      final reminders = planned.where(
        (n) =>
            n.date == friday &&
            n.prayer == PrayerName.dhuhr &&
            n.kind == PrayerNotificationKind.reminder,
      );

      for (final reminder in reminders) {
        expect(reminder.instant.isBefore(start), isTrue);
      }
    });
  });
}
