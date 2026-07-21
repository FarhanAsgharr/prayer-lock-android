/// Performs an emergency unlock, then returns to the dashboard.
///
/// Reached only from the lock screen's confirmed emergency action. The
/// confirmation already happened there, so this screen does the work rather
/// than asking again — a second dialog during what the user considers an
/// emergency would be obstructive.
///
/// The unlock runs here, in the main app's engine, because spending the daily
/// quota and stopping the blocking service both belong to the orchestrator,
/// which lives here and not in the lock screen's separate engine.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/app_theme.dart';
import '../providers/orchestrator_provider.dart';

class EmergencyUnlockScreen extends ConsumerStatefulWidget {
  const EmergencyUnlockScreen({super.key});

  @override
  ConsumerState<EmergencyUnlockScreen> createState() =>
      _EmergencyUnlockScreenState();
}

class _EmergencyUnlockScreenState
    extends ConsumerState<EmergencyUnlockScreen> {
  bool _done = false;
  bool _granted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _perform());
  }

  Future<void> _perform() async {
    final granted = await ref
        .read(lockStateProvider.notifier)
        .requestEmergencyUnlock(reason: 'User requested from lock screen');

    if (!mounted) return;
    setState(() {
      _done = true;
      _granted = granted;
    });

    // Return to the dashboard after a beat, so the outcome is legible without
    // needing a tap. A trapped user should never have to hunt for a way back.
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_done)
                const CircularProgressIndicator()
              else ...[
                Icon(
                  _granted ? Icons.lock_open : Icons.error_outline,
                  size: 56,
                  color: _granted ? AppColors.success : AppColors.warning,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  _granted
                      ? 'Apps unlocked'
                      : "You've used all your emergency unlocks today",
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _granted
                      ? 'Your apps are available again. This has been recorded.'
                      : 'Apps will unlock once you complete and verify your '
                          'prayer.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
