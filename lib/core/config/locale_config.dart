/// Language and text direction.
///
/// Two of the three supported languages are right-to-left, which is not a
/// styling detail: it flips every row, every icon that implies direction, and
/// every padding that was written as "left". Flutter handles that automatically
/// *provided* the localisation delegates are installed and layouts use
/// directional insets rather than absolute ones — so the delegates are wired
/// here once, at the app root, rather than per screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../features/settings/presentation/providers/settings_provider.dart';

/// The languages the app ships translations for.
enum AppLanguage {
  /// Follow the device. The default: a user who has set their phone to Arabic
  /// should not have to set the app to Arabic as well.
  system('system', 'Match system', null),

  english('en', 'English', Locale('en')),
  arabic('ar', 'العربية', Locale('ar')),
  urdu('ur', 'اردو', Locale('ur'));

  const AppLanguage(this.wireValue, this.displayName, this.locale);

  final String wireValue;

  /// Shown in the language picker, in the language itself — a user looking for
  /// Urdu is looking for "اردو", not for "Urdu".
  final String displayName;

  /// Null for [system], which defers to the platform.
  final Locale? locale;

  static AppLanguage fromWire(String value) => AppLanguage.values.firstWhere(
        (language) => language.wireValue == value,
        orElse: () => AppLanguage.system,
      );

  /// Whether this language is written right to left.
  ///
  /// Reported for the settings preview; the framework resolves direction from
  /// the locale itself, so nothing branches on this to lay anything out.
  bool get isRightToLeft =>
      this == AppLanguage.arabic || this == AppLanguage.urdu;
}

/// The locale the app should render in, or null to follow the device.
final appLocaleProvider = Provider<Locale?>((ref) {
  return ref.watch(settingsProvider).language.locale;
});

abstract final class LocaleConfig {
  /// Locales the app claims to support.
  ///
  /// Order matters: Flutter picks the first supported locale that matches the
  /// device when no exact match exists, so English leads as the fallback.
  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('ar'),
    Locale('ur'),
  ];

  /// Delegates for the app's own strings and for the framework's.
  ///
  /// The three framework delegates are what localise Material and Cupertino
  /// widgets — date pickers, dialog buttons, semantics labels — and what makes
  /// `Directionality` resolve to RTL for Arabic and Urdu. Omitting them leaves
  /// a half-translated app that still lays out left to right.
  static const List<LocalizationsDelegate<Object>> delegates = [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  /// Resolve the locale to use, given the device's preferences.
  ///
  /// Falls back to English rather than to the device's first choice when
  /// nothing matches, so an unsupported language renders in a language the app
  /// actually has strings for instead of showing raw keys.
  static Locale resolve(
    List<Locale>? deviceLocales,
    Iterable<Locale> supported,
  ) {
    if (deviceLocales == null || deviceLocales.isEmpty) {
      return const Locale('en');
    }

    for (final device in deviceLocales) {
      for (final candidate in supported) {
        if (candidate.languageCode == device.languageCode) return candidate;
      }
    }

    return const Locale('en');
  }
}
