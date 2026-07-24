/// The Friday card: what is happening, where, and how long is left.
///
/// Replaces the ordinary "next prayer" card on Fridays. It answers the four
/// questions a person actually has on a Friday morning — which mosque, what
/// time, how long until then, and have I confirmed it — without them having to
/// open anything.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/countdown_text.dart';
import '../../../prayer_times/domain/entities/prayer_enums.dart';
import '../../../prayer_times/presentation/providers/prayer_times_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../providers/jumuah_providers.dart';
import 'jumuah_icon.dart';

class JumuahCard extends ConsumerWidget {
  const JumuahCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(jumuahStatusProvider);

    // Not a Friday, or Jumu'ah is off or unconfigured — the ordinary next-prayer
    // card handles those.
    if (!status.isActive) return const SizedBox.shrink();

    final day = ref.watch(prayerDayProvider);
    final now = ref.watch(nowProvider);
    final mosque = status.mosque;
    if (day == null || mosque == null) return const SizedBox.shrink();

    final slot = day.slotFor(
      PrayerName.dhuhr,
      ref.watch(settingsProvider).prayerGrouping,
    );
    if (!slot.isJumuah) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final phase = slot.phaseAt(now);
    final window = slot.window;

    // Three states, each with a different useful number: before (how long
    // until), during (how long left), after (settled).
    final untilStart = window.startsAt.difference(now);
    final isBefore = untilStart.isNegative == false && untilStart.inSeconds > 0;
    final remaining = window.remainingAt(now);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                JumuahIcon(size: 22, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  "JUMU'AH",
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.sm),

            Text(
              mosque.displayName,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: AppSpacing.xs),

            Text(
              mosque.formattedRange,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            _StatusLine(
              phase: phase,
              isBefore: isBefore,
              untilStart: untilStart,
              remaining: remaining,
            ),

            if (phase.isVerifiable) ...[
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                icon: const Icon(Icons.check),
                label: const Text("I prayed Jumu'ah"),
                onPressed: () => context.push('/verify/dhuhr'),
              ),
            ],

            if (mosque.address != null &&
                mosque.address!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                mosque.address!,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The one line that changes as the day moves through the congregation.
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.phase,
    required this.isBefore,
    required this.untilStart,
    required this.remaining,
  });

  final PrayerPhase phase;
  final bool isBefore;
  final Duration untilStart;
  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (String text, Color color, IconData icon) = switch (phase) {
      PrayerPhase.verifiedOnTime => (
          'Confirmed',
          AppColors.success,
          Icons.check_circle,
        ),
      PrayerPhase.qazaCompleted => (
          'Confirmed late',
          AppColors.warning,
          Icons.check_circle_outline,
        ),
      PrayerPhase.excused => ('Excused', AppColors.warning, Icons.pause_circle),
      // Jumu'ah has no qaza — a missed one is prayed as Dhuhr instead, so the
      // message says that rather than offering a make-up.
      PrayerPhase.missed || PrayerPhase.qazaAvailable => (
          'Missed — pray Dhuhr instead',
          AppColors.danger,
          Icons.info_outline,
        ),
      PrayerPhase.verifyOnTime => (
          '${formatCountdown(remaining)} left to confirm',
          theme.colorScheme.primary,
          Icons.timelapse,
        ),
      PrayerPhase.upcoming => isBefore
          ? (
              'Starts in ${formatCountdown(untilStart)}',
              theme.colorScheme.primary,
              Icons.schedule,
            )
          : ('Upcoming', theme.colorScheme.primary, Icons.schedule),
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.bodyLarge?.copyWith(color: color),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
