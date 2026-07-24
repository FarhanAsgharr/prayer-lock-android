/// Tests for the bounded exponential backoff used by network calls.
///
/// Two properties matter and both are load-bearing: the loop must terminate,
/// and a permanent failure must not be retried at all. Getting either wrong
/// turns an outage into a battery-drain bug on every install.
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/core/network/retry_policy.dart';

/// Records the delays asked for instead of actually waiting.
class _RecordingSleeper {
  final List<Duration> delays = [];

  Future<void> call(Duration duration) async {
    delays.add(duration);
  }
}

class _Permanent implements Exception {}

class _Transient implements Exception {}

void main() {
  const policy = RetryPolicy(
    maxAttempts: 4,
    initialDelay: Duration(seconds: 1),
    maxDelay: Duration(seconds: 30),
    jitterFactor: 0.0,
  );

  group('delay schedule', () {
    test('grows exponentially', () {
      expect(policy.delayForAttempt(1), const Duration(seconds: 1));
      expect(policy.delayForAttempt(2), const Duration(seconds: 2));
      expect(policy.delayForAttempt(3), const Duration(seconds: 4));
      expect(policy.delayForAttempt(4), const Duration(seconds: 8));
    });

    test('is capped', () {
      // Unbounded growth would eventually schedule a retry hours away, which
      // is indistinguishable from never retrying.
      expect(policy.delayForAttempt(20), const Duration(seconds: 30));
    });
  });

  group('retrying', () {
    test('returns the first success without waiting', () async {
      final sleeper = _RecordingSleeper();
      var calls = 0;

      final result = await policy.run(
        () async {
          calls++;
          return 'ok';
        },
        sleep: sleeper.call,
      );

      expect(result, 'ok');
      expect(calls, 1);
      expect(sleeper.delays, isEmpty);
    });

    test('retries a transient failure and succeeds', () async {
      final sleeper = _RecordingSleeper();
      var calls = 0;

      final result = await policy.run(
        () async {
          calls++;
          if (calls < 3) throw _Transient();
          return 'ok';
        },
        sleep: sleeper.call,
      );

      expect(result, 'ok');
      expect(calls, 3);
      expect(sleeper.delays, hasLength(2));
    });

    test('gives up after maxAttempts and rethrows', () async {
      final sleeper = _RecordingSleeper();
      var calls = 0;

      await expectLater(
        policy.run(
          () async {
            calls++;
            throw _Transient();
          },
          sleep: sleeper.call,
        ),
        throwsA(isA<_Transient>()),
      );

      expect(calls, 4);
      // One fewer sleep than attempts: nothing is waited after the last one.
      expect(sleeper.delays, hasLength(3));
    });

    test('does not retry a failure marked permanent', () async {
      final sleeper = _RecordingSleeper();
      var calls = 0;

      await expectLater(
        policy.run(
          () async {
            calls++;
            throw _Permanent();
          },
          isRetryable: (error) => error is! _Permanent,
          sleep: sleeper.call,
        ),
        throwsA(isA<_Permanent>()),
      );

      expect(calls, 1);
      expect(sleeper.delays, isEmpty);
    });

    test('a single-attempt policy never sleeps', () async {
      const single = RetryPolicy(maxAttempts: 1, jitterFactor: 0.0);
      final sleeper = _RecordingSleeper();

      await expectLater(
        single.run(() async => throw _Transient(), sleep: sleeper.call),
        throwsA(isA<_Transient>()),
      );
      expect(sleeper.delays, isEmpty);
    });

    test('preserves the original stack trace', () async {
      // A rethrow that loses the stack makes a production failure untraceable
      // to the call that caused it.
      StackTrace? thrown;
      try {
        await policy.run(
          () async => throw _Permanent(),
          isRetryable: (_) => false,
          sleep: (_) async {},
        );
      } catch (_, stackTrace) {
        thrown = stackTrace;
      }

      expect(thrown.toString(), contains('retry_policy_test.dart'));
    });
  });

  group('jitter', () {
    test('spreads delays around the base value', () async {
      // Without jitter, every install that failed during an outage retries in
      // lockstep and the recovering service is hit by a synchronised herd.
      const jittered = RetryPolicy(
        maxAttempts: 2,
        initialDelay: Duration(seconds: 10),
        jitterFactor: 0.25,
      );

      final observed = <int>{};
      for (var seed = 0; seed < 20; seed++) {
        final sleeper = _RecordingSleeper();

        await jittered
            .run(
              () async => throw _Transient(),
              sleep: sleeper.call,
              random: math.Random(seed),
            )
            // Every run fails by design; only the delays it asked for matter.
            .then<void>((_) {}, onError: (Object _) {});

        expect(sleeper.delays, hasLength(1));
        observed.add(sleeper.delays.single.inMilliseconds);
      }

      // Values land inside the +/-25% band...
      for (final value in observed) {
        expect(value, inInclusiveRange(7500, 12500));
      }
      // ...and are not all identical.
      expect(observed.length, greaterThan(1));
    });

    test('zero jitter is deterministic', () {
      const exact = RetryPolicy(
        initialDelay: Duration(seconds: 5),
        jitterFactor: 0.0,
      );
      expect(exact.delayForAttempt(1), const Duration(seconds: 5));
    });
  });
}
