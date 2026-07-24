/// Tests for notifications under combined prayers.
///
/// The failure to prevent: announcing Asr in the middle of a Dhuhr+Asr window.
/// The user is already locked, the countdown already runs to Asr's end, and a
/// second adhan would tell them something has started when nothing changed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/core/notifications/notification_service.dart';
import 'package:prayer_lock/core/notifications/prayer_notification_scheduler.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:prayer_lock/features/sections/domain/entities/prayer_grouping.dart';
import 'package:prayer_lock/features/settings/domain/entities/app_settings.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

import '../support/prayer_fixtures.dart';

void main() {
  tz_data.initializeTimeZones();

  // Fixed instant so the plan is deterministic: 2026-07-20 00:00 UTC, which is
  // 03:00 in Makkah — before Fajr, so a full day is ahead.
  final referenceNow = DateTime.utc(2026, 7, 20, 0, 0);
  final today = DateTime(2026, 7, 20);

  final scheduler = PrayerNotificationScheduler(NotificationService());

  AppSettings settingsFor(PrayerGrouping grouping) =>
      settingsWith().copyWith(prayerGroupingOverride: grouping);

  List<PlannedNotification> planFor(PrayerGrouping grouping) => scheduler
      .plan(settings: settingsFor(grouping), from: referenceNow)
      .where((n) => n.date == today)
      .toList();

  group('combined prayers produce one set of notices', () {
    test('three adhans instead of five', () {
      final adhans = planFor(PrayerGrouping.both).where((n) => n.isAdhan);
      expect(adhans, hasLength(3));
    });

    test('no adhan fires at the second prayer of a pair', () {
      // The regression this suite exists for.
      final day = buildDay();
      final asrStart = day.entryFor(PrayerName.asr).scheduledAt;

      final adhanInstants =
          planFor(PrayerGrouping.both).where((n) => n.isAdhan).map((n) => n.instant);

      expect(adhanInstants, isNot(contains(asrStart)));
    });

    test('the adhan for a pair fires at the first prayer', () {
      final day = buildDay();
      final dhuhrStart = day.entryFor(PrayerName.dhuhr).scheduledAt;

      final adhanInstants =
          planFor(PrayerGrouping.both).where((n) => n.isAdhan).map((n) => n.instant);

      expect(adhanInstants, contains(dhuhrStart));
    });

    test('the window-end notice fires at the end of the joined window', () {
      final day = buildDay();
      final combinedEnd = day.entryFor(PrayerName.asr).windowEndsAt;

      final ended = planFor(PrayerGrouping.both).where(
        (n) => n.kind == PrayerNotificationKind.windowEnded,
      );

      expect(ended, hasLength(3));
      expect(ended.map((n) => n.instant), contains(combinedEnd));
    });

    test('combining reduces the total notification count', () {
      // Which is what buys back iOS's 64-notification budget.
      expect(
        planFor(PrayerGrouping.both).length,
        lessThan(planFor(PrayerGrouping.none).length),
      );
    });

    test('one pair combined leaves the other announced separately', () {
      final adhans =
          planFor(PrayerGrouping.dhuhrAsr).where((n) => n.isAdhan);
      expect(adhans, hasLength(4));
    });
  });

  group('notification content', () {
    test('a combined notice names both prayers', () {
      final adhan = planFor(PrayerGrouping.both).firstWhere(
        (n) => n.isAdhan && n.prayer == PrayerName.dhuhr,
      );
      expect(adhan.title, contains('Dhuhr + Asr'));
    });

    test('a separate notice names one prayer', () {
      final adhan = planFor(PrayerGrouping.none).firstWhere(
        (n) => n.isAdhan && n.prayer == PrayerName.dhuhr,
      );
      expect(adhan.title, contains('Dhuhr'));
      expect(adhan.title, isNot(contains('+')));
    });

    test('reminders count down to the joined window opening', () {
      final day = buildDay();
      final dhuhrStart = day.entryFor(PrayerName.dhuhr).scheduledAt;

      final reminders = planFor(PrayerGrouping.both).where(
        (n) =>
            n.kind == PrayerNotificationKind.reminder &&
            n.prayer == PrayerName.dhuhr,
      );

      expect(reminders, isNotEmpty);
      for (final reminder in reminders) {
        expect(reminder.instant.isBefore(dhuhrStart), isTrue);
      }
    });
  });

  group('identifier safety', () {
    test('ids stay unique when combining', () {
      // A collision would silently replace one notification with another.
      for (final grouping in PrayerGrouping.values) {
        final ids = scheduler
            .plan(settings: settingsFor(grouping), from: referenceNow)
            .map((n) => n.id)
            .toList();

        expect(
          ids.toSet().length,
          ids.length,
          reason: 'duplicate ids under ${grouping.wireValue}',
        );
      }
    });

    test('every planned instant is in the future', () {
      for (final grouping in PrayerGrouping.values) {
        for (final notification in scheduler.plan(
          settings: settingsFor(grouping),
          from: referenceNow,
        )) {
          expect(notification.instant.isAfter(referenceNow), isTrue);
        }
      }
    });

    test('notifications remain chronological', () {
      final planned = scheduler.plan(
        settings: settingsFor(PrayerGrouping.both),
        from: referenceNow,
      );
      final instants = planned.map((n) => n.instant).toList();

      expect(instants, orderedEquals(List.of(instants)..sort()));
    });
  });

  group('the reminder ladder', () {
    test('offers a thirty-minute rung when the lead time allows', () {
      // The spec asks for 30/15/10/5.
      expect(AppSettings.reminderLadderFor(30), [30, 15, 10, 5]);
    });

    test('never schedules a rung beyond the chosen lead time', () {
      expect(AppSettings.reminderLadderFor(10), [10, 5]);
      expect(AppSettings.reminderLadderFor(5), [5]);
    });

    test('zero disables reminders entirely', () {
      expect(AppSettings.reminderLadderFor(0), isEmpty);

      final planned = scheduler.plan(
        settings: settingsWith().copyWith(
          reminderOffsetsMinutes: AppSettings.reminderLadderFor(0),
        ),
        from: referenceNow,
      );
      expect(
        planned.any((n) => n.kind == PrayerNotificationKind.reminder),
        isFalse,
      );
    });
  });
}
