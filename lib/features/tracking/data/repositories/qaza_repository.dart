/// The ledger of outstanding make-up prayers.
///
/// A prayer whose window closed unfulfilled does not stop mattering when the
/// day ends. `prayer_history` records what happened on a date and is closed
/// once written; this records what is still *owed*, and stays open until the
/// user discharges it — possibly weeks later.
///
/// Keeping the two apart is what lets the app say "you have four prayers to make
/// up" without re-deriving that from the whole of history on every read, and
/// what lets a qaza completed in June clear a prayer missed in March.
library;

import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../prayer_times/domain/entities/prayer_day.dart';
import '../../../prayer_times/domain/entities/prayer_enums.dart';

/// One outstanding or discharged make-up prayer.
@immutable
class QazaRecord {
  const QazaRecord({
    required this.id,
    required this.date,
    required this.prayer,
    required this.scheduledAt,
    required this.windowEndedAt,
    required this.createdAt,
    this.completedAt,
  });

  final String id;

  /// The local calendar date the prayer belonged to.
  final DateTime date;

  final PrayerName prayer;
  final DateTime scheduledAt;

  /// When the prayer's own window closed — the moment the debt was incurred.
  final DateTime windowEndedAt;

  final DateTime createdAt;

  /// When the make-up prayer was performed, or null while still owed.
  final DateTime? completedAt;

  bool get isOutstanding => completedAt == null;

  /// How long the debt has been outstanding at [now].
  Duration ageAt(DateTime now) => now.difference(windowEndedAt);

  factory QazaRecord.fromRow(Map<String, Object?> row) {
    DateTime instant(String column) => DateTime.fromMillisecondsSinceEpoch(
          row[column]! as int,
          isUtc: true,
        );

    final completed = row['completed_at'] as int?;

    return QazaRecord(
      id: row['id']! as String,
      date: DateTime.parse(row['prayer_date']! as String),
      prayer: PrayerName.fromWire(row['prayer']! as String),
      scheduledAt: instant('scheduled_at'),
      windowEndedAt: instant('window_ended_at'),
      createdAt: instant('created_at'),
      completedAt: completed == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(completed, isUtc: true),
    );
  }
}

class QazaRepository {
  const QazaRepository(this._database);

  final Database _database;

  static const String _table = 'qaza_records';

  /// Deterministic row id, matching the prayer_history convention.
  ///
  /// Not random: the same missed prayer discovered twice — once by the
  /// reconciliation pass, once by the user opening the qaza screen — must
  /// collide and update rather than create a duplicate debt.
  static String recordId(DateTime date, PrayerName prayer) =>
      '${_dateKey(date)}:${prayer.wireValue}';

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Record a prayer whose window closed unfulfilled.
  ///
  /// Ignores the insert if a record already exists, so re-running the
  /// reconciliation pass cannot resurrect a debt the user has already cleared.
  Future<void> recordMissed({
    required DateTime date,
    required PrayerEntry entry,
  }) async {
    await _database.insert(
      _table,
      {
        'id': recordId(date, entry.prayer),
        'prayer_date': _dateKey(date),
        'prayer': entry.prayer.wireValue,
        'scheduled_at': entry.scheduledAt.millisecondsSinceEpoch,
        'window_ended_at': entry.windowEndsAt.millisecondsSinceEpoch,
        'completed_at': null,
        'created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
        'synced': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Mark a debt discharged.
  ///
  /// Returns false when no outstanding record matched — a double submission,
  /// or a debt already cleared on another device — so the caller can avoid
  /// telling the user they cleared something twice.
  Future<bool> markCompleted({
    required DateTime date,
    required PrayerName prayer,
    DateTime? at,
  }) async {
    final updated = await _database.update(
      _table,
      {
        'completed_at':
            (at ?? DateTime.now().toUtc()).millisecondsSinceEpoch,
        'synced': 0,
      },
      // The completed_at guard makes this idempotent: a retry after a dropped
      // response updates nothing rather than rewriting the completion time.
      where: 'id = ? AND completed_at IS NULL',
      whereArgs: [recordId(date, prayer)],
    );

    return updated > 0;
  }

  /// Outstanding debts, oldest first — the order they should be discharged in.
  Future<List<QazaRecord>> outstanding({int limit = 200}) async {
    final rows = await _database.query(
      _table,
      where: 'completed_at IS NULL',
      orderBy: 'scheduled_at ASC',
      limit: limit,
    );
    return rows.map(QazaRecord.fromRow).toList(growable: false);
  }

  Future<int> outstandingCount() async {
    final result = await _database.rawQuery(
      'SELECT COUNT(*) AS count FROM $_table WHERE completed_at IS NULL',
    );
    return (result.first['count'] as int?) ?? 0;
  }

  /// Outstanding debts grouped by prayer, for the "you owe 3 Fajr" summary.
  Future<Map<PrayerName, int>> outstandingByPrayer() async {
    final rows = await _database.rawQuery(
      'SELECT prayer, COUNT(*) AS count FROM $_table '
      'WHERE completed_at IS NULL GROUP BY prayer',
    );

    return {
      for (final row in rows)
        PrayerName.fromWire(row['prayer']! as String):
            (row['count'] as int?) ?? 0,
    };
  }

  /// Recently discharged debts, most recent first.
  Future<List<QazaRecord>> completed({int limit = 50}) async {
    final rows = await _database.query(
      _table,
      where: 'completed_at IS NOT NULL',
      orderBy: 'completed_at DESC',
      limit: limit,
    );
    return rows.map(QazaRecord.fromRow).toList(growable: false);
  }

  /// Whether a specific prayer on a specific date is still owed.
  Future<bool> isOutstanding(DateTime date, PrayerName prayer) async {
    final rows = await _database.query(
      _table,
      columns: ['id'],
      where: 'id = ? AND completed_at IS NULL',
      whereArgs: [recordId(date, prayer)],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
