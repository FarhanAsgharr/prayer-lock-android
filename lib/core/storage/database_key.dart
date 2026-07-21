/// Database encryption key management.
///
/// The key is random, generated once on first launch, and stored in the
/// platform keystore. Two things it deliberately is *not*:
///
/// It is not derived from a device identifier. Device ids are readable by
/// other apps and are not secret, so a derived key would be reproducible by an
/// attacker holding the database file.
///
/// It is not a hardcoded constant. A key compiled into the binary is
/// extractable from any copy of the APK, which would make the encryption
/// decorative.
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract final class DatabaseKey {
  static const String _storageKey = 'db_encryption_key_v1';

  /// 256 bits, the key size SQLCipher uses.
  static const int _keyLengthBytes = 32;

  /// Fetch the existing key, or generate and persist one on first run.
  static Future<String> resolve({required FlutterSecureStorage storage}) async {
    const androidOptions = AndroidOptions(
      // Backs the key with the Android Keystore rather than shared
      // preferences, so it is not extractable even with root on most devices.
      encryptedSharedPreferences: true,
    );
    const iosOptions = IOSOptions(
      // Available only once the device has been unlocked since boot, and never
      // included in an iCloud or iTunes backup. The database is device-local
      // by design; a key that syncs to a backup would defeat that.
      accessibility: KeychainAccessibility.first_unlock_this_device,
    );

    final existing = await storage.read(
      key: _storageKey,
      aOptions: androidOptions,
      iOptions: iosOptions,
    );
    if (existing != null && existing.isNotEmpty) return existing;

    final generated = _generateKey();
    await storage.write(
      key: _storageKey,
      value: generated,
      aOptions: androidOptions,
      iOptions: iosOptions,
    );
    return generated;
  }

  /// Generate a base64 key from a cryptographically secure source.
  ///
  /// `Random.secure()` maps to the platform CSPRNG. `Random()` would be
  /// seeded predictably and is unusable for key material.
  static String _generateKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(
      _keyLengthBytes,
      (_) => random.nextInt(256),
    );
    return base64UrlEncode(bytes);
  }

  /// Erase the key, rendering the database permanently unreadable.
  ///
  /// Used by "delete my data": destroying the key is faster and more complete
  /// than overwriting rows, which SQLite may leave recoverable in free pages.
  static Future<void> destroy({required FlutterSecureStorage storage}) async {
    await storage.delete(key: _storageKey);
  }
}
