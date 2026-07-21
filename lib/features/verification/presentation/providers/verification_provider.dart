/// Verification service wiring.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../prayer_times/domain/entities/prayer_enums.dart';
import '../../data/repositories/verification_repository.dart';
import '../../domain/entities/verification_result.dart';

final verificationServiceProvider = Provider<VerificationService>(
  (ref) => VerificationService(VerificationRepository()),
);

/// Coordinates a verification attempt.
///
/// Sits between the camera screen and the network layer so the screen never
/// has to reason about connectivity, retries or fallback policy.
class VerificationService {
  VerificationService(this._repository);

  final VerificationRepository _repository;

  Future<VerificationResult> verify({
    required PrayerName prayer,
    required String imageBase64,
  }) async {
    return _repository.submit(prayer: prayer, imageBase64: imageBase64);
  }
}
