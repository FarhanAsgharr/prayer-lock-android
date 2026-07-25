/// Every screen, rendered in all three languages.
///
/// Translating strings is the visible half of localisation. The half that
/// actually breaks is layout: Arabic and Urdu flip every row, every
/// `EdgeInsets.only(left:)`, and every icon that points somewhere. A screen can
/// have perfect translations and still render with its back button on the wrong
/// side and its text running off the edge.
///
/// So these tests do not assert on wording. They render each screen under each
/// locale and assert that it builds without throwing and resolves to the
/// expected text direction — which is what catches a directional inset, a
/// missing delegate, or an overflow that only appears when a sentence gets
/// longer in translation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/core/config/locale_config.dart';
import 'package:prayer_lock/features/jumuah/presentation/screens/jumuah_settings_screen.dart';
import 'package:prayer_lock/features/jumuah/presentation/screens/mosque_editor_screen.dart';
import 'package:prayer_lock/features/sections/presentation/screens/islamic_section_screen.dart';
import 'package:prayer_lock/features/sections/presentation/screens/prayer_mode_screen.dart';
import 'package:prayer_lock/features/settings/presentation/screens/settings_screen.dart';
import 'package:prayer_lock/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_settings.dart';

void main() {
  // Screens read settings, so a container with real (empty) preferences stands
  // in for the app's own.
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  Widget harness(Widget screen, Locale locale) => ProviderScope(
        overrides: settingsOverrides(preferences),
        child: MaterialApp(
          locale: locale,
          supportedLocales: LocaleConfig.supportedLocales,
          localizationsDelegates: LocaleConfig.delegates,
          localeListResolutionCallback: LocaleConfig.resolve,
          home: screen,
        ),
      );

  final locales = {
    'English': (const Locale('en'), TextDirection.ltr),
    'Arabic': (const Locale('ar'), TextDirection.rtl),
    'Urdu': (const Locale('ur'), TextDirection.rtl),
  };

  final screens = <String, Widget Function()>{
    'Islamic section': () => const IslamicSectionScreen(),
    'Prayer mode': () => const PrayerModeScreen(),
    'Settings': () => const SettingsScreen(),
    'Jumu\'ah settings': () => const JumuahSettingsScreen(),
    'Mosque editor': () => const MosqueEditorScreen(),
  };

  for (final screen in screens.entries) {
    for (final locale in locales.entries) {
      final (code, direction) = locale.value;

      testWidgets('${screen.key} renders in ${locale.key}', (tester) async {
        // A phone-sized surface: overflow is a function of width, and the
        // default 800x600 test window is wider than any phone.
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(harness(screen.value(), code));
        await tester.pumpAndSettle();

        // Overflow is reported as an exception, so this catches a layout that
        // only breaks once a sentence gets longer in translation — which is
        // how a screen that looks fine in English ships broken in Urdu.
        expect(tester.takeException(), isNull);

        // The delegates resolved, and resolved to the right direction. Without
        // GlobalWidgetsLocalizations this silently stays left-to-right while
        // showing Arabic text, which looks wrong in a way that is easy to miss
        // in a screenshot and impossible to miss on a phone.
        final context = tester.element(find.byType(Scaffold).first);
        expect(Directionality.of(context), direction);
      });
    }
  }

  testWidgets('a translated screen shows no untranslated placeholder braces',
      (tester) async {
    // A dropped ICU placeholder renders as a literal "{count}". The
    // completeness test catches this in the ARB; this catches a call site that
    // passes the wrong thing.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(const PrayerModeScreen(), const Locale('ar')));
    await tester.pumpAndSettle();

    final texts = find.byType(Text).evaluate().map((e) => (e.widget as Text).data);
    for (final text in texts) {
      if (text == null) continue;
      expect(
        RegExp(r'\{\w+\}').hasMatch(text),
        isFalse,
        reason: 'unresolved placeholder in "$text"',
      );
    }
  });

  test('English is the fallback for an unsupported language', () {
    // A user whose phone is in French should get English, not a crash and not
    // whichever locale happens to be first in the list.
    final resolved = LocaleConfig.resolve(
      [const Locale('fr')],
      LocaleConfig.supportedLocales,
    );
    expect(resolved, const Locale('en'));
  });

  test('every supported locale has a generated delegate', () {
    for (final locale in LocaleConfig.supportedLocales) {
      expect(
        AppLocalizations.delegate.isSupported(locale),
        isTrue,
        reason: '${locale.languageCode} has no generated class',
      );
    }
  });
}
