/// Riverpod wiring for the Jumu'ah feature.
///
/// The domain classes take their dependencies as constructor arguments and know
/// nothing about Riverpod; this file is the only place they meet it. That is
/// what lets [JumuahManager] be tested with an in-memory repository and a fixed
/// date, with no container and no overrides.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../prayer_times/presentation/providers/prayer_times_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/repositories/jumuah_preference_repository.dart';
import '../../domain/entities/mosque_profile.dart';
import '../../domain/usecases/jumuah_manager.dart';

/// Persistence for the Jumu'ah preference, on the app's settings store.
final jumuahPreferenceRepositoryProvider =
    Provider<JumuahPreferenceRepository>((ref) {
  return SettingsJumuahPreferenceRepository(
    // Read rather than watched: the manager asks at call time, so it always
    // sees current settings without this provider being rebuilt underneath it.
    readSettings: () => ref.read(settingsProvider),
    writeSettings: (jumuah) =>
        ref.read(settingsProvider.notifier).setJumuahSettings(jumuah),
  );
});

final jumuahManagerProvider = Provider<JumuahManager>(
  (ref) => JumuahManager(ref.watch(jumuahPreferenceRepositoryProvider)),
);

/// The Jumu'ah picture for the user's current local date.
///
/// Watches settings so toggling the feature, or choosing a location, re-renders
/// every dependent screen with no restart.
final jumuahStatusProvider = Provider<JumuahStatus>((ref) {
  // Depended on explicitly: JumuahManager reads settings rather than watching
  // them, so without this the status would not refresh when they change.
  ref.watch(settingsProvider);

  return ref
      .watch(jumuahManagerProvider)
      .statusFor(ref.watch(localDateProvider));
});

/// Whether today's Dhuhr slot is a Jumu'ah congregation.
final isJumuahTodayProvider = Provider<bool>(
  (ref) => ref.watch(jumuahStatusProvider).isActive,
);

/// Whether to show the "where will you pray today?" prompt.
final needsJumuahLocationProvider = Provider<bool>(
  (ref) => ref.watch(jumuahStatusProvider).needsLocationChoice,
);

/// The mosque governing today, or null when Jumu'ah is not in force.
final activeJumuahMosqueProvider = Provider<MosqueProfile?>(
  (ref) => ref.watch(jumuahStatusProvider).mosque,
);

/// Every mosque the user has, for the pickers.
final mosquesProvider = Provider<List<MosqueProfile>>(
  (ref) => ref.watch(jumuahManagerProvider).settings.mosques,
);
