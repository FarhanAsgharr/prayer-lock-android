/// Settings.
///
/// Grouped by what the user is trying to change, not by which subsystem owns
/// the value. Prayer calculation first because it is what people actually
/// adjust; enforcement second; diagnostics last.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/locale_config.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../blocking/data/datasources/blocking_platform_channel.dart';
import '../../../prayer_times/domain/entities/prayer_enums.dart';
import '../../domain/entities/app_settings.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          const _SectionHeader('Prayer times'),

          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: const Text('Location'),
            subtitle: Text(settings.location?.label ?? 'Not set'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/onboarding'),
          ),

          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Calculation method'),
            subtitle: Text(settings.calculationMethod.displayName),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickCalculationMethod(context, ref),
          ),

          ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: const Text('Islamic section'),
            subtitle: Text(settings.section.displayName),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/islamic-section'),
          ),

          ListTile(
            leading: const Icon(Icons.view_agenda_outlined),
            title: const Text('Prayer mode'),
            subtitle: Text(
              settings.prayerGrouping.combinesAnything
                  ? '${settings.prayerGrouping.displayName} — '
                      '${settings.prayerGrouping.slotCount} prayer cards'
                  : 'Five separate prayers',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/prayer-mode'),
          ),

          ListTile(
            leading: const Icon(Icons.mosque_outlined),
            title: const Text("Jumu'ah"),
            subtitle: Text(_jumuahSubtitle(settings)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/jumuah'),
          ),

          ListTile(
            leading: const Icon(Icons.wb_shade),
            title: const Text('Asr timing'),
            subtitle: Text(settings.madhab.description),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickMadhab(context, ref),
          ),

          // Offered only when there is something to undo, so it is not a
          // permanent button that appears to do nothing.
          if (settings.hasSectionOverrides)
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('Reset to section defaults'),
              subtitle: Text(
                'Return to what ${settings.section.displayName} suggests',
              ),
              onTap: () =>
                  ref.read(settingsProvider.notifier).resetToSectionDefaults(),
            ),

          ListTile(
            leading: const Icon(Icons.explore_outlined),
            title: const Text('High latitude rule'),
            subtitle: Text(settings.highLatitudeRule.displayName),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickHighLatitudeRule(context, ref),
          ),

          ListTile(
            leading: const Icon(Icons.translate),
            title: const Text('Language'),
            subtitle: Text(settings.language.displayName),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickLanguage(context, ref),
          ),

          const _SectionHeader('Reminders'),

          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Remind me before prayer'),
            subtitle: Text('${settings.reminderMinutesBefore} minutes before'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickReminderMinutes(context, ref),
          ),

          SwitchListTile(
            secondary: const Icon(Icons.volume_up_outlined),
            title: const Text('Play adhan'),
            subtitle: const Text('Sound the call to prayer at prayer time'),
            value: settings.adhanEnabled,
            onChanged: notifier.setAdhanEnabled,
          ),

          const _SectionHeader('App blocking'),

          if (!BlockingPlatformChannel.isSupported)
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Text(
                'Blocking other apps is not available on this platform. '
                'Prayer times, reminders, tracking and verification all work '
                'normally.',
              ),
            )
          else ...[
            SwitchListTile(
              secondary: const Icon(Icons.lock_outline),
              title: const Text('Block apps during prayer'),
              value: settings.blockingEnabled,
              onChanged: notifier.setBlockingEnabled,
            ),

            ListTile(
              enabled: settings.blockingEnabled,
              leading: const Icon(Icons.apps),
              title: const Text('Blocked apps'),
              subtitle: Text(
                settings.blockedPackages.isEmpty
                    ? 'None selected'
                    : '${settings.blockedPackages.length} selected',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: settings.blockingEnabled
                  ? () => context.push('/settings/blocked-apps')
                  : null,
            ),

            ListTile(
              enabled: settings.blockingEnabled,
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Grace period'),
              subtitle: Text(
                '${settings.lockGracePeriodMinutes} minutes after the adhan '
                'before apps lock',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: settings.blockingEnabled
                  ? () => _pickGracePeriod(context, ref)
                  : null,
            ),

            ListTile(
              enabled: settings.blockingEnabled,
              leading: const Icon(Icons.lock_open_outlined),
              title: const Text('When apps unlock'),
              subtitle: Text(settings.unlockPolicy.description),
              trailing: const Icon(Icons.chevron_right),
              onTap: settings.blockingEnabled
                  ? () => _pickUnlockPolicy(context, ref)
                  : null,
            ),

            ListTile(
              enabled: settings.blockingEnabled,
              leading: const Icon(Icons.hourglass_bottom),
              title: const Text('Prayer durations'),
              subtitle: const Text(
                'See how long each prayer window lasts today',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: settings.blockingEnabled
                  ? () => context.push('/durations')
                  : null,
            ),

            SwitchListTile(
              secondary: const Icon(Icons.wb_twilight),
              title: const Text('Morning protection'),
              subtitle: const Text(
                'Keep apps locked after Fajr begins until you have prayed',
              ),
              value: settings.morningProtectionEnabled,
              onChanged: settings.blockingEnabled
                  ? notifier.setMorningProtection
                  : null,
            ),

            SwitchListTile(
              secondary: const Icon(Icons.history_toggle_off),
              title: const Text('Keep apps locked until qaza is made'),
              // Stated plainly rather than softened. Turning this on can mean
              // a missed Fajr keeps apps blocked until the following dawn, and
              // a user who is surprised by that will uninstall rather than
              // hunt for the setting.
              subtitle: const Text(
                'A missed prayer keeps apps blocked for the rest of the day '
                'until you make it up',
              ),
              value: settings.blockUntilQazaCompleted,
              onChanged: settings.blockingEnabled
                  ? notifier.setBlockUntilQazaCompleted
                  : null,
            ),

            ListTile(
              leading: const Icon(Icons.event_repeat),
              title: const Text('Make-up prayers'),
              subtitle: const Text('Prayers you still owe'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/qaza'),
            ),
          ],

          const _SectionHeader('Prayer time source'),

          SwitchListTile(
            secondary: const Icon(Icons.cloud_sync_outlined),
            title: const Text('Confirm times online'),
            subtitle: const Text(
              'Check prayer times against an online service when possible. '
              'Times are always calculated on this device as well, so the app '
              'works fully offline either way.',
            ),
            value: settings.preferRemotePrayerTimes,
            onChanged: notifier.setPreferRemotePrayerTimes,
          ),

          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Notify when a window ends'),
            subtitle: const Text(
              'Warn before a prayer window closes, and confirm when apps '
              'unlock',
            ),
            value: settings.notifyOnWindowEnd,
            onChanged: notifier.setNotifyOnWindowEnd,
          ),

          const _SectionHeader('Verification'),

          SwitchListTile(
            secondary: const Icon(Icons.camera_alt_outlined),
            title: const Text('Photo verification'),
            subtitle: const Text(
              'Take a photo of your prayer mat to unlock apps',
            ),
            value: settings.requireAiVerification,
            onChanged: notifier.setRequireAiVerification,
          ),

          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Text(
              'Photos are analysed and immediately discarded. They are never '
              'saved to your device, uploaded to storage, or shared.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCalculationMethod(
      BuildContext context, WidgetRef ref) async {
    final current = ref.read(settingsProvider).calculationMethod;
    final choice = await _showOptionSheet<CalculationMethod>(
      context: context,
      title: 'Calculation method',
      options: CalculationMethod.values,
      current: current,
      labelFor: (method) => method.displayName,
    );
    if (choice != null) {
      await ref.read(settingsProvider.notifier).setCalculationMethod(choice);
    }
  }

  Future<void> _pickMadhab(BuildContext context, WidgetRef ref) async {
    final choice = await _showOptionSheet<Madhab>(
      context: context,
      title: 'School',
      options: Madhab.values,
      current: ref.read(settingsProvider).madhab,
      labelFor: (madhab) => madhab.displayName,
    );
    if (choice != null) {
      await ref.read(settingsProvider.notifier).setMadhab(choice);
    }
  }

  Future<void> _pickHighLatitudeRule(
      BuildContext context, WidgetRef ref) async {
    final choice = await _showOptionSheet<HighLatitudeRule>(
      context: context,
      title: 'High latitude rule',
      options: HighLatitudeRule.values,
      current: ref.read(settingsProvider).highLatitudeRule,
      labelFor: (rule) => rule.displayName,
    );
    if (choice != null) {
      await ref.read(settingsProvider.notifier).setHighLatitudeRule(choice);
    }
  }

  Future<void> _pickReminderMinutes(BuildContext context, WidgetRef ref) async {
    const options = [0, 5, 10, 15, 20, 30, 45, 60];
    final choice = await _showOptionSheet<int>(
      context: context,
      title: 'Remind me before prayer',
      options: options,
      current: ref.read(settingsProvider).reminderMinutesBefore,
      labelFor: (minutes) =>
          minutes == 0 ? 'At prayer time' : '$minutes minutes before',
    );
    if (choice != null) {
      await ref.read(settingsProvider.notifier).setReminderMinutes(choice);
    }
  }

  /// One line describing the Friday setup, so the user can see it is
  /// configured without opening the screen.
  static String _jumuahSubtitle(AppSettings settings) {
    final jumuah = settings.jumuah;
    if (!jumuah.enabled) return 'Off — Dhuhr is used every day';

    final profile = jumuah.activeProfile;
    if (profile == null) return "Choose where you pray Jumu'ah";

    return '${profile.location.displayName} · ${profile.formattedRange}';
  }

  Future<void> _pickLanguage(BuildContext context, WidgetRef ref) async {
    final choice = await _showOptionSheet<AppLanguage>(
      context: context,
      title: 'Language',
      options: AppLanguage.values,
      current: ref.read(settingsProvider).language,
      // Each language names itself: someone looking for Urdu is looking for
      // "اردو", not for the English word.
      labelFor: (language) => language.displayName,
    );
    if (choice != null) {
      await ref.read(settingsProvider.notifier).setLanguage(choice);
    }
  }

  Future<void> _pickUnlockPolicy(BuildContext context, WidgetRef ref) async {
    final choice = await _showOptionSheet<UnlockPolicy>(
      context: context,
      title: 'When apps unlock',
      options: UnlockPolicy.values,
      current: ref.read(settingsProvider).unlockPolicy,
      labelFor: (policy) => policy.displayName,
    );
    if (choice != null) {
      await ref.read(settingsProvider.notifier).setUnlockPolicy(choice);
    }
  }

  Future<void> _pickGracePeriod(BuildContext context, WidgetRef ref) async {
    const options = [0, 2, 5, 10, 15, 20, 30];
    final choice = await _showOptionSheet<int>(
      context: context,
      title: 'Grace period',
      options: options,
      current: ref.read(settingsProvider).lockGracePeriodMinutes,
      labelFor: (minutes) =>
          minutes == 0 ? 'Lock immediately' : 'Lock after $minutes minutes',
    );
    if (choice != null) {
      await ref.read(settingsProvider.notifier).setGracePeriod(choice);
    }
  }

  Future<T?> _showOptionSheet<T>({
    required BuildContext context,
    required String title,
    required List<T> options,
    required T current,
    required String Function(T) labelFor,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: RadioGroup<T>(
                groupValue: current,
                onChanged: (value) => Navigator.of(sheetContext).pop(value),
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options[index];
                    return RadioListTile<T>(
                      value: option,
                      title: Text(labelFor(option)),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}
