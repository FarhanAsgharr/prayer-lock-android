/// What it takes to discharge a prayer.
///
/// Two arrangements ship. One asks for a photograph and has it checked; the
/// other takes the user at their word. They are not a toggle on one code path —
/// they differ in what evidence is collected, what the screen looks like, how
/// many attempts are allowed, and what the record afterwards is allowed to
/// claim.
///
/// That last point is why this is a strategy rather than an `if`. A prayer
/// recorded after a photo check and one recorded by tapping a button are
/// different facts, and the statistics screen must not present them as the
/// same. When the distinction lives in a branch inside the camera screen, the
/// recording code has no way to know which happened; when it lives in an
/// object, the object carries it.
///
/// Failing open is deliberate throughout. The user has already prayed. Holding
/// their phone hostage because our service is down, their signal is poor, or
/// their camera is broken would be punishing them for our problem.
library;

import '../../../prayer_times/domain/entities/prayer_enums.dart';
import '../entities/verification_result.dart';

/// How a prayer is discharged.
enum VerificationMode {
  /// A photograph, checked by the verification service.
  aiPhoto('ai_photo'),

  /// The user's own confirmation, taken at face value.
  selfDeclared('self_declared');

  const VerificationMode(this.wireValue);

  final String wireValue;

  static VerificationMode fromWire(String value) =>
      VerificationMode.values.firstWhere(
        (mode) => mode.wireValue == value,
        // Self-declaration is the safe default for an unrecognised value: it
        // can never lock someone out of recording a prayer they performed.
        orElse: () => VerificationMode.selfDeclared,
      );
}

/// Submits evidence and reports the outcome.
///
/// The transport, injected so a strategy can be exercised without a network.
abstract interface class VerificationGateway {
  Future<VerificationResult> submit({
    required PrayerName prayer,
    required String imageBase64,
  });
}

/// One way of discharging a prayer.
abstract interface class VerificationStrategy {
  VerificationMode get mode;

  /// Whether the screen must capture a photograph before it can proceed.
  bool get requiresPhoto;

  /// How many failed attempts before the user is let through anyway.
  ///
  /// Finite on purpose. An unbounded retry loop turns a bad camera or an
  /// unusual prayer position into a phone the user cannot unlock, and there is
  /// no version of this app where that is the right outcome.
  int get maxAttempts;

  /// Whether a result from this strategy may be recorded as *verified*.
  ///
  /// False for self-declaration — the prayer is recorded, but the statistics
  /// must not claim anything was checked.
  bool get producesVerifiedRecord;

  /// Localisation key for what the screen asks the user to do.
  String get promptKey;

  /// Run one attempt.
  ///
  /// [imageBase64] is null for strategies that require no photograph.
  Future<VerificationResult> verify({
    required PrayerName prayer,
    String? imageBase64,
  });
}

/// A photograph, checked by the verification service.
class AiPhotoVerificationStrategy implements VerificationStrategy {
  const AiPhotoVerificationStrategy(this._gateway);

  final VerificationGateway _gateway;

  @override
  VerificationMode get mode => VerificationMode.aiPhoto;

  @override
  bool get requiresPhoto => true;

  @override
  int get maxAttempts => 3;

  @override
  bool get producesVerifiedRecord => true;

  @override
  String get promptKey => 'verifyPhotoPrompt';

  @override
  Future<VerificationResult> verify({
    required PrayerName prayer,
    String? imageBase64,
  }) async {
    // No image where one is required means the camera failed, not that the
    // user declined. Recording the prayer is the honest outcome; refusing it
    // would penalise them for a hardware fault.
    if (imageBase64 == null || imageBase64.isEmpty) {
      return VerificationResult.offlineApproval();
    }

    return _gateway.submit(prayer: prayer, imageBase64: imageBase64);
  }
}

/// The user's own confirmation.
///
/// Not a lesser mode. Many users want the structure of the block without being
/// photographed praying, which is a reasonable thing to want, and treating that
/// preference as second-class would be the wrong posture for this app.
class SelfDeclaredVerificationStrategy implements VerificationStrategy {
  const SelfDeclaredVerificationStrategy();

  @override
  VerificationMode get mode => VerificationMode.selfDeclared;

  @override
  bool get requiresPhoto => false;

  @override
  int get maxAttempts => 1;

  @override
  bool get producesVerifiedRecord => false;

  @override
  String get promptKey => 'verifyManualPrompt';

  @override
  Future<VerificationResult> verify({
    required PrayerName prayer,
    String? imageBase64,
  }) async =>
      const VerificationResult(
        approved: true,
        message: 'Recorded.',
        // Nothing was checked, and the record says so. The statistics screen
        // reads this rather than assuming every approval was a detection.
        releasedWithoutDetection: true,
      );
}

/// Resolves a mode to the strategy that applies it.
class VerificationRegistry {
  VerificationRegistry(Iterable<VerificationStrategy> strategies)
      : _strategies = {
          for (final strategy in strategies) strategy.mode: strategy,
        };

  /// The arrangements the app ships with.
  factory VerificationRegistry.standard(VerificationGateway gateway) =>
      VerificationRegistry([
        AiPhotoVerificationStrategy(gateway),
        const SelfDeclaredVerificationStrategy(),
      ]);

  final Map<VerificationMode, VerificationStrategy> _strategies;

  /// The strategy for [mode].
  ///
  /// Falls back to self-declaration. If a mode were ever unregistered, the
  /// failure that leaves a user able to record their prayer is the only
  /// acceptable one.
  VerificationStrategy forMode(VerificationMode mode) =>
      _strategies[mode] ?? const SelfDeclaredVerificationStrategy();

  /// The strategy matching the user's preference.
  ///
  /// Takes the boolean the settings screen writes rather than the enum, so
  /// existing stored settings need no migration and the enum stays the
  /// domain's own vocabulary.
  VerificationStrategy forPreference({required bool requirePhoto}) => forMode(
        requirePhoto ? VerificationMode.aiPhoto : VerificationMode.selfDeclared,
      );

  List<VerificationStrategy> get all => List.unmodifiable(_strategies.values);

  /// A copy with [strategy] replacing whatever answered for its mode.
  VerificationRegistry withStrategy(VerificationStrategy strategy) =>
      VerificationRegistry([
        ..._strategies.values.where((s) => s.mode != strategy.mode),
        strategy,
      ]);
}
