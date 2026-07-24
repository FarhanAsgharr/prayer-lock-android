/// First-run setup: location, madhab, calculation method, permissions.
///
/// Ordered so the app becomes useful as early as possible. Location comes
/// first because without it nothing can be computed; permissions come last
/// because they are the most likely step to be abandoned, and a user who
/// quits at that point still has a working prayer-time app.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../blocking/data/datasources/blocking_platform_channel.dart';
import '../../../blocking/domain/entities/blocking_entities.dart';
import '../../../prayer_times/domain/entities/prayer_enums.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../sections/presentation/screens/islamic_section_screen.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/city_catalog.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _pageIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_pageIndex >= _pageCount - 1) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  static const int _pageCount = 4;

  Future<void> _finish() async {
    await ref.read(settingsProvider.notifier).completeOnboarding();
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final canAdvance = _pageIndex != 0 || settings.location != null;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: _ProgressDots(index: _pageIndex, count: _pageCount),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _pageIndex = index),
                children: const [
                  _LocationPage(),
                  _SectionPage(),
                  _MethodPage(),
                  _PermissionsPage(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: FilledButton(
                onPressed: canAdvance ? _next : null,
                child: Text(
                  _pageIndex == _pageCount - 1 ? 'Start praying on time' : 'Continue',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Step ${index + 1} of $count',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) {
          final isActive = i <= index;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: 4,
            width: i == index ? 24 : 12,
            decoration: BoxDecoration(
              color: isActive ? theme.colorScheme.primary : theme.dividerColor,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          );
        }),
      ),
    );
  }
}

class _PageScaffold extends StatelessWidget {
  const _PageScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(subtitle, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.lg),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _LocationPage extends ConsumerStatefulWidget {
  const _LocationPage();

  @override
  ConsumerState<_LocationPage> createState() => _LocationPageState();
}

class _LocationPageState extends ConsumerState<_LocationPage> {
  bool _isDetecting = false;
  String? _error;
  String _query = '';

  Future<void> _detectLocation() async {
    setState(() {
      _isDetecting = true;
      _error = null;
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const _LocationFailure(
          'Location services are turned off. Turn them on, or pick a city below.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const _LocationFailure(
          'Location permission was declined. You can pick a city below instead.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          // Low accuracy is deliberate and sufficient: prayer times shift by
          // under a minute across a whole city, so a GPS fix would cost
          // battery and privacy for no benefit.
          timeLimit: Duration(seconds: 20),
        ),
      );

      final nearest = CityCatalog.nearest(
        position.latitude,
        position.longitude,
      );

      await ref.read(settingsProvider.notifier).setLocation(
            PrayerLocation(
              latitude: position.latitude,
              longitude: position.longitude,
              // The catalog supplies the IANA zone, which the OS position
              // does not carry.
              timezone: nearest.timezone,
              label: nearest.name,
              isAutoDetected: true,
            ),
          );
    } on _LocationFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (error) {
      if (mounted) {
        setState(() => _error =
            'Could not determine your location. Pick a city below instead.');
      }
    } finally {
      if (mounted) setState(() => _isDetecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(settingsProvider).location;
    final matches = CityCatalog.search(_query);

    return _PageScaffold(
      title: 'Where are you?',
      subtitle:
          'Prayer times depend on your location. Detect it automatically, or '
          'choose the nearest city.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: _isDetecting ? null : _detectLocation,
            icon: _isDetecting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
            label: Text(_isDetecting ? 'Detecting…' : 'Use my location'),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.warning),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search for a city',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: ListView.builder(
              itemCount: matches.length,
              itemBuilder: (context, index) {
                final city = matches[index];
                final isSelected = selected?.label == city.name;

                return ListTile(
                  title: Text(city.name),
                  subtitle: Text(city.country),
                  trailing: isSelected
                      ? const Icon(Icons.check, color: AppColors.success)
                      : null,
                  onTap: () =>
                      ref.read(settingsProvider.notifier).setLocation(
                            PrayerLocation(
                              latitude: city.latitude,
                              longitude: city.longitude,
                              timezone: city.timezone,
                              label: city.name,
                              isAutoDetected: false,
                            ),
                          ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationFailure implements Exception {
  const _LocationFailure(this.message);
  final String message;
}

/// Choosing an Islamic section during first-run setup.
///
/// Uses the same picker as the settings screen rather than a simplified copy,
/// so the two cannot offer different sections or describe them differently.
/// Nothing is required here: the default is already a working configuration,
/// and a user who skips past this page gets a correct schedule.
class _SectionPage extends ConsumerWidget {
  const _SectionPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return _PageScaffold(
      title: 'Which Islamic section do you follow?',
      subtitle:
          'This sets a starting point for prayer times and how prayers are '
          'grouped. You can change everything later.',
      child: IslamicSectionPicker(
        selected: settings.section,
        onSelected: notifier.setSection,
        onLabelChanged: notifier.setCustomSectionLabel,
        // The page already carries the explanation in its subtitle.
        showIntro: false,
      ),
    );
  }
}

class _MethodPage extends ConsumerWidget {
  const _MethodPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(settingsProvider).calculationMethod;

    return _PageScaffold(
      title: 'Calculation method',
      subtitle:
          'Different authorities use different sun angles for Fajr and Isha. '
          'Choose the one your local mosque follows.',
      child: RadioGroup<CalculationMethod>(
        groupValue: selected,
        onChanged: (value) => value == null
            ? null
            : ref.read(settingsProvider.notifier).setCalculationMethod(value),
        child: ListView(
          children: CalculationMethod.values.map((method) {
            return RadioListTile<CalculationMethod>(
              value: method,
              title: Text(method.displayName),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _PermissionsPage extends ConsumerStatefulWidget {
  const _PermissionsPage();

  @override
  ConsumerState<_PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends ConsumerState<_PermissionsPage>
    with WidgetsBindingObserver {
  final BlockingPlatformChannel _channel = BlockingPlatformChannel();
  BlockingPermissions _permissions = const BlockingPermissions.none();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Special permissions are granted in Settings, outside our process, so
    // the only way to learn the result is to re-check on return.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final permissions = await _channel.getPermissionStatus();
    if (mounted) setState(() => _permissions = permissions);
  }

  @override
  Widget build(BuildContext context) {
    if (!BlockingPlatformChannel.isSupported) {
      return const _PageScaffold(
        title: 'App blocking',
        subtitle:
            'Restricting other apps is not available on this platform. '
            'Prayer times, reminders, tracking and verification all work '
            'normally.',
        child: SizedBox.shrink(),
      );
    }

    // iOS gates all of app blocking behind a single Screen Time authorization,
    // where Android needs three separate special permissions. Showing the
    // Android labels on iOS would be wrong, so each platform gets its own copy.
    if (BlockingPlatformChannel.usesSystemPicker) {
      return _PageScaffold(
        title: 'Allow Screen Time access',
        subtitle:
            'Prayer Lock uses Screen Time to pause distracting apps during '
            'prayer. iPhone asks for this once. You can skip it and enable it '
            'later in Settings.',
        child: ListView(
          children: [
            _PermissionTile(
              title: 'Screen Time',
              description:
                  'Lets Prayer Lock pause the apps you choose during prayer, '
                  'and release them once you have prayed. Your app choices stay '
                  'private — even Prayer Lock cannot see which apps you pick.',
              granted: _permissions.hasUsageStats,
              onRequest: () async {
                await _channel.requestUsageStatsPermission();
                await _refresh();
              },
            ),
          ],
        ),
      );
    }

    return _PageScaffold(
      title: 'Allow app blocking',
      subtitle:
          'These permissions let Prayer Lock restrict distracting apps during '
          'prayer. Without them, blocking cannot work. You can skip this and '
          'enable it later.',
      child: ListView(
        children: [
          _PermissionTile(
            title: 'Usage access',
            description: 'Lets the app see which app is currently open.',
            granted: _permissions.hasUsageStats,
            onRequest: () async {
              await _channel.requestUsageStatsPermission();
            },
          ),
          _PermissionTile(
            title: 'Display over other apps',
            description: 'Lets the prayer reminder appear over a blocked app.',
            granted: _permissions.hasOverlay,
            onRequest: () async {
              await _channel.requestOverlayPermission();
            },
          ),
          _PermissionTile(
            title: 'Ignore battery optimisation',
            description:
                'Stops the system pausing the reminder service in the '
                'background. Strongly recommended on Samsung and Xiaomi '
                'devices.',
            granted: _permissions.batteryOptimizationDisabled,
            onRequest: () async {
              await _channel.requestDisableBatteryOptimization();
            },
          ),
        ],
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.title,
    required this.description,
    required this.granted,
    required this.onRequest,
  });

  final String title;
  final String description;
  final bool granted;
  final Future<void> Function() onRequest;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(
              granted ? Icons.check_circle : Icons.radio_button_unchecked,
              color: granted ? AppColors.success : Theme.of(context).dividerColor,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            if (!granted)
              TextButton(onPressed: onRequest, child: const Text('Allow')),
          ],
        ),
      ),
    );
  }
}
