/// Choosing whether prayers are combined.
///
/// Presented as two independent switches rather than a four-way list, because
/// that is how the decision is actually made: someone who combines Maghrib with
/// Isha has not thereby said anything about Dhuhr and Asr.
///
/// The screen shows the consequence of the setting — how many prayer cards,
/// locks and verifications result — because "combine Dhuhr and Asr" sounds like
/// a display preference and is in fact a change to when the phone unlocks.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../prayer_times/domain/usecases/dynamic_duration_calculator.dart';
import '../../../prayer_times/presentation/providers/prayer_times_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/prayer_grouping.dart';

class PrayerModeScreen extends ConsumerWidget {
  const PrayerModeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final grouping = settings.prayerGrouping;
    final theme = Theme.of(context);
    final strings = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(strings.prayerModeTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              strings.prayerModeIntro,
              style: theme.textTheme.bodyMedium,
            ),
          ),

          // Shown only when the section suggested something, so a user whose
          // section suggests nothing is not told about a default they never saw.
          if (settings.sectionDefaults.prayerGrouping.combinesAnything &&
              settings.prayerGroupingOverride == null)
            _SuggestionNotice(sectionName: settings.section.displayName),

          for (final pair in PrayerPair.values)
            SwitchListTile(
              title: Text(pair.displayName),
              subtitle: Text(
                grouping.includes(pair)
                    ? strings.prayerModeCombinedSubtitle
                    : strings.prayerModeSeparateSubtitle,
              ),
              value: grouping.includes(pair),
              onChanged: (enabled) =>
                  notifier.togglePrayerPair(pair, enabled: enabled),
            ),

          const Divider(height: AppSpacing.xl),

          SwitchListTile(
            title: Text(strings.prayerModeOneConfirmation),
            subtitle: Text(strings.prayerModeOneConfirmationHelp),
            value: settings.combinedVerification,
            // Meaningless with nothing combined, so it is disabled rather than
            // left as a switch that silently does nothing.
            onChanged: grouping.combinesAnything
                ? notifier.setCombinedVerification
                : null,
          ),

          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: _ModePreview(grouping: grouping),
          ),
        ],
      ),
    );
  }
}

class _SuggestionNotice extends ConsumerWidget {
  const _SuggestionNotice({required this.sectionName});

  final String sectionName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Text(
          AppLocalizations.of(context).prayerModeSuggestion(sectionName),
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }
}

/// The day as it will actually appear, with real durations.
///
/// A preview rather than a description: the point of the setting is that a
/// combined window is as long as two, and reading "3 hours 37 minutes" next to
/// "Dhuhr + Asr" conveys that in a way prose does not.
class _ModePreview extends ConsumerWidget {
  const _ModePreview({required this.grouping});

  final PrayerGrouping grouping;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final day = ref.watch(prayerDayProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).prayerModeCardCount(grouping.slotCount),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (day == null)
          Text(
            grouping.description,
            style: theme.textTheme.bodySmall,
          )
        else
          for (final slot in day.slots(grouping))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      slot.displayName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            slot.isCombined ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  Text(
                    formatPrayerDurationShort(slot.duration),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
