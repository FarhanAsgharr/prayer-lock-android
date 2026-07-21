/// Durable outbound sync queue.
///
/// Every record the user creates offline — a completed prayer, a verification,
/// a lock session, an emergency unlock — is written locally first and enqueued
/// here. The queue survives app kills and reboots because it lives in the
/// encrypted database, not in memory.
///
/// The guiding rule is that **no user data is ever lost**. A failed upload is
/// retried, not discarded. An item is only removed once the server has
/// acknowledged it, or once it is proven permanently unacceptable (a 4xx that
/// retrying cannot fix), and even then the local record remains intact — only
/// the *upload* is abandoned, never the data.
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// What kind of record an item carries.
enum SyncEntityType {
  prayerHistory('prayer_history'),
  verification('verification'),
  lockSession('lock_session'),
  emergencyUnlock('emergency_unlock');

  const SyncEntityType(this.wireValue);
  final String wireValue;

  static SyncEntityType fromWire(String value) =>
      SyncEntityType.values.firstWhere((type) => type.wireValue == value);
}

enum SyncOperation {
  create('create'),
  update('update');

  const SyncOperation(this.wireValue);
  final String wireValue;

  static SyncOperation fromWire(String value) =>
      SyncOperation.values.firstWhere((op) => op.wireValue == value);
}

@immutable
class SyncQueueItem {
  const SyncQueueItem({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.attempts,
    required this.nextAttemptAt,
    required this.createdAt,
    this.lastError,
  });

  final String id;
  final SyncEntityType entityType;
  final String entityId;
  final SyncOperation operation;
  final Map<String, dynamic> payload;
  final int attempts;
  final DateTime nextAttemptAt;
  final DateTime createdAt;
  final String? lastError;

  factory SyncQueueItem.fromRow(Map<String, Object?> row) => SyncQueueItem(
        id: row['id']! as String,
        entityType: SyncEntityType.fromWire(row['entity_type']! as String),
        entityId: row['entity_id']! as String,
        operation: SyncOperation.fromWire(row['operation']! as String),
        payload:
            jsonDecode(row['payload']! as String) as Map<String, dynamic>,
        attempts: row['attempts']! as int,
        nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(
          row['next_attempt_at']! as int,
          isUtc: true,
        ),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row['created_at']! as int,
          isUtc: true,
        ),
        lastError: row['last_error'] as String?,
      );
}

/// Outcome of attempting to upload one item.
enum SyncAttemptResult {
  /// Server accepted it. Remove from the queue.
  success,

  /// Transient failure — offline, timeout, 5xx. Retry later.
  retryable,

  /// Server rejected it permanently — malformed, or already superseded.
  /// Retrying cannot help, so stop trying. The local record is untouched.
  permanentFailure,
}

class SyncQueue {
  SyncQueue(this._database);

  final Database _database;

  /// Cap on retries before an item is parked.
  ///
  /// Parked items are not deleted; they remain queryable so a support case can
  /// see exactly what failed to upload rather than the data vanishing.
  static const int maxAttempts = 12;

  /// Enqueue a record for upload.
  ///
  /// Uses upsert on (entity_type, entity_id, operation). If a prayer is
  /// completed and then edited before the first upload succeeds, the queue
  /// should hold one item carrying the latest state — not two items racing to
  /// apply stale and fresh versions in an unpredictable order.
  Future<void> enqueue({
    required SyncEntityType entityType,
    required String entityId,
    required SyncOperation operation,
    required Map<String, dynamic> payload,
    DateTime? now,
  }) async {
    final timestamp = (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch;

    await _database.insert(
      'sync_queue',
      {
        'id': '${entityType.wireValue}:$entityId:${operation.wireValue}',
        'entity_type': entityType.wireValue,
        'entity_id': entityId,
        'operation': operation.wireValue,
        'payload': jsonEncode(payload),
        'attempts': 0,
        'next_attempt_at': timestamp,
        'created_at': timestamp,
        'last_error': null,
      },
      // Replace resets attempts and backoff, which is correct: fresh data
      // deserves a fresh attempt rather than inheriting an old item's penalty.
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Items due for an attempt, oldest first.
  Future<List<SyncQueueItem>> due({DateTime? now, int limit = 50}) async {
    final timestamp = (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch;

    final rows = await _database.query(
      'sync_queue',
      where: 'next_attempt_at <= ? AND attempts < ?',
      whereArgs: [timestamp, maxAttempts],
      orderBy: 'created_at ASC',
      limit: limit,
    );

    return rows.map(SyncQueueItem.fromRow).toList(growable: false);
  }

  /// Everything still queued, including parked items.
  Future<List<SyncQueueItem>> all() async {
    final rows = await _database.query('sync_queue', orderBy: 'created_at ASC');
    return rows.map(SyncQueueItem.fromRow).toList(growable: false);
  }

  Future<int> pendingCount() async {
    final result = await _database.rawQuery(
      'SELECT COUNT(*) AS count FROM sync_queue WHERE attempts < ?',
      [maxAttempts],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  /// Number of items that exhausted their retries and are awaiting attention.
  Future<int> parkedCount() async {
    final result = await _database.rawQuery(
      'SELECT COUNT(*) AS count FROM sync_queue WHERE attempts >= ?',
      [maxAttempts],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  /// Record the outcome of an attempt.
  Future<void> recordResult(
    SyncQueueItem item,
    SyncAttemptResult result, {
    String? error,
    DateTime? now,
  }) async {
    switch (result) {
      case SyncAttemptResult.success:
        await _database.delete(
          'sync_queue',
          where: 'id = ?',
          whereArgs: [item.id],
        );

      case SyncAttemptResult.permanentFailure:
        // Park immediately rather than burning eleven more attempts on
        // something the server has already refused.
        await _database.update(
          'sync_queue',
          {'attempts': maxAttempts, 'last_error': error},
          where: 'id = ?',
          whereArgs: [item.id],
        );

      case SyncAttemptResult.retryable:
        final attempts = item.attempts + 1;
        final delay = backoffFor(attempts);
        final nextAttempt = (now ?? DateTime.now().toUtc()).add(delay);

        await _database.update(
          'sync_queue',
          {
            'attempts': attempts,
            'next_attempt_at': nextAttempt.millisecondsSinceEpoch,
            'last_error': error,
          },
          where: 'id = ?',
          whereArgs: [item.id],
        );
    }
  }

  /// Exponential backoff with jitter, capped at six hours.
  ///
  /// Jitter matters at scale: without it, every device that lost connectivity
  /// during the same outage retries in lockstep and stampedes the server the
  /// moment it recovers.
  static Duration backoffFor(int attempts, {Random? random}) {
    const baseSeconds = 5;
    const maxSeconds = 6 * 60 * 60;

    // 5s, 10s, 20s, 40s ... capped.
    final exponential = baseSeconds * pow(2, (attempts - 1).clamp(0, 20));
    final capped = exponential.clamp(baseSeconds, maxSeconds).toInt();

    // Up to 25% jitter, always downward so the cap is never exceeded.
    final jitterSource = random ?? Random();
    final jitter = (capped * 0.25 * jitterSource.nextDouble()).toInt();

    return Duration(seconds: capped - jitter);
  }

  /// Re-arm parked items for another attempt.
  ///
  /// Offered to the user as an explicit "retry sync" action rather than run
  /// automatically: if twelve attempts failed, something is genuinely wrong,
  /// and silently looping forever would drain the battery without fixing it.
  Future<int> retryParked({DateTime? now}) async {
    final timestamp = (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch;

    return _database.update(
      'sync_queue',
      {'attempts': 0, 'next_attempt_at': timestamp, 'last_error': null},
      where: 'attempts >= ?',
      whereArgs: [maxAttempts],
    );
  }

  Future<void> clear() => _database.delete('sync_queue');
}
