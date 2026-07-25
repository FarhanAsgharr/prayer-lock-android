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

import '../../../../l10n/app_localizations.dart';
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
      // The keyboard overlays rather than resizes. Onboarding pages are
      // full-height with their own scrolling — the city search has a scrollable
      // results list — so resizing only squeezes fixed controls into a space
      // too small for them and overflows, while the list under the keyboard
      // scrolls perfectly well.
      resizeToAvoidBottomInset: false,
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
                  _pageIndex == _pageCount - 1 ? AppLocalizations.of(context).onboardingStart : AppLocalizations.of(context).actionContinue,
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
      label: AppLocalizations.of(context).onboardingStepOf(index + 1, count),
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
    // Resolved before any await. Reading localisations after one means reading
    // them from a context that may already be gone, which is what the analyzer
    // is warning about — and the failure is a crash on a slow GPS fix.
    final strings = AppLocalizations.of(context);

    setState(() {
      _isDetecting = true;
      _error = null;
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw _LocationFailure(strings.onboardingLocationOff);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw _LocationFailure(strings.onboardingLocationDenied);
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
            strings.onboardingLocationFailed);
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
      title: AppLocalizations.of(context).onboardingWhereAreYou,
      subtitle:
          AppLocalizations.of(context).onboardingWhereBody,
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
            label: Text(_isDetecting ? AppLocalizations.of(context).onboardingDetecting : AppLocalizations.of(context).onboardingUseLocation),
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
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: AppLocalizations.of(context).onboardingSearchCity,
              border: const OutlineInputBorder(),
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
      title: AppLocalizations.of(context).onboardingSectionQuestion,
      subtitle:
          AppLocalizations.of(context).onboardingSectionBody,
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
      title: AppLocalizations.of(context).settingsCalculationMethod,
      subtitle:
          AppLocalizations.of(context).onboardingMethodBody,
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
      return _PageScaffold(
        title: AppLocalizations.of(context).settingsSectionBlocking,
        subtitle:
            AppLocalizations.of(context).onboardingBlockingUnavailable,
        child: const SizedBox.shrink(),
      );
    }

    // iOS gates all of app blocking behind a single Screen Time authorization,
    // where Android needs three separate special permissions. Showing the
    // Android labels on iOS would be wrong, so each platform gets its own copy.
    if (BlockingPlatformChannel.usesSystemPicker) {
      return _PageScaffold(
        title: AppLocalizations.of(context).onboardingScreenTimeTitle,
        subtitle:
            AppLocalizations.of(context).onboardingScreenTimeBody,
        child: ListView(
          children: [
            _PermissionTile(
              title: AppLocalizations.of(context).onboardingScreenTime,
              description:
                  AppLocalizations.of(context).onboardingScreenTimeDetail,
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
      title: AppLocalizations.of(context).onboardingBlockingTitle,
      subtitle:
          AppLocalizations.of(context).onboardingBlockingBody,
      child: ListView(
        children: [
          _PermissionTile(
            title: AppLocalizations.of(context).onboardingUsageAccess,
            description: AppLocalizations.of(context).onboardingUsageAccessBody,
            granted: _permissions.hasUsageStats,
            onRequest: () async {
              await _channel.requestUsageStatsPermission();
            },
          ),
          _PermissionTile(
            title: AppLocalizations.of(context).onboardingOverlay,
            description: AppLocalizations.of(context).onboardingOverlayBody,
            granted: _permissions.hasOverlay,
            onRequest: () async {
              await _channel.requestOverlayPermission();
            },
          ),
          _PermissionTile(
            title: AppLocalizations.of(context).onboardingBattery,
            description:
                AppLocalizations.of(context).onboardingBatteryBody,
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
              TextButton(onPressed: onRequest, child: Text(AppLocalizations.of(context).onboardingAllow)),
          ],
        ),
      ),
    );
  }
}
