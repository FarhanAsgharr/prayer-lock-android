/// Outcome of a verification attempt.
library;

import 'package:flutter/foundation.dart';

@immutable
class VerificationResult {
  const VerificationResult({
    required this.approved,
    required this.message,
    this.attemptNumber = 1,
    this.attemptsRemaining = 0,
    this.releasedWithoutDetection = false,
    this.isSuspectedReplay = false,
  });

  /// Whether apps should unlock.
  final bool approved;

  /// User-facing explanation. Always populated, including on success.
  final String message;

  final int attemptNumber;
  final int attemptsRemaining;

  /// True when the user was let through by the attempt limit, an offline
  /// fallback, or a provider outage rather than a positive detection.
  ///
  /// Surfaced so statistics stay honest and the UI can avoid claiming the
  /// prayer was "verified" when nothing was actually verified.
  final bool releasedWithoutDetection;

  final bool isSuspectedReplay;

  /// Approval when the verification service could not be reached.
  ///
  /// Failing open is deliberate: the user has already prayed, and holding
  /// their phone hostage because of our outage or their poor signal would be
  /// punishing them for our problem.
  factory VerificationResult.offlineApproval() => const VerificationResult(
        approved: true,
        message: 'Recorded. This will be confirmed when you are back online.',
        releasedWithoutDetection: true,
      );

  factory VerificationResult.rejected(String reason) => VerificationResult(
        approved: false,
        message: reason,
      );

  factory VerificationResult.approved() => const VerificationResult(
        approved: true,
        message: 'Prayer verified. Your apps are unlocked.',
      );
}
