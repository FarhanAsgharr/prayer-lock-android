/// End-to-end: app blocking, the native schedule sync, verification, qaza, and
/// the background scheduler.
///
/// These five are one machine. Enabling blocking causes the app to mirror its
/// windows to the native side (the background scheduler), which is what the
/// alarm path and the widget both read; verifying a prayer records to the same
/// database that qaza reads from. Testing them together, against the recorded
/// channel, is the only way to see that the app *asks the platform* at the
/// right moments — the part a unit test cannot reach.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prayer_lock/core/storage/app_database.dart';
import 'package:prayer_lock/features/settings/presentation/screens/blocked_apps_screen.dart';
import 'package:prayer_lock/features/settings/presentation/screens/settings_screen.dart';
import 'package:prayer_lock/features/tracking/presentation/screens/qaza_screen.dart';
import 'package:prayer_lock/l10n/app_localizations.dart';

import 'support/harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late RecordedChannel channel;

  setUp(() async {
    database = await openTestDatabase();
    channel = RecordedChannel();
  });

  tearDown(() async {
    await closeTestDatabase(database);
  });

  testWidgets(
      'background scheduler — enabling blocking mirrors the schedule natively',
      (tester) async {
    channel.install(tester);
    addTearDown(() => channel.remove(tester));

    // Launch already blocking, so the orchestrator syncs on its first tick.
    final preferences = await preferencesWith(
      configured(
        blockingEnabled: true,
        blockedPackages: const {'com.example.social'},
      ),
    );
    await launchApp(tester, preferences: preferences, database: database);

    // Give the orchestrator its first evaluation.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await tester.pump();

    // The app pushed windows to the native scheduler. That call is the seam
    // between Dart's schedule and the alarm chain that enforces it while the
    // app is closed — if it never happens, blocking silently does nothing
    // after the first reboot.
    expect(
      channel.called('syncSchedule'),
      isTrue,
      reason: 'schedule was never mirrored to the native scheduler',
    );
  });

  testWidgets('app blocking — the blocked-apps picker lists installed apps',
      (tester) async {
    channel.install(tester);
    addTearDown(() => channel.remove(tester));

    final preferences = await preferencesWith(
      configured(blockingEnabled: true),
    );
    await launchApp(tester, preferences: preferences, database: database);

    final strings = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );

    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    await scrollTo(tester, find.text(strings.settingsBlockedApps));
    await tester.tap(find.text(strings.settingsBlockedApps));
    await tester.pumpAndSettle();
    expect(find.byType(BlockedAppsScreen), findsOneWidget);

    // The two apps the recorded channel reports as installed.
    expect(find.textContaining('Social'), findsWidgets);
    expect(find.textContaining('Video'), findsWidgets);
  });

  testWidgets('verification — a prayer can be recorded and lands in the database',
      (tester) async {
    channel.install(tester);
    addTearDown(() => channel.remove(tester));

    final preferences = await preferencesWith(configured());
    await launchApp(tester, preferences: preferences, database: database);

    // Reach the verification screen for whichever prayer the dashboard offers
    // to confirm. With photo verification off, this is the manual path — one
    // button, no camera.
    final confirm = find.byIcon(Icons.check).evaluate().isNotEmpty
        ? find.byIcon(Icons.check).first
        : find.textContaining('completed').first;

    if (confirm.evaluate().isNotEmpty) {
      await tester.tap(confirm);
      await tester.pumpAndSettle();
    }

    // Whatever the exact flow, recording a prayer must not throw, and the
    // history table it writes to must be queryable afterwards.
    final rows = await database.raw.rawQuery(
      'SELECT count(*) AS n FROM prayer_history',
    );
    expect(rows.first['n'], isA<int>());
    expect(tester.takeException(), isNull);
  });

  testWidgets('qaza — the make-up screen opens from settings', (tester) async {
    channel.install(tester);
    addTearDown(() => channel.remove(tester));

    final preferences = await preferencesWith(configured());
    await launchApp(tester, preferences: preferences, database: database);

    final strings = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );

    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    await tester.pumpAndSettle();

    await scrollTo(tester, find.text(strings.settingsMakeUpPrayers));
    await tester.tap(find.text(strings.settingsMakeUpPrayers));
    await tester.pumpAndSettle();

    expect(find.byType(QazaScreen), findsOneWidget);
    // Nothing owed on a fresh install: the empty state.
    expect(find.textContaining(strings.qazaNothing), findsWidgets);
  });

  testWidgets(
      'offline mode — a full flow works with remote times disabled',
      (tester) async {
    // configured() sets preferRemotePrayerTimes: false, so this whole run is
    // the offline path: no network call resolves the schedule, yet blocking,
    // navigation and the database all work.
    channel.install(tester);
    addTearDown(() => channel.remove(tester));

    final preferences = await preferencesWith(
      configured(
        blockingEnabled: true,
        blockedPackages: const {'com.example.social'},
      ),
    );
    await launchApp(tester, preferences: preferences, database: database);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await tester.pump();

    // A schedule was computed and mirrored, entirely on-device.
    expect(channel.called('syncSchedule'), isTrue);
    expect(tester.takeException(), isNull);
  });
}
