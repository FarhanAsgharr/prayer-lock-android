/// Settings.
///
/// Grouped by what the user is trying to change, not by which subsystem owns
/// the value. Prayer calculation first because it is what people actually
/// adjust; enforcement second; diagnostics last.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/app_localizations.dart';
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
          _SectionHeader(AppLocalizations.of(context).settingsSectionPrayerTimes),

          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: const Text('Location'),
            subtitle: Text(settings.location?.label ?? AppLocalizations.of(context).commonNotSet),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/onboarding'),
          ),

          ListTile(
            leading: const Icon(Icons.schedule),
            title: Text(AppLocalizations.of(context).settingsCalculationMethod),
            subtitle: Text(settings.calculationMethod.displayName),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickCalculationMethod(context, ref),
          ),

          ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: Text(AppLocalizations.of(context).settingsIslamicSection),
            subtitle: Text(settings.section.displayName),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/islamic-section'),
          ),

          ListTile(
            leading: const Icon(Icons.view_agenda_outlined),
            title: Text(AppLocalizations.of(context).settingsPrayerMode),
            subtitle: Text(
              settings.prayerGrouping.combinesAnything
                  ? AppLocalizations.of(context).settingsPrayerCards(settings.prayerGrouping.displayName, settings.prayerGrouping.slotCount)
                  : AppLocalizations.of(context).groupingNone,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/prayer-mode'),
          ),

          ListTile(
            leading: const Icon(Icons.mosque_outlined),
            title: Text(AppLocalizations.of(context).settingsJumuah),
            subtitle: Text(_jumuahSubtitle(context, settings)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/jumuah'),
          ),

          ListTile(
            leading: const Icon(Icons.wb_shade),
            title: Text(AppLocalizations.of(context).settingsAsrTiming),
            subtitle: Text(settings.madhab.description),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickMadhab(context, ref),
          ),

          // Offered only when there is something to undo, so it is not a
          // permanent button that appears to do nothing.
          if (settings.hasSectionOverrides)
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: Text(AppLocalizations.of(context).settingsResetSectionDefaults),
              subtitle: Text(
                AppLocalizations.of(context).settingsReturnToSuggested(settings.section.displayName),
              ),
              onTap: () =>
                  ref.read(settingsProvider.notifier).resetToSectionDefaults(),
            ),

          ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: Text(AppLocalizations.of(context).settingsHijriDate),
            subtitle: Text(
              settings.hijriAdjustmentDays == 0
                  ? AppLocalizations.of(context).settingsHijriCalculated
                  : settings.hijriAdjustmentDays > 0
                      ? (settings.hijriAdjustmentDays == 1
                          ? AppLocalizations.of(context).settingsHijriDayLater
                          : AppLocalizations.of(context)
                              .settingsHijriDaysLater(
                                  settings.hijriAdjustmentDays))
                      : (settings.hijriAdjustmentDays == -1
                          ? AppLocalizations.of(context).settingsHijriDayEarlier
                          : AppLocalizations.of(context)
                              .settingsHijriDaysEarlier(
                                  settings.hijriAdjustmentDays.abs())),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickHijriAdjustment(context, ref),
          ),

          ListTile(
            leading: const Icon(Icons.explore_outlined),
            title: Text(AppLocalizations.of(context).settingsHighLatitude),
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

          _SectionHeader(AppLocalizations.of(context).settingsSectionReminders),

          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: Text(AppLocalizations.of(context).settingsRemindBefore),
            subtitle: Text(AppLocalizations.of(context).settingsMinutesBefore(settings.reminderMinutesBefore)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickReminderMinutes(context, ref),
          ),

          SwitchListTile(
            secondary: const Icon(Icons.volume_up_outlined),
            title: Text(AppLocalizations.of(context).settingsPlayAdhan),
            subtitle: Text(AppLocalizations.of(context).settingsPlayAdhanBody),
            value: settings.adhanEnabled,
            onChanged: notifier.setAdhanEnabled,
          ),

          _SectionHeader(AppLocalizations.of(context).settingsSectionBlocking),

          if (!BlockingPlatformChannel.isSupported)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Text(
                AppLocalizations.of(context).settingsBlockingUnavailable,
              ),
            )
          else ...[
            SwitchListTile(
              secondary: const Icon(Icons.lock_outline),
              title: Text(AppLocalizations.of(context).settingsBlockDuringPrayer),
              value: settings.blockingEnabled,
              onChanged: notifier.setBlockingEnabled,
            ),

            ListTile(
              enabled: settings.blockingEnabled,
              leading: const Icon(Icons.apps),
              title: Text(AppLocalizations.of(context).settingsBlockedApps),
              subtitle: Text(
                settings.blockedPackages.isEmpty
                    ? AppLocalizations.of(context).settingsNoneSelected
                    : AppLocalizations.of(context).settingsCountSelected(settings.blockedPackages.length),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: settings.blockingEnabled
                  ? () => context.push('/settings/blocked-apps')
                  : null,
            ),

            ListTile(
              enabled: settings.blockingEnabled,
              leading: const Icon(Icons.timer_outlined),
              title: Text(AppLocalizations.of(context).settingsGracePeriod),
              subtitle: Text(
                AppLocalizations.of(context).settingsGraceBody(settings.lockGracePeriodMinutes),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: settings.blockingEnabled
                  ? () => _pickGracePeriod(context, ref)
                  : null,
            ),

            ListTile(
              enabled: settings.blockingEnabled,
              leading: const Icon(Icons.lock_open_outlined),
              title: Text(AppLocalizations.of(context).settingsWhenAppsUnlock),
              subtitle: Text(settings.unlockPolicy.description),
              trailing: const Icon(Icons.chevron_right),
              onTap: settings.blockingEnabled
                  ? () => _pickUnlockPolicy(context, ref)
                  : null,
            ),

            ListTile(
              enabled: settings.blockingEnabled,
              leading: const Icon(Icons.hourglass_bottom),
              title: Text(AppLocalizations.of(context).settingsPrayerDurations),
              subtitle: Text(
                AppLocalizations.of(context).settingsPrayerDurationsBody,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: settings.blockingEnabled
                  ? () => context.push('/durations')
                  : null,
            ),

            SwitchListTile(
              secondary: const Icon(Icons.wb_twilight),
              title: Text(AppLocalizations.of(context).settingsMorningProtection),
              subtitle: Text(
                AppLocalizations.of(context).settingsMorningProtectionBody,
              ),
              value: settings.morningProtectionEnabled,
              onChanged: settings.blockingEnabled
                  ? notifier.setMorningProtection
                  : null,
            ),

            SwitchListTile(
              secondary: const Icon(Icons.history_toggle_off),
              title: Text(AppLocalizations.of(context).settingsBlockUntilQaza),
              // Stated plainly rather than softened. Turning this on can mean
              // a missed Fajr keeps apps blocked until the following dawn, and
              // a user who is surprised by that will uninstall rather than
              // hunt for the setting.
              subtitle: Text(
                AppLocalizations.of(context).settingsBlockUntilQazaBody,
              ),
              value: settings.blockUntilQazaCompleted,
              onChanged: settings.blockingEnabled
                  ? notifier.setBlockUntilQazaCompleted
                  : null,
            ),

            ListTile(
              leading: const Icon(Icons.event_repeat),
              title: Text(AppLocalizations.of(context).settingsMakeUpPrayers),
              subtitle: Text(AppLocalizations.of(context).settingsMakeUpPrayersBody),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/qaza'),
            ),
          ],

          _SectionHeader(AppLocalizations.of(context).settingsSectionSource),

          SwitchListTile(
            secondary: const Icon(Icons.cloud_sync_outlined),
            title: Text(AppLocalizations.of(context).settingsConfirmOnline),
            subtitle: Text(
              AppLocalizations.of(context).settingsConfirmOnlineBody,
            ),
            value: settings.preferRemotePrayerTimes,
            onChanged: notifier.setPreferRemotePrayerTimes,
          ),

          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: Text(AppLocalizations.of(context).settingsNotifyWindowEnd),
            subtitle: Text(
              AppLocalizations.of(context).settingsNotifyWindowEndBody,
            ),
            value: settings.notifyOnWindowEnd,
            onChanged: notifier.setNotifyOnWindowEnd,
          ),

          _SectionHeader(AppLocalizations.of(context).settingsSectionAfterPrayer),

          SwitchListTile(
            secondary: const Icon(Icons.repeat),
            title: Text(AppLocalizations.of(context).settingsTasbih),
            subtitle: Text(
              AppLocalizations.of(context).settingsTasbihBody,
            ),
            value: settings.dhikrRemindersEnabled,
            onChanged: notifier.setDhikrReminders,
          ),

          SwitchListTile(
            secondary: const Icon(Icons.menu_book_outlined),
            title: Text(AppLocalizations.of(context).settingsQuranReminder),
            subtitle: Text(
              AppLocalizations.of(context).settingsQuranReminderBody,
            ),
            value: settings.quranRemindersEnabled,
            onChanged: notifier.setQuranReminders,
          ),

          _SectionHeader(AppLocalizations.of(context).settingsSectionVerification),

          SwitchListTile(
            secondary: const Icon(Icons.camera_alt_outlined),
            title: Text(AppLocalizations.of(context).settingsPhotoVerification),
            subtitle: Text(
              AppLocalizations.of(context).settingsPhotoVerificationBody,
            ),
            value: settings.requireAiVerification,
            onChanged: notifier.setRequireAiVerification,
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Text(
              AppLocalizations.of(context).settingsPhotoPrivacy,
              style: const TextStyle(fontSize: 13),
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
      title: AppLocalizations.of(context).settingsCalculationMethod,
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
      title: AppLocalizations.of(context).settingsHighLatitude,
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
      title: AppLocalizations.of(context).settingsRemindBefore,
      options: options,
      current: ref.read(settingsProvider).reminderMinutesBefore,
      labelFor: (minutes) =>
          minutes == 0 ? AppLocalizations.of(context).settingsAtPrayerTime : AppLocalizations.of(context).settingsMinutesBefore(minutes),
    );
    if (choice != null) {
      await ref.read(settingsProvider.notifier).setReminderMinutes(choice);
    }
  }

  /// One line describing the Friday setup, so the user can see it is
  /// configured without opening the screen.
  static String _jumuahSubtitle(BuildContext context, AppSettings settings) {
    final jumuah = settings.jumuah;
    if (!jumuah.enabled) return AppLocalizations.of(context).jumuahDhuhrEveryDay;

    final mosque = jumuah.activeMosque;
    if (mosque == null) return AppLocalizations.of(context).jumuahChooseMosqueTitle;

    return '${mosque.displayName} · ${mosque.formattedRange}';
  }

  /// Let the user align the computed Hijri date with a local announcement.
  ///
  /// The tabular calendar can differ from a moon sighting by a day. Rather than
  /// pretend otherwise, the offset is theirs to set. It never moves a prayer
  /// time — those are astronomical and exact.
  Future<void> _pickHijriAdjustment(BuildContext context, WidgetRef ref) async {
    final choice = await _showOptionSheet<int>(
      context: context,
      title: AppLocalizations.of(context).settingsHijriAdjustment,
      options: const [-2, -1, 0, 1, 2],
      current: ref.read(settingsProvider).hijriAdjustmentDays,
      labelFor: (days) => switch (days) {
        0 => AppLocalizations.of(context).settingsHijriAsCalculated,
        1 => AppLocalizations.of(context).settingsHijriDayLater,
        -1 => AppLocalizations.of(context).settingsHijriDayEarlier,
        _ => days > 0 ? AppLocalizations.of(context).settingsHijriDaysLater(days) : AppLocalizations.of(context).settingsHijriDaysEarlier(days.abs()),
      },
    );
    if (choice != null) {
      await ref.read(settingsProvider.notifier).setHijriAdjustment(choice);
    }
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
      title: AppLocalizations.of(context).settingsWhenAppsUnlock,
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
      title: AppLocalizations.of(context).settingsGracePeriod,
      options: options,
      current: ref.read(settingsProvider).lockGracePeriodMinutes,
      labelFor: (minutes) =>
          minutes == 0 ? AppLocalizations.of(context).settingsLockImmediately : AppLocalizations.of(context).settingsLockAfterMinutes(minutes),
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
