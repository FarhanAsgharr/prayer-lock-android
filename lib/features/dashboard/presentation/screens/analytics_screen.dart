/// Prayer analytics: streaks, rates, charts and history.
///
/// Every figure comes from the local encrypted database, so this screen works
/// fully offline — the same data that drives the dashboard, aggregated.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
      appBar: AppBar(title: const Text('Your prayers')),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              'Could not load your statistics.\n$error',
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
                label: stats.streak.current == 1 ? 'day streak' : 'day streak',
                icon: Icons.local_fire_department,
                accent: AppColors.accent,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: StatTile(
                value: '${stats.streak.longest}',
                label: 'longest streak',
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
                label: 'all-time completion',
                icon: Icons.check_circle_outline,
                accent: AppColors.success,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: StatTile(
                value: '${stats.allTime.fulfilled}',
                label: 'prayers fulfilled',
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
                label: 'on time',
                icon: Icons.schedule,
                accent: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: StatTile(
                value: '${stats.allTime.qaza}',
                label: 'qaza (make-up)',
                icon: Icons.history,
                accent: AppColors.warning,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: StatTile(
                value: '${stats.allTime.missed}',
                label: 'missed',
                icon: Icons.remove_circle_outline,
                accent: AppColors.danger,
              ),
            ),
          ],
        ),

        const SizedBox(height: AppSpacing.lg),

        // --- Weekly chart -------------------------------------------------
        Text('THIS WEEK', style: theme.textTheme.labelLarge),
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
        Text('COMPLETION RATE', style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        _card(
          context,
          child: Column(
            children: [
              _PeriodRow(label: 'This week', counts: stats.week),
              Divider(color: theme.dividerColor, height: AppSpacing.lg),
              _PeriodRow(label: 'This month', counts: stats.month),
              Divider(color: theme.dividerColor, height: AppSpacing.lg),
              _PeriodRow(label: 'This year', counts: stats.year),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.lg),

        // --- Per-prayer breakdown ----------------------------------------
        Text('BY PRAYER', style: theme.textTheme.labelLarge),
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
                  detail: _prayerDetail(stats.byPrayer[prayer]),
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
                label: 'Verification history',
                onTap: () => _showHistory(
                  context,
                  ref,
                  'Verification history',
                  verificationHistoryProvider,
                  _describeVerification,
                ),
              ),
              _historyLink(
                context,
                icon: Icons.lock_outline,
                label: 'Lock history',
                onTap: () => _showHistory(
                  context,
                  ref,
                  'Lock history',
                  lockHistoryProvider,
                  _describeLock,
                ),
              ),
              _historyLink(
                context,
                icon: Icons.lock_open_outlined,
                label: 'Emergency unlocks',
                onTap: () => _showHistory(
                  context,
                  ref,
                  'Emergency unlocks',
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
    String Function(Map<String, Object?>) describe,
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

  static String _prayerDetail(PrayerCounts? counts) {
    if (counts == null || counts.assessed == 0) return 'No data';
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
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LegendDot(color: AppColors.primary, label: 'On time'),
        SizedBox(width: AppSpacing.md),
        _LegendDot(color: AppColors.warning, label: 'Qaza'),
        SizedBox(width: AppSpacing.md),
        _LegendDot(color: AppColors.danger, label: 'Missed'),
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
              '${prayer.displayName} is the prayer you miss most. '
              'A little extra focus there will lift your whole week.',
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
                  ? '${status.parked} record(s) could not be uploaded.'
                  : '${status.pending} record(s) waiting to sync.',
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
  final String Function(Map<String, Object?>) describe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load: $error')),
        data: (rows) {
          if (rows.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'Nothing here yet.',
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
                title: Text(describe(row)),
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

String _describeVerification(Map<String, Object?> row) {
  final approved = (row['approved'] as int?) == 1;
  final released = (row['released_without_detection'] as int?) == 1;
  if (released) return 'Released without detection';
  return approved ? 'Verified' : 'Not verified';
}

String _describeLock(Map<String, Object?> row) {
  final prayer = row['prayer'] as String? ?? 'prayer';
  final reason = row['end_reason'] as String?;
  final ended = row['ended_at'] != null;
  final name = prayer.isEmpty ? prayer : prayer[0].toUpperCase() + prayer.substring(1);
  if (!ended) return '$name — active';
  return '$name — ${_endReasonLabel(reason)}';
}

String _describeEmergencyUnlock(Map<String, Object?> row) {
  final sequence = row['daily_sequence'] as int? ?? 1;
  final reason = row['reason'] as String?;
  return reason?.isNotEmpty == true
      ? 'Unlock #$sequence — $reason'
      : 'Emergency unlock #$sequence';
}

String _endReasonLabel(String? reason) => switch (reason) {
      'verified' => 'unlocked after prayer',
      'emergency_unlock' => 'emergency unlock',
      'window_expired' => 'prayer window ended',
      'user_disabled' => 'blocking turned off',
      'app_restarted' => 'app restarted',
      _ => 'ended',
    };
