/// Verification service wiring.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../prayer_times/domain/entities/prayer_enums.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/repositories/verification_repository.dart';
import '../../domain/entities/verification_result.dart';
import '../../domain/strategies/verification_strategy.dart';

/// The transport every photo strategy submits through.
final verificationGatewayProvider = Provider<VerificationGateway>(
  (ref) => VerificationRepository(),
);

/// The arrangements available.
///
/// A provider rather than a constant so a test — or a build that adds a mode,
/// such as a mosque-attendance check — substitutes the set at one point.
final verificationRegistryProvider = Provider<VerificationRegistry>(
  (ref) => VerificationRegistry.standard(ref.watch(verificationGatewayProvider)),
);

/// The strategy in force for the user's current preference.
///
/// Watched by the verification screen, which asks it whether a photograph is
/// needed instead of reading the settings flag directly. That indirection is
/// what lets a third mode be added without touching the screen.
final verificationStrategyProvider = Provider<VerificationStrategy>((ref) {
  final requirePhoto = ref.watch(settingsProvider).requireAiVerification;
  return ref
      .watch(verificationRegistryProvider)
      .forPreference(requirePhoto: requirePhoto);
});

final verificationServiceProvider = Provider<VerificationService>(
  (ref) => VerificationService(ref.watch(verificationStrategyProvider)),
);

/// Coordinates a verification attempt.
///
/// Sits between the camera screen and the strategy so the screen never has to
/// reason about connectivity, retries or fallback policy.
class VerificationService {
  VerificationService(this._strategy);

  final VerificationStrategy _strategy;

  /// What the current arrangement requires of the screen.
  VerificationStrategy get strategy => _strategy;

  Future<VerificationResult> verify({
    required PrayerName prayer,
    String? imageBase64,
  }) =>
      _strategy.verify(prayer: prayer, imageBase64: imageBase64);
}
