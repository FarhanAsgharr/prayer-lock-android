/// Local persistence for prayer history, verifications and lock sessions.
///
/// Every write is local-first and immediately enqueued for upload. The user's
/// record of their own worship must never depend on a network round trip.
library;

import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../core/sync/sync_queue.dart';
import '../../../jumuah/domain/usecases/jumuah_verification_controller.dart';
import '../../../prayer_times/domain/entities/prayer_day.dart';
import '../../../prayer_times/domain/entities/prayer_enums.dart';
import '../../domain/entities/friday_analytics.dart';
import '../../domain/entities/prayer_statistics.dart';
import '../../domain/usecases/streak_calculator.dart';

class TrackingRepository {
  TrackingRepository(this._database, this._queue);

  final Database _database;
  final SyncQueue _queue;

  /// Deterministic row id for a prayer on a date.
  ///
  /// Not random: the same prayer recorded twice — once by the user tapping
  /// complete, once by a background reconciliation — must collide and update
  /// rather than create a duplicate.
  static String prayerId(DateTime date, PrayerName prayer) =>
      '${_dateKey(date)}:${prayer.wireValue}';

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  // -- Writes -------------------------------------------------------------

  /// Record a prayer's outcome and queue it for upload.
  Future<String> recordPrayer({
    required DateTime date,
    required PrayerEntry entry,
    required PrayerStatus status,
    DateTime? completedAt,
    DateTime? qazaCompletedAt,
    DateTime? startedAt,
    String? excuseReason,
    bool wasCombined = false,
    JumuahRecord? jumuah,
  }) async {
    final id = prayerId(date, entry.prayer);
    final now = DateTime.now().toUtc();

    final verifiedAt = completedAt ?? qazaCompletedAt;

    // Clamped at zero: a prayer performed before its scheduled instant would
    // otherwise record a negative delay, which the statistics treat as time
    // travel rather than as on time.
    final delayMinutes = verifiedAt
        ?.difference(entry.scheduledAt)
        .inMinutes
        .clamp(0, 1 << 30);

    final row = {
      'id': id,
      'prayer_date': _dateKey(date),
      'prayer': entry.prayer.wireValue,
      'status': status.wireValue,
      'scheduled_at': entry.scheduledAt.millisecondsSinceEpoch,
      'window_ends_at': entry.windowEndsAt.millisecondsSinceEpoch,
      'verification_deadline':
          entry.verificationDeadline.millisecondsSinceEpoch,
      'qaza_deadline': entry.qazaDeadline.millisecondsSinceEpoch,
      'started_at': startedAt?.millisecondsSinceEpoch,
      'completed_at': completedAt?.millisecondsSinceEpoch,
      'qaza_completed_at': qazaCompletedAt?.millisecondsSinceEpoch,
      'delay_minutes': delayMinutes,
      'excuse_reason': excuseReason,
      'was_combined': wasCombined ? 1 : 0,
      ...?jumuah?.toColumns(),
      'synced': 0,
      'updated_at': now.millisecondsSinceEpoch,
    };

    await _database.insert(
      'prayer_history',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _queue.enqueue(
      entityType: SyncEntityType.prayerHistory,
      entityId: id,
      operation: SyncOperation.create,
      payload: {
        'prayer_date': row['prayer_date'],
        'prayer': row['prayer'],
        'status': row['status'],
        'scheduled_at': entry.scheduledAt.toIso8601String(),
        'window_ends_at': entry.windowEndsAt.toIso8601String(),
        'verification_deadline': entry.verificationDeadline.toIso8601String(),
        'qaza_deadline': entry.qazaDeadline.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
        'qaza_completed_at': qazaCompletedAt?.toIso8601String(),
        'delay_minutes': delayMinutes,
        'excuse_reason': excuseReason,
        'was_combined': wasCombined,
        'was_jumuah': jumuah != null,
        'jumuah_location': jumuah?.mosqueId,
        'jumuah_mosque_name': jumuah?.mosqueName,
        'jumuah_block_seconds': jumuah?.blockDuration.inSeconds,
      },
    );

    return id;
  }

  /// Change a recorded prayer's status without rewriting its window.
  ///
  /// Used when a debt is discharged from the qaza screen days later: the
  /// prayer's original scheduled instant and window must not move, because they
  /// describe when it was due, not when it was eventually made up.
  ///
  /// Does nothing when no row exists — a prayer with no history row was never
  /// missed in a way this app observed, so there is nothing to promote.
  Future<bool> updateStatus({
    required DateTime date,
    required PrayerName prayer,
    required PrayerStatus status,
    DateTime? completedAt,
    DateTime? qazaCompletedAt,
  }) async {
    final id = prayerId(date, prayer);
    final now = DateTime.now().toUtc();

    final updated = await _database.update(
      'prayer_history',
      {
        'status': status.wireValue,
        if (completedAt != null)
          'completed_at': completedAt.millisecondsSinceEpoch,
        if (qazaCompletedAt != null)
          'qaza_completed_at': qazaCompletedAt.millisecondsSinceEpoch,
        'synced': 0,
        'updated_at': now.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    if (updated == 0) return false;

    await _queue.enqueue(
      entityType: SyncEntityType.prayerHistory,
      entityId: id,
      // The server already has this row; sending a create again would be
      // rejected or would duplicate it.
      operation: SyncOperation.update,
      payload: {
        'prayer_date': _dateKey(date),
        'prayer': prayer.wireValue,
        'status': status.wireValue,
        'completed_at': completedAt?.toIso8601String(),
        'qaza_completed_at': qazaCompletedAt?.toIso8601String(),
      },
    );

    return true;
  }

  /// Record a verification attempt against a prayer.
  Future<void> recordVerification({
    required String prayerHistoryId,
    required String verificationId,
    required bool approved,
    required int attemptNumber,
    required bool releasedWithoutDetection,
    String? message,
  }) async {
    final now = DateTime.now().toUtc();

    await _database.insert(
      'verifications',
      {
        'id': verificationId,
        'prayer_history_id': prayerHistoryId,
        'status': approved ? 'approved' : 'rejected',
        'approved': approved ? 1 : 0,
        'attempt_number': attemptNumber,
        'released_without_detection': releasedWithoutDetection ? 1 : 0,
        'message': message,
        'created_at': now.millisecondsSinceEpoch,
        'synced': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _queue.enqueue(
      entityType: SyncEntityType.verification,
      entityId: verificationId,
      operation: SyncOperation.create,
      payload: {
        'prayer_history_id': prayerHistoryId,
        'approved': approved,
        'attempt_number': attemptNumber,
        'released_without_detection': releasedWithoutDetection,
        'message': message,
        'created_at': now.toIso8601String(),
      },
    );
  }

  /// Open a lock session.
  Future<void> openLockSession({
    required String sessionId,
    required PrayerName prayer,
    required String? prayerHistoryId,
    required int blockedAppCount,
    bool isMorningProtection = false,
  }) async {
    await _database.insert(
      'lock_sessions',
      {
        'id': sessionId,
        'prayer_history_id': prayerHistoryId,
        'prayer': prayer.wireValue,
        'started_at': DateTime.now().toUtc().millisecondsSinceEpoch,
        'ended_at': null,
        'end_reason': null,
        'blocked_app_count': blockedAppCount,
        'interception_count': 0,
        'is_morning_protection': isMorningProtection ? 1 : 0,
        'synced': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Close a lock session and queue it for upload.
  ///
  /// Only uploaded on close: an open session is still changing, and uploading
  /// it repeatedly would spend the user's data to say "still locked".
  Future<void> closeLockSession({
    required String sessionId,
    required String endReason,
  }) async {
    final endedAt = DateTime.now().toUtc();

    await _database.update(
      'lock_sessions',
      {
        'ended_at': endedAt.millisecondsSinceEpoch,
        'end_reason': endReason,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );

    final rows = await _database.query(
      'lock_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final row = rows.first;
    await _queue.enqueue(
      entityType: SyncEntityType.lockSession,
      entityId: sessionId,
      operation: SyncOperation.create,
      payload: {
        'prayer': row['prayer'],
        'started_at': DateTime.fromMillisecondsSinceEpoch(
          row['started_at']! as int,
          isUtc: true,
        ).toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'end_reason': endReason,
        'blocked_app_count': row['blocked_app_count'],
        'interception_count': row['interception_count'],
        'is_morning_protection': (row['is_morning_protection'] as int) == 1,
      },
    );
  }

  /// The session left open by a crash or force-quit, if any.
  Future<Map<String, Object?>?> openLockSessionRow() async {
    final rows = await _database.query(
      'lock_sessions',
      where: 'ended_at IS NULL',
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> incrementInterceptions(String sessionId) async {
    await _database.rawUpdate(
      'UPDATE lock_sessions SET interception_count = interception_count + 1 '
      'WHERE id = ?',
      [sessionId],
    );
  }

  /// Record an emergency unlock, respecting the daily quota.
  ///
  /// Returns null when the quota is already spent. The unique constraint on
  /// (unlock_date, daily_sequence) is what makes a retried request idempotent
  /// rather than silently consuming a second unlock.
  Future<String?> recordEmergencyUnlock({
    required DateTime localDate,
    required int maxPerDay,
    String? lockSessionId,
    String? reason,
  }) async {
    final dateKey = _dateKey(localDate);

    final used = await countEmergencyUnlocks(localDate);
    if (used >= maxPerDay) return null;

    final sequence = used + 1;
    final id = '$dateKey:$sequence';
    final now = DateTime.now().toUtc();

    try {
      await _database.insert(
        'emergency_unlocks',
        {
          'id': id,
          'lock_session_id': lockSessionId,
          'unlock_date': dateKey,
          'daily_sequence': sequence,
          'reason': reason,
          'created_at': now.millisecondsSinceEpoch,
          'synced': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } on DatabaseException catch (error) {
      // Unique violation: a concurrent request already took this slot. Losing
      // the race must not grant a second unlock.
      if (error.isUniqueConstraintError()) return null;
      rethrow;
    }

    await _queue.enqueue(
      entityType: SyncEntityType.emergencyUnlock,
      entityId: id,
      operation: SyncOperation.create,
      payload: {
        'unlock_date': dateKey,
        'daily_sequence': sequence,
        'reason': reason,
        'created_at': now.toIso8601String(),
      },
    );

    return id;
  }

  Future<int> countEmergencyUnlocks(DateTime localDate) async {
    final result = await _database.rawQuery(
      'SELECT COUNT(*) AS count FROM emergency_unlocks WHERE unlock_date = ?',
      [_dateKey(localDate)],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  // -- Reads --------------------------------------------------------------

  /// How many recorded prayers were prayed joined with their neighbour.
  ///
  /// Read from the stored flag rather than from the current grouping setting,
  /// so the answer describes what the user actually did rather than what their
  /// settings say today.
  Future<CombinedPrayerCounts> combinedCounts({
    DateTime? from,
    DateTime? to,
  }) async {
    final clauses = <String>[];
    final args = <Object?>[];

    if (from != null) {
      clauses.add('prayer_date >= ?');
      args.add(_dateKey(from));
    }
    if (to != null) {
      clauses.add('prayer_date <= ?');
      args.add(_dateKey(to));
    }

    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';

    final rows = await _database.rawQuery(
      'SELECT was_combined, COUNT(*) AS count FROM prayer_history '
      '$where GROUP BY was_combined',
      args,
    );

    var combined = 0;
    var separate = 0;
    for (final row in rows) {
      final count = (row['count'] as int?) ?? 0;
      if ((row['was_combined'] as int? ?? 0) == 1) {
        combined += count;
      } else {
        separate += count;
      }
    }

    return CombinedPrayerCounts(combined: combined, separate: separate);
  }

  /// Every recorded Friday, most recent first.
  ///
  /// Selected by the stored `was_jumuah` flag *or* by the date falling on a
  /// Friday, so a Friday recorded while Smart Jumu'ah was switched off still
  /// appears in the history — it was a Friday whether or not the app treated it
  /// as a congregation.
  Future<List<FridayRecord>> fridayHistory({int limit = 260}) async {
    final rows = await _database.query(
      'prayer_history',
      where: 'prayer = ?',
      whereArgs: [PrayerName.dhuhr.wireValue],
      orderBy: 'prayer_date DESC',
      // Five years of Fridays. Beyond that the streak arithmetic is the same
      // and the query cost is not.
      limit: limit,
    );

    final records = <FridayRecord>[];
    for (final row in rows) {
      final date = DateTime.parse(row['prayer_date']! as String);
      final wasJumuah = (row['was_jumuah'] as int? ?? 0) == 1;

      if (!wasJumuah && date.weekday != DateTime.friday) continue;

      final blockSeconds = row['jumuah_block_seconds'] as int?;
      final delayMinutes = row['delay_minutes'] as int?;

      records.add(
        FridayRecord(
          date: date,
          status: PrayerStatus.fromWire(row['status']! as String),
          wasJumuah: wasJumuah,
          mosqueName: row['jumuah_mosque_name'] as String?,
          blockDuration:
              blockSeconds == null ? null : Duration(seconds: blockSeconds),
          verificationDelay:
              delayMinutes == null ? null : Duration(minutes: delayMinutes),
        ),
      );
    }

    return records;
  }

  /// Per-prayer completion and mean confirmation delay.
  ///
  /// `delay_minutes` is only populated for prayers that were actually
  /// confirmed, so the average is over completions rather than over everything
  /// — averaging in a missed prayer as a zero delay would flatter the number.
  Future<List<PrayerPerformance>> prayerPerformance() async {
    final rows = await _database.rawQuery('''
      SELECT prayer,
             SUM(CASE WHEN status IN ('completed', 'qaza_completed', 'late',
                                      'excused') THEN 1 ELSE 0 END) AS completed,
             SUM(CASE WHEN status = 'missed' THEN 1 ELSE 0 END) AS missed,
             AVG(CASE WHEN delay_minutes IS NOT NULL
                       AND status IN ('completed', 'qaza_completed')
                      THEN delay_minutes END) AS avg_delay
      FROM prayer_history
      GROUP BY prayer
    ''');

    return [
      for (final row in rows)
        PrayerPerformance(
          prayer: PrayerName.fromWire(row['prayer']! as String),
          completed: (row['completed'] as int?) ?? 0,
          missed: (row['missed'] as int?) ?? 0,
          averageDelay: row['avg_delay'] == null
              ? null
              : Duration(
                  minutes: (row['avg_delay']! as num).round(),
                ),
        ),
    ];
  }

  /// Mean time from a prayer beginning to the user confirming it.
  Future<Duration?> averageVerificationTime() async {
    final result = await _database.rawQuery('''
      SELECT AVG(delay_minutes) AS avg_delay
      FROM prayer_history
      WHERE delay_minutes IS NOT NULL
        AND status IN ('completed', 'qaza_completed')
    ''');

    final value = result.first['avg_delay'] as num?;
    return value == null ? null : Duration(minutes: value.round());
  }

  /// Tracked entries for a date, for merging into a recalculated schedule.
  Future<Map<PrayerName, PrayerStatus>> statusesForDate(DateTime date) async {
    final rows = await _database.query(
      'prayer_history',
      columns: ['prayer', 'status'],
      where: 'prayer_date = ?',
      whereArgs: [_dateKey(date)],
    );

    return {
      for (final row in rows)
        PrayerName.fromWire(row['prayer']! as String):
            PrayerStatus.fromWire(row['status']! as String),
    };
  }

  /// Daily summaries over a window, most recent last.
  Future<List<DailySummary>> dailySummaries({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _database.query(
      'prayer_history',
      columns: ['prayer_date', 'status'],
      where: 'prayer_date >= ? AND prayer_date <= ?',
      whereArgs: [_dateKey(from), _dateKey(to)],
      orderBy: 'prayer_date ASC',
    );

    final grouped = <String, List<PrayerStatus>>{};
    for (final row in rows) {
      final key = row['prayer_date']! as String;
      grouped
          .putIfAbsent(key, () => [])
          .add(PrayerStatus.fromWire(row['status']! as String));
    }

    return grouped.entries
        .map((entry) => DailySummary(
              date: DateTime.parse(entry.key),
              counts: PrayerCounts.fromStatuses(entry.value),
            ))
        .toList(growable: false);
  }

  /// Full statistics bundle for the dashboard.
  Future<PrayerStatistics> statistics({DateTime? today}) async {
    final anchor = today ?? DateTime.now();
    final todayDate = DateTime(anchor.year, anchor.month, anchor.day);

    final allRows = await _database.query(
      'prayer_history',
      columns: ['prayer_date', 'prayer', 'status'],
    );

    if (allRows.isEmpty) return const PrayerStatistics.empty();

    final byDate = <String, List<PrayerStatus>>{};
    final byPrayer = <PrayerName, List<PrayerStatus>>{};

    for (final row in allRows) {
      final status = PrayerStatus.fromWire(row['status']! as String);
      final prayer = PrayerName.fromWire(row['prayer']! as String);

      byDate.putIfAbsent(row['prayer_date']! as String, () => []).add(status);
      byPrayer.putIfAbsent(prayer, () => []).add(status);
    }

    final summaries = byDate.entries
        .map((entry) => DailySummary(
              date: DateTime.parse(entry.key),
              counts: PrayerCounts.fromStatuses(entry.value),
            ))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    PrayerCounts sumSince(DateTime start) => summaries
        .where((summary) => !summary.date.isBefore(start))
        .fold(const PrayerCounts(), (total, s) => total + s.counts);

    return PrayerStatistics(
      today: sumSince(todayDate),
      week: sumSince(todayDate.subtract(const Duration(days: 6))),
      month: sumSince(DateTime(todayDate.year, todayDate.month, 1)),
      year: sumSince(DateTime(todayDate.year, 1, 1)),
      allTime: summaries.fold(
        const PrayerCounts(),
        (total, s) => total + s.counts,
      ),
      streak: StreakCalculator.calculate(days: summaries, today: todayDate),
      // Reversed so the most recent day is first, which is the order the
      // charts and the history list both want.
      dailyHistory: summaries.reversed.toList(growable: false),
      byPrayer: {
        for (final entry in byPrayer.entries)
          entry.key: PrayerCounts.fromStatuses(entry.value),
      },
    );
  }

  /// Verification history, most recent first.
  Future<List<Map<String, Object?>>> verificationHistory({int limit = 50}) {
    return _database.query(
      'verifications',
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  /// Lock session history, most recent first.
  Future<List<Map<String, Object?>>> lockHistory({int limit = 50}) {
    return _database.query(
      'lock_sessions',
      orderBy: 'started_at DESC',
      limit: limit,
    );
  }

  /// Emergency unlock history, most recent first.
  Future<List<Map<String, Object?>>> emergencyUnlockHistory({int limit = 50}) {
    return _database.query(
      'emergency_unlocks',
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  /// Mark a record as uploaded.
  Future<void> markSynced(SyncEntityType type, String entityId) async {
    final table = switch (type) {
      SyncEntityType.prayerHistory => 'prayer_history',
      SyncEntityType.verification => 'verifications',
      SyncEntityType.lockSession => 'lock_sessions',
      SyncEntityType.emergencyUnlock => 'emergency_unlocks',
    };

    await _database.update(
      table,
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [entityId],
    );
  }

  @visibleForTesting
  Future<int> countPrayers() async {
    final result =
        await _database.rawQuery('SELECT COUNT(*) AS count FROM prayer_history');
    return (result.first['count'] as int?) ?? 0;
  }
}
