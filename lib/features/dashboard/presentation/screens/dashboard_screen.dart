/// The home screen: what is next, what is left, and how the week has gone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/countdown_text.dart';
import '../../../prayer_times/domain/entities/prayer_day.dart';
import '../../../prayer_times/domain/entities/prayer_enums.dart';
import '../../../prayer_times/domain/entities/prayer_slot.dart';
import '../../../prayer_times/presentation/providers/prayer_times_provider.dart';
import '../../../blocking/presentation/providers/orchestrator_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../tracking/presentation/providers/tracking_providers.dart';
import '../../../islamic_calendar/presentation/widgets/islamic_day_banner.dart';
import '../../../jumuah/presentation/providers/jumuah_providers.dart';
import '../../../jumuah/presentation/widgets/jumuah_card.dart';
import '../../../jumuah/presentation/widgets/jumuah_location_prompt.dart';
import '../../../jumuah/presentation/widgets/jumuah_travel_prompt.dart';
import '../widgets/prayer_list_tile.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final day = ref.watch(prayerDayProvider);
    final slots = ref.watch(prayerSlotsProvider);
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
                      const SizedBox(height: AppSpacing.xs),
                      const HijriDateLine(),
                      const SizedBox(height: AppSpacing.md),
                      // Ramadan, Eid, and any other occasion worth noting.
                      // Renders nothing on an ordinary day.
                      const IslamicDayBanner(),
                      const SizedBox(height: AppSpacing.sm),
                      // Only renders on a Friday when no mosque has been
                      // chosen yet. Placed under the header so it reads as
                      // part of the dashboard rather than as a system dialog.
                      const JumuahLocationPrompt(),
                      // Only ever one of these shows: the location prompt
                      // needs no mosque chosen, the travel prompt needs one.
                      const JumuahTravelPrompt(),
                      // Replaces the ordinary next-prayer card on Fridays;
                      // renders nothing on any other day.
                      const JumuahCard(),
                      const _NextPrayerCard(),
                      const SizedBox(height: AppSpacing.md),
                      _TodayProgress(day: day, now: now),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        AppLocalizations.of(context).dashboardTodaysPrayers,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ),
                ),
              ),
              // Slots, not prayers: three or four rows under a combined
              // grouping, five otherwise. Switching modes re-renders here with
              // no restart, because the projection is computed on every build.
              SliverList.builder(
                itemCount: slots.length,
                itemBuilder: (context, index) {
                  final slot = slots[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    child: PrayerListTile(
                      slot: slot,
                      now: now,
                      timezoneName: settings.location!.timezone,
                      onTap: () => _showPrayerActions(context, ref, slot, now),
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
    PrayerSlot slot,
    DateTime now,
  ) {
    final phase = slot.phaseAt(now);

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
                slot.displayName,
                style: Theme.of(sheetContext).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (slot.isCombined) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  AppLocalizations.of(context).dashboardBothRecorded,
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
              if (isQaza) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  AppLocalizations.of(context).dashboardQazaExplain,
                  style: Theme.of(sheetContext).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(
                  isQaza ? AppLocalizations.of(context).dashboardVerifyQaza : AppLocalizations.of(context).dashboardConfirmPrayer,
                ),
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  // Routed by the slot's first prayer; the verification screen
                  // resolves the whole slot from the current grouping.
                  context.push('/verify/${slot.first.prayer.wireValue}');
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: () async {
                  final navigator = Navigator.of(sheetContext);
                  final date = ref.read(localDateProvider);
                  // Every prayer in the slot is excused: leaving one owed
                  // would keep the window locked for a slot the user has just
                  // marked exempt.
                  for (final entry in slot.prayers) {
                    await ref.read(prayerTrackerProvider).markExcused(
                          date: date,
                          entry: entry,
                        );
                  }
                  // Release any active lock immediately rather than waiting
                  // for the next orchestrator tick.
                  await ref.read(lockStateProvider.notifier).onPrayerCompleted();
                  navigator.pop();
                },
                child: Text(AppLocalizations.of(context).dashboardMarkExcused),
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
              Text(AppLocalizations.of(context).appTitle, style: theme.textTheme.headlineMedium),
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
          tooltip: AppLocalizations.of(context).dashboardYourPrayers,
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

    // The Jumu'ah card already answers AppLocalizations.of(context).dashboardWhatIsNext on a Friday, and two
    // cards competing to say it would be worse than either alone.
    if (ref.watch(isJumuahTodayProvider)) return const SizedBox.shrink();

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
                AppLocalizations.of(context).dashboardItIsTimeFor,
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
                label: Text(AppLocalizations.of(context).dashboardConfirmPrayer),
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
              AppLocalizations.of(context).dashboardNextUpper(next.entry.prayer.displayName.toUpperCase()),
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
                label: AppLocalizations.of(context).dashboardCompleted,
              ),
            ),
            Container(width: 1, height: 36, color: theme.dividerColor),
            Expanded(
              child: _Stat(
                value: '${day.remainingCount}',
                label: AppLocalizations.of(context).dashboardRemaining,
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
      AppLocalizations.of(context).dashboardFajrBeforeSunrise,
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
                AppLocalizations.of(context).dashboardSetLocation,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                AppLocalizations.of(context).dashboardSetLocationBody,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: () => context.push('/onboarding'),
                child: Text(AppLocalizations.of(context).dashboardChooseLocation),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
