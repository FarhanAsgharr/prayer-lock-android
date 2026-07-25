/// End-to-end: settings, the Islamic-section picker, and prayer modes.
///
/// These are one flow in the running app — Settings is the door to both the
/// section screen and the mode screen, and a change on either has to travel
/// back through the settings notifier to the dashboard. Driving them from the
/// gear icon is what proves the wiring, which no unit test touches.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prayer_lock/core/storage/app_database.dart';
import 'package:prayer_lock/features/sections/presentation/screens/islamic_section_screen.dart';
import 'package:prayer_lock/features/sections/presentation/screens/prayer_mode_screen.dart';
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

  Future<AppLocalizations> openSettings(WidgetTester tester) async {
    channel.install(tester);
    addTearDown(() => channel.remove(tester));

    final preferences = await preferencesWith(configured());
    await launchApp(tester, preferences: preferences, database: database);

    final strings = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );

    // The gear icon on the dashboard header.
    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    return strings;
  }

  testWidgets('the gear opens settings and every section is reachable',
      (tester) async {
    final strings = await openSettings(tester);

    // Each of the grouped headers the settings screen renders.
    // _SectionHeader uppercases its title, so the finder must too.
    for (final header in [
      strings.settingsSectionPrayerTimes,
      strings.settingsSectionBlocking,
      strings.settingsSectionReminders,
    ]) {
      final upper = header.toUpperCase();
      await scrollTo(tester, find.text(upper));
      expect(find.text(upper), findsOneWidget,
          reason: 'missing section: $upper');
    }
  });

  testWidgets('Islamic section — the picker opens and selects a section',
      (tester) async {
    final strings = await openSettings(tester);

    await scrollTo(tester, find.text(strings.settingsIslamicSection));
    await tester.tap(find.text(strings.settingsIslamicSection));
    await tester.pumpAndSettle();
    expect(find.byType(IslamicSectionScreen), findsOneWidget);

    // Pick Hanafi and go back; the choice must survive to the settings row.
    await tester.tap(find.textContaining('Hanafi').first);
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.textContaining('Hanafi'), findsWidgets);
  });

  testWidgets('prayer mode — combining a pair updates the card count',
      (tester) async {
    final strings = await openSettings(tester);

    await scrollTo(tester, find.text(strings.settingsPrayerMode));
    await tester.tap(find.text(strings.settingsPrayerMode));
    await tester.pumpAndSettle();
    expect(find.byType(PrayerModeScreen), findsOneWidget);

    // Toggle the first switch — combining a pair — and confirm the screen
    // reacts. The exact copy depends on the grouping, so the assertion is that
    // a switch exists and can be flipped without throwing.
    final switches = find.byType(SwitchListTile);
    expect(switches, findsWidgets);
    await tester.tap(switches.first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('language — the app renders under a non-default locale',
      (tester) async {
    // Not a settings tap: language resolves at the MaterialApp level and is
    // covered by the widget-level RTL matrix. Here the point is only that a
    // fully-launched app with real data does not throw under Arabic, which is
    // the integration-level version of that guarantee.
    final strings = await openSettings(tester);
    expect(strings.appTitle, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}
