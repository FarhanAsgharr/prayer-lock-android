/// Decides which prayer notifications should exist, and keeps them current.
///
/// Under dynamic durations each prayer produces up to six notices — a ladder of
/// pre-prayer reminders, the adhan, a warning before the window closes, and the
/// close itself. That is a lot of scheduled items, and iOS caps pending
/// notifications at 64 and silently drops the *newest* past the cap. So the
/// horizon is derived from how many notices a day actually produces rather than
/// fixed, and the per-prayer notices are added in priority order so that if
/// anything is lost it is the least important.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../features/jumuah/domain/usecases/jumuah_notification_manager.dart';
import '../../features/jumuah/domain/usecases/jumuah_scheduler.dart';
import '../../features/prayer_times/domain/entities/prayer_day.dart';
import '../../features/prayer_times/domain/entities/prayer_enums.dart';
import '../../features/prayer_times/domain/entities/prayer_slot.dart';
import '../../features/prayer_times/domain/entities/prayer_window.dart';
import '../../features/prayer_times/domain/usecases/dynamic_duration_calculator.dart';
import '../../features/prayer_times/domain/usecases/prayer_time_calculator.dart';
import '../../features/settings/domain/entities/app_settings.dart';
import 'notification_service.dart';

/// What a planned notification is for. Drives channel choice and lets tests
/// assert on intent rather than on wording.
enum PrayerNotificationKind {
  /// "Dhuhr in 15 minutes."
  reminder,

  /// The adhan itself — the prayer has begun and apps are about to lock.
  adhan,

  /// The window is nearly over.
  windowEnding,

  /// The window has closed; apps are released and qaza begins.
  windowEnded,
}

/// One notification the scheduler intends to exist.
@immutable
class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.instant,
    required this.title,
    required this.body,
    required this.kind,
    required this.prayer,
    required this.date,
  });

  final int id;
  final DateTime instant;
  final String title;
  final String body;
  final PrayerNotificationKind kind;
  final PrayerName prayer;
  final DateTime date;

  bool get isAdhan => kind == PrayerNotificationKind.adhan;
}

class PrayerNotificationScheduler {
  PrayerNotificationScheduler(this._service);

  final NotificationService _service;

  /// Friday wording. Owns only the copy — never when anything fires.
  static const JumuahNotificationManager _jumuahCopy =
      JumuahNotificationManager();

  /// iOS silently drops anything beyond 64 pending notifications, and drops
  /// the *newest* — so exceeding the cap loses the far future first, which is
  /// invisible until a user notices reminders stopped.
  static const int _iosPendingLimit = 60;

  /// Warning issued this long before a window closes.
  ///
  /// Fifteen minutes on a three-hour Dhuhr window and on an eighty-minute Fajr
  /// window are both useful; a percentage would make the Fajr warning almost
  /// worthless and the Dhuhr one absurdly early.
  static const Duration windowEndingLead = Duration(minutes: 15);

  static int _horizonDaysFor(int notificationsPerDay) {
    if (!Platform.isIOS) return 7;
    if (notificationsPerDay <= 0) return 7;
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
    final offsets = settings.effectiveReminderOffsets
        .take(NotificationIds.maxReminderRungs)
        .toList();

    // adhan + ladder + (ending, ended when enabled), times the number of slots.
    // Counting slots rather than prayers matters on iOS: combining halves two
    // of the day's units, which buys back enough of the 64-notification budget
    // to extend the horizon by days.
    final perSlot = 1 + offsets.length + (settings.notifyOnWindowEnd ? 2 : 0);
    final horizonDays =
        _horizonDaysFor(perSlot * settings.prayerGrouping.slotCount);

    final planned = <PlannedNotification>[];

    // One extra day is computed so the final day's Isha window has a closing
    // Fajr; notifications are not emitted for it.
    final schedules = <DateTime, PrayerSchedule>{};
    for (var dayOffset = 0; dayOffset <= horizonDays; dayOffset++) {
      final date = _dateAt(now, location.timezone, dayOffset);
      schedules[date] = _scheduleFor(settings, location, date);
    }

    for (var dayOffset = 0; dayOffset < horizonDays; dayOffset++) {
      final date = _dateAt(now, location.timezone, dayOffset);
      final nextDate = _dateAt(now, location.timezone, dayOffset + 1);

      final schedule = schedules[date]!;
      final next = schedules[nextDate]!;

      final windows = JumuahScheduler.applyTo(
        windows: DynamicDurationCalculator.fromSchedule(
          schedule: schedule,
          nextDayFajr: next.fajr,
        ),
        settings: settings.jumuah,
        timezone: location.timezone,
      );

      // Notices are emitted per *slot*, so a combined Dhuhr+Asr produces one
      // adhan, one ladder and one window-end notice rather than two of each.
      // Two would announce Asr in the middle of a window that is already
      // locked and already counting down to Asr's end — telling the user
      // something has started when nothing changed.
      for (final slot in _slotsFor(windows, settings)) {
        planned.addAll(
          _forSlot(
            slot: slot,
            date: date,
            now: now,
            settings: settings,
            offsets: offsets,
          ),
        );
      }
    }

    planned.sort((a, b) => a.instant.compareTo(b.instant));
    return planned;
  }

  /// The day's windows projected into the slots the user acts on.
  ///
  /// Built here from raw windows rather than from a [PrayerDay], because the
  /// scheduler plans days that have no tracked outcomes yet — a week ahead,
  /// where no prayer has been verified or missed.
  static List<PrayerSlot> _slotsFor(
    DailyPrayerWindows windows,
    AppSettings settings,
  ) {
    final day = PrayerDay.fromWindows(windows);
    return day.slots(settings.prayerGrouping);
  }

  /// Every notification one slot produces.
  List<PlannedNotification> _forSlot({
    required PrayerSlot slot,
    required DateTime date,
    required DateTime now,
    required AppSettings settings,
    required List<int> offsets,
  }) {
    final window = slot.window;
    // Notification ids key off the first prayer in the slot, which is unique
    // per slot and stable whatever the grouping.
    final prayer = slot.first.prayer;
    final name = slot.displayName;
    final duration = formatPrayerDuration(window.duration);
    final result = <PlannedNotification>[];

    // Past instants are skipped rather than scheduled: the platform would
    // either reject them or fire immediately.
    void add({
      required int id,
      required DateTime instant,
      required String title,
      required String body,
      required PrayerNotificationKind kind,
    }) {
      if (!instant.isAfter(now)) return;
      result.add(
        PlannedNotification(
          id: id,
          instant: instant,
          title: title,
          body: body,
          kind: kind,
          prayer: prayer,
          date: date,
        ),
      );
    }

    // On a Friday the Dhuhr window has already been replaced by the mosque's
    // Jumu'ah window, so nothing here checks the weekday — only whether the
    // window it was handed is a congregation, which decides the wording.
    final jumuah = slot.isJumuah ? settings.jumuah.activeProfile : null;

    // The adhan. Added first so that if the platform starts rejecting
    // scheduling mid-loop, the most important notice for each prayer is
    // already in.
    add(
      id: NotificationIds.adhan(date, prayer),
      instant: window.startsAt,
      title: jumuah != null
          ? _jumuahCopy.startedTitle()
          : "It's time for $name",
      body: jumuah != null
          ? _jumuahCopy.startedBody(
              profile: jumuah,
              blockingEnabled: settings.blockingEnabled,
            )
          : settings.blockingEnabled
              ? _adhanBody(settings, duration)
              : 'May Allah accept your prayer.',
      kind: PrayerNotificationKind.adhan,
    );

    for (var rung = 0; rung < offsets.length; rung++) {
      final minutes = offsets[rung];
      add(
        id: NotificationIds.reminder(date, prayer, rung: rung),
        instant: window.startsAt.subtract(Duration(minutes: minutes)),
        title: jumuah != null
            ? _jumuahCopy.reminderTitle(minutes)
            : '$name in $minutes ${minutes == 1 ? 'minute' : 'minutes'}',
        body: jumuah != null
            ? _jumuahCopy.reminderBody(
                profile: jumuah,
                minutes: minutes,
                blockingEnabled: settings.blockingEnabled,
              )
            : settings.blockingEnabled && minutes <= 5
                // The last rung is the one that should change behaviour, so it
                // says what is about to happen rather than repeating the
                // countdown.
                ? 'Selected apps lock when $name begins.'
                : 'Prepare for prayer.',
        kind: PrayerNotificationKind.reminder,
      );
    }

    if (!settings.notifyOnWindowEnd) return result;

    // Only worth warning when there is meaningfully more window left than the
    // lead time — otherwise the warning lands on top of the adhan.
    // A Jumu'ah window is short by design — often fifteen minutes — so the
    // usual "warn well before it closes" lead is scaled down rather than
    // skipped, which would leave a congregation with no closing warning at all.
    final endingLead = jumuah != null
        ? Duration(minutes: (window.duration.inMinutes / 3).clamp(1, 15).round())
        : windowEndingLead;

    if (window.duration > endingLead * 2) {
      add(
        id: NotificationIds.windowEnding(date, prayer),
        instant: window.endsAt.subtract(endingLead),
        title: jumuah != null
            ? _jumuahCopy.endingTitle()
            : '$name window ends soon',
        body: jumuah != null
            ? _jumuahCopy.endingBody(
                profile: jumuah,
                leadMinutes: endingLead.inMinutes,
              )
            : '${endingLead.inMinutes} minutes left to pray $name '
                'before ${window.boundary.displayName}.',
        kind: PrayerNotificationKind.windowEnding,
      );
    }

    add(
      id: NotificationIds.windowEnded(date, prayer),
      instant: window.endsAt,
      title: jumuah != null
          ? _jumuahCopy.endedTitle()
          : '$name window has ended',
      body: jumuah != null
          ? _jumuahCopy.endedBody(blockingEnabled: settings.blockingEnabled)
          : settings.blockingEnabled
              ? 'Apps are unlocked. You can still pray $name as qaza today.'
              : 'You can still pray $name as qaza today.',
      kind: PrayerNotificationKind.windowEnded,
    );

    return result;
  }

  /// What the adhan notification promises, which depends on the unlock policy —
  /// telling a Mode B user they can verify to unlock would be a lie.
  static String _adhanBody(AppSettings settings, String duration) =>
      switch (settings.unlockPolicy) {
        UnlockPolicy.fullDuration =>
          'Apps are locked for the next $duration.',
        UnlockPolicy.onVerification =>
          'Apps are locked. Verify your prayer to unlock.',
        UnlockPolicy.earliestOf =>
          'Apps are locked. Verify your prayer, or wait $duration.',
      };

  static PrayerSchedule _scheduleFor(
    AppSettings settings,
    PrayerLocation location,
    DateTime date,
  ) =>
      prayerTimeCalculator.calculate(
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

  /// The local calendar date [dayOffset] days from [now] at [timezoneName].
  static DateTime _dateAt(DateTime now, String timezoneName, int dayOffset) {
    final offset = _utcOffsetHours(timezoneName, now);
    final local = now.add(Duration(minutes: (offset * 60).round()));
    // Calendar-day arithmetic rather than adding a Duration, so a DST
    // transition inside the horizon cannot skip or repeat a date.
    return DateTime(local.year, local.month, local.day + dayOffset);
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
