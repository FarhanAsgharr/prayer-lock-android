/// Camera capture and prayer verification.
///
/// The user photographs their prayer mat; the image is evaluated and, on
/// success, apps unlock. Two design choices worth stating:
///
/// The image is never written to disk or the gallery. It is captured, encoded
/// in memory, sent, and discarded. These are photographs of people's homes.
///
/// The user is never trapped. After the attempt limit, or if verification is
/// unavailable, they are released — with the outcome recorded honestly rather
/// than logged as a success.
library;

import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../prayer_times/domain/entities/prayer_enums.dart';
import '../../../blocking/presentation/providers/orchestrator_provider.dart';
import '../../../prayer_times/presentation/providers/prayer_times_provider.dart';
import '../../../../core/notifications/notification_providers.dart';
import '../../../tracking/data/repositories/tracking_repository.dart';
import '../../../tracking/presentation/providers/tracking_providers.dart';
import '../../../../core/storage/storage_providers.dart';
import '../../../jumuah/presentation/providers/jumuah_providers.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/verification_result.dart';
import '../providers/verification_provider.dart';

class VerificationScreen extends ConsumerStatefulWidget {
  const VerificationScreen({super.key, required this.prayer});

  final PrayerName prayer;

  @override
  ConsumerState<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends ConsumerState<VerificationScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initialisation;

  String? _cameraError;
  bool _isSubmitting = false;
  VerificationResult? _lastResult;
  int _attempts = 0;

  static const int _maxAttempts = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialisation = _setUpCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    // The OS reclaims the camera when the app is backgrounded; without an
    // explicit teardown and rebuild the preview returns as a frozen frame.
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      setState(() => _initialisation = _setUpCamera());
    }
  }

  Future<void> _setUpCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError =
            'No camera was found on this device. You can still record this '
            'prayer without a photo.');
        return;
      }

      // Prefer the rear camera: the user is photographing a mat on the floor,
      // not themselves.
      final camera = cameras.firstWhere(
        (candidate) => candidate.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        camera,
        // Medium is deliberate. The vision model downsamples anyway, and a
        // full-resolution frame would mean multi-megabyte uploads on mobile
        // data for no accuracy gain.
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _cameraError = null;
      });
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() {
        _cameraError = switch (error.code) {
          'CameraAccessDenied' =>
            'Camera permission was declined. Allow it in Settings, or record '
                'this prayer without a photo.',
          _ => 'The camera could not be opened (${error.code}).',
        };
      });
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      final photo = await controller.takePicture();
      final bytes = await photo.readAsBytes();
      final encoded = base64Encode(bytes);

      final result = await ref
          .read(verificationServiceProvider)
          .verify(prayer: widget.prayer, imageBase64: encoded);

      if (!mounted) return;

      setState(() {
        _attempts += 1;
        _lastResult = result;
        _isSubmitting = false;
      });

      if (result.approved) {
        await _completePrayer(result: result);
      }
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _cameraError = 'The photo could not be taken (${error.code}).';
      });
    }
  }

  /// Persist the prayer, record the verification, and release the lock.
  ///
  /// Order matters. The prayer is written first so that a failure between
  /// steps leaves the user's worship recorded rather than lost — a stale lock
  /// is recoverable on the next orchestrator tick, a lost prayer record is not.
  ///
  /// Every step is guarded. A failure to record the verification, or to
  /// release the lock, must not prevent the two things the user actually
  /// cares about: their prayer being saved, and being returned to their phone.
  Future<void> _completePrayer({VerificationResult? result}) async {
    final day = ref.read(prayerDayProvider);
    final date = ref.read(localDateProvider);

    if (day == null) {
      // Should not happen — a location is required to reach this screen — but
      // if it does, get the user out rather than stranding them here.
      debugPrint('Cannot complete prayer: no schedule available');
      if (mounted) context.go('/');
      return;
    }

    final settings = ref.read(settingsProvider);
    // Resolved as a slot, so confirming a combined Dhuhr+Asr discharges both
    // prayers from one photo. Under the default grouping the slot holds only
    // the prayer that was routed to, and this is unchanged behaviour.
    final slot = day.slotFor(widget.prayer, settings.prayerGrouping);

    VerificationOutcome outcome;
    String prayerHistoryId;
    try {
      outcome = await ref.read(prayerTrackerProvider).markSlotVerified(
            date: date,
            slot: slot,
            combinedVerification: settings.combinedVerification,
            // Null on any day that is not a Friday, so the ordinary path is
            // untouched.
            jumuahProfile: ref.read(activeJumuahProfileProvider),
          );
      prayerHistoryId = TrackingRepository.prayerId(date, widget.prayer);
    } catch (error, stack) {
      // The single most important write. If it fails, surface it and stop,
      // rather than releasing the lock for a prayer that was not recorded.
      debugPrint('Failed to record prayer: $error\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save your prayer. Please try again.'),
          ),
        );
      }
      return;
    }

    // The qaza window closed before the photo was submitted. The prayer is now
    // permanently missed and no verification is possible — tell the user
    // plainly rather than pretending it was recorded.
    if (outcome == VerificationOutcome.expired) {
      // Release the lock anyway — nothing more can be done here.
      await ref.read(lockStateProvider.notifier).onPrayerCompleted();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The prayer and qaza windows have both passed. This prayer is '
              'now recorded as missed.',
            ),
          ),
        );
        context.go('/');
      }
      return;
    }

    // Best-effort from here: the prayer is saved, so nothing below may block
    // the user's return to their phone.
    if (result != null) {
      try {
        await ref.read(prayerTrackerProvider).recordVerification(
              prayerHistoryId: prayerHistoryId,
              verificationId: '$prayerHistoryId:${result.attemptNumber}',
              approved: result.approved,
              attemptNumber: result.attemptNumber,
              releasedWithoutDetection: result.releasedWithoutDetection,
              message: result.message,
            );
      } catch (error) {
        debugPrint('Failed to record verification (non-fatal): $error');
      }
    }

    // The prayer is verified, so its "qaza now available" notice must not fire.
    try {
      await ref
          .read(notificationServiceProvider)
          .cancelQazaNotice(date, widget.prayer);
    } catch (error) {
      debugPrint('Failed to cancel qaza notice (non-fatal): $error');
    }

    // Release immediately rather than waiting up to thirty seconds for the
    // next orchestrator tick. Someone who has just proved they prayed should
    // not be left staring at a locked phone.
    try {
      await ref.read(lockStateProvider.notifier).onPrayerCompleted();
    } catch (error) {
      debugPrint('Failed to release lock immediately (non-fatal): $error');
      // The orchestrator's periodic tick will release it shortly, since the
      // prayer is now recorded as complete.
    }

    // Upload opportunistically; the queue retries if this fails.
    unawaited(ref.read(syncEngineProvider).drain());

    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    // Verification disabled, or no camera: recording the prayer directly is
    // the honest path. Blocking someone from marking a prayer they performed
    // because our camera failed would be indefensible.
    if (!settings.requireAiVerification || _cameraError != null) {
      return _ManualConfirmationView(
        prayer: widget.prayer,
        message: _cameraError,
        onConfirm: () => unawaited(_completePrayer()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text('Verify ${widget.prayer.displayName}'),
      ),
      body: FutureBuilder<void>(
        future: _initialisation,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done ||
              _controller == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(_controller!),
              _CaptureOverlay(
                isSubmitting: _isSubmitting,
                result: _lastResult,
                attempts: _attempts,
                maxAttempts: _maxAttempts,
                onCapture: _capture,
                onGiveUp: () => unawaited(_completePrayer()),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CaptureOverlay extends StatelessWidget {
  const _CaptureOverlay({
    required this.isSubmitting,
    required this.result,
    required this.attempts,
    required this.maxAttempts,
    required this.onCapture,
    required this.onGiveUp,
  });

  final bool isSubmitting;
  final VerificationResult? result;
  final int attempts;
  final int maxAttempts;
  final VoidCallback onCapture;
  final VoidCallback onGiveUp;

  @override
  Widget build(BuildContext context) {
    final rejection = result != null && !result!.approved ? result : null;
    final attemptsExhausted = attempts >= maxAttempts;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(
                rejection?.message ??
                    'Point the camera at your prayer mat and take a photo.',
                style: const TextStyle(color: Colors.white, fontSize: 15),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const Spacer(),
          if (attemptsExhausted)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Having trouble? You can record this prayer without a '
                      'photo.',
                      style: TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                      onPressed: onGiveUp,
                      child: const Text('Record without a photo'),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Semantics(
              button: true,
              label: 'Take photo of prayer mat',
              child: GestureDetector(
                onTap: isSubmitting ? null : onCapture,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.22),
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: isSubmitting
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.camera_alt,
                          color: Colors.white, size: 30),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualConfirmationView extends StatelessWidget {
  const _ManualConfirmationView({
    required this.prayer,
    required this.onConfirm,
    this.message,
  });

  final PrayerName prayer;
  final VoidCallback onConfirm;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('Record ${prayer.displayName}')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline, size: 56),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Did you complete ${prayer.displayName}?',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: onConfirm,
              child: const Text('Yes, I completed it'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: () => context.pop(),
              child: const Text('Not yet'),
            ),
          ],
        ),
      ),
    );
  }
}
