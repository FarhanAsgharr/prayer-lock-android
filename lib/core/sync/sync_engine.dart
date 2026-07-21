/// Drains the outbound sync queue.
///
/// Runs on three triggers: app start, connectivity restored, and app resume.
/// There is deliberately no periodic background timer — Android and iOS both
/// throttle those aggressively, and a queue that drains on the events that
/// actually matter is more reliable than one that pretends to poll.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../features/tracking/data/repositories/tracking_repository.dart';
import 'sync_queue.dart';

/// Where each entity type is uploaded.
const Map<SyncEntityType, String> _endpoints = {
  SyncEntityType.prayerHistory: '/api/v1/prayer-history',
  SyncEntityType.verification: '/api/v1/verifications/record',
  SyncEntityType.lockSession: '/api/v1/lock-sessions',
  SyncEntityType.emergencyUnlock: '/api/v1/emergency-unlocks',
};

@immutable
class SyncStatus {
  const SyncStatus({
    required this.pending,
    required this.parked,
    required this.isSyncing,
    this.lastSyncedAt,
    this.lastError,
  });

  const SyncStatus.idle()
      : pending = 0,
        parked = 0,
        isSyncing = false,
        lastSyncedAt = null,
        lastError = null;

  final int pending;
  final int parked;
  final bool isSyncing;
  final DateTime? lastSyncedAt;
  final String? lastError;

  bool get hasUnsyncedData => pending > 0 || parked > 0;

  /// Whether anything needs the user's attention.
  ///
  /// Pending items are normal and are not surfaced; parked items mean repeated
  /// failure and are worth telling the user about.
  bool get needsAttention => parked > 0;
}

class SyncEngine {
  SyncEngine({
    required SyncQueue queue,
    required TrackingRepository repository,
    required Dio client,
    Connectivity? connectivity,
  })  : _queue = queue,
        _repository = repository,
        _client = client,
        _connectivity = connectivity ?? Connectivity();

  final SyncQueue _queue;
  final TrackingRepository _repository;
  final Dio _client;
  final Connectivity _connectivity;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  /// Guards against two drains running at once, which would double-upload.
  bool _isDraining = false;

  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;

  SyncStatus _status = const SyncStatus.idle();
  SyncStatus get status => _status;

  /// Begin watching for connectivity and drain once.
  Future<void> start() async {
    _connectivitySubscription ??=
        _connectivity.onConnectivityChanged.listen((results) {
      final isOnline =
          results.isNotEmpty && !results.contains(ConnectivityResult.none);
      // Only drain on the transition to online. Draining on every change
      // would fire repeatedly as the radio flaps between cell and wifi.
      if (isOnline) unawaited(drain());
    });

    await refreshStatus();
    await drain();
  }

  Future<void> stop() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    await _statusController.close();
  }

  /// Attempt to upload everything currently due.
  Future<void> drain() async {
    if (_isDraining) return;
    if (!await _isOnline()) {
      await refreshStatus();
      return;
    }

    _isDraining = true;
    _emit(isSyncing: true);

    try {
      final items = await _queue.due();

      for (final item in items) {
        final result = await _upload(item);
        await _queue.recordResult(
          item,
          result.outcome,
          error: result.error,
        );

        if (result.outcome == SyncAttemptResult.success) {
          await _repository.markSynced(item.entityType, item.entityId);
        }

        // Stop the whole drain when the network drops mid-run rather than
        // burning retry budget on items that cannot possibly succeed.
        if (result.outcome == SyncAttemptResult.retryable &&
            result.isConnectivityFailure) {
          break;
        }
      }

      _status = SyncStatus(
        pending: await _queue.pendingCount(),
        parked: await _queue.parkedCount(),
        isSyncing: false,
        lastSyncedAt: DateTime.now().toUtc(),
      );
      _statusController.add(_status);
    } finally {
      _isDraining = false;
    }
  }

  Future<_UploadOutcome> _upload(SyncQueueItem item) async {
    final endpoint = _endpoints[item.entityType];
    if (endpoint == null) {
      // An entity with no endpoint is a programming error, not a transient
      // fault. Parking it stops an infinite retry loop and makes the bug
      // visible in the sync status.
      return const _UploadOutcome(
        SyncAttemptResult.permanentFailure,
        error: 'No endpoint configured for this record type',
      );
    }

    try {
      final response = await _client.post<Map<String, dynamic>>(
        endpoint,
        data: {
          // Lets the server deduplicate a retry that succeeded but whose
          // response never reached us.
          'client_id': item.entityId,
          ...item.payload,
        },
      );

      final status = response.statusCode ?? 0;

      if (status >= 200 && status < 300) {
        return const _UploadOutcome(SyncAttemptResult.success);
      }

      // 409 means the server already has it — from our own earlier retry.
      // That is success from the user's point of view.
      if (status == 409) {
        return const _UploadOutcome(SyncAttemptResult.success);
      }

      // 401 is retryable: the token refresh interceptor may fix it, and
      // discarding the user's prayer record over an expired token would be
      // unacceptable.
      if (status == 401 || status == 403) {
        return _UploadOutcome(
          SyncAttemptResult.retryable,
          error: 'Not authorised (HTTP $status)',
        );
      }

      if (status >= 400 && status < 500) {
        return _UploadOutcome(
          SyncAttemptResult.permanentFailure,
          error: 'Server rejected the record (HTTP $status)',
        );
      }

      return _UploadOutcome(
        SyncAttemptResult.retryable,
        error: 'Server error (HTTP $status)',
      );
    } on DioException catch (error) {
      final isConnectivity = error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout;

      return _UploadOutcome(
        SyncAttemptResult.retryable,
        error: error.message ?? error.type.name,
        isConnectivityFailure: isConnectivity,
      );
    }
  }

  Future<void> refreshStatus() async {
    _status = SyncStatus(
      pending: await _queue.pendingCount(),
      parked: await _queue.parkedCount(),
      isSyncing: _isDraining,
      lastSyncedAt: _status.lastSyncedAt,
    );
    _statusController.add(_status);
  }

  /// Re-arm parked items, then drain. Offered as an explicit user action.
  Future<void> retryFailed() async {
    await _queue.retryParked();
    await drain();
  }

  Future<bool> _isOnline() async {
    final results = await _connectivity.checkConnectivity();
    return results.isNotEmpty && !results.contains(ConnectivityResult.none);
  }

  void _emit({required bool isSyncing}) {
    _status = SyncStatus(
      pending: _status.pending,
      parked: _status.parked,
      isSyncing: isSyncing,
      lastSyncedAt: _status.lastSyncedAt,
      lastError: _status.lastError,
    );
    _statusController.add(_status);
  }
}

@immutable
class _UploadOutcome {
  const _UploadOutcome(
    this.outcome, {
    this.error,
    this.isConnectivityFailure = false,
  });

  final SyncAttemptResult outcome;
  final String? error;
  final bool isConnectivityFailure;
}
