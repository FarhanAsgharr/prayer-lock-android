/// Riverpod wiring for the Jumu'ah feature.
///
/// The domain classes take their dependencies as constructor arguments and know
/// nothing about Riverpod; this file is the only place they meet it. That is
/// what lets [JumuahManager] be tested with an in-memory repository and a fixed
/// date, with no container and no overrides.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../blocking/data/datasources/blocking_platform_channel.dart';
import '../../../prayer_times/presentation/providers/prayer_times_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/repositories/jumuah_preference_repository.dart';
import '../../domain/entities/mosque_profile.dart';
import '../../domain/usecases/friday_detector.dart';
import '../../domain/usecases/jumuah_manager.dart';
import '../../domain/usecases/mosque_proximity_detector.dart';

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

/// Whether the app may change Do Not Disturb.
///
/// Notification-policy access is granted in system Settings, not by a runtime
/// dialog, so the answer changes while the app is backgrounded. Consumers
/// invalidate this on resume rather than caching it for the session — a stale
/// "no" would leave the user looking at a warning they had already resolved.
final silencePermissionProvider = FutureProvider<bool>(
  (ref) => BlockingPlatformChannel().canSilence(),
);

/// A single coarse position fix, taken only when a travel prompt could act on
/// it.
///
/// Guarded hard, because the cost of getting this wrong is a prayer app that
/// reads someone's location in the background. It resolves to null — without
/// ever touching the GPS — unless it is Friday, smart prompts are on, and the
/// user has saved coordinates for more than one mosque. On any other day the
/// answer could not change anything, so it is not asked for.
///
/// Permission is never *requested* here either: a location dialog appearing
/// unbidden on a Friday would be alarming. It uses the grant the user already
/// gave when setting their prayer location, and stays silent without one.
final _fridayPositionProvider = FutureProvider<MosqueCoordinates?>((ref) async {
  final jumuah = ref.watch(settingsProvider).jumuah;
  if (!jumuah.enabled || !jumuah.smartLocationPrompts) return null;

  if (!FridayDetector.isFriday(ref.watch(localDateProvider))) return null;

  // Nothing to compare against, so nothing worth a fix.
  final located = jumuah.mosques.where((m) => m.coordinates != null);
  if (located.length < 2) return null;

  try {
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return null;
    }
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        // City-level is all this needs — the decision is measured in tens of
        // kilometres — and it is far cheaper and less invasive than a fix.
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return MosqueCoordinates(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  } catch (_) {
    // A timeout, a revoked permission, an emulator with no fix. Silence is the
    // right failure mode: the user keeps the mosque they chose.
    return null;
  }
});

/// The mosque to offer instead of the selected one, or null to stay quiet.
final mosqueSuggestionProvider = Provider<MosqueSuggestion?>((ref) {
  final jumuah = ref.watch(settingsProvider).jumuah;
  final position = ref.watch(_fridayPositionProvider).valueOrNull;

  return MosqueProximityDetector.suggestionFor(
    mosques: jumuah.mosques,
    selectedMosqueId: jumuah.activeMosque?.id,
    currentPosition: position,
    smartPromptsEnabled: jumuah.smartLocationPrompts,
  );
});
