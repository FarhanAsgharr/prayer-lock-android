/// Network layer for prayer verification.
///
/// The backend is optional by design. When it is unreachable — no signal, a
/// server outage, or simply a user who never signed in — verification falls
/// back to local approval and the attempt is queued for later reconciliation.
/// The app must never require a network round trip to release a lock.
library;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import '../../../../core/config/api_config.dart';
import '../../../prayer_times/domain/entities/prayer_enums.dart';
import '../../domain/entities/verification_result.dart';

class VerificationRepository {
  VerificationRepository({Dio? client, Connectivity? connectivity})
      : _client = client ?? ApiConfig.createClient(),
        _connectivity = connectivity ?? Connectivity();

  final Dio _client;
  final Connectivity _connectivity;

  Future<VerificationResult> submit({
    required PrayerName prayer,
    required String imageBase64,
  }) async {
    if (!await _hasConnection()) {
      return VerificationResult.offlineApproval();
    }

    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/api/v1/verifications',
        data: {
          'prayer': prayer.wireValue,
          'image_base64': imageBase64,
        },
      );

      final status = response.statusCode ?? 0;

      // Only a genuine 2xx is a real verdict. The Dio client is configured
      // with validateStatus < 500, so 4xx responses arrive here rather than
      // throwing — they must NOT be parsed as a verdict, or a 401 body with no
      // "approved" field reads as a rejection and the prayer is never
      // recorded. This was a real bug; the status check is the guard.
      if (status >= 200 && status < 300) {
        return _parseVerdict(response.data);
      }

      return _resultForStatus(status);
    } on DioException catch (error) {
      // No response at all — connection error, timeout. The failure is ours,
      // and the user has already prayed, so release them.
      return _resultForStatus(error.response?.statusCode);
    }
  }

  VerificationResult _parseVerdict(Map<String, dynamic>? body) {
    if (body == null) return VerificationResult.offlineApproval();

    return VerificationResult(
      approved: body['approved'] as bool? ?? false,
      message: body['message'] as String? ?? 'Verification complete.',
      attemptNumber: (body['attempt_number'] as num?)?.toInt() ?? 1,
      attemptsRemaining: (body['attempts_remaining'] as num?)?.toInt() ?? 0,
      releasedWithoutDetection:
          body['released_without_detection'] as bool? ?? false,
      isSuspectedReplay: body['is_suspected_replay'] as bool? ?? false,
    );
  }

  /// Map a non-success status onto a user-facing outcome.
  ///
  /// The governing principle: only a definitive content rejection (the photo
  /// could not be read) keeps the user locked. Auth failures, server errors,
  /// missing endpoints and connection failures all release them, because the
  /// user has already prayed and the failure is not theirs. Being trapped
  /// behind our outage is never acceptable.
  VerificationResult _resultForStatus(int? status) {
    if (status == 400 || status == 422) {
      return VerificationResult.rejected(
        'That photo could not be read. Please try again.',
      );
    }
    if (status == 409) {
      return const VerificationResult(
        approved: true,
        message: 'This prayer was already recorded.',
      );
    }
    if (status == 429) {
      return VerificationResult.rejected(
        'Too many attempts just now. Please wait a moment and try again.',
      );
    }

    // 401, 403, 404, 5xx, or no response: fail open. The attempt is queued
    // and reconciled later once the user is authenticated and online.
    return VerificationResult.offlineApproval();
  }

  Future<bool> _hasConnection() async {
    final results = await _connectivity.checkConnectivity();
    return !results.contains(ConnectivityResult.none) && results.isNotEmpty;
  }
}
