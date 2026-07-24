/// Tests for language selection and right-to-left layout.
///
/// Two of the three supported languages are right-to-left, which is not a
/// styling detail: it flips every row and every directional inset. Flutter does
/// that automatically *provided* the localisation delegates are installed — so
/// the most valuable assertion here is that they are, and that Arabic and Urdu
/// actually resolve to RTL rather than rendering translated text in a
/// left-to-right layout.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/core/config/locale_config.dart';
import 'package:prayer_lock/l10n/app_localizations.dart';

Widget _app({Locale? locale, required Widget child}) => MaterialApp(
      locale: locale,
      supportedLocales: LocaleConfig.supportedLocales,
      localizationsDelegates: LocaleConfig.delegates,
      localeListResolutionCallback: LocaleConfig.resolve,
      home: child,
    );

void main() {
  group('supported languages', () {
    test('cover English, Arabic and Urdu', () {
      expect(
        LocaleConfig.supportedLocales.map((l) => l.languageCode),
        containsAll(['en', 'ar', 'ur']),
      );
    });

    test('every language names itself in its own script', () {
      // Someone looking for Urdu is looking for "اردو", not for "Urdu".
      expect(AppLanguage.arabic.displayName, 'العربية');
      expect(AppLanguage.urdu.displayName, 'اردو');
      expect(AppLanguage.english.displayName, 'English');
    });

    test('Arabic and Urdu are flagged right-to-left', () {
      expect(AppLanguage.arabic.isRightToLeft, isTrue);
      expect(AppLanguage.urdu.isRightToLeft, isTrue);
      expect(AppLanguage.english.isRightToLeft, isFalse);
    });

    test('the system option defers to the device', () {
      expect(AppLanguage.system.locale, isNull);
    });

    test('wire values round-trip', () {
      for (final language in AppLanguage.values) {
        expect(AppLanguage.fromWire(language.wireValue), language);
      }
      expect(AppLanguage.fromWire('klingon'), AppLanguage.system);
    });
  });

  group('locale resolution', () {
    test('matches a supported language', () {
      expect(
        LocaleConfig.resolve(
          [const Locale('ar', 'EG')],
          LocaleConfig.supportedLocales,
        ),
        const Locale('ar'),
      );
    });

    test('falls back to English rather than showing raw keys', () {
      expect(
        LocaleConfig.resolve(
          [const Locale('fr')],
          LocaleConfig.supportedLocales,
        ),
        const Locale('en'),
      );
    });

    test('honours the device preference order', () {
      // A device set to French then Urdu should get Urdu, not English.
      expect(
        LocaleConfig.resolve(
          [const Locale('fr'), const Locale('ur')],
          LocaleConfig.supportedLocales,
        ),
        const Locale('ur'),
      );
    });

    test('handles an absent device locale', () {
      expect(
        LocaleConfig.resolve(null, LocaleConfig.supportedLocales),
        const Locale('en'),
      );
    });
  });

  group('text direction', () {
    testWidgets('Arabic lays out right to left', (tester) async {
      late TextDirection direction;

      await tester.pumpWidget(
        _app(
          locale: const Locale('ar'),
          child: Builder(
            builder: (context) {
              direction = Directionality.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(direction, TextDirection.rtl);
    });

    testWidgets('Urdu lays out right to left', (tester) async {
      late TextDirection direction;

      await tester.pumpWidget(
        _app(
          locale: const Locale('ur'),
          child: Builder(
            builder: (context) {
              direction = Directionality.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(direction, TextDirection.rtl);
    });

    testWidgets('English lays out left to right', (tester) async {
      late TextDirection direction;

      await tester.pumpWidget(
        _app(
          locale: const Locale('en'),
          child: Builder(
            builder: (context) {
              direction = Directionality.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(direction, TextDirection.ltr);
    });
  });

  group('translations', () {
    testWidgets('prayer names are translated', (tester) async {
      for (final (locale, fajr) in [
        (const Locale('en'), 'Fajr'),
        (const Locale('ar'), 'الفجر'),
        (const Locale('ur'), 'فجر'),
      ]) {
        late AppLocalizations strings;

        await tester.pumpWidget(
          _app(
            locale: locale,
            child: Builder(
              builder: (context) {
                strings = AppLocalizations.of(context);
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(strings.prayerFajr, fajr);
      }
    });

    testWidgets('the section screen title is never "Madhab"', (tester) async {
      // The product requirement: the list includes movements and orientations
      // that are not schools of jurisprudence, so calling it "Madhab" would be
      // wrong as well as unwelcoming.
      late AppLocalizations strings;

      await tester.pumpWidget(
        _app(
          locale: const Locale('en'),
          child: Builder(
            builder: (context) {
              strings = AppLocalizations.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(strings.islamicSectionTitle.toLowerCase(), isNot(contains('madhab')));
    });

    testWidgets('every locale supplies every key', (tester) async {
      // A missing key falls back to English silently, so a half-translated
      // release looks fine in testing and wrong to the user.
      final samples = <Locale, List<String>>{};

      for (final locale in LocaleConfig.supportedLocales) {
        late AppLocalizations strings;

        await tester.pumpWidget(
          _app(
            locale: locale,
            child: Builder(
              builder: (context) {
                strings = AppLocalizations.of(context);
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        samples[locale] = [
          strings.prayerFajr,
          strings.prayerIsha,
          strings.islamicSectionTitle,
          strings.prayerModeTitle,
          strings.groupingBoth,
          strings.islamicSectionNotSet,
        ];
      }

      final english = samples[const Locale('en')]!;
      for (final locale in [const Locale('ar'), const Locale('ur')]) {
        final translated = samples[locale]!;
        for (var i = 0; i < english.length; i++) {
          expect(
            translated[i],
            isNot(english[i]),
            reason: '${locale.languageCode} falls back to English at index $i',
          );
        }
      }
    });

    testWidgets('the combined-pair format is shared across locales',
        (tester) async {
      // Prayer names differ; the "A + B" shape does not, and inventing a
      // different separator per locale would make the string untranslatable.
      late AppLocalizations strings;

      await tester.pumpWidget(
        _app(
          locale: const Locale('ar'),
          child: Builder(
            builder: (context) {
              strings = AppLocalizations.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(strings.combinedPair('الظهر', 'العصر'), 'الظهر + العصر');
    });
  });
}
