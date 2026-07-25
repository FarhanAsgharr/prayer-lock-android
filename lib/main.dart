/// Application entrypoints.
///
/// Two exist. `main` runs the normal app. `lockScreenMain` runs the prayer
/// lock in a separate Flutter engine, launched from the native blocking
/// service, so showing the lock never disturbs the user's place in the app.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'core/config/app_router.dart';
import 'core/config/locale_config.dart';
import 'core/config/deep_link_handler.dart';
import 'core/notifications/notification_providers.dart';
import 'core/scheduling/daily_schedule_refresher.dart';
import 'core/storage/app_database.dart';
import 'core/storage/storage_providers.dart';
import 'features/blocking/presentation/providers/orchestrator_provider.dart';
import 'features/blocking/presentation/screens/lock_screen.dart';
import 'features/settings/presentation/providers/settings_provider.dart';
import 'shared/theme/app_theme.dart';
import 'core/utils/app_log.dart';

/// Loads the timezone database.
///
/// Required before any prayer time can be computed: without it, every DST
/// transition and every non-UTC location produces wrong times.
void _initialiseTimezones() {
  tz_data.initializeTimeZones();
  // A guaranteed-initialised default. The notification scheduler resets this to
  // the prayer location's zone on every reschedule; until then, tz.local must
  // still resolve rather than throw, which it does not do on its own.
  tz.setLocalLocation(tz.getLocation('UTC'));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  _initialiseTimezones();

  // Read preferences before the first frame so the dashboard can render the
  // real schedule immediately rather than flashing an empty state.
  final preferences = await SharedPreferences.getInstance();

  // Open the encrypted database up front. Key derivation is deliberately slow,
  // so doing it lazily would stall whichever screen queried first.
  final database = await AppDatabase.open();
  logDiagnostic('Encrypted database ready');

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        appDatabaseProvider.overrideWithValue(database),
      ],
      child: const PrayerLockApp(),
    ),
  );
}

/// Entrypoint for the lock screen's dedicated engine.
///
/// Referenced by name from `LockScreenActivity.warmUpEngine`. The `@pragma`
/// annotation is required: without it, tree shaking removes this function in
/// release builds and the lock screen renders a blank white page.
@pragma('vm:entry-point')
Future<void> lockScreenMain() async {
  WidgetsFlutterBinding.ensureInitialized();

  _initialiseTimezones();
  final preferences = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: const PrayerLockScreenApp(),
    ),
  );
}

class PrayerLockApp extends ConsumerStatefulWidget {
  const PrayerLockApp({super.key});

  @override
  ConsumerState<PrayerLockApp> createState() => _PrayerLockAppState();
}

class _PrayerLockAppState extends ConsumerState<PrayerLockApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Reading the provider starts the settings listener that keeps
    // notifications scheduled. Deferred past the first frame so startup is
    // not blocked on writing alarms.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationSyncProvider);
      // Keeps the prayer schedule current across midnight, travel, DST and
      // settings changes, and keeps the offline cache filled ahead of today.
      unawaited(ref.read(dailyScheduleRefresherProvider).start());
      // Drains anything queued while offline, and begins watching for
      // connectivity so a restored connection triggers an upload.
      unawaited(ref.read(syncEngineProvider).start());
      // Recovers any lock session orphaned by a crash or reboot, then begins
      // converging enforcement onto whatever the prayer schedule requires.
      unawaited(ref.read(lockStateProvider.notifier).start());
      // Deliver any route the native lock screen handed over — the "complete
      // prayer" tap that opens verification.
      unawaited(
        DeepLinkHandler(ref.read(appRouterProvider)).start(),
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    // Covers the cases the settings listener cannot see: the device timezone
    // changed, the clock was adjusted, or the app sat closed long enough for
    // the seven-day horizon to run down.
    unawaited(
      ref.read(notificationSyncProvider).refreshIfStale(
            ref.read(settingsProvider),
          ),
    );

    // The date may have rolled over, or the device may have travelled, while
    // the app was backgrounded. Checked before enforcement is re-evaluated so
    // the lock decision runs against the correct day's windows.
    unawaited(
      ref
          .read(dailyScheduleRefresherProvider)
          .refreshIfNeeded()
          .then((_) => ref.read(lockStateProvider.notifier).evaluate()),
    );

    // Upload anything recorded while the app was in the background.
    unawaited(ref.read(syncEngineProvider).drain());
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Prayer Lock',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      // Null follows the device. Arabic and Urdu flip the whole layout to
      // right-to-left through Directionality, which the framework resolves
      // from the locale once the delegates below are installed.
      locale: ref.watch(appLocaleProvider),
      supportedLocales: LocaleConfig.supportedLocales,
      localizationsDelegates: LocaleConfig.delegates,
      localeListResolutionCallback: LocaleConfig.resolve,
      routerConfig: router,
    );
  }
}

/// Minimal app shell for the lock screen engine.
///
/// Deliberately not routed: the lock screen is a single destination, and a
/// router here would permit navigating away from a screen whose entire purpose
/// is to not be navigated away from.
class PrayerLockScreenApp extends StatelessWidget {
  const PrayerLockScreenApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Immersive: hides the status and navigation bars so the reminder is not
    // competing with notification badges from the app just blocked.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    return MaterialApp(
      title: 'Prayer Lock',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      // The lock screen runs in its own engine with no settings provider, so
      // it follows the device rather than the in-app language choice.
      supportedLocales: LocaleConfig.supportedLocales,
      localizationsDelegates: LocaleConfig.delegates,
      localeListResolutionCallback: LocaleConfig.resolve,
      home: const LockScreen(),
    );
  }
}
