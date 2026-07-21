/// Tests for verification response handling.
///
/// The central regression: the Dio client is configured with
/// validateStatus < 500, so 4xx responses do NOT throw. A 401 (unauthenticated)
/// therefore arrives as a normal response, and an earlier version parsed its
/// error body as a verdict — reading the absent "approved" field as a
/// rejection, so the prayer was silently never recorded and the lock never
/// released. These tests pin every status code to its intended outcome.
library;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:prayer_lock/features/verification/data/repositories/verification_repository.dart';
import 'package:prayer_lock/features/verification/domain/entities/verification_result.dart';

/// A Dio adapter returning a canned response, so no real network is used.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({this.statusCode = 200, this.body = '{}', this.throwError});

  final int statusCode;
  final String body;
  final DioExceptionType? throwError;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final error = throwError;
    if (error != null) {
      throw DioException(requestOptions: options, type: error);
    }
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

VerificationRepository repositoryReturning({
  int statusCode = 200,
  String body = '{}',
  DioExceptionType? throwError,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'http://test.local',
      // Mirror the production configuration exactly — this is the setting that
      // caused the bug, so testing with it is the whole point.
      validateStatus: (status) => status != null && status < 500,
    ),
  )..httpClientAdapter = _StubAdapter(
      statusCode: statusCode,
      body: body,
      throwError: throwError,
    );

  return VerificationRepository(client: dio, connectivity: _AlwaysOnline());
}

Future<VerificationResult> submit(VerificationRepository repository) =>
    repository.submit(prayer: PrayerName.fajr, imageBase64: 'x' * 100);

void main() {
  group('successful verdicts', () {
    test('a 200 approval is respected', () async {
      final result = await submit(
        repositoryReturning(
          body: '{"approved": true, "message": "Prayer verified.", '
              '"attempt_number": 1, "attempts_remaining": 2}',
        ),
      );

      expect(result.approved, isTrue);
      expect(result.message, 'Prayer verified.');
      expect(result.attemptNumber, 1);
    });

    test('a 200 rejection is respected', () async {
      final result = await submit(
        repositoryReturning(
          body: '{"approved": false, "message": "Prayer mat not detected."}',
        ),
      );

      expect(result.approved, isFalse);
      expect(result.message, 'Prayer mat not detected.');
    });
  });

  group('the 401 regression', () {
    test('a 401 does NOT parse the error body as a rejection', () async {
      // The exact failing case: a 401 body has no "approved" field. Parsing it
      // as a verdict yielded approved:false, so the prayer was never recorded.
      final result = await submit(
        repositoryReturning(
          statusCode: 401,
          body: '{"detail": "Authorization header is missing"}',
        ),
      );

      // Fail open: the user has prayed, so release them and reconcile later.
      expect(result.approved, isTrue);
      expect(result.releasedWithoutDetection, isTrue);
      expect(result.message, isNot('Verification complete.'));
    });

    test('a 403 also fails open', () async {
      final result = await submit(
        repositoryReturning(statusCode: 403, body: '{"detail": "Forbidden"}'),
      );

      expect(result.approved, isTrue);
    });

    test('a 404 (endpoint missing) fails open', () async {
      // The tracking endpoints may not be deployed yet; a user must not be
      // trapped because the server has not caught up.
      final result = await submit(
        repositoryReturning(statusCode: 404, body: 'Not Found'),
      );

      expect(result.approved, isTrue);
    });
  });

  group('content rejections keep the user locked', () {
    test('a 400 is a genuine rejection', () async {
      final result = await submit(
        repositoryReturning(statusCode: 400, body: '{"detail": "bad image"}'),
      );

      expect(result.approved, isFalse);
      expect(result.message, contains('photo'));
    });

    test('a 422 is a genuine rejection', () async {
      final result = await submit(
        repositoryReturning(statusCode: 422, body: '{}'),
      );

      expect(result.approved, isFalse);
    });
  });

  group('other outcomes', () {
    test('a 409 is treated as already recorded', () async {
      final result = await submit(
        repositoryReturning(statusCode: 409, body: '{}'),
      );

      expect(result.approved, isTrue);
      expect(result.message, contains('already'));
    });

    test('a 429 asks the user to wait', () async {
      final result = await submit(
        repositoryReturning(statusCode: 429, body: '{}'),
      );

      expect(result.approved, isFalse);
      expect(result.message, contains('wait'));
    });

    test('a 500 fails open', () async {
      final result = await submit(
        repositoryReturning(statusCode: 500, body: 'error'),
      );

      expect(result.approved, isTrue);
    });

    test('a connection error fails open', () async {
      final result = await submit(
        repositoryReturning(throwError: DioExceptionType.connectionError),
      );

      expect(result.approved, isTrue);
      expect(result.releasedWithoutDetection, isTrue);
    });

    test('a timeout fails open', () async {
      final result = await submit(
        repositoryReturning(throwError: DioExceptionType.receiveTimeout),
      );

      expect(result.approved, isTrue);
    });
  });
}

/// Connectivity that always reports online, so the repository proceeds to the
/// network call rather than short-circuiting to offline approval.
class _AlwaysOnline implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      Stream.value([ConnectivityResult.wifi]);
}
