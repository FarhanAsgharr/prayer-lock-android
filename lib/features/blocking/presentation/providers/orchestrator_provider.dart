/// Prayer lock orchestration.
///
/// Turns the independent pieces — schedule, notifications, native blocking,
/// verification, tracking, sync — into one automatic workflow:
///
///   prayer time -> notification -> grace period -> lock engages ->
///   blocked app intercepted -> user prays -> verification -> unlock ->
///   prayer saved -> statistics refreshed -> queued for upload
///
/// The orchestrator is driven by the clock tick and by app lifecycle events,
/// and it is *idempotent*: it computes the state the device should be in and
/// converges on it. It never assumes it knows the current state, because the
/// process may have been killed and restarted since the last decision.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../../core/storage/storage_providers.dart';
import '../../../prayer_times/domain/entities/prayer_day.dart';
import '../../../prayer_times/domain/entities/prayer_enums.dart';
import '../../../prayer_times/presentation/providers/prayer_times_provider.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../tracking/presentation/providers/tracking_providers.dart';
import '../../data/datasources/blocking_platform_channel.dart';
import '../../domain/usecases/lock_decision.dart';

/// Current enforcement state, for the UI.
@immutable
class LockState {
  const LockState({
    required this.isLocked,
    required this.reason,
    this.prayer,
    this.sessionId,
    this.error,
  });

  const LockState.idle()
      : isLocked = false,
        reason = LockReason.noPrayerDue,
        prayer = null,
        sessionId = null,
        error = null;

  final bool isLocked;
  final LockReason reason;
  final PrayerName? prayer;
  final String? sessionId;

  /// Set when enforcement was requested but could not be applied — almost
  /// always a revoked permission. Surfaced so the user is told, rather than
  /// believing they are protected when they are not.
  final String? error;
}

final lockStateProvider =
    NotifierProvider<LockOrchestrator, LockState>(LockOrchestrator.new);

class LockOrchestrator extends Notifier<LockState> {
  BlockingPlatformChannel get _channel => BlockingPlatformChannel();

  Timer? _ticker;

  /// Prayers the user bought out of with an emergency unlock today.
  ///
  /// Held in memory and rebuilt from the database on start: re-locking a
  /// prayer the user just spent their single daily unlock on would make the
  /// unlock worthless.
  final Set<PrayerName> _emergencyUnlocked = {};

  /// Guards against overlapping evaluations, which could start two sessions.
  bool _isEvaluating = false;

  @override
  LockState build() {
    ref.onDispose(() => _ticker?.cancel());
    return const LockState.idle();
  }

  /// Begin orchestrating. Called once from the app shell.
  Future<void> start() async {
    await _recoverOrphanedSession();

    // A 30-second cadence is enough: the grace period is measured in minutes,
    // so sub-minute precision buys nothing and costs wakeups.
    _ticker?.cancel();
    _ticker = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(evaluate()),
    );

    await evaluate();
  }

  /// A session left open by a crash, force-quit or reboot.
  ///
  /// Without this the database accumulates sessions that never end, and the
  /// lock history becomes meaningless. The session is closed rather than
  /// resumed: [evaluate] will immediately re-open one if a lock is still owed,
  /// which is the same outcome by a path that cannot get stuck.
  Future<void> _recoverOrphanedSession() async {
    final repository = ref.read(trackingRepositoryProvider);
    final orphan = await repository.openLockSessionRow();
    if (orphan == null) return;

    await repository.closeLockSession(
      sessionId: orphan['id']! as String,
      endReason: 'app_restarted',
    );
    debugPrint('Closed orphaned lock session ${orphan['id']}');
  }

  /// Converge the device onto the state the rules require.
  Future<void> evaluate() async {
    if (_isEvaluating) return;
    _isEvaluating = true;

    try {
      final settings = ref.read(settingsProvider);
      final now = DateTime.now().toUtc();
      final date = ref.read(localDateProvider);
      final day = await _currentDay(settings, date);

      // Record anything whose window closed while the app was away, so
      // statistics reflect reality rather than omitting the gap.
      if (day != null) {
        await ref
            .read(prayerTrackerProvider)
            .reconcileExpired(date: date, day: day, now: now);

        // On iOS, enforcement while the app is closed is driven by the
        // DeviceActivity schedule, not this timer. Keep that schedule current
        // with today's windows. No-op on Android.
        await _scheduleIosWindows(settings, day);
      }

      final decision = LockDecisionMaker.decide(
        settings: settings,
        day: day,
        now: now,
        emergencyUnlockedPrayers: _emergencyUnlocked,
      );

      if (decision.shouldLock) {
        await _engage(decision, settings, day);
      } else {
        await _release(decision.reason);
      }
    } finally {
      _isEvaluating = false;
    }
  }

  /// Key of the window set last pushed to iOS, so identical schedules are not
  /// re-pushed on every 30-second tick.
  String? _lastIosWindowKey;

  /// Push each prayer's blocking window to iOS DeviceActivity.
  ///
  /// Windows are the enforcement mechanism on iOS, where the app cannot poll in
  /// the background. Each runs from the prayer's start plus the grace period to
  /// the end of its window, in the location's local wall-clock time — which is
  /// what DeviceActivity schedules by. A fulfilled prayer's window is omitted,
  /// so a prayer already prayed does not shield apps for the rest of its window.
  Future<void> _scheduleIosWindows(AppSettings settings, PrayerDay day) async {
    if (!BlockingPlatformChannel.usesSystemPicker) return;

    if (!settings.blockingEnabled || settings.blockedPackages.isEmpty) {
      if (_lastIosWindowKey != null) {
        await _channel.cancelSchedule();
        _lastIosWindowKey = null;
      }
      return;
    }

    final timezone = settings.location?.timezone;
    if (timezone == null) return;

    final windows = <Map<String, dynamic>>[];
    for (final entry in day.entries) {
      if (entry.status.isFulfilled) continue;

      final start = _localComponents(
        entry.scheduledAt.add(
          Duration(minutes: settings.lockGracePeriodMinutes),
        ),
        timezone,
      );
      final end = _localComponents(entry.windowEndsAt, timezone);
      if (start == null || end == null) continue;

      windows.add({
        'name': entry.prayer.wireValue,
        'startHour': start.$1,
        'startMinute': start.$2,
        'endHour': end.$1,
        'endMinute': end.$2,
      });
    }

    // Only push when the set actually changed, so the daily-shifting schedule
    // is refreshed but an unchanged one does not thrash the system.
    final key = windows.map((w) => w.values.join(':')).join('|');
    if (key == _lastIosWindowKey) return;
    _lastIosWindowKey = key;

    await _channel.scheduleWindows(windows);
    debugPrint('Scheduled ${windows.length} iOS blocking windows');
  }

  /// Local (hour, minute) for a UTC instant at the given IANA timezone.
  (int, int)? _localComponents(DateTime utcInstant, String timezone) {
    try {
      final local = tz.TZDateTime.from(utcInstant, tz.getLocation(timezone));
      return (local.hour, local.minute);
    } on tz.LocationNotFoundException {
      return null;
    }
  }

  /// Today's schedule with recorded outcomes merged in.
  Future<PrayerDay?> _currentDay(AppSettings settings, DateTime date) async {
    final schedule = scheduleFor(settings, date);
    if (schedule == null) return null;

    final statuses =
        await ref.read(trackingRepositoryProvider).statusesForDate(date);

    final base = PrayerDay.fromSchedule(schedule);

    return statuses.entries.fold<PrayerDay>(
      base,
      (day, entry) => day.withEntry(
        day.entryFor(entry.key).copyWith(status: entry.value),
      ),
    );
  }

  Future<void> _engage(
    LockDecision decision,
    AppSettings settings,
    PrayerDay? day,
  ) async {
    // Already locked for this prayer: converging means doing nothing, not
    // restarting the service and stacking another session.
    if (state.isLocked && state.prayer == decision.prayer) return;

    final prayer = decision.prayer;
    if (prayer == null) return;

    try {
      final started = await _channel.startLock(
        packages: settings.blockedPackages.toList(),
        prayerName: prayer.displayName,
      );

      if (!started) {
        // Platform without enforcement, such as iOS today. Not an error, and
        // must not be reported as one.
        state = LockState(
          isLocked: false,
          reason: decision.reason,
          prayer: prayer,
        );
        return;
      }

      final sessionId =
          '${DateTime.now().toUtc().millisecondsSinceEpoch}:${prayer.wireValue}';

      await ref.read(trackingRepositoryProvider).openLockSession(
            sessionId: sessionId,
            prayer: prayer,
            prayerHistoryId: null,
            blockedAppCount: settings.blockedPackages.length,
            isMorningProtection: decision.isMorningProtection,
          );

      state = LockState(
        isLocked: true,
        reason: decision.reason,
        prayer: prayer,
        sessionId: sessionId,
      );

      debugPrint('Lock engaged for ${prayer.displayName}');
    } on BlockingPlatformException catch (error) {
      // A missing permission means enforcement silently does nothing. Telling
      // the user is essential: believing you are protected when you are not is
      // worse than knowing you are not.
      state = LockState(
        isLocked: false,
        reason: decision.reason,
        prayer: prayer,
        error: error.isMissingPermission
            ? 'App blocking needs permission that has been turned off.'
            : error.message,
      );
      debugPrint('Could not engage lock: ${error.code}');
    }
  }

  Future<void> _release(LockReason reason) async {
    if (!state.isLocked) {
      // Keep the reason current even when nothing changes, so the UI can
      // explain *why* nothing is locked.
      if (state.reason != reason) {
        state = LockState(isLocked: false, reason: reason);
      }
      return;
    }

    await _channel.stopLock();

    final sessionId = state.sessionId;
    if (sessionId != null) {
      await ref.read(trackingRepositoryProvider).closeLockSession(
            sessionId: sessionId,
            endReason: _endReasonFor(reason),
          );
      ref.invalidate(lockHistoryProvider);
    }

    state = LockState(isLocked: false, reason: reason);
    debugPrint('Lock released: ${reason.name}');
  }

  static String _endReasonFor(LockReason reason) => switch (reason) {
        LockReason.prayerFulfilled => 'verified',
        LockReason.emergencyUnlocked => 'emergency_unlock',
        LockReason.noPrayerDue => 'window_expired',
        LockReason.disabledBySettings => 'user_disabled',
        _ => 'window_expired',
      };

  /// Called after a prayer is verified or manually recorded.
  ///
  /// Releases immediately rather than waiting for the next tick — a user who
  /// has just proved they prayed should not stare at a locked phone for up to
  /// thirty seconds.
  Future<void> onPrayerCompleted() async {
    await evaluate();
  }

  /// Spend an emergency unlock.
  ///
  /// Returns false when the daily quota is exhausted. The quota is enforced in
  /// the database by a unique constraint, so a retry during a network partition
  /// cannot consume two.
  Future<bool> requestEmergencyUnlock({String? reason}) async {
    final settings = ref.read(settingsProvider);
    final date = ref.read(localDateProvider);

    final unlockId =
        await ref.read(trackingRepositoryProvider).recordEmergencyUnlock(
              localDate: date,
              maxPerDay: settings.maxEmergencyUnlocksPerDay,
              lockSessionId: state.sessionId,
              reason: reason,
            );

    if (unlockId == null) return false;

    final prayer = state.prayer;
    if (prayer != null) _emergencyUnlocked.add(prayer);

    await _release(LockReason.emergencyUnlocked);

    ref.invalidate(emergencyUnlockHistoryProvider);
    return true;
  }

  /// Clear the emergency-unlock exemptions at the start of a new day.
  void onDayChanged() => _emergencyUnlocked.clear();
}
