/// Bounded exponential backoff with jitter.
///
/// Used by anything that talks to a network the user cannot be asked to fix.
/// Two properties matter more than the exact numbers:
///
///   * It is *bounded*. An unbounded retry loop against a service that is down
///     is indistinguishable from a battery drain bug, and it is the app that
///     gets uninstalled, not the service that gets fixed.
///
///   * It is *jittered*. Without jitter, every install that failed during an
///     outage retries in lockstep, and the recovering service is hit by a
///     synchronised thundering herd from the entire user base.
library;

import 'dart:async';
import 'dart:math' as math;

/// Decides whether a failure is worth retrying at all.
typedef RetryPredicate = bool Function(Object error);

class RetryPolicy {
  const RetryPolicy({
    this.maxAttempts = 4,
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.multiplier = 2.0,
    this.jitterFactor = 0.25,
  })  : assert(maxAttempts >= 1, 'At least one attempt must be made'),
        assert(
          jitterFactor >= 0.0 && jitterFactor < 1.0,
          'Jitter must be a fraction of the delay',
        );

  /// Total attempts including the first. Four attempts over roughly 1s, 2s and
  /// 4s covers a transient blip without keeping the radio awake for a minute.
  final int maxAttempts;

  final Duration initialDelay;
  final Duration maxDelay;
  final double multiplier;

  /// Delays are multiplied by a random factor in [1 - j, 1 + j].
  final double jitterFactor;

  /// Delay before the attempt following [attempt] (1-based), before jitter.
  Duration delayForAttempt(int attempt) {
    final raw = initialDelay.inMilliseconds * math.pow(multiplier, attempt - 1);
    final capped = math.min(raw.toDouble(), maxDelay.inMilliseconds.toDouble());
    return Duration(milliseconds: capped.round());
  }

  /// Run [action], retrying transient failures.
  ///
  /// [isRetryable] decides which failures are transient; the default retries
  /// everything, which is only correct when the caller has already narrowed the
  /// error type. Callers with typed errors should pass a predicate — retrying a
  /// permanent failure such as "this location is unsupported" is pure waste.
  Future<T> run<T>(
    Future<T> Function() action, {
    RetryPredicate? isRetryable,
    math.Random? random,
    Future<void> Function(Duration)? sleep,
  }) async {
    final rng = random ?? math.Random();
    final wait = sleep ?? Future<void>.delayed;

    Object lastError = StateError('Retry policy ran no attempts');
    StackTrace lastStackTrace = StackTrace.current;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await action();
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;

        final retryable = isRetryable?.call(error) ?? true;
        if (!retryable || attempt == maxAttempts) {
          Error.throwWithStackTrace(error, stackTrace);
        }

        await wait(_jittered(delayForAttempt(attempt), rng));
      }
    }

    // Unreachable: the loop either returns or throws. Present so the function
    // is total rather than relying on the analyzer's flow inference.
    Error.throwWithStackTrace(lastError, lastStackTrace);
  }

  Duration _jittered(Duration base, math.Random random) {
    if (jitterFactor == 0) return base;
    final factor = 1 + (random.nextDouble() * 2 - 1) * jitterFactor;
    return Duration(milliseconds: (base.inMilliseconds * factor).round());
  }
}
