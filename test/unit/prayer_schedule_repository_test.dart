/// Tests for offline-first schedule resolution.
///
/// The requirement is that no feature stops working without a network. These
/// tests are what make that structural rather than aspirational: they assert
/// that a complete, ordered, usable schedule comes back when the remote
/// provider fails outright, when it returns nonsense, and when it has never
/// been reachable at all.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/core/network/retry_policy.dart';
import 'package:prayer_lock/features/prayer_times/data/repositories/prayer_schedule_repository_impl.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:prayer_lock/features/settings/domain/entities/app_settings.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

import '../support/prayer_fixtures.dart';

/// No delay and a single attempt: these tests exercise resolution, not backoff,
/// and real backoff would make the suite take half a minute.
const _immediate = RetryPolicy(
  maxAttempts: 1,
  initialDelay: Duration.zero,
  jitterFactor: 0.0,
);

void main() {
  tz_data.initializeTimeZones();

  final date = DateTime(2026, 7, 20);

  PrayerScheduleRepositoryImpl build({
    required FakeScheduleCache cache,
    required dynamic remote,
    bool preferRemote = true,
  }) =>
      PrayerScheduleRepositoryImpl(
        cache: cache,
        remoteProvider: remote,
        readSettings: () => settingsWith(preferRemote: preferRemote),
        retryPolicy: _immediate,
      );

  group('offline resolution', () {
    test('returns a complete schedule when the network fails', () async {
      final cache = FakeScheduleCache();
      final remote = FailingPrayerTimeProvider();
      final repository = build(cache: cache, remote: remote);

      final resolved = await repository.resolveDay(date);

      expect(resolved.windows.windows, hasLength(5));
      expect(resolved.source, PrayerTimeSource.device);
      for (final window in resolved.windows.windows) {
        expect(window.duration, greaterThan(Duration.zero));
      }
    });

    test('marks a device-computed day as refreshable', () async {
      final repository = build(
        cache: FakeScheduleCache(),
        remote: FailingPrayerTimeProvider(),
      );

      final resolved = await repository.resolveDay(date);
      expect(resolved.isStale, isTrue);
    });

    test('caches what it computed, so the next read needs no provider',
        () async {
      final cache = FakeScheduleCache();
      final remote = FailingPrayerTimeProvider();
      final repository = build(cache: cache, remote: remote);

      await repository.resolveDay(date);
      expect(cache.length, greaterThanOrEqualTo(2)); // today and tomorrow
    });

    test('never calls the network when remote times are switched off',
        () async {
      final remote = StubRemoteProvider();
      final repository = build(
        cache: FakeScheduleCache(),
        remote: remote,
        preferRemote: false,
      );

      final resolved = await repository.resolveDay(date);

      expect(remote.fetchCount, 0);
      expect(resolved.source, PrayerTimeSource.device);
    });

    test('a failure does not throw out of the repository', () async {
      final repository = build(
        cache: FakeScheduleCache(),
        remote: FailingPrayerTimeProvider(isRetryable: false),
      );

      // The device calculator is the floor, so this must simply succeed.
      await expectLater(repository.resolveDay(date), completes);
    });
  });

  group('remote resolution', () {
    test('prefers the remote provider when it answers', () async {
      final remote = StubRemoteProvider();
      final repository = build(cache: FakeScheduleCache(), remote: remote);

      final resolved = await repository.resolveDay(date);

      expect(resolved.source, PrayerTimeSource.remote);
      expect(resolved.isStale, isFalse);
      expect(remote.fetchCount, greaterThan(0));
    });

    test('the remote times actually drive the windows', () async {
      final remote = StubRemoteProvider(shift: const Duration(minutes: 11));
      final repository = build(cache: FakeScheduleCache(), remote: remote);

      final resolved = await repository.resolveDay(date);
      final device = windowsAt(date: date);

      expect(
        resolved.windows.windowFor(PrayerName.dhuhr).startsAt,
        device.windowFor(PrayerName.dhuhr).startsAt.add(
              const Duration(minutes: 11),
            ),
      );
    });

    test('rejects a non-monotonic response in favour of the device', () async {
      // A response whose Isha precedes Maghrib would produce a backwards
      // window — a lock whose end is before its start.
      final remote = StubRemoteProvider(monotonic: false);
      final repository = build(cache: FakeScheduleCache(), remote: remote);

      final resolved = await repository.resolveDay(date);

      expect(resolved.source, PrayerTimeSource.device);
      for (final window in resolved.windows.windows) {
        expect(window.duration.isNegative, isFalse);
      }
    });

    test('stops retrying the network after a failure, for a while', () async {
      final remote = FailingPrayerTimeProvider();
      final repository = build(cache: FakeScheduleCache(), remote: remote);

      await repository.resolveDay(date);
      final afterFirst = remote.fetchAttempts;

      // A device offline for a day must not attempt a fetch on every tick.
      await repository.resolveDay(DateTime(2026, 8, 1));
      expect(remote.fetchAttempts, afterFirst);
    });
  });

  group('cache behaviour', () {
    test('a remotely sourced cached day is served without refetching',
        () async {
      final cache = FakeScheduleCache();
      final remote = StubRemoteProvider();
      final repository = build(cache: cache, remote: remote);

      await repository.resolveDay(date);
      final afterFirst = remote.fetchCount;

      await repository.resolveDay(date);
      expect(remote.fetchCount, afterFirst);
    });

    test('a device-computed cached day is upgraded when the network returns',
        () async {
      final cache = FakeScheduleCache();

      // First pass: offline, so the day is computed and cached.
      await build(cache: cache, remote: FailingPrayerTimeProvider())
          .resolveDay(date);

      // Second pass: network back, same cache.
      final remote = StubRemoteProvider();
      final resolved =
          await build(cache: cache, remote: remote).resolveDay(date);

      expect(remote.fetchCount, greaterThan(0));
      expect(resolved.source, PrayerTimeSource.remote);
    });

    test('invalidate empties the cache', () async {
      final cache = FakeScheduleCache();
      final repository =
          build(cache: cache, remote: FailingPrayerTimeProvider());

      await repository.resolveDay(date);
      expect(cache.length, greaterThan(0));

      await repository.invalidate();
      expect(cache.length, 0);
      expect(cache.clearCount, 1);
    });

    test('concurrent requests for the same day share one resolution',
        () async {
      final remote = StubRemoteProvider();
      final repository = build(cache: FakeScheduleCache(), remote: remote);

      // The orchestrator, the UI and the notification scheduler can all ask for
      // today in the same frame.
      await Future.wait([
        repository.resolveDay(date),
        repository.resolveDay(date),
        repository.resolveDay(date),
      ]);

      // Two days are resolved (today plus tomorrow for the Isha boundary), and
      // each should be fetched once rather than three times.
      expect(remote.fetchCount, lessThanOrEqualTo(2));
    });
  });

  group('prefetch', () {
    test('fills the horizon so later days need no provider', () async {
      final cache = FakeScheduleCache();
      final repository =
          build(cache: cache, remote: FailingPrayerTimeProvider());

      final written = await repository.prefetch(from: date, days: 7);

      // Seven days plus the extra day that closes the last Isha window.
      expect(written, 8);
      expect(cache.length, 8);
    });

    test('is idempotent for days already cached remotely', () async {
      final cache = FakeScheduleCache();
      final remote = StubRemoteProvider();
      final repository = build(cache: cache, remote: remote);

      await repository.prefetch(from: date, days: 3);
      final second = await repository.prefetch(from: date, days: 3);

      expect(second, 0);
    });
  });

  group('preconditions', () {
    test('asking for a schedule with no location is a programming error',
        () async {
      final repository = PrayerScheduleRepositoryImpl(
        cache: FakeScheduleCache(),
        remoteProvider: FailingPrayerTimeProvider(),
        readSettings: () => const AppSettings(),
        retryPolicy: _immediate,
      );

      // A StateError rather than a null: a caller reaching here has skipped the
      // isReady guard, and returning null would let that bug travel further.
      await expectLater(
        repository.resolveDay(date),
        throwsA(isA<StateError>()),
      );
    });
  });
}
