/// Encrypted local database.
///
/// Prayer history reveals a person's religion and their daily routine down to
/// the minute. On a lost or seized device that is genuinely sensitive, so the
/// database is encrypted at rest with SQLCipher rather than stored as a plain
/// file that any file manager with root can read.
///
/// The encryption key is generated once, at random, and held in the platform
/// keystore (Android Keychain / iOS Keychain) via flutter_secure_storage. It
/// is never derived from anything guessable and never leaves the device.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'database_key.dart';

class AppDatabase {
  AppDatabase._(this._database);

  final Database _database;

  Database get raw => _database;

  static const String _fileName = 'prayer_lock.db';
  static const int _schemaVersion = 1;

  static AppDatabase? _instance;

  /// Open (or create) the encrypted database.
  ///
  /// Cached: opening a SQLCipher database performs key derivation, which is
  /// deliberately slow, so doing it per query would be a visible stall.
  static Future<AppDatabase> open({
    FlutterSecureStorage? secureStorage,
    String? overridePath,
  }) async {
    final existing = _instance;
    if (existing != null) return existing;

    final key = await DatabaseKey.resolve(
      storage: secureStorage ?? const FlutterSecureStorage(),
    );

    final path = overridePath ?? p.join(await getDatabasesPath(), _fileName);

    final database = await openDatabase(
      path,
      password: key,
      version: _schemaVersion,
      onConfigure: (db) async {
        // Foreign keys are off by default in SQLite. Without this, the
        // cascade deletes below are silently ignored and orphan rows
        // accumulate.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );

    final instance = AppDatabase._(database);
    _instance = instance;
    return instance;
  }

  static Future<void> _createSchema(Database db, int version) async {
    // --- Prayer history -------------------------------------------------
    //
    // The local mirror of the backend's prayer_history table. `prayer_date`
    // is stored as an ISO date string rather than an epoch, because queries
    // group by local calendar day and epoch arithmetic across DST would
    // straddle day boundaries incorrectly.
    await db.execute('''
      CREATE TABLE prayer_history (
        id TEXT PRIMARY KEY,
        prayer_date TEXT NOT NULL,
        prayer TEXT NOT NULL,
        status TEXT NOT NULL,
        scheduled_at INTEGER NOT NULL,
        window_ends_at INTEGER NOT NULL,
        started_at INTEGER,
        completed_at INTEGER,
        delay_minutes INTEGER,
        excuse_reason TEXT,
        synced INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        UNIQUE (prayer_date, prayer)
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_history_date ON prayer_history (prayer_date)',
    );
    await db.execute(
      'CREATE INDEX idx_history_status ON prayer_history (status)',
    );
    // Partial index: the sync drain only ever asks for unsynced rows, and the
    // unsynced set is tiny compared to total history.
    await db.execute(
      'CREATE INDEX idx_history_unsynced ON prayer_history (synced) '
      'WHERE synced = 0',
    );

    // --- Verification attempts ------------------------------------------
    //
    // No image is ever stored, only the verdict. See the backend's
    // PrayerVerification model for the reasoning.
    await db.execute('''
      CREATE TABLE verifications (
        id TEXT PRIMARY KEY,
        prayer_history_id TEXT NOT NULL,
        status TEXT NOT NULL,
        approved INTEGER NOT NULL,
        attempt_number INTEGER NOT NULL,
        released_without_detection INTEGER NOT NULL DEFAULT 0,
        message TEXT,
        created_at INTEGER NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (prayer_history_id)
          REFERENCES prayer_history (id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_verifications_prayer '
      'ON verifications (prayer_history_id)',
    );

    // --- Lock sessions ---------------------------------------------------
    await db.execute('''
      CREATE TABLE lock_sessions (
        id TEXT PRIMARY KEY,
        prayer_history_id TEXT,
        prayer TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        end_reason TEXT,
        blocked_app_count INTEGER NOT NULL DEFAULT 0,
        interception_count INTEGER NOT NULL DEFAULT 0,
        is_morning_protection INTEGER NOT NULL DEFAULT 0,
        synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (prayer_history_id)
          REFERENCES prayer_history (id) ON DELETE SET NULL
      )
    ''');

    // Finds the open session, which the orchestrator checks on every resume.
    await db.execute(
      'CREATE INDEX idx_lock_open ON lock_sessions (ended_at) '
      'WHERE ended_at IS NULL',
    );

    // --- Emergency unlocks ------------------------------------------------
    //
    // unlock_date is the user's local calendar day, so the daily quota means
    // "one per day as the user experiences days", not one per UTC day.
    await db.execute('''
      CREATE TABLE emergency_unlocks (
        id TEXT PRIMARY KEY,
        lock_session_id TEXT,
        unlock_date TEXT NOT NULL,
        daily_sequence INTEGER NOT NULL,
        reason TEXT,
        created_at INTEGER NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0,
        UNIQUE (unlock_date, daily_sequence)
      )
    ''');

    // --- Outbound sync queue ----------------------------------------------
    //
    // A durable queue rather than an in-memory list: the whole point is to
    // survive an app kill, a reboot, and days without connectivity.
    await db.execute('''
      CREATE TABLE sync_queue (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        next_attempt_at INTEGER NOT NULL,
        last_error TEXT,
        created_at INTEGER NOT NULL,
        UNIQUE (entity_type, entity_id, operation)
      )
    ''');

    // Drain order: due items first.
    await db.execute(
      'CREATE INDEX idx_queue_due ON sync_queue (next_attempt_at)',
    );
  }

  /// Migrations.
  ///
  /// Empty at version 1 by definition. Kept as an explicit switch so the next
  /// schema change has an obvious home and cannot be bolted on ad hoc.
  static Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    for (var version = oldVersion + 1; version <= newVersion; version++) {
      switch (version) {
        case 1:
          await _createSchema(db, version);
        default:
          throw StateError(
            'No migration defined from schema v${version - 1} to v$version',
          );
      }
    }
  }

  Future<void> close() async {
    await _database.close();
    _instance = null;
  }

  /// Drop every row. Used by "delete my data" and by tests.
  Future<void> clear() async {
    await _database.transaction((txn) async {
      for (final table in [
        'sync_queue',
        'emergency_unlocks',
        'lock_sessions',
        'verifications',
        'prayer_history',
      ]) {
        await txn.delete(table);
      }
    });
  }

  /// Resets the cached instance. Tests only.
  static void resetForTesting() => _instance = null;
}
