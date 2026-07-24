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
  // v2 added the qaza columns (verification_deadline, qaza_deadline,
  // qaza_completed_at) for the on-time / qaza / missed model.
  // v3 added prayer_schedules (the offline cache of fetched/computed days) and
  // qaza_records (the ledger of outstanding make-up prayers) for dynamic
  // prayer-duration blocking.
  // v4 added prayer_history.was_combined, so a prayer logged while Dhuhr and
  // Asr were joined stays identifiable as such after the user changes mode.
  // v5 added the Jumu'ah columns, so a Friday Dhuhr row records that it was a
  // congregation, which mosque, and how long apps were blocked for it.
  static const int _schemaVersion = 5;

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
        -- End of the on-time window (scheduled_at + 30m) and of the qaza
        -- window (scheduled_at + 90m). Stored so history stays interpretable
        -- even if the window durations change in a later version.
        verification_deadline INTEGER,
        qaza_deadline INTEGER,
        started_at INTEGER,
        completed_at INTEGER,
        -- When the prayer was verified as qaza (make-up), distinct from the
        -- on-time completed_at.
        qaza_completed_at INTEGER,
        delay_minutes INTEGER,
        excuse_reason TEXT,
        -- Whether this prayer was joined with its neighbour when it was
        -- recorded. Stored rather than derived from the current setting, so a
        -- user who switches modes does not retroactively rewrite their own
        -- history into something that never happened.
        was_combined INTEGER NOT NULL DEFAULT 0,
        -- Jumu'ah. A Friday Dhuhr row is still a Dhuhr row — same prayer, same
        -- contribution to statistics and the streak — but these record that it
        -- was prayed as a congregation, at which mosque, and how long apps were
        -- blocked. Stored rather than derived from the weekday, because the
        -- user can switch mosques or disable the feature and history must keep
        -- describing what actually happened.
        was_jumuah INTEGER NOT NULL DEFAULT 0,
        jumuah_location TEXT,
        jumuah_block_seconds INTEGER,
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

    await _createScheduleTables(db);
  }

  /// Tables introduced in v3 for dynamic prayer-duration blocking.
  ///
  /// Factored out because a fresh install creates them from here and an
  /// upgrading install creates them from the migration; two hand-kept copies of
  /// the same DDL is how the schema of a new install drifts from an upgraded one.
  static Future<void> _createScheduleTables(Database db) async {
    // --- Cached prayer schedules ------------------------------------------
    //
    // The offline spine. One row per (date, location, method): a user who
    // travels or changes method gets a distinct row rather than a silently
    // wrong one served from cache.
    //
    // Instants are stored as epoch milliseconds in UTC. Storing local wall
    // clock would make every DST transition a data-migration problem.
    //
    // Coordinates are rounded into the key rather than stored raw, because a
    // few metres of GPS jitter must not miss the cache and force a refetch —
    // prayer times do not measurably change over such distances.
    await db.execute('''
      CREATE TABLE prayer_schedules (
        id TEXT PRIMARY KEY,
        prayer_date TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        location_key TEXT NOT NULL,
        timezone TEXT NOT NULL,
        method TEXT NOT NULL,
        madhab TEXT NOT NULL,
        high_latitude_rule TEXT NOT NULL,
        city TEXT,
        country TEXT,
        fajr INTEGER NOT NULL,
        sunrise INTEGER NOT NULL,
        dhuhr INTEGER NOT NULL,
        asr INTEGER NOT NULL,
        maghrib INTEGER NOT NULL,
        isha INTEGER NOT NULL,
        -- Denormalised durations in minutes. Derivable from the instants
        -- above, but stored so the native scheduler and the widget layer can
        -- read a schedule without linking the calculator.
        fajr_duration_minutes INTEGER,
        dhuhr_duration_minutes INTEGER,
        asr_duration_minutes INTEGER,
        maghrib_duration_minutes INTEGER,
        isha_duration_minutes INTEGER,
        -- The following day's Fajr, which closes the Isha window.
        next_day_fajr INTEGER,
        source TEXT NOT NULL,
        fetched_at INTEGER NOT NULL,
        UNIQUE (prayer_date, location_key, method, madhab, high_latitude_rule)
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_schedules_date ON prayer_schedules (prayer_date)',
    );
    // The eviction sweep orders by age.
    await db.execute(
      'CREATE INDEX idx_schedules_fetched ON prayer_schedules (fetched_at)',
    );

    // --- Qaza ledger -------------------------------------------------------
    //
    // A prayer whose window closed unfulfilled becomes a debt that outlives the
    // day it was incurred. Kept separate from prayer_history because history
    // records what happened on a date, whereas this records what is still owed
    // — the same prayer appears in both, with different lifetimes.
    await db.execute('''
      CREATE TABLE qaza_records (
        id TEXT PRIMARY KEY,
        prayer_date TEXT NOT NULL,
        prayer TEXT NOT NULL,
        scheduled_at INTEGER NOT NULL,
        window_ended_at INTEGER NOT NULL,
        completed_at INTEGER,
        created_at INTEGER NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0,
        UNIQUE (prayer_date, prayer)
      )
    ''');

    // The qaza screen asks only for outstanding debts, which are a small
    // fraction of all rows once the app has been used for a while.
    await db.execute(
      'CREATE INDEX idx_qaza_outstanding ON qaza_records (completed_at) '
      'WHERE completed_at IS NULL',
    );
  }

  /// Migrations.
  ///
  /// A fresh install runs `_createSchema` at the current version and never
  /// enters this. This upgrades a database created by an earlier app version.
  static Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    for (var version = oldVersion + 1; version <= newVersion; version++) {
      switch (version) {
        case 2:
          // Add the qaza columns to an existing v1 prayer_history table. They
          // are nullable, so rows written before this migration remain valid;
          // their windows are recomputed on read from scheduled_at when needed.
          await db.execute(
            'ALTER TABLE prayer_history ADD COLUMN verification_deadline INTEGER',
          );
          await db.execute(
            'ALTER TABLE prayer_history ADD COLUMN qaza_deadline INTEGER',
          );
          await db.execute(
            'ALTER TABLE prayer_history ADD COLUMN qaza_completed_at INTEGER',
          );
        case 3:
          // Two new tables only — nothing existing is rewritten, so an upgrade
          // cannot lose prayer history. The cache starts empty and refills on
          // the next refresh; the qaza ledger backfills from prayer_history so
          // prayers already recorded as missed appear as outstanding debts
          // rather than vanishing.
          await _createScheduleTables(db);
          await db.execute('''
            INSERT OR IGNORE INTO qaza_records (
              id, prayer_date, prayer, scheduled_at, window_ended_at,
              completed_at, created_at, synced
            )
            SELECT
              id, prayer_date, prayer, scheduled_at, window_ends_at,
              NULL, updated_at, 0
            FROM prayer_history
            WHERE status = 'missed'
          ''');
        case 4:
          // Defaults to 0: every prayer recorded before this column existed
          // was recorded under the five-separate-prayers model, which is
          // exactly what 0 means.
          await db.execute(
            'ALTER TABLE prayer_history '
            'ADD COLUMN was_combined INTEGER NOT NULL DEFAULT 0',
          );
        case 5:
          // Additive and nullable/defaulted: every prayer recorded before this
          // column existed was recorded without Jumu'ah tracking, which is
          // exactly what 0 and NULL mean.
          await db.execute(
            'ALTER TABLE prayer_history '
            'ADD COLUMN was_jumuah INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE prayer_history ADD COLUMN jumuah_location TEXT',
          );
          await db.execute(
            'ALTER TABLE prayer_history ADD COLUMN jumuah_block_seconds INTEGER',
          );
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
        'qaza_records',
        'prayer_schedules',
      ]) {
        await txn.delete(table);
      }
    });
  }

  /// Resets the cached instance. Tests only.
  static void resetForTesting() => _instance = null;
}
