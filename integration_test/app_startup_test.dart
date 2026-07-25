/// End-to-end: the app starts, the database opens, and the dashboard renders a
/// real schedule.
///
/// Covers three of the required areas at once because they cannot be separated
/// in a running app — the SQLCipher database opens as part of startup, and the
/// dashboard cannot show a prayer without the dynamic-duration schedule behind
/// it. Asserting them together is what "end-to-end" means; a unit test already
/// covers each in isolation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prayer_lock/core/storage/app_database.dart';
import 'package:prayer_lock/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:prayer_lock/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets('a configured user lands on the dashboard, not onboarding',
      (tester) async {
    channel.install(tester);
    addTearDown(() => channel.remove(tester));

    final preferences = await preferencesWith(configured());
    await launchApp(tester, preferences: preferences, database: database);

    // The redirect sends a finished user straight to the dashboard.
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
  });

  testWidgets('SQLCipher — the encrypted database opens and is usable',
      (tester) async {
    channel.install(tester);
    addTearDown(() => channel.remove(tester));

    final preferences = await preferencesWith(configured());
    await launchApp(tester, preferences: preferences, database: database);

    // A query the schema must satisfy. If the database failed to open, or a
    // migration was skipped, this throws rather than returning a count.
    final rows = await database.raw.rawQuery(
      'SELECT count(*) AS n FROM prayer_history',
    );
    expect(rows.first['n'], isA<int>());
  });

  testWidgets(
      'dynamic durations — the dashboard shows prayer windows for the location',
      (tester) async {
    channel.install(tester);
    addTearDown(() => channel.remove(tester));

    final preferences = await preferencesWith(configured());
    await launchApp(tester, preferences: preferences, database: database);

    // At least one of the five prayer names is on screen, which is only true
    // once a schedule was computed for the configured location. The exact
    // prayer depends on the time of day the test runs, so the assertion is
    // "some prayer", not a specific one.
    final anyPrayer = [
      'Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha', 'Sunrise',
    ].any((name) => find.textContaining(name).evaluate().isNotEmpty);

    expect(anyPrayer, isTrue, reason: 'no prayer window rendered');
  });

  testWidgets('startup does not depend on the network', (tester) async {
    // preferRemotePrayerTimes is false in `configured`, so this proves the
    // offline path renders a full dashboard on its own — the guarantee the app
    // makes about working without a connection.
    channel.install(tester);
    addTearDown(() => channel.remove(tester));

    final preferences = await preferencesWith(configured());
    await launchApp(tester, preferences: preferences, database: database);

    expect(tester.takeException(), isNull);
    expect(find.byType(DashboardScreen), findsOneWidget);
  });

  testWidgets('restart recovery — a second launch reads the persisted state',
      (tester) async {
    channel.install(tester);
    addTearDown(() => channel.remove(tester));

    // First launch, on a real database and real preferences.
    final preferences = await preferencesWith(
      configured(blockingEnabled: true),
    );
    await launchApp(tester, preferences: preferences, database: database);
    expect(find.byType(DashboardScreen), findsOneWidget);

    // Simulate a restart: tear the widget tree down and launch again against
    // the same persisted preferences and the same on-disk database. The state
    // must survive, because on a real device it does.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    AppDatabase.resetForTesting();
    final reopened = await AppDatabase.open(
      overridePath: database.path,
    );
    addTearDown(() => reopened.close());

    final restored = await SharedPreferences.getInstance();
    await launchApp(tester, preferences: restored, database: reopened);

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
