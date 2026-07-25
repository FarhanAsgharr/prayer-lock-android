/// When a slot holds the lock, and until when.
///
/// Three arrangements ship, and they differ on one question: what ends a lock.
/// Verification, the window closing, or whichever happens first. That single
/// difference used to be an `if (unlockPolicy == fullDuration)` sitting in the
/// middle of [LockDecisionMaker], checked before the "is anything owed" path
/// for a reason that took a paragraph of comment to justify.
///
/// Pulling it into a strategy makes the reason structural instead of prose: a
/// policy that holds through verification is a different *object*, not a
/// branch, so it cannot be half-applied by a later edit to the surrounding
/// function.
///
/// What stays outside a strategy — deliberately — is everything that is not a
/// policy choice: emergency unlocks, exemptions, the grace period, morning
/// protection, and qaza. Those apply identically under all three arrangements,
/// and duplicating them into each implementation would be three places for the
/// emergency-unlock rule to drift, which is the one rule that must never fail.
library;

import '../../../prayer_times/domain/entities/prayer_enums.dart';
import '../../../prayer_times/domain/entities/prayer_slot.dart';
import '../entities/lock_reason.dart';

/// What a policy decides for one slot at one instant.
class BlockingVerdict {
  const BlockingVerdict({
    required this.shouldLock,
    required this.reason,
    this.lockUntil,
  });

  /// Nothing to enforce for this slot right now.
  const BlockingVerdict.open(this.reason)
      : shouldLock = false,
        lockUntil = null;

  final bool shouldLock;
  final LockReason reason;

  /// When the lock is expected to lift on its own, if it will.
  final DateTime? lockUntil;
}

/// One unlock arrangement.
abstract interface class BlockingStrategy {
  /// The policy this strategy answers for.
  UnlockPolicy get policy;

  /// Whether a slot already discharged still holds the lock.
  ///
  /// The whole difference between the three arrangements, exposed as a
  /// property because callers outside the decision — the native mirror, the
  /// settings preview — need the answer without running a decision.
  bool get holdsAfterVerification;

  /// Whether an *open* window holds the lock, and until when.
  ///
  /// Called only for the slot whose window contains `now`, and only after the
  /// universal exclusions have already been applied. Returning a verdict with
  /// `shouldLock: false` means this policy has nothing to say, and the ordinary
  /// "is anything owed" path continues.
  BlockingVerdict verdictFor({
    required PrayerSlot slot,
    required DateTime now,
  });
}

/// Mode A — the lock lifts the moment the prayer is verified.
///
/// The default. Under dynamic durations a Dhuhr window runs to Asr, which can
/// be three and a half hours; blocking for all of it by default would be a
/// surprise severe enough that most users would simply uninstall.
class VerificationUnlockStrategy implements BlockingStrategy {
  const VerificationUnlockStrategy();

  @override
  UnlockPolicy get policy => UnlockPolicy.onVerification;

  @override
  bool get holdsAfterVerification => false;

  @override
  BlockingVerdict verdictFor({
    required PrayerSlot slot,
    required DateTime now,
  }) =>
      // Nothing policy-specific: a verified slot is simply no longer owed, and
      // the ordinary path already declines to lock for it.
      const BlockingVerdict.open(LockReason.noPrayerDue);
}

/// Mode B — the window holds the lock, verified or not.
///
/// For users who want the time protected rather than the obligation tracked:
/// the point is not to be released early by praying quickly.
class FullDurationBlockingStrategy implements BlockingStrategy {
  const FullDurationBlockingStrategy();

  @override
  UnlockPolicy get policy => UnlockPolicy.fullDuration;

  @override
  bool get holdsAfterVerification => true;

  @override
  BlockingVerdict verdictFor({
    required PrayerSlot slot,
    required DateTime now,
  }) =>
      BlockingVerdict(
        shouldLock: true,
        // A verified prayer still blocking is a different situation from one
        // still owed, and the lock screen says so — otherwise a user who has
        // just prayed sees a screen telling them to pray.
        reason: slot.isFulfilled
            ? LockReason.durationRemaining
            : LockReason.prayerActive,
        lockUntil: slot.windowEndsAt,
      );
}

/// Whichever comes first: verification, or the window ending.
///
/// Behaves as [VerificationUnlockStrategy] does — the window ending already
/// ends the lock under every arrangement. It exists as its own policy because
/// users asked for the guarantee explicitly, and an option that says what it
/// does is worth more than one inferred from the absence of another.
class EarliestOfBlockingStrategy implements BlockingStrategy {
  const EarliestOfBlockingStrategy();

  @override
  UnlockPolicy get policy => UnlockPolicy.earliestOf;

  @override
  bool get holdsAfterVerification => false;

  @override
  BlockingVerdict verdictFor({
    required PrayerSlot slot,
    required DateTime now,
  }) =>
      const BlockingVerdict.open(LockReason.noPrayerDue);
}

/// Resolves an unlock policy to the strategy that applies it.
class BlockingRegistry {
  BlockingRegistry(Iterable<BlockingStrategy> strategies)
      : _strategies = {
          for (final strategy in strategies) strategy.policy: strategy,
        };

  /// The arrangements the app ships with.
  factory BlockingRegistry.standard() => BlockingRegistry(const [
        VerificationUnlockStrategy(),
        FullDurationBlockingStrategy(),
        EarliestOfBlockingStrategy(),
      ]);

  final Map<UnlockPolicy, BlockingStrategy> _strategies;

  /// The strategy for [policy].
  ///
  /// Falls back to the verification arrangement rather than throwing. If a
  /// policy is ever unregistered, releasing on verification is the failure
  /// direction that leaves a user in control of their own phone.
  BlockingStrategy forPolicy(UnlockPolicy policy) =>
      _strategies[policy] ?? const VerificationUnlockStrategy();

  List<BlockingStrategy> get all => List.unmodifiable(_strategies.values);

  /// A copy with [strategy] replacing whatever answered for its policy.
  BlockingRegistry withStrategy(BlockingStrategy strategy) => BlockingRegistry([
        ..._strategies.values.where((s) => s.policy != strategy.policy),
        strategy,
      ]);
}
