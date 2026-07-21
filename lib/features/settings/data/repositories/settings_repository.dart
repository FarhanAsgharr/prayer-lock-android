/// Local persistence for user settings.
///
/// SharedPreferences rather than the encrypted database: these are
/// preferences, not secrets, and they must be readable synchronously at
/// startup to compute the first schedule without a visible loading state.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/app_settings.dart';

class SettingsRepository {
  SettingsRepository(this._preferences);

  static const String _settingsKey = 'app_settings_v1';

  final SharedPreferences _preferences;

  static Future<SettingsRepository> create() async =>
      SettingsRepository(await SharedPreferences.getInstance());

  AppSettings load() {
    final raw = _preferences.getString(_settingsKey);
    if (raw == null) return const AppSettings();

    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      // Corrupt or from an incompatible older version. Falling back to
      // defaults keeps the app usable; throwing here would brick startup and
      // leave the user with no way to recover short of reinstalling.
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    await _preferences.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  Future<void> clear() async {
    await _preferences.remove(_settingsKey);
  }
}
