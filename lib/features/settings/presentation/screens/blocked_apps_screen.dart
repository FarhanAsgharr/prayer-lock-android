/// Picker for which apps to restrict during prayer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../blocking/data/datasources/blocking_platform_channel.dart';
import '../../../blocking/domain/entities/blocking_entities.dart';
import '../providers/settings_provider.dart';

/// Apps installed on the device, loaded once per visit.
final installedAppsProvider = FutureProvider<List<InstalledApp>>((ref) async {
  return BlockingPlatformChannel().getInstalledApps();
});

/// Commonly-blocked packages, offered as a one-tap starting point.
///
/// Bundled rather than fetched so the picker is useful offline and on first
/// run. The user can block anything installed; this list only saves scrolling.
const Map<String, String> _suggestedPackages = {
  'com.instagram.android': 'Instagram',
  'com.zhiliaoapp.musically': 'TikTok',
  'com.facebook.katana': 'Facebook',
  'com.google.android.youtube': 'YouTube',
  'com.netflix.mediaclient': 'Netflix',
  'com.snapchat.android': 'Snapchat',
  'com.twitter.android': 'X',
  'com.reddit.frontpage': 'Reddit',
  'com.tencent.ig': 'PUBG Mobile',
  'com.activision.callofduty.shooter': 'Call of Duty Mobile',
  'com.android.chrome': 'Chrome',
};

class BlockedAppsScreen extends ConsumerWidget {
  const BlockedAppsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final apps = ref.watch(installedAppsProvider);

    // iOS selects apps through Apple's system picker, which returns opaque
    // tokens — the app is never told which apps were chosen. So the whole
    // list-and-checkbox UI does not apply there; a single picker button does.
    if (BlockingPlatformChannel.usesSystemPicker) {
      return _IosPickerView();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Blocked apps'),
        actions: [
          TextButton(
            onPressed: () => _applySuggested(ref),
            child: const Text('Suggested'),
          ),
        ],
      ),
      body: apps.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _ErrorView(message: error.toString()),
        data: (installed) {
          if (installed.isEmpty) {
            return const _EmptyView();
          }

          return ListView.builder(
            itemCount: installed.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Text(
                    'Selected apps will be unavailable from the start of each '
                    'prayer until you confirm you have prayed.\n\n'
                    'Phone, messages and settings can never be blocked.',
                  ),
                );
              }

              final app = installed[index - 1];
              final isBlocked =
                  settings.blockedPackages.contains(app.packageIdentifier);

              return CheckboxListTile(
                value: isBlocked,
                onChanged: (_) => ref
                    .read(settingsProvider.notifier)
                    .toggleBlockedPackage(app.packageIdentifier),
                title: Text(app.appName),
                subtitle: Text(
                  app.packageIdentifier,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Select every suggested app that is actually installed.
  ///
  /// Intersecting with the installed list avoids blocking package names that
  /// are not present, which would silently do nothing and mislead the user
  /// into thinking they were protected.
  Future<void> _applySuggested(WidgetRef ref) async {
    final installed = await ref.read(installedAppsProvider.future);
    final installedIdentifiers =
        installed.map((app) => app.packageIdentifier).toSet();

    final selection = _suggestedPackages.keys
        .where(installedIdentifiers.contains)
        .toSet();

    final existing = ref.read(settingsProvider).blockedPackages;
    await ref
        .read(settingsProvider.notifier)
        .setBlockedPackages({...existing, ...selection});
  }
}

/// iOS blocked-app management: a single button that opens Apple's picker.
///
/// The count of selected apps is all iOS lets the app know — never their
/// identities — so that is all this screen shows.
class _IosPickerView extends ConsumerStatefulWidget {
  @override
  ConsumerState<_IosPickerView> createState() => _IosPickerViewState();
}

class _IosPickerViewState extends ConsumerState<_IosPickerView> {
  int? _selectedCount;

  Future<void> _openPicker() async {
    final count = await BlockingPlatformChannel().presentAppPicker();
    if (mounted) setState(() => _selectedCount = count);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Blocked apps')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choose which apps to pause during prayer. On iPhone, apps are '
              'selected through Apple\'s Screen Time picker — Prayer Lock '
              'never sees which apps you pick, only how many.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_selectedCount != null)
              Text(
                _selectedCount == 0
                    ? 'No apps selected'
                    : '$_selectedCount app(s) or categories selected',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              icon: const Icon(Icons.apps),
              label: const Text('Choose apps'),
              onPressed: _openPicker,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Phone, Messages and Settings can never be paused.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.apps, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No apps found',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'App blocking is only available on Android.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.warning),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Could not list your apps',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
