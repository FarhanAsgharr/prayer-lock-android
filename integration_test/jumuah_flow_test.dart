/// End-to-end: the Friday flow, and the analytics screen.
///
/// Jumu'ah settings, adding a mosque, and the analytics view all hang off the
/// running app's navigation, and all read the same real database. Grouped
/// because they share that setup and because they are the remaining
/// user-reachable screens the other suites do not visit.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prayer_lock/core/storage/app_database.dart';
import 'package:prayer_lock/features/dashboard/presentation/screens/analytics_screen.dart';
import 'package:prayer_lock/features/jumuah/presentation/screens/jumuah_settings_screen.dart';
import 'package:prayer_lock/features/jumuah/presentation/screens/mosque_editor_screen.dart';
import 'package:prayer_lock/features/settings/presentation/screens/settings_screen.dart';
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

  Future<AppLocalizations> launch(WidgetTester tester) async {
    channel.install(tester);
    addTearDown(() => channel.remove(tester));

    final preferences = await preferencesWith(configured());
    await launchApp(tester, preferences: preferences, database: database);
    return AppLocalizations.of(tester.element(find.byType(Scaffold).first));
  }

  testWidgets('Jumu\'ah workflow — settings open and a mosque can be added',
      (tester) async {
    final strings = await launch(tester);

    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    await scrollTo(tester, find.text(strings.settingsJumuah));
    await tester.tap(find.text(strings.settingsJumuah));
    await tester.pumpAndSettle();
    expect(find.byType(JumuahSettingsScreen), findsOneWidget);

    // The add-mosque FAB opens the editor.
    await tester.tap(find.byType(FloatingActionButton).first);
    await tester.pumpAndSettle();
    expect(find.byType(MosqueEditorScreen), findsOneWidget);

    // Name it, then save. The mosque must appear back on the settings screen.
    await tester.enterText(find.byType(TextField).first, 'Test Mosque');
    await tester.pump();

    await tester.tap(find.text(strings.actionSave));
    await tester.pumpAndSettle();

    expect(find.textContaining('Test Mosque'), findsWidgets);
  });

  testWidgets('analytics — the screen opens and renders without a crash',
      (tester) async {
    final strings = await launch(tester);

    // The bar-chart icon on the dashboard header.
    await tester.tap(find.byIcon(Icons.bar_chart_outlined).first);
    await tester.pumpAndSettle();

    expect(find.byType(AnalyticsScreen), findsOneWidget);
    // A fresh install has no history, so the empty state, not the chart.
    expect(find.textContaining(strings.analyticsTitle), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
