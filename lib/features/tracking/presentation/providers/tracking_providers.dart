/// Database-backed prayer tracking.
///
/// Replaces the in-memory tracking used during UI development. The difference
/// that matters: a prayer recorded here survives an app kill, a reboot, and a
/// week offline. Losing someone's record of their own worship because the
/// process was reclaimed would be unacceptable.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/storage_providers.dart';
import '../../../prayer_times/domain/entities/prayer_day.dart';
import '../../../prayer_times/domain/entities/prayer_enums.dart';
import '../../data/repositories/tracking_repository.dart';
import '../../domain/entities/prayer_statistics.dart';

/// Statuses recorded for a given local date.
///
/// Keyed by date so switching the viewed day does not refetch the whole
/// history, and so the dashboard's merge into a freshly calculated schedule
/// stays a cheap map lookup.
final trackedStatusesProvider = FutureProvider.family<
    Map<PrayerName, PrayerStatus>, DateTime>((ref, date) async {
  final repository = ref.watch(trackingRepositoryProvider);
  return repository.statusesForDate(date);
});

/// Full statistics bundle for the dashboard.
///
/// Invalidated by [PrayerTracker] after every write, so charts and streaks
/// update without any screen having to remember to refresh them.
final prayerStatisticsProvider = FutureProvider<PrayerStatistics>((ref) async {
  final repository = ref.watch(trackingRepositoryProvider);
  return repository.statistics();
});

final verificationHistoryProvider =
    FutureProvider<List<Map<String, Object?>>>((ref) async {
  return ref.watch(trackingRepositoryProvider).verificationHistory();
});

final lockHistoryProvider =
    FutureProvider<List<Map<String, Object?>>>((ref) async {
  return ref.watch(trackingRepositoryProvider).lockHistory();
});

final emergencyUnlockHistoryProvider =
    FutureProvider<List<Map<String, Object?>>>((ref) async {
  return ref.watch(trackingRepositoryProvider).emergencyUnlockHistory();
});

/// How many emergency unlocks remain today.
final remainingEmergencyUnlocksProvider =
    FutureProvider.family<int, ({DateTime date, int maxPerDay})>(
        (ref, args) async {
  final used = await ref
      .watch(trackingRepositoryProvider)
      .countEmergencyUnlocks(args.date);
  return (args.maxPerDay - used).clamp(0, args.maxPerDay);
});

/// Which window a verification landed in, or that it was too late.
enum VerificationOutcome {
  onTime,
  qaza,
  expired;

  bool get succeeded => this == onTime || this == qaza;
}

final prayerTrackerProvider = Provider<PrayerTracker>(
  (ref) => PrayerTracker(ref),
);

/// Writes prayer outcomes and refreshes everything that derives from them.
class PrayerTracker {
  PrayerTracker(this._ref);

  final Ref _ref;

  TrackingRepository get _repository => _ref.read(trackingRepositoryProvider);

  /// Record a completed prayer.
  ///
  /// Whether it counts as on time or late is decided here, from the window,
  /// rather than trusted from the caller — a screen passing the wrong status
  /// would silently corrupt the user's history.
  /// Result of attempting to verify a prayer.
  ///
  /// Distinguishes the three outcomes the UI must present differently: verified
  /// on time, verified as qaza, or refused because the qaza window has closed.
  Future<VerificationOutcome> markVerified({
    required DateTime date,
    required PrayerEntry entry,
    DateTime? at,
  }) async {
    final verifiedAt = at ?? DateTime.now().toUtc();

    // Decide on-time vs qaza vs expired from the deadlines, never from the
    // caller — a screen passing the wrong kind would corrupt the history.
    if (entry.isInVerificationWindow(verifiedAt)) {
      await _repository.recordPrayer(
        date: date,
        entry: entry,
        status: PrayerStatus.completed,
        completedAt: verifiedAt,
      );
      _invalidate(date);
      return VerificationOutcome.onTime;
    }

    if (entry.isInQazaWindow(verifiedAt)) {
      await _repository.recordPrayer(
        date: date,
        entry: entry,
        status: PrayerStatus.qazaCompleted,
        qazaCompletedAt: verifiedAt,
      );
      _invalidate(date);
      return VerificationOutcome.qaza;
    }

    // Past the qaza deadline: no verification is possible. The prayer is
    // recorded missed if it was not already, and no photo can change it.
    if (entry.status == PrayerStatus.pending) {
      await _repository.recordPrayer(
        date: date,
        entry: entry,
        status: PrayerStatus.missed,
      );
      _invalidate(date);
    }
    return VerificationOutcome.expired;
  }

  Future<String> markExcused({
    required DateTime date,
    required PrayerEntry entry,
    String? reason,
  }) async {
    final id = await _repository.recordPrayer(
      date: date,
      entry: entry,
      status: PrayerStatus.excused,
      excuseReason: reason,
    );

    _invalidate(date);
    return id;
  }

  /// Record a prayer whose window closed unfulfilled.
  ///
  /// Called by the reconciliation pass rather than by the user. Writing a
  /// missed prayer explicitly, instead of inferring it from absence, is what
  /// lets statistics distinguish "missed" from "the app was not installed".
  Future<void> markMissed({
    required DateTime date,
    required PrayerEntry entry,
  }) async {
    await _repository.recordPrayer(
      date: date,
      entry: entry,
      status: PrayerStatus.missed,
    );

    _invalidate(date);
  }

  /// Persist a verification attempt against a prayer.
  Future<void> recordVerification({
    required String prayerHistoryId,
    required String verificationId,
    required bool approved,
    required int attemptNumber,
    required bool releasedWithoutDetection,
    String? message,
  }) async {
    await _repository.recordVerification(
      prayerHistoryId: prayerHistoryId,
      verificationId: verificationId,
      approved: approved,
      attemptNumber: attemptNumber,
      releasedWithoutDetection: releasedWithoutDetection,
      message: message,
    );

    _ref.invalidate(verificationHistoryProvider);
  }

  /// Write any prayer whose window has closed without an outcome.
  ///
  /// Run on app start and on resume. Without it, a user who does not open the
  /// app for three days has no record of those prayers at all — neither
  /// completed nor missed — and their statistics silently omit the period
  /// rather than reflecting it.
  Future<int> reconcileExpired({
    required DateTime date,
    required PrayerDay day,
    required DateTime now,
  }) async {
    final existing = await _repository.statusesForDate(date);
    var written = 0;

    for (final entry in day.entries) {
      if (!entry.hasExpired(now)) continue;
      // Never overwrite a recorded outcome; only fill genuine gaps.
      if (existing.containsKey(entry.prayer)) continue;

      await _repository.recordPrayer(
        date: date,
        entry: entry,
        status: PrayerStatus.missed,
      );
      written++;
    }

    if (written > 0) _invalidate(date);
    return written;
  }

  void _invalidate(DateTime date) {
    _ref.invalidate(trackedStatusesProvider(date));
    _ref.invalidate(prayerStatisticsProvider);
  }
}
