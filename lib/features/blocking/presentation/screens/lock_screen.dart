/// The full-screen prayer reminder shown when a blocked app is opened.
///
/// Tone matters more than usual here. This screen interrupts someone, so it
/// stays calm and brief: what time it is, what is owed, and two clear ways
/// forward. It does not scold, gamify, or guilt — the user already chose this.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../prayer_times/domain/entities/prayer_enums.dart';
import '../../../prayer_times/presentation/providers/prayer_times_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  /// Channel the native activity uses to tell us which app was blocked.
  static const MethodChannel _channel =
      MethodChannel('com.prayerlock/lock_screen');

  String? _blockedPackage;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onAppBlocked' && mounted) {
      final arguments = (call.arguments as Map?)?.cast<String, dynamic>();
      setState(() => _blockedPackage = arguments?['package'] as String?);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = ref.watch(currentPrayerProvider);
    final morningProtection = ref.watch(morningProtectionActiveProvider);

    final prayerName = current?.prayer.displayName ?? 'prayer';

    return PopScope(
      // Back must not dismiss the reminder. The native activity also swallows
      // the gesture; this is the Flutter-side guarantee so the behaviour holds
      // even if the activity is reused elsewhere.
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),

                const Icon(
                  Icons.mosque_outlined,
                  size: 64,
                  color: AppColors.primaryLight,
                ),
                const SizedBox(height: AppSpacing.lg),

                if (morningProtection) ...[
                  Text(
                    AppLocalizations.of(context).lockGoodMorning,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: AppColors.darkTextPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    AppLocalizations.of(context).lockFajrFirst,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: AppColors.darkTextSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ] else ...[
                  Text(
                    AppLocalizations.of(context).lockItIsTimeFor(prayerName),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: AppColors.darkTextPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    AppLocalizations.of(context).lockPerformPrayer,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: AppColors.darkTextSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],

                const Spacer(),

                FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: Text(AppLocalizations.of(context).lockCompletedPrayer),
                  onPressed: () => _openVerification(current?.prayer),
                ),
                const SizedBox(height: AppSpacing.sm),

                TextButton(
                  onPressed: () => _confirmEmergencyUnlock(context),
                  child: Text(
                    AppLocalizations.of(context).lockEmergencyUnlock,
                    style: const TextStyle(color: AppColors.darkTextSecondary),
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                if (_blockedPackage != null)
                  Text(
                    AppLocalizations.of(context).lockAppPaused(_friendlyAppName(_blockedPackage!, context)),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.darkTextSecondary,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),

                const SizedBox(height: AppSpacing.sm),
                // Stated plainly rather than buried: someone who genuinely
                // needs help must know instantly that they are not trapped.
                Text(
                  AppLocalizations.of(context).lockEssentialsNeverBlocked,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.darkTextSecondary,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Turn a package name into something readable.
  ///
  /// The native side sends a package identifier, which is what the OS knows.
  /// Resolving it to a real label would require another platform call while
  /// the user is waiting, so common apps are mapped directly and anything
  /// else falls back to its last path segment — "com.foo.bar" reads as "Bar",
  /// which is imperfect but better than showing a raw identifier.
  String _friendlyAppName(String packageName, BuildContext context) {
    const known = {
      'com.instagram.android': 'Instagram',
      'com.zhiliaoapp.musically': 'TikTok',
      'com.facebook.katana': 'Facebook',
      'com.google.android.youtube': 'YouTube',
      'com.netflix.mediaclient': 'Netflix',
      'com.snapchat.android': 'Snapchat',
      'com.twitter.android': 'X',
      'com.reddit.frontpage': 'Reddit',
      'com.android.chrome': 'Chrome',
    };

    final match = known[packageName];
    if (match != null) return match;

    final segment = packageName.split('.').last;
    if (segment.isEmpty) return AppLocalizations.of(context).lockThatApp;
    return segment[0].toUpperCase() + segment.substring(1);
  }

  /// Hand off to the main app's verification flow.
  ///
  /// The lock runs in its own engine with no router, so it asks the native
  /// layer to open the main app on the verification route and close this lock.
  /// The main app owns the camera flow; duplicating it here would mean two
  /// camera implementations to keep in step.
  Future<void> _openVerification(PrayerName? prayer) async {
    final route =
        prayer == null ? '/' : '/verify/${prayer.wireValue}';
    await _channel.invokeMethod('openVerification', {'route': route});
  }

  Future<void> _confirmEmergencyUnlock(BuildContext context) async {
    final settings = ref.read(settingsProvider);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(context).lockEmergencyTitle),
        content: Text(
          AppLocalizations.of(context).lockEmergencyBodyCount(settings.maxEmergencyUnlocksPerDay),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocalizations.of(context).actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Unlock'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      // The unlock must spend the daily quota and stop the blocking service,
      // both of which the orchestrator owns and which live in the main app's
      // engine. Hand off to a route there that performs it; the native layer
      // closes this lock as part of the handoff.
      await _channel.invokeMethod(
        'openVerification',
        {'route': '/emergency-unlock'},
      );
    }
  }
}
