/// Shared setup for the end-to-end suites.
///
/// These tests run the real app on a real engine, which is the whole point:
/// they exercise what unit tests structurally cannot — the router, the
/// encrypted database, the method channels, and the app's own startup
/// sequence. What they must *not* do is touch the user's actual data or make
/// network calls, so every external edge is stubbed here in one place.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:prayer_lock/core/storage/app_database.dart';
import 'package:prayer_lock/core/storage/storage_providers.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:prayer_lock/features/sections/domain/entities/prayer_grouping.dart';
import 'package:prayer_lock/features/settings/data/repositories/settings_repository.dart';
import 'package:prayer_lock/features/settings/domain/entities/app_settings.dart';
import 'package:prayer_lock/features/settings/presentation/providers/settings_provider.dart';
import 'package:prayer_lock/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Lahore. A real location with a real timezone, so prayer times are plausible
/// and the DST-free zone keeps assertions stable year-round.
const testLocation = PrayerLocation(
  latitude: 31.5204,
  longitude: 74.3587,
  timezone: 'Asia/Karachi',
  label: 'Lahore',
  isAutoDetected: false,
);

/// Settings for a user who has finished onboarding.
///
/// Most suites are not testing onboarding, and making each of them walk through
/// four pages first would make every failure ambiguous — a broken assertion
/// three screens later reads as a broken dashboard.
AppSettings configured({
  PrayerGrouping grouping = PrayerGrouping.none,
  UnlockPolicy unlockPolicy = UnlockPolicy.onVerification,
  bool blockingEnabled = false,
  Set<String> blockedPackages = const {},
}) =>
    AppSettings(
      location: testLocation,
      onboardingComplete: true,
      prayerGroupingOverride: grouping,
      unlockPolicy: unlockPolicy,
      blockingEnabled: blockingEnabled,
      // The native mirror is only pushed when there is something to block, so a
      // suite testing the sync must select at least one app.
      blockedPackages: blockedPackages,
      // Off by default: the photo path needs a camera the test device may not
      // have, and every suite that wants it turns it on explicitly.
      requireAiVerification: false,
      // Local computation only. A test that reaches the network is a test that
      // fails when the network does, which teaches nobody anything.
      preferRemotePrayerTimes: false,
    );

/// A distinct database file per test, so suites cannot leak state into one
/// another when run together.
int _dbSequence = 0;

/// Opens a database in a temporary file, and deletes it afterwards.
///
/// A real SQLCipher database rather than a fake: the encryption, the schema
/// migrations and the foreign keys are among the things these tests exist to
/// exercise, and an in-memory substitute would skip all three.
///
/// The file name is unique per call. When every suite shared one path, a suite
/// that started before the previous one's async teardown had finished deleting
/// the file would open a handle the teardown then closed — the "database_closed"
/// failures that only appeared when the suites ran in one process.
Future<AppDatabase> openTestDatabase() async {
  final path = p.join(
    await getDatabasesPath(),
    'prayer_lock_integration_test_${_dbSequence++}.db',
  );
  await deleteDatabase(path);

  AppDatabase.resetForTesting();
  return AppDatabase.open(overridePath: path);
}

Future<void> closeTestDatabase(AppDatabase database) async {
  await database.close();
  AppDatabase.resetForTesting();
}

/// Stubs the Android blocking channel.
///
/// The real channel talks to a foreground service that cannot run under a test
/// harness. Recording the calls instead is more useful than letting them
/// through: what these tests need to assert is *that the app asked*, at the
/// right moment and with the right windows.
class RecordedChannel {
  final List<MethodCall> calls = [];

  static const _blocking = MethodChannel('com.prayerlock/blocking');
  static const _navigation = MethodChannel('com.prayerlock/navigation');
  static const _notifications =
      MethodChannel('dexterous.com/flutter/local_notifications');

  void install(WidgetTester tester) {
    void handle(MethodChannel channel, Object? Function(MethodCall) reply) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          calls.add(call);
          return reply(call);
        },
      );
    }

    handle(_blocking, (call) => switch (call.method) {
          'getPermissionStatus' => <String, bool>{
              'usageStats': true,
              'overlay': true,
              'batteryOptimisationIgnored': true,
            },
          'getInstalledApps' => <Map<String, String>>[
              {'packageName': 'com.example.social', 'appName': 'Social'},
              {'packageName': 'com.example.video', 'appName': 'Video'},
            ],
          'canSilence' => false,
          'hasAdhanSound' => false,
          'canScheduleExactAlarms' => true,
          'syncSchedule' => 0,
          'updateWidget' => 0,
          _ => true,
        });

    handle(_navigation, (_) => null);
    handle(_notifications, (call) => switch (call.method) {
          'pendingNotificationRequests' => <Map<String, Object?>>[],
          _ => true,
        });
  }

  void remove(WidgetTester tester) {
    for (final channel in [_blocking, _navigation, _notifications]) {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  }

  /// Every call made to one method, oldest first.
  List<MethodCall> of(String method) =>
      calls.where((call) => call.method == method).toList();

  bool called(String method) => of(method).isNotEmpty;
}

/// Launches the real app and waits for its first settled frame.
/// Loads the timezone database once, as the real `main()` does.
///
/// The harness builds `PrayerLockApp` directly rather than going through
/// `main()`, so the initialisation `main()` performs has to be repeated here or
/// the first notification schedule throws.
bool _timezonesReady = false;
void _ensureTimezones() {
  if (_timezonesReady) return;
  tz_data.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('UTC'));
  _timezonesReady = true;
}

Future<void> launchApp(
  WidgetTester tester, {
  required SharedPreferences preferences,
  required AppDatabase database,
}) async {
  _ensureTimezones();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        appDatabaseProvider.overrideWithValue(database),
      ],
      child: const PrayerLockApp(),
    ),
  );

  // Unmount at the end of the test. The orchestrator arms a real 30-second
  // periodic timer, and on the live integration binding a timer that is still
  // pending when the test ends leaves a frame scheduled — which trips the
  // binding's own "_pendingFrame == null" assertion in teardown. Replacing the
  // tree lets the ProviderScope dispose and cancel the timer first.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    // Let any in-flight orchestrator evaluation finish before the outer
    // tearDown closes the database out from under it.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
  });

  // The dashboard resolves a schedule on its first build, which is async.
  // pumpAndSettle would wait on the periodic timer forever, so pump discrete
  // frames — long enough for the first schedule to resolve and paint, using
  // runAsync so the real database and channel work completes.
  await tester.pump();
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Writes settings straight to preferences, bypassing the UI.
Future<SharedPreferences> preferencesWith(AppSettings settings) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  await SettingsRepository(preferences).save(settings);
  return preferences;
}

/// Scrolls until [finder] is on screen, or gives up quietly.
///
/// Settings is long enough that half its rows are off screen on a phone, and a
/// test that fails because a row was below the fold is a test about scrolling,
/// not about the thing it claims to check.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(Scrollable).first;
  for (var attempt = 0; attempt < 20; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.drag(scrollable, const Offset(0, -260));
    await tester.pump(const Duration(milliseconds: 120));
  }
}
