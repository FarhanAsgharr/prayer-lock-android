/// Prayer analytics: streaks, rates, charts and history.
///
/// Every figure comes from the local encrypted database, so this screen works
/// fully offline — the same data that drives the dashboard, aggregated.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../core/sync/sync_engine.dart';
import '../../../../core/storage/storage_providers.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../prayer_times/domain/entities/prayer_enums.dart';
import '../../../tracking/domain/entities/prayer_statistics.dart';
import '../../../tracking/presentation/providers/tracking_providers.dart';
import '../widgets/prayer_bar_chart.dart';
import '../widgets/stat_tile.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(prayerStatisticsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).analyticsTitle)),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              '${AppLocalizations.of(context).analyticsStatsFailed}\n$error',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
        data: (stats) => _AnalyticsBody(stats: stats),
      ),
    );
  }
}

class _AnalyticsBody extends ConsumerWidget {
  const _AnalyticsBody({required this.stats});

  final PrayerStatistics stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final syncStatus = ref.watch(syncStatusProvider).valueOrNull;

    // The last 7 daily summaries, oldest first, padded so a new user still
    // sees a full week's axis rather than one lonely bar.
    final week = _lastNDays(stats.dailyHistory, 7);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (syncStatus != null && syncStatus.hasUnsyncedData)
          _SyncBanner(status: syncStatus),

        // --- Streaks ------------------------------------------------------
        Row(
          children: [
            Expanded(
              child: StatTile(
                value: '${stats.streak.current}',
                label: stats.streak.current == 1 ? AppLocalizations.of(context).analyticsDayStreak : AppLocalizations.of(context).analyticsDayStreak,
                icon: Icons.local_fire_department,
                accent: AppColors.accent,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: StatTile(
                value: '${stats.streak.longest}',
                label: AppLocalizations.of(context).analyticsLongestStreak,
                icon: Icons.emoji_events_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: StatTile(
                value: '${(stats.allTime.successRate * 100).round()}%',
                label: AppLocalizations.of(context).analyticsAllTimeCompletion,
                icon: Icons.check_circle_outline,
                accent: AppColors.success,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: StatTile(
                value: '${stats.allTime.fulfilled}',
                label: AppLocalizations.of(context).analyticsPrayersFulfilled,
                icon: Icons.mosque_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: StatTile(
                value: '${stats.allTime.completed}',
                label: AppLocalizations.of(context).analyticsOnTime,
                icon: Icons.schedule,
                accent: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: StatTile(
                value: '${stats.allTime.qaza}',
                label: AppLocalizations.of(context).analyticsQazaMakeUp,
                icon: Icons.history,
                accent: AppColors.warning,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: StatTile(
                value: '${stats.allTime.missed}',
                label: AppLocalizations.of(context).analyticsMissed,
                icon: Icons.remove_circle_outline,
                accent: AppColors.danger,
              ),
            ),
          ],
        ),

        const SizedBox(height: AppSpacing.lg),

        // --- Weekly chart -------------------------------------------------
        Text(AppLocalizations.of(context).analyticsThisWeek, style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        _card(
          context,
          child: Column(
            children: [
              PrayerBarChart(days: week),
              const SizedBox(height: AppSpacing.md),
              const _ChartLegend(),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.lg),

        // --- Period comparison -------------------------------------------
        Text(AppLocalizations.of(context).analyticsCompletionRate, style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        _card(
          context,
          child: Column(
            children: [
              _PeriodRow(label: AppLocalizations.of(context).analyticsRangeWeek, counts: stats.week),
              Divider(color: theme.dividerColor, height: AppSpacing.lg),
              _PeriodRow(label: AppLocalizations.of(context).analyticsRangeMonth, counts: stats.month),
              Divider(color: theme.dividerColor, height: AppSpacing.lg),
              _PeriodRow(label: AppLocalizations.of(context).analyticsRangeYear, counts: stats.year),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.lg),

        // --- Per-prayer breakdown ----------------------------------------
        Text(AppLocalizations.of(context).analyticsByPrayer, style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        _card(
          context,
          child: Column(
            children: [
              for (final prayer in PrayerName.values)
                RateBar(
                  label: prayer.displayName,
                  rate: (stats.byPrayer[prayer] ?? const PrayerCounts())
                      .successRate,
                  detail: _prayerDetail(context, stats.byPrayer[prayer]),
                ),
            ],
          ),
        ),

        if (stats.weakestPrayer != null) ...[
          const SizedBox(height: AppSpacing.md),
          _WeakestPrayerNote(prayer: stats.weakestPrayer!),
        ],

        const SizedBox(height: AppSpacing.lg),

        // --- History links ------------------------------------------------
        Text('HISTORY', style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        _card(
          context,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _historyLink(
                context,
                icon: Icons.camera_alt_outlined,
                label: AppLocalizations.of(context).analyticsVerificationHistory,
                onTap: () => _showHistory(
                  context,
                  ref,
                  AppLocalizations.of(context).analyticsVerificationHistory,
                  verificationHistoryProvider,
                  _describeVerification,
                ),
              ),
              _historyLink(
                context,
                icon: Icons.lock_outline,
                label: AppLocalizations.of(context).analyticsLockHistory,
                onTap: () => _showHistory(
                  context,
                  ref,
                  AppLocalizations.of(context).analyticsLockHistory,
                  lockHistoryProvider,
                  _describeLock,
                ),
              ),
              _historyLink(
                context,
                icon: Icons.lock_open_outlined,
                label: AppLocalizations.of(context).analyticsEmergencyUnlocks,
                onTap: () => _showHistory(
                  context,
                  ref,
                  AppLocalizations.of(context).analyticsEmergencyUnlocks,
                  emergencyUnlockHistoryProvider,
                  _describeEmergencyUnlock,
                ),
                isLast: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  Widget _card(
    BuildContext context, {
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(AppSpacing.md),
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: theme.dividerColor),
      ),
      child: child,
    );
  }

  Widget _historyLink(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isLast = false,
  }) {
    return Column(
      children: [
        ListTile(
          leading: Icon(icon),
          title: Text(label),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
        if (!isLast) Divider(color: Theme.of(context).dividerColor, height: 1),
      ],
    );
  }

  void _showHistory(
    BuildContext context,
    WidgetRef ref,
    String title,
    ProviderListenable<AsyncValue<List<Map<String, Object?>>>> provider,
    String Function(BuildContext, Map<String, Object?>) describe,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _HistoryListScreen(
          title: title,
          provider: provider,
          describe: describe,
        ),
      ),
    );
  }

  static List<DailySummary> _lastNDays(List<DailySummary> history, int n) {
    // history is most-recent-first; take the newest n and reverse to
    // chronological order for the chart's left-to-right axis.
    final recent = history.take(n).toList().reversed.toList();
    return recent;
  }

  static String _prayerDetail(BuildContext context, PrayerCounts? counts) {
    if (counts == null || counts.assessed == 0) return AppLocalizations.of(context).commonNoData;
    return '${counts.fulfilled}/${counts.assessed}';
  }
}

class _PeriodRow extends StatelessWidget {
  const _PeriodRow({required this.label, required this.counts});

  final String label;
  final PrayerCounts counts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.titleMedium),
        Row(
          children: [
            Text(
              '${counts.fulfilled}/${counts.assessed}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              '${(counts.successRate * 100).round()}%',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LegendDot(color: AppColors.primary, label: AppLocalizations.of(context).analyticsOnTime),
        const SizedBox(width: AppSpacing.md),
        _LegendDot(color: AppColors.warning, label: AppLocalizations.of(context).analyticsQazaShort),
        const SizedBox(width: AppSpacing.md),
        const _LegendDot(color: AppColors.danger, label: 'Missed'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _WeakestPrayerNote extends StatelessWidget {
  const _WeakestPrayerNote({required this.prayer});

  final PrayerName prayer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline, color: AppColors.accent),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              AppLocalizations.of(context).analyticsMostMissed(prayer.displayName),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncBanner extends ConsumerWidget {
  const _SyncBanner({required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final needsAttention = status.needsAttention;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: (needsAttention ? AppColors.warning : theme.colorScheme.primary)
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(
            needsAttention ? Icons.sync_problem : Icons.sync,
            color: needsAttention ? AppColors.warning : theme.colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              needsAttention
                  ? AppLocalizations.of(context).analyticsParked(status.parked)
                  : AppLocalizations.of(context).analyticsPending(status.pending),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (needsAttention)
            TextButton(
              onPressed: () => ref.read(syncEngineProvider).retryFailed(),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}

/// A generic history list, shared by verifications, locks and unlocks.
class _HistoryListScreen extends ConsumerWidget {
  const _HistoryListScreen({
    required this.title,
    required this.provider,
    required this.describe,
  });

  final String title;
  final ProviderListenable<AsyncValue<List<Map<String, Object?>>>> provider;
  final String Function(BuildContext, Map<String, Object?>) describe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(AppLocalizations.of(context).commonLoadFailed(error.toString()))),
        data: (rows) {
          if (rows.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  AppLocalizations.of(context).commonNothingYet,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (context, _) =>
                Divider(color: Theme.of(context).dividerColor, height: 1),
            itemBuilder: (context, index) {
              final row = rows[index];
              return ListTile(
                title: Text(describe(context, row)),
                subtitle: Text(_formatTimestamp(row)),
              );
            },
          );
        },
      ),
    );
  }

  static String _formatTimestamp(Map<String, Object?> row) {
    final raw = row['created_at'] ?? row['started_at'];
    if (raw is! int) return '';
    final time = DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true).toLocal();
    return DateFormat.yMMMd().add_jm().format(time);
  }
}

String _describeVerification(BuildContext context, Map<String, Object?> row) {
  final approved = (row['approved'] as int?) == 1;
  final released = (row['released_without_detection'] as int?) == 1;
  if (released) return AppLocalizations.of(context).analyticsReleasedWithoutDetection;
  return approved ? AppLocalizations.of(context).analyticsVerified : AppLocalizations.of(context).analyticsNotVerified;
}

String _describeLock(BuildContext context, Map<String, Object?> row) {
  final prayer = row['prayer'] as String? ?? 'prayer';
  final reason = row['end_reason'] as String?;
  final ended = row['ended_at'] != null;
  final name = prayer.isEmpty ? prayer : prayer[0].toUpperCase() + prayer.substring(1);
  if (!ended) return AppLocalizations.of(context).analyticsLockActive(name);
  return AppLocalizations.of(context).analyticsLockEnded(name, _endReasonLabel(context, reason));
}

String _describeEmergencyUnlock(BuildContext context, Map<String, Object?> row) {
  final sequence = row['daily_sequence'] as int? ?? 1;
  final reason = row['reason'] as String?;
  return reason?.isNotEmpty == true
      ? AppLocalizations.of(context).analyticsUnlockNumbered(sequence, reason!)
      : AppLocalizations.of(context).analyticsUnlockPlain(sequence);
}

String _endReasonLabel(BuildContext context, String? reason) => switch (reason) {
      'verified' => AppLocalizations.of(context).lockEndVerified,
      'emergency_unlock' => AppLocalizations.of(context).lockEndEmergency,
      'window_expired' => AppLocalizations.of(context).lockEndWindowExpired,
      'user_disabled' => AppLocalizations.of(context).lockEndDisabled,
      'app_restarted' => AppLocalizations.of(context).lockEndRestarted,
      _ => 'ended',
    };
