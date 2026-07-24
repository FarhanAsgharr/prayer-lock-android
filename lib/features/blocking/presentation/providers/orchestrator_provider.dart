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
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../../core/storage/storage_providers.dart';
import '../../../prayer_times/domain/entities/prayer_day.dart';
import '../../../prayer_times/domain/entities/prayer_enums.dart';
import '../../../prayer_times/presentation/providers/prayer_times_provider.dart';
import '../../../jumuah/presentation/providers/jumuah_providers.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../tracking/presentation/providers/tracking_providers.dart';
import '../../data/datasources/blocking_platform_channel.dart';
import '../../domain/entities/blocking_entities.dart';
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
    this.lockUntil,
    this.windowDuration,
    this.prayers = const [],
    this.slotName,
  });

  const LockState.idle()
      : isLocked = false,
        reason = LockReason.noPrayerDue,
        prayer = null,
        sessionId = null,
        error = null,
        lockUntil = null,
        windowDuration = null,
        prayers = const [],
        slotName = null;

  /// Every prayer the current lock covers — two under a combined grouping.
  final List<PrayerName> prayers;

  /// What to call the lock in the UI: "Dhuhr + Asr", or a single prayer's name.
  final String? slotName;

  /// Whether the lock covers a joined pair.
  bool get isCombined => prayers.length > 1;

  final bool isLocked;
  final LockReason reason;
  final PrayerName? prayer;
  final String? sessionId;

  /// When the lock releases on its own, if it does. Drives the countdown on
  /// the lock screen — under dynamic durations a user facing a three-hour
  /// window needs to see the end of it.
  final DateTime? lockUntil;

  /// The governing prayer's full computed window length.
  final Duration? windowDuration;

  /// Time left before the lock lifts by itself, or null if it will not.
  Duration? remainingAt(DateTime now) {
    final until = lockUntil;
    if (until == null) return null;
    final remaining = until.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }

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

        // On Android, mirror the coming week's windows to native storage and
        // re-arm the alarm chain. This is what keeps blocking working after a
        // reboot or a process kill, when no Dart code is running at all.
        await _syncNativeSchedule(settings, date);

        // Not inside the blocking gate: the widget is a prayer-times display,
        // and a user who has blocking switched off still wants it to show the
        // right prayer.
        await _syncWidget(settings, day, date);
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

  /// Key of the widget payload last pushed, so an unchanged day does not
  /// rewrite SharedPreferences and rebroadcast to the launcher every tick.
  String? _lastWidgetKey;

  /// Push today's windows to the home-screen widget.
  ///
  /// Only today: a widget shows the next prayer, and beyond the end of the day
  /// the answer is tomorrow's Fajr, which the next sync supplies. Mirroring a
  /// week would be data the widget never reads.
  Future<void> _syncWidget(
    AppSettings settings,
    PrayerDay day,
    DateTime date,
  ) async {
    if (!Platform.isAndroid) return;

    final mosque = ref.read(activeJumuahMosqueProvider);

    final windows = [
      for (final slot in day.slots(settings.prayerGrouping))
        WidgetWindow(
          name: slot.displayName,
          startsAt: slot.scheduledAt,
          endsAt: slot.windowEndsAt,
          isJumuah: slot.isJumuah,
          // The mosque is the one detail a Friday widget carries that nothing
          // else on the home screen does.
          detail: slot.isJumuah ? mosque?.displayName : null,
        ),
    ];

    final key = [
      for (final window in windows)
        '${window.name}:${window.startsAt.millisecondsSinceEpoch}'
            ':${window.endsAt.millisecondsSinceEpoch}:${window.detail}',
    ].join('|');

    try {
      if (key == _lastWidgetKey) {
        // Same windows, different minute. The words on the widget are a
        // function of the clock as much as of the schedule, so it still needs
        // redrawing — skipping this is how it ends up naming the wrong prayer.
        await _channel.refreshWidget();
      } else {
        _lastWidgetKey = key;
        await _channel.updateWidget(windows);
      }
    } catch (error) {
      // A widget that could not be redrawn must never break enforcement.
      debugPrint('Widget update failed: $error');
    }
  }

  /// Key of the window set last pushed to iOS, so identical schedules are not
  /// re-pushed on every 30-second tick.
  String? _lastIosWindowKey;

  /// Key of the schedule last mirrored to Android, for the same reason.
  String? _lastNativeScheduleKey;

  /// How many days of windows to mirror natively.
  ///
  /// The native side cannot compute prayer times — that needs the Dart layer —
  /// so the mirror is the entire horizon over which enforcement can survive
  /// without the app being opened. A week is long enough that a user who
  /// forgets about the app for a few days is still protected, and short enough
  /// that a settings change is fully reflected within one sync.
  static const int _nativeHorizonDays = 7;

  /// Push the coming week's windows and the blocking policy to native storage.
  ///
  /// Days are read through the repository, so they come from the cache when
  /// present — this is a database read per day, not a network call.
  Future<void> _syncNativeSchedule(AppSettings settings, DateTime date) async {
    if (!Platform.isAndroid) return;

    // Nothing to enforce: clear the mirror so armed alarms do not keep firing
    // for a feature the user has switched off.
    if (!settings.blockingEnabled || settings.blockedPackages.isEmpty) {
      if (_lastNativeScheduleKey != null) {
        await _channel.clearSchedule();
        _lastNativeScheduleKey = null;
      }
      return;
    }

    final repository = ref.read(prayerScheduleRepositoryProvider);
    final grace = Duration(minutes: settings.lockGracePeriodMinutes);

    final windows = <NativePrayerWindow>[];

    for (var offset = 0; offset < _nativeHorizonDays; offset++) {
      final target = DateTime(date.year, date.month, date.day + offset);

      final PrayerDay dayForOffset;
      try {
        dayForOffset = await repository.prayerDay(target);
      } catch (error) {
        // One unreadable day must not abort the whole mirror; the days that
        // did resolve are still worth arming.
        debugPrint('Skipping native mirror for $target: $error');
        continue;
      }

      // Mirrored as slots, so a combined pair crosses the channel as one
      // window. Sending two would have the native side release the lock at
      // Asr's start and immediately re-engage — visible to the user as apps
      // flickering unblocked in the middle of a joined window.
      for (final slot in dayForOffset.slots(settings.prayerGrouping)) {
        // The grace period cannot push engagement past the window's own end,
        // or the lock would be armed to start after it should already have
        // finished.
        final engagesAt = slot.scheduledAt.add(grace);

        windows.add(
          NativePrayerWindow(
            // The slot id, so the native side's logs and notification text
            // name what is actually being enforced.
            prayer: slot.id,
            startsAt: slot.scheduledAt,
            engagesAt: engagesAt.isAfter(slot.windowEndsAt)
                ? slot.windowEndsAt
                : engagesAt,
            endsAt: slot.windowEndsAt,
            qazaEndsAt: slot.qazaDeadline,
            fulfilled: slot.isFulfilled,
            // Only Jumu'ah silences, and only with the opt-in. Whether the
            // phone goes quiet is decided here rather than natively, because
            // the native side has no notion of which prayer is which.
            silence: slot.isJumuah && settings.jumuah.silenceDuringJumuah,
            // So a Friday lock says "Jumu'ah" rather than "Dhuhr".
            label: slot.displayName,
          ),
        );
      }
    }

    if (windows.isEmpty) return;

    // Only push when something actually changed. Without this the mirror would
    // be rewritten and every alarm re-armed twice a minute, which is both a
    // synchronous disk commit and a burst of AlarmManager churn.
    final key = [
      settings.unlockPolicy.wireValue,
      settings.blockUntilQazaCompleted,
      settings.morningProtectionEnabled,
      settings.blockedPackages.length,
      for (final window in windows)
        '${window.prayer}:${window.startsAt.millisecondsSinceEpoch}'
            ':${window.endsAt.millisecondsSinceEpoch}:${window.fulfilled}'
            ':${window.silence}',
    ].join('|');

    if (key == _lastNativeScheduleKey) return;
    _lastNativeScheduleKey = key;

    final stored = await _channel.syncSchedule(
      windows: windows,
      packages: settings.blockedPackages.toList(),
      blockingEnabled: settings.blockingEnabled,
      unlockPolicy: settings.unlockPolicy.wireValue,
      blockUntilQaza: settings.blockUntilQazaCompleted,
      morningProtection: settings.morningProtectionEnabled,
    );

    debugPrint('Mirrored $stored prayer windows to the native scheduler');
  }

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
  ///
  /// Resolved through the repository so the orchestrator sees the same times
  /// the UI does — cached or fetched where available, computed on-device
  /// otherwise. A divergence here would mean the lock engaging at a different
  /// instant from the one the countdown on screen is showing.
  Future<PrayerDay?> _currentDay(AppSettings settings, DateTime date) async {
    if (!settings.isReady) return null;

    try {
      return await ref.read(prayerScheduleRepositoryProvider).prayerDay(date);
    } catch (error) {
      // Enforcement must not stop because a database read failed. The device
      // calculator needs nothing but the settings, so it is always available as
      // a floor — and a lock driven by locally computed times is far better
      // than no lock at all.
      debugPrint('Falling back to on-device schedule: $error');
      return _deviceDay(settings, date);
    }
  }

  /// The purely computed fallback day, with tracked outcomes merged in.
  Future<PrayerDay?> _deviceDay(AppSettings settings, DateTime date) async {
    final windows = windowsFor(settings, date);
    if (windows == null) return null;

    final base = PrayerDay.fromWindows(windows);
    final statuses =
        await ref.read(trackingRepositoryProvider).statusesForDate(date);

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
        // The slot's name, so a combined lock says "Dhuhr + Asr" rather than
        // naming one prayer and appearing not to release when it is prayed.
        prayerName: decision.slotName ?? prayer.displayName,
        // Handed to native so the service can release itself at the end of the
        // window even if the alarm that should have released it never arrives.
        endsAt: decision.lockUntil,
        silence: decision.isJumuah && settings.jumuah.silenceDuringJumuah,
      );

      if (!started) {
        // Platform without enforcement, such as iOS today. Not an error, and
        // must not be reported as one.
        state = LockState(
          isLocked: false,
          reason: decision.reason,
          prayer: prayer,
          prayers: decision.prayers,
          slotName: decision.slotName,
          lockUntil: decision.lockUntil,
          windowDuration: decision.windowDuration,
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
        prayers: decision.prayers,
        slotName: decision.slotName,
        sessionId: sessionId,
        lockUntil: decision.lockUntil,
        windowDuration: decision.windowDuration,
      );

      debugPrint(
        'Lock engaged for ${prayer.displayName}'
        '${decision.lockUntil == null ? '' : ' until ${decision.lockUntil}'}',
      );
    } on BlockingPlatformException catch (error) {
      // A missing permission means enforcement silently does nothing. Telling
      // the user is essential: believing you are protected when you are not is
      // worse than knowing you are not.
      state = LockState(
        isLocked: false,
        reason: decision.reason,
        prayer: prayer,
        prayers: decision.prayers,
        slotName: decision.slotName,
        lockUntil: decision.lockUntil,
        windowDuration: decision.windowDuration,
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

    // Exempt every prayer in the governing slot, not just the one that named
    // it. Under a combined grouping, exempting only Dhuhr would let the lock
    // re-engage for Asr inside the same window — the user would have spent
    // their single daily unlock and gained nothing.
    final covered = state.prayers.isNotEmpty
        ? state.prayers
        : [if (state.prayer != null) state.prayer!];
    _emergencyUnlocked.addAll(covered);

    await _release(LockReason.emergencyUnlocked);

    ref.invalidate(emergencyUnlockHistoryProvider);
    return true;
  }

  /// Clear the emergency-unlock exemptions at the start of a new day.
  void onDayChanged() => _emergencyUnlocked.clear();
}
