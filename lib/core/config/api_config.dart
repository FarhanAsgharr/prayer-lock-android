/// Backend connection configuration.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

abstract final class ApiConfig {
  /// Base URL, supplied at build time.
  ///
  /// Passed with --dart-define rather than hardcoded so debug, staging and
  /// release builds cannot accidentally ship pointing at the wrong backend:
  ///
  ///   flutter build apk --dart-define=API_BASE_URL=https://api.example.com
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    // 10.0.2.2 is the host machine as seen from the Android emulator.
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Generous relative to a normal API call: the verification endpoint waits
  /// on a vision model, which routinely takes several seconds.
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration connectTimeout = Duration(seconds: 10);

  static Dio createClient() {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        headers: {'content-type': 'application/json'},
        // Handle all statuses ourselves so failures arrive as typed results
        // rather than exceptions thrown from arbitrary call sites.
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    assert(() {
      if (kDebugMode) {
        dio.interceptors.add(
          LogInterceptor(
            // Never log bodies: verification requests carry base64 images and
            // auth requests carry tokens.
            requestBody: false,
            responseBody: false,
          ),
        );
      }
      return true;
    }());

    return dio;
  }
}
