/// Jumu'ah settings.
///
/// Every value here is a wall-clock time set by a mosque, not something the app
/// can compute, so this screen is where the user tells it what their mosques
/// actually do. It shows the consequence of each choice — the resulting window,
/// and a warning when a configured time falls outside Dhuhr and had to be
/// clamped — because a Jumu'ah time that is silently ignored looks identical to
/// one that works.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../prayer_times/presentation/providers/prayer_times_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/jumuah_profile.dart';
import '../../domain/usecases/friday_detector.dart';
import '../../domain/usecases/jumuah_scheduler.dart';
import '../providers/jumuah_providers.dart';

class JumuahSettingsScreen extends ConsumerWidget {
  const JumuahSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(jumuahManagerProvider);
    final settings = ref.watch(jumuahStatusProvider);
    final jumuah = manager.settings;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Jumu'ah")),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              "On Fridays, Dhuhr is replaced by Jumu'ah at the time your mosque "
              'holds it. Every other day is unchanged.',
              style: theme.textTheme.bodyMedium,
            ),
          ),

          SwitchListTile(
            secondary: const Icon(Icons.mosque_outlined),
            title: const Text("Smart Jumu'ah"),
            subtitle: Text(
              jumuah.enabled
                  ? "Jumu'ah replaces Dhuhr on Fridays"
                  : 'Dhuhr is used every day',
            ),
            value: jumuah.enabled,
            onChanged: (value) => manager.setEnabled(value),
          ),

          if (jumuah.enabled) ...[
            const _SectionHeader('Where you pray'),

            RadioGroup<JumuahLocation>(
              groupValue: jumuah.selectedLocation,
              onChanged: (value) => value == null
                  ? null
                  : manager.chooseLocation(value),
              child: Column(
                children: [
                  for (final location in JumuahLocation.values)
                    RadioListTile<JumuahLocation>(
                      value: location,
                      title: Text(location.displayName),
                      subtitle: Text(
                        jumuah.profileFor(location).formattedRange,
                      ),
                    ),
                ],
              ),
            ),

            if (jumuah.needsLocationChoice)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Text(
                  "Choose a mosque so Jumu'ah can replace Dhuhr this Friday.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.warning,
                  ),
                ),
              ),

            const _SectionHeader('Mosque times'),

            for (final location in JumuahLocation.values)
              _ProfileEditor(profile: jumuah.profileFor(location)),

            const _SectionHeader('Reset'),

            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('Reset mosque times'),
              subtitle: const Text('Restore 2:00 PM and 1:15 PM defaults'),
              onTap: () => manager.resetProfiles(),
            ),

            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Forget where I pray'),
              subtitle: const Text(
                "You'll be asked again on the next Friday",
              ),
              // Only offered once there is something to forget.
              enabled: jumuah.selectedLocation != null,
              onTap: jumuah.selectedLocation == null
                  ? null
                  : () => manager.resetSelection(),
            ),

            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: _TodayPreview(isFriday: settings.isFriday),
            ),
          ],
        ],
      ),
    );
  }
}

/// Editable start and end times for one mosque.
class _ProfileEditor extends ConsumerWidget {
  const _ProfileEditor({required this.profile});

  final JumuahProfile profile;

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref, {
    required bool isStart,
  }) async {
    final current = isStart ? profile.startsAt : profile.endsAt;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      helpText: isStart
          ? "${profile.location.displayName} — Jumu'ah starts"
          : '${profile.location.displayName} — verification closes',
    );
    if (picked == null) return;

    final next = LocalTimeOfDay(picked.hour, picked.minute);
    final updated = isStart
        ? profile.copyWith(
            startsAt: next,
            // Keep the window valid: dragging the start past the end would
            // otherwise produce a negative window that the scheduler discards
            // silently, and the user would see Dhuhr with no explanation.
            endsAt: next < profile.endsAt ? profile.endsAt : next.plusMinutes(15),
          )
        : profile.copyWith(
            endsAt: next > profile.startsAt
                ? next
                : profile.startsAt.plusMinutes(15),
          );

    await ref.read(jumuahManagerProvider).updateProfile(updated);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(profile.location.displayName,
              style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pick(context, ref, isStart: true),
                  child: Text('Starts ${profile.startsAt.format()}'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pick(context, ref, isStart: false),
                  child: Text('Ends ${profile.endsAt.format()}'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What today actually looks like under the current configuration.
class _TodayPreview extends ConsumerWidget {
  const _TodayPreview({required this.isFriday});

  final bool isFriday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final date = ref.watch(localDateProvider);

    if (!isFriday) {
      final next = FridayDetector.nextFridayOnOrAfter(date);
      final days = next.difference(date).inDays;

      return Text(
        days == 0
            ? "Today is Friday."
            : "Today is not Friday. Jumu'ah next applies in "
                '$days ${days == 1 ? 'day' : 'days'}.',
        style: theme.textTheme.bodySmall,
      );
    }

    final windows = ref.watch(todayWindowsProvider);
    final manager = ref.watch(jumuahManagerProvider);
    final timezone = ref.watch(settingsProvider).location?.timezone;

    if (windows == null || timezone == null) {
      return Text("Today is Friday.", style: theme.textTheme.bodySmall);
    }

    final result = manager.applyWithResult(windows, timezone: timezone);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          switch (result.application) {
            JumuahApplication.applied =>
              "Today Dhuhr is replaced by Jumu'ah.",
            JumuahApplication.appliedWithClamping =>
              "Today Dhuhr is replaced by Jumu'ah, adjusted to fit inside "
                  "Dhuhr's time.",
            JumuahApplication.invalidProfile =>
              "Your Jumu'ah time falls outside Dhuhr today, so ordinary Dhuhr "
                  'is being used.',
            JumuahApplication.notApplied =>
              "Jumu'ah is not active today.",
          },
          style: theme.textTheme.bodySmall?.copyWith(
            color: result.application == JumuahApplication.invalidProfile
                ? AppColors.danger
                : null,
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      );
}
