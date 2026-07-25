/// Wiring that keeps scheduled notifications in step with settings.
///
/// The scheduler is driven by a listener on the settings provider rather than
/// by explicit calls from each settings screen. Requiring every future
/// settings control to remember to reschedule is exactly how a "my reminders
/// stopped working" bug gets shipped.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/domain/entities/app_settings.dart';
import '../../features/settings/presentation/providers/settings_provider.dart';
import 'adhan_player.dart';
import 'notification_service.dart';
import 'prayer_notification_scheduler.dart';
import '../../core/utils/app_log.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService();
  ref.onDispose(service.cancelAll);
  return service;
});

final prayerNotificationSchedulerProvider =
    Provider<PrayerNotificationScheduler>((ref) {
  return PrayerNotificationScheduler(ref.watch(notificationServiceProvider));
});

final adhanPlayerProvider = Provider<AdhanPlayer>((ref) {
  final player = AdhanPlayer();
  ref.onDispose(player.dispose);
  return player;
});

/// Fields that, when changed, invalidate the current notification schedule.
///
/// Compared as a record so that toggling an unrelated setting — blocked apps,
/// verification preference — does not trigger a pointless reschedule of
/// seventy notifications.
({
  Object? location,
  Object method,
  Object madhab,
  Object highLatitude,
  int reminderMinutes,
  bool adhanEnabled,
  bool blockingEnabled,
  int adjustmentHash,
}) _scheduleInputs(AppSettings settings) => (
      location: settings.location,
      method: settings.calculationMethod,
      madhab: settings.madhab,
      highLatitude: settings.highLatitudeRule,
      reminderMinutes: settings.reminderMinutesBefore,
      adhanEnabled: settings.adhanEnabled,
      blockingEnabled: settings.blockingEnabled,
      adjustmentHash: Object.hashAllUnordered(
        settings.adjustments.entries.map((e) => Object.hash(e.key, e.value)),
      ),
    );

/// Keeps the schedule current for the app's lifetime.
///
/// Watch this once from the app shell. It reschedules on startup and whenever
/// a schedule-relevant setting changes.
final notificationSyncProvider = Provider<NotificationSync>((ref) {
  final sync = NotificationSync(
    ref.watch(prayerNotificationSchedulerProvider),
    ref.watch(notificationServiceProvider),
  );

  ref.listen<AppSettings>(
    settingsProvider,
    (previous, next) {
      if (previous != null &&
          _scheduleInputs(previous) == _scheduleInputs(next)) {
        return;
      }
      sync.rescheduleFor(next);
    },
    fireImmediately: true,
  );

  return sync;
});

class NotificationSync {
  // Positional rather than named: Dart forbids `this._field` in named
  // parameters, so named ones would force a redundant assigning constructor.
  NotificationSync(this._scheduler, this._service);

  final PrayerNotificationScheduler _scheduler;
  final NotificationService _service;

  bool _isInitialised = false;
  DateTime? _lastScheduledAt;

  /// Number of notifications currently scheduled, for the diagnostics screen.
  int scheduledCount = 0;

  Future<void> ensureInitialised() async {
    if (_isInitialised) return;
    await _service.initialise();
    _isInitialised = true;
  }

  Future<void> rescheduleFor(AppSettings settings) async {
    await ensureInitialised();

    final planned = await _scheduler.reschedule(settings: settings);
    scheduledCount = planned.length;
    _lastScheduledAt = DateTime.now().toUtc();

    logDiagnostic(
      'Scheduled ${planned.length} prayer notifications '
      '(${settings.location?.label ?? 'no location'})',
    );
  }

  /// Re-run the schedule if it has not been refreshed recently.
  ///
  /// Called when the app returns to the foreground. The horizon is a week, so
  /// a daily refresh is ample; refreshing on every resume would rewrite
  /// seventy alarms every time the user glanced at the app.
  Future<void> refreshIfStale(AppSettings settings) async {
    final last = _lastScheduledAt;
    final isStale = last == null ||
        DateTime.now().toUtc().difference(last) > const Duration(hours: 12);

    if (isStale) await rescheduleFor(settings);
  }
}
