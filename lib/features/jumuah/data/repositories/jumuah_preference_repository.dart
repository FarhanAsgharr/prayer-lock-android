/// Persistence for the user's Jumu'ah preference.
///
/// Thin by design. The preference is four small values and it must survive a
/// reboot, so it rides on the same encrypted-at-rest preferences store as the
/// rest of the settings rather than earning its own database table. What this
/// class buys is a *seam*: the Jumu'ah feature depends on this interface, not
/// on `SharedPreferences` or on `AppSettings`, so the storage can move — to the
/// SQLCipher database, to a synced backend — without touching the manager, the
/// scheduler, or any screen.
///
/// It is also what makes the memory requirement testable without a device:
/// "remember where I pray and use it every Friday" is asserted against an
/// in-memory implementation of this interface.
library;

import '../../../settings/domain/entities/app_settings.dart';
import '../../domain/entities/jumuah_settings.dart';

/// Reads and writes the Jumu'ah preference.
abstract interface class JumuahPreferenceRepository {
  /// The stored preference. Never null — an unconfigured install returns
  /// defaults with no location chosen, which is what triggers the prompt.
  JumuahSettings read();

  Future<void> write(JumuahSettings settings);
}

/// The production implementation, backed by the app's settings store.
class SettingsJumuahPreferenceRepository
    implements JumuahPreferenceRepository {
  SettingsJumuahPreferenceRepository({
    required AppSettings Function() readSettings,
    required Future<void> Function(JumuahSettings) writeSettings,
  })  : _readSettings = readSettings,
        _writeSettings = writeSettings;

  final AppSettings Function() _readSettings;
  final Future<void> Function(JumuahSettings) _writeSettings;

  @override
  JumuahSettings read() => _readSettings().jumuah;

  @override
  Future<void> write(JumuahSettings settings) => _writeSettings(settings);
}

/// In-memory implementation for tests and previews.
class InMemoryJumuahPreferenceRepository
    implements JumuahPreferenceRepository {
  InMemoryJumuahPreferenceRepository([JumuahSettings? initial])
      : _settings = initial ?? const JumuahSettings();

  JumuahSettings _settings;

  /// How many times a write has happened, so a test can assert that choosing a
  /// location is persisted once rather than on every Friday.
  int writeCount = 0;

  @override
  JumuahSettings read() => _settings;

  @override
  Future<void> write(JumuahSettings settings) async {
    _settings = settings;
    writeCount++;
  }
}
