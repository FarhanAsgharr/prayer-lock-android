/// The home screen: what is next, what is left, and how the week has gone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/countdown_text.dart';
import '../../../prayer_times/domain/entities/prayer_day.dart';
import '../../../prayer_times/domain/entities/prayer_enums.dart';
import '../../../prayer_times/presentation/providers/prayer_times_provider.dart';
import '../../../blocking/presentation/providers/orchestrator_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../tracking/presentation/providers/tracking_providers.dart';
import '../widgets/prayer_list_tile.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final day = ref.watch(prayerDayProvider);
    final now = ref.watch(nowProvider);

    if (!settings.isReady || day == null) {
      return const _LocationRequiredView();
    }

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          // Recomputation is local and instant; the pull gesture exists
          // because users expect it, and it re-reads the clock.
          onRefresh: () async => ref.invalidate(clockProvider),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(locationLabel: settings.location?.label),
                      const SizedBox(height: AppSpacing.lg),
                      const _NextPrayerCard(),
                      const SizedBox(height: AppSpacing.md),
                      _TodayProgress(day: day, now: now),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        "TODAY'S PRAYERS",
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: day.entries.length,
                itemBuilder: (context, index) {
                  final entry = day.entries[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    child: PrayerListTile(
                      entry: entry,
                      now: now,
                      timezoneName: settings.location!.timezone,
                      onTap: () => _showPrayerActions(context, ref, entry, now),
                    ),
                  );
                },
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: _SunriseNote(),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
            ],
          ),
        ),
      ),
    );
  }

  void _showPrayerActions(
    BuildContext context,
    WidgetRef ref,
    PrayerEntry entry,
    DateTime now,
  ) {
    final phase = entry.phaseAt(now);

    // Verification is only offered while a window is open. Upcoming, verified,
    // qaza-completed and missed prayers have no action — once the qaza window
    // closes, no photo can be submitted, ever.
    if (!phase.isVerifiable) return;

    final isQaza = phase == PrayerPhase.qazaAvailable;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                entry.prayer.displayName,
                style: Theme.of(sheetContext).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (isQaza) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'The on-time window has passed. Verifying now records this '
                  'as a qaza (make-up) prayer.',
                  style: Theme.of(sheetContext).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(
                  isQaza ? 'Verify qaza prayer' : 'I completed this prayer',
                ),
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  context.push('/verify/${entry.prayer.wireValue}');
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: () async {
                  final navigator = Navigator.of(sheetContext);
                  await ref.read(prayerTrackerProvider).markExcused(
                        date: ref.read(localDateProvider),
                        entry: entry,
                      );
                  // Release any active lock immediately rather than waiting
                  // for the next orchestrator tick.
                  await ref.read(lockStateProvider.notifier).onPrayerCompleted();
                  navigator.pop();
                },
                child: const Text('Mark as excused'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.locationLabel});

  final String? locationLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Prayer Lock', style: theme.textTheme.headlineMedium),
              if (locationLabel != null) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.place_outlined,
                      size: 14,
                      color: theme.textTheme.bodyMedium?.color,
                    ),
                    const SizedBox(width: 4),
                    Text(locationLabel!, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ],
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.bar_chart_outlined),
          tooltip: 'Your prayers',
          onPressed: () => context.push('/analytics'),
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Settings',
          onPressed: () => context.push('/settings'),
        ),
      ],
    );
  }
}

class _NextPrayerCard extends ConsumerWidget {
  const _NextPrayerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final current = ref.watch(currentPrayerProvider);
    final next = ref.watch(nextPrayerProvider);

    // An active prayer takes precedence over the countdown: what the user owes
    // right now matters more than what comes later.
    if (current != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              Text(
                'IT IS TIME FOR',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                current.prayer.displayName,
                style: theme.textTheme.displayLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('I completed this prayer'),
                onPressed: () =>
                    context.push('/verify/${current.prayer.wireValue}'),
              ),
            ],
          ),
        ),
      );
    }

    if (next == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Text(
              'NEXT: ${next.entry.prayer.displayName.toUpperCase()}',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            CountdownText(duration: next.until),
          ],
        ),
      ),
    );
  }
}

class _TodayProgress extends StatelessWidget {
  const _TodayProgress({required this.day, required this.now});

  final PrayerDay day;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completed = day.completedCount;
    final total = day.entries.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: _Stat(
                value: '$completed of $total',
                label: 'Completed',
              ),
            ),
            Container(width: 1, height: 36, color: theme.dividerColor),
            Expanded(
              child: _Stat(
                value: '${day.remainingCount}',
                label: 'Remaining',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value, style: theme.textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(label, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _SunriseNote extends ConsumerWidget {
  const _SunriseNote();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(prayerDayProvider);
    if (day == null) return const SizedBox.shrink();

    return Text(
      'Fajr must be prayed before sunrise. After sunrise it is recorded as late.',
      style: Theme.of(context).textTheme.bodyMedium,
      textAlign: TextAlign.center,
    );
  }
}

class _LocationRequiredView extends StatelessWidget {
  const _LocationRequiredView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.place_outlined, size: 48),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Set your location',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Prayer times depend on where you are. '
                'Choose a location to get started.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: () => context.push('/onboarding'),
                child: const Text('Choose location'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
