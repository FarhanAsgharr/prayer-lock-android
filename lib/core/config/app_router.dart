/// Application routing.
///
/// Declarative rather than imperative because navigation is triggered from
/// places that have no BuildContext — notification taps and the native lock
/// screen both need to land on a specific route.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/blocking/presentation/screens/emergency_unlock_screen.dart';
import '../../features/dashboard/presentation/screens/analytics_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../../features/prayer_times/domain/entities/prayer_enums.dart';
import '../../features/prayer_times/presentation/screens/prayer_durations_screen.dart';
import '../../features/sections/presentation/screens/islamic_section_screen.dart';
import '../../features/sections/presentation/screens/prayer_mode_screen.dart';
import '../../features/settings/presentation/providers/settings_provider.dart';
import '../../features/settings/presentation/screens/blocked_apps_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/tracking/presentation/screens/qaza_screen.dart';
import '../../features/verification/presentation/screens/verification_screen.dart';

abstract final class Routes {
  static const String dashboard = '/';
  static const String onboarding = '/onboarding';
  static const String settings = '/settings';
  static const String blockedApps = '/settings/blocked-apps';
  static const String verify = '/verify';
  static const String emergencyUnlock = '/emergency-unlock';
  static const String analytics = '/analytics';

  /// Today's windows and how long each blocks apps.
  static const String durations = '/durations';

  /// Outstanding make-up prayers.
  static const String qaza = '/qaza';

  /// Choosing an Islamic section.
  static const String islamicSection = '/settings/islamic-section';

  /// Choosing whether prayers are combined.
  static const String prayerMode = '/settings/prayer-mode';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.dashboard,
    redirect: (context, state) {
      final settings = ref.read(settingsProvider);

      // A user who has not finished onboarding has no location, so every
      // other screen would render an empty state. Send them to onboarding
      // once, rather than letting them wander through broken screens.
      final isOnboarding = state.matchedLocation == Routes.onboarding;
      if (!settings.onboardingComplete && !isOnboarding) {
        return Routes.onboarding;
      }
      if (settings.onboardingComplete && isOnboarding) {
        return Routes.dashboard;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.dashboard,
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'blocked-apps',
            builder: (context, state) => const BlockedAppsScreen(),
          ),
          GoRoute(
            path: 'islamic-section',
            builder: (context, state) => const IslamicSectionScreen(),
          ),
          GoRoute(
            path: 'prayer-mode',
            builder: (context, state) => const PrayerModeScreen(),
          ),
        ],
      ),
      GoRoute(
        path: Routes.emergencyUnlock,
        builder: (context, state) => const EmergencyUnlockScreen(),
      ),
      GoRoute(
        path: Routes.analytics,
        builder: (context, state) => const AnalyticsScreen(),
      ),
      GoRoute(
        path: Routes.durations,
        builder: (context, state) => const PrayerDurationsScreen(),
      ),
      GoRoute(
        path: Routes.qaza,
        builder: (context, state) => const QazaScreen(),
      ),
      GoRoute(
        path: '${Routes.verify}/:prayer',
        builder: (context, state) {
          final raw = state.pathParameters['prayer'];
          PrayerName? prayer;
          try {
            prayer = raw == null ? null : PrayerName.fromWire(raw);
          } on ArgumentError {
            prayer = null;
          }

          if (prayer == null) {
            return const _RouteErrorScreen(
              message: 'That prayer could not be found.',
            );
          }
          return VerificationScreen(prayer: prayer);
        },
      ),
    ],
    errorBuilder: (context, state) => _RouteErrorScreen(
      message: 'No screen exists at ${state.uri}',
    ),
  );
});

class _RouteErrorScreen extends StatelessWidget {
  const _RouteErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Something went wrong')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go(Routes.dashboard),
                child: const Text('Back to prayers'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
