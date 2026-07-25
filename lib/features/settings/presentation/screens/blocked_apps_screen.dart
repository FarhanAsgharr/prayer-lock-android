/// Picker for which apps to restrict during prayer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
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
        title: Text(AppLocalizations.of(context).blockedAppsTitle),
        actions: [
          TextButton(
            onPressed: () => _applySuggested(ref),
            child: Text(AppLocalizations.of(context).blockedAppsSuggested),
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
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Text(
                    '${AppLocalizations.of(context).blockedAppsIntro}\n\n'
                    '${AppLocalizations.of(context).blockedAppsEssentials}',
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
      appBar: AppBar(title: Text(AppLocalizations.of(context).blockedAppsTitle)),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AppLocalizations.of(context).blockedAppsIosIntro,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_selectedCount != null)
              Text(
                _selectedCount == 0
                    ? AppLocalizations.of(context).settingsNoneSelected
                    : AppLocalizations.of(context).blockedAppsSelectedCount(_selectedCount!),
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              icon: const Icon(Icons.apps),
              label: Text(AppLocalizations.of(context).blockedAppsChoose),
              onPressed: _openPicker,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              AppLocalizations.of(context).blockedAppsEssentials,
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
              AppLocalizations.of(context).blockedAppsNoneFound,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              AppLocalizations.of(context).blockedAppsAndroidOnly,
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
              AppLocalizations.of(context).blockedAppsListFailed,
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
