/// Today's prayer windows and how long each one blocks apps.
///
/// The screen exists to answer one question that the dashboard cannot: "why is
/// my phone locked, and for how long?". Under dynamic durations the answer
/// changes daily and differs by hours between prayers, so showing the derivation
/// — start, what ends it, and the resulting duration — is what makes the
/// behaviour feel principled rather than arbitrary.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/prayer_day.dart';
import '../../domain/entities/prayer_enums.dart';
import '../../domain/usecases/dynamic_duration_calculator.dart';
import '../providers/prayer_times_provider.dart';
import '../../../../core/di/strategy_providers.dart';

class PrayerDurationsScreen extends ConsumerWidget {
  const PrayerDurationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(prayerDayProvider);
    final settings = ref.watch(settingsProvider);
    final now = ref.watch(nowProvider);

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).durationsTitle)),
      body: day == null
          ? const _EmptyState()
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xxl,
              ),
              children: [
                _PolicyBanner(settings: settings, day: day),
                const SizedBox(height: AppSpacing.md),
                for (final entry in day.entries) ...[
                  _DurationCard(
                    entry: entry,
                    timezone: settings.location?.timezone,
                    now: now,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                const SizedBox(height: AppSpacing.sm),
                _SourceFooter(
                  source: ref.watch(prayerTimeSourceProvider),
                  isStale: ref.watch(prayerTimesAreStaleProvider),
                ),
              ],
            ),
    );
  }
}

/// Explains what the durations mean under the current unlock policy.
///
/// Without this the numbers are ambiguous: three hours and thirty-seven minutes
/// is a deadline under one policy and a sentence under the other.
class _PolicyBanner extends ConsumerWidget {
  const _PolicyBanner({required this.settings, required this.day});

  final AppSettings settings;
  final PrayerDay day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Asked of the strategy rather than compared against a policy value: the
    // total only means something under an arrangement that blocks for the whole
    // window, and that is the strategy's own definition, not this screen's.
    final holdsThroughout =
        ref.watch(blockingStrategyProvider).holdsAfterVerification;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            settings.unlockPolicy.displayName,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            settings.unlockPolicy.description,
            style: theme.textTheme.bodySmall,
          ),
          if (holdsThroughout) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              AppLocalizations.of(context).durationsTotalBlocking(formatPrayerDuration(day.totalWindowDuration)),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One prayer: start, end boundary, and computed duration.
class _DurationCard extends StatelessWidget {
  const _DurationCard({
    required this.entry,
    required this.timezone,
    required this.now,
  });

  final PrayerEntry entry;
  final String? timezone;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = entry.window.contains(now);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isActive
              ? theme.colorScheme.primary
              : theme.dividerColor,
          width: isActive ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.prayer.displayName,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    'Now',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Field(
                  label: 'Start',
                  value: _formatTime(entry.window.startsAt, timezone),
                ),
              ),
              Expanded(
                child: _Field(
                  label: 'End',
                  value: entry.window.boundary.displayName,
                  secondary: _formatTime(entry.window.endsAt, timezone),
                ),
              ),
              Expanded(
                child: _Field(
                  label: 'Duration',
                  value: formatPrayerDurationShort(entry.duration),
                  secondary: formatPrayerDuration(entry.duration),
                  emphasise: true,
                ),
              ),
            ],
          ),
          if (isActive) ...[
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(
              value: entry.window.progressAt(now),
              minHeight: 4,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${formatPrayerDuration(entry.window.remainingAt(now))} left',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  /// Rendered in the *location's* timezone, not the device's.
  ///
  /// A traveller whose phone has switched zones must still see the schedule for
  /// where they set their location, or the times will not match the mosque
  /// they are actually praying at.
  static String _formatTime(DateTime instant, String? timezone) {
    final formatter = DateFormat.jm();

    if (timezone == null) return formatter.format(instant.toLocal());

    try {
      return formatter.format(
        tz.TZDateTime.from(instant, tz.getLocation(timezone)),
      );
    } on tz.LocationNotFoundException {
      return formatter.format(instant.toLocal());
    }
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    this.secondary,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final String? secondary;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.textTheme.bodySmall?.color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: emphasise
              ? theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                )
              : theme.textTheme.bodyMedium,
        ),
        if (secondary != null)
          Text(
            secondary!,
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

/// States plainly where the times came from.
///
/// Claiming authority the app does not have would be worse than admitting the
/// times are computed locally — a user comparing against their mosque needs to
/// know which is which.
class _SourceFooter extends StatelessWidget {
  const _SourceFooter({required this.source, required this.isStale});

  final PrayerTimeSource source;
  final bool isStale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final label = switch (source) {
      PrayerTimeSource.remote => AppLocalizations.of(context).durationsSourceConfirmed,
      PrayerTimeSource.cache => isStale
          ? AppLocalizations.of(context).durationsSourceCachedOffline
          : AppLocalizations.of(context).durationsSourceCached,
      PrayerTimeSource.device =>
        AppLocalizations.of(context).durationsSourceDevice,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          source == PrayerTimeSource.remote
              ? Icons.cloud_done_outlined
              : Icons.phone_android_outlined,
          size: 16,
          color: theme.textTheme.bodySmall?.color,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          AppLocalizations.of(context).durationsSetLocation,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
