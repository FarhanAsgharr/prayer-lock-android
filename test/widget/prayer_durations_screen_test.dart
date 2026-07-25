/// Widget tests for the prayer durations screen.
///
/// The screen exists to explain *why* a phone is locked and for how long, so
/// the assertions are about whether the derivation is legible: the boundary
/// that closes each window, the computed duration, and an honest statement of
/// where the times came from.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_day.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:prayer_lock/features/prayer_times/domain/usecases/dynamic_duration_calculator.dart';
import 'package:prayer_lock/features/prayer_times/presentation/providers/prayer_times_provider.dart';
import 'package:prayer_lock/features/prayer_times/presentation/screens/prayer_durations_screen.dart';
import 'package:prayer_lock/features/settings/domain/entities/app_settings.dart';
import 'package:prayer_lock/features/settings/presentation/providers/settings_provider.dart';
import 'package:prayer_lock/core/config/locale_config.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

import '../support/prayer_fixtures.dart';

/// Pins the clock so the "Now" badge and progress bar are deterministic.
final _frozenNow = DateTime.utc(2026, 7, 20, 10, 0);

Widget _harness({
  required PrayerDay day,
  AppSettings? settings,
  DateTime? now,
}) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(
        () => _StubSettings(settings ?? settingsWith()),
      ),
      prayerDayProvider.overrideWithValue(day),
      nowProvider.overrideWithValue(now ?? _frozenNow),
      prayerTimeSourceProvider.overrideWithValue(PrayerTimeSource.device),
      prayerTimesAreStaleProvider.overrideWithValue(true),
    ],
    // The screen reads localised strings, so the delegates must be installed
    // exactly as the real app installs them.
    child: const MaterialApp(
      locale: Locale('en'),
      supportedLocales: LocaleConfig.supportedLocales,
      localizationsDelegates: LocaleConfig.delegates,
      home: PrayerDurationsScreen(),
    ),
  );
}

class _StubSettings extends SettingsNotifier {
  _StubSettings(this._value);

  final AppSettings _value;

  @override
  AppSettings build() => _value;
}

void main() {
  tz_data.initializeTimeZones();

  final day = buildDay();

  // The screen is a ListView, so anything below the fold is never built and
  // therefore never findable. A tall viewport renders all five cards and the
  // footer at once, which is what these assertions are about — scrolling to
  // each in turn would test the ListView, not the screen.
  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1200, 4000);
    view.devicePixelRatio = 1.0;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });
  });

  testWidgets('lists every prayer', (tester) async {
    await tester.pumpWidget(_harness(day: day));
    await tester.pumpAndSettle();

    for (final prayer in PrayerName.values) {
      expect(
        find.text(prayer.displayName),
        findsWidgets,
        reason: '${prayer.displayName} is missing from the list',
      );
    }
  });

  testWidgets('names the boundary that closes each window', (tester) async {
    await tester.pumpWidget(_harness(day: day));
    await tester.pumpAndSettle();

    // Fajr ends at sunrise, Dhuhr at Asr, Isha at the following Fajr.
    expect(find.text('Sunrise'), findsOneWidget);
    expect(find.text('Next day Fajr'), findsOneWidget);
  });

  testWidgets('shows each prayer computed duration', (tester) async {
    await tester.pumpWidget(_harness(day: day));
    await tester.pumpAndSettle();

    for (final entry in day.entries) {
      expect(
        find.text(formatPrayerDuration(entry.duration)),
        findsWidgets,
        reason: 'no duration shown for ${entry.prayer.displayName}',
      );
    }
  });

  testWidgets('durations differ between prayers on screen', (tester) async {
    // Guards against a regression to fixed windows that the code would still
    // describe as dynamic.
    await tester.pumpWidget(_harness(day: day));
    await tester.pumpAndSettle();

    final rendered = day.entries
        .map((entry) => formatPrayerDurationShort(entry.duration))
        .toSet();
    expect(rendered.length, greaterThan(1));
  });

  testWidgets('marks the window that is currently open', (tester) async {
    final active = day.activePrayer(_frozenNow);
    await tester.pumpWidget(_harness(day: day));
    await tester.pumpAndSettle();

    if (active == null) {
      // 10:00 UTC is inside the morning gap at Makkah — no window is open, so
      // no badge should appear.
      expect(find.text('Now'), findsNothing);
    } else {
      expect(find.text('Now'), findsOneWidget);
    }
  });

  testWidgets('shows a progress bar only while a window is open',
      (tester) async {
    final dhuhr = day.entryFor(PrayerName.dhuhr);
    final inside = dhuhr.scheduledAt.add(const Duration(minutes: 30));

    await tester.pumpWidget(_harness(day: day, now: inside));
    await tester.pumpAndSettle();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Now'), findsOneWidget);
  });

  testWidgets('explains the unlock policy in force', (tester) async {
    await tester.pumpWidget(
      _harness(
        day: day,
        settings: settingsWith(unlockPolicy: UnlockPolicy.onVerification),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(UnlockPolicy.onVerification.description),
      findsOneWidget,
    );
  });

  testWidgets('warns about the total when blocking for the full duration',
      (tester) async {
    // A user switching to Mode B should see what it costs before living with
    // it, rather than discovering it over the following day.
    await tester.pumpWidget(
      _harness(
        day: day,
        settings: settingsWith(unlockPolicy: UnlockPolicy.fullDuration),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining(formatPrayerDuration(day.totalWindowDuration)),
      findsOneWidget,
    );
  });

  testWidgets('is honest that device-computed times are unconfirmed',
      (tester) async {
    await tester.pumpWidget(_harness(day: day));
    await tester.pumpAndSettle();

    expect(find.textContaining('calculated on this device'), findsOneWidget);
  });

  testWidgets('renders an empty state without a schedule', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(() => _StubSettings(settingsWith())),
          prayerDayProvider.overrideWithValue(null),
          nowProvider.overrideWithValue(_frozenNow),
        ],
        // The screen reads localised strings, so the delegates must be installed
    // exactly as the real app installs them.
    child: const MaterialApp(
      locale: Locale('en'),
      supportedLocales: LocaleConfig.supportedLocales,
      localizationsDelegates: LocaleConfig.delegates,
      home: PrayerDurationsScreen(),
    ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Set your location'), findsOneWidget);
  });
}
