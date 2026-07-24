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
import '../../../jumuah/domain/entities/mosque_profile.dart';
import '../../../jumuah/domain/usecases/jumuah_verification_controller.dart';
import '../../../prayer_times/domain/entities/prayer_slot.dart';
import '../../data/repositories/qaza_repository.dart';
import '../../data/repositories/tracking_repository.dart';
import '../../domain/entities/friday_analytics.dart';
import '../../domain/entities/prayer_statistics.dart';

/// The ledger of make-up prayers still owed.
final qazaRepositoryProvider = Provider<QazaRepository>(
  (ref) => QazaRepository(ref.watch(appDatabaseProvider).raw),
);

/// Outstanding make-up prayers, oldest first.
final qazaLedgerProvider = FutureProvider<List<QazaRecord>>((ref) async {
  return ref.watch(qazaRepositoryProvider).outstanding();
});

/// How many prayers are still owed, for the dashboard badge.
final qazaOutstandingCountProvider = FutureProvider<int>((ref) async {
  return ref.watch(qazaRepositoryProvider).outstandingCount();
});

/// Outstanding debts grouped by prayer, for the qaza screen's summary.
final qazaByPrayerProvider =
    FutureProvider<Map<PrayerName, int>>((ref) async {
  return ref.watch(qazaRepositoryProvider).outstandingByPrayer();
});

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

/// Every recorded Friday, most recent first.
final fridayHistoryProvider = FutureProvider<List<FridayRecord>>((ref) async {
  return ref.watch(trackingRepositoryProvider).fridayHistory();
});

/// Friday streaks, completion rate and averages.
final fridayAnalyticsProvider = FutureProvider<FridayAnalytics>((ref) async {
  final records = await ref.watch(fridayHistoryProvider.future);
  return FridayAnalytics.from(records);
});

/// Most-missed prayer, best prayer, consistency and verification averages.
final extendedAnalyticsProvider =
    FutureProvider<ExtendedPrayerAnalytics>((ref) async {
  final repository = ref.watch(trackingRepositoryProvider);

  return ExtendedPrayerAnalytics(
    byPrayer: await repository.prayerPerformance(),
    averageVerificationTime: await repository.averageVerificationTime(),
    friday: await ref.watch(fridayAnalyticsProvider.future),
  );
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

  QazaRepository get _qaza => _ref.read(qazaRepositoryProvider);

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
    bool wasCombined = false,
    JumuahRecord? jumuah,
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
        wasCombined: wasCombined,
        jumuah: jumuah,
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
        wasCombined: wasCombined,
        jumuah: jumuah,
      );
      // The window closed before this, so a debt may already have been booked
      // by the reconciliation pass. Clearing it here keeps the ledger and the
      // history from disagreeing about whether the prayer is still owed.
      await _qaza.markCompleted(date: date, prayer: entry.prayer, at: verifiedAt);
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
      await _qaza.recordMissed(date: date, entry: entry);
      _invalidate(date);
    }
    return VerificationOutcome.expired;
  }

  /// Verify a whole slot: one prayer, or a combined pair.
  ///
  /// Under a combined grouping a single confirmation discharges both prayers,
  /// because the user prayed both. They are recorded as **two separate history
  /// rows**, not one — the obligation was two prayers, and collapsing them
  /// would make a combining user's statistics incomparable with everyone
  /// else's and would break the streak arithmetic.
  ///
  /// Each prayer's on-time/qaza classification is decided against *its own*
  /// window, not the slot's. Praying Dhuhr and Asr together at 15:00 is on time
  /// for Asr and late for Dhuhr, and recording both as on time would be a
  /// flattering fiction.
  ///
  /// Returns the outcome for the slot as a whole: the weakest of the
  /// constituent outcomes, since a slot is only as discharged as its
  /// least-discharged prayer.
  Future<VerificationOutcome> markSlotVerified({
    required DateTime date,
    required PrayerSlot slot,
    required bool combinedVerification,
    DateTime? at,
    MosqueProfile? jumuahMosque,
  }) async {
    final verifiedAt = at ?? DateTime.now().toUtc();

    // A Jumu'ah slot writes the same Dhuhr row as any other day, plus the
    // congregation details. Built here rather than by the caller so the record
    // and the prayer write cannot disagree about which mosque or how long.
    final jumuahRecord = slot.isJumuah && jumuahMosque != null
        ? const JumuahVerificationController().recordFor(
            slot: slot,
            date: date,
            mosque: jumuahMosque,
            verifiedAt: verifiedAt,
          )
        : null;

    // With combined verification off, only the prayer whose window is open is
    // discharged; the other is left for its own confirmation.
    final targets = combinedVerification
        ? slot.prayers
        : slot.prayers
            .where((entry) => entry.phaseAt(verifiedAt).isVerifiable)
            .toList();

    if (targets.isEmpty) return VerificationOutcome.expired;

    final outcomes = <VerificationOutcome>[];
    for (final entry in targets) {
      // Skip anything already settled rather than overwriting it: a prayer
      // verified on time an hour ago must not be downgraded to qaza because
      // its partner is being confirmed now.
      if (entry.status.isFulfilled) continue;

      outcomes.add(
        await markVerified(
          date: date,
          entry: entry,
          at: verifiedAt,
          // Recorded from the slot's shape, not from the current setting: a
          // prayer logged today as combined must still read as combined after
          // the user switches back to five separate prayers.
          wasCombined: slot.isCombined,
          jumuah: jumuahRecord,
        ),
      );
    }

    if (outcomes.isEmpty) return VerificationOutcome.onTime;

    // Weakest wins: expired beats qaza beats on time.
    if (outcomes.contains(VerificationOutcome.expired)) {
      return VerificationOutcome.expired;
    }
    if (outcomes.contains(VerificationOutcome.qaza)) {
      return VerificationOutcome.qaza;
    }
    return VerificationOutcome.onTime;
  }

  /// Discharge an outstanding make-up prayer from the qaza screen.
  ///
  /// Distinct from [markVerified]: that records a prayer within its own day's
  /// windows, whereas this clears a debt carried forward from an earlier day,
  /// whose windows are long closed.
  ///
  /// Returns false when the debt was already cleared, so the UI does not report
  /// success twice for one prayer.
  Future<bool> completeQaza({
    required DateTime date,
    required PrayerName prayer,
    DateTime? at,
  }) async {
    final performedAt = at ?? DateTime.now().toUtc();

    final cleared = await _qaza.markCompleted(
      date: date,
      prayer: prayer,
      at: performedAt,
    );
    if (!cleared) return false;

    // Promote the history row from missed to qaza-completed, so statistics and
    // streaks reflect that the obligation was ultimately discharged.
    await _repository.updateStatus(
      date: date,
      prayer: prayer,
      status: PrayerStatus.qazaCompleted,
      qazaCompletedAt: performedAt,
    );

    _invalidate(date);
    return true;
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
    await _qaza.recordMissed(date: date, entry: entry);

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
      // Book the debt at the same time. A missed prayer that never reaches the
      // ledger is one the user is never offered the chance to make up.
      await _qaza.recordMissed(date: date, entry: entry);
      written++;
    }

    if (written > 0) _invalidate(date);
    return written;
  }

  void _invalidate(DateTime date) {
    _ref.invalidate(trackedStatusesProvider(date));
    _ref.invalidate(prayerStatisticsProvider);
    _ref.invalidate(qazaLedgerProvider);
    _ref.invalidate(qazaOutstandingCountProvider);
    _ref.invalidate(qazaByPrayerProvider);
    _ref.invalidate(fridayHistoryProvider);
    _ref.invalidate(fridayAnalyticsProvider);
    _ref.invalidate(extendedAnalyticsProvider);
  }
}
