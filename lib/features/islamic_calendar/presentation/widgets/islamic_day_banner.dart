/// The Hijri date, and whatever today happens to be.
///
/// Three pieces, each shown only when it has something to say: the Hijri date
/// (always), a Ramadan strip with the live Sehri or Iftar countdown, and an Eid
/// strip. On an ordinary day in an ordinary month this is a single quiet line.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/countdown_text.dart';
import '../../../prayer_times/presentation/providers/prayer_times_provider.dart';
import '../../domain/entities/islamic_occasion.dart';
import '../../domain/usecases/ramadan_status.dart';
import '../providers/islamic_calendar_providers.dart';

/// The Hijri date line. Always present.
class HijriDateLine extends ConsumerWidget {
  const HijriDateLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hijri = ref.watch(hijriDateProvider);
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          Icons.calendar_month_outlined,
          size: 14,
          color: theme.textTheme.bodySmall?.color,
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(hijri.format(), style: theme.textTheme.bodySmall),
        if (hijri.month.isSacred) ...[
          const SizedBox(width: AppSpacing.xs),
          Text(
            '· ${AppLocalizations.of(context).calendarSacredMonth}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Ramadan and Eid strips, plus any other occasion worth a mention.
class IslamicDayBanner extends ConsumerWidget {
  const IslamicDayBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ramadan = ref.watch(ramadanStatusProvider);
    final eid = ref.watch(eidStatusProvider);
    final occasions = ref.watch(todaysOccasionsProvider);

    final children = <Widget>[
      if (eid.isEid) _EidStrip(status: eid),
      if (ramadan.isRamadan) _RamadanStrip(status: ramadan),
      // Anything else worth noting — a White Day, Ashura, Arafah. Ramadan and
      // Eid are already covered above, so they are filtered out to avoid
      // saying the same thing twice.
      for (final occasion in occasions)
        if (occasion.kind != OccasionKind.eid && occasion.name != 'Ramadan')
          _OccasionStrip(occasion: occasion),
    ];

    if (children.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (final child in children) ...[
          child,
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _RamadanStrip extends ConsumerWidget {
  const _RamadanStrip({required this.status});

  final RamadanStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = ref.watch(nowProvider);

    // Whichever countdown is live: Sehri before Fajr, Iftar during the fast,
    // Taraweeh after. Showing all three at once would bury the one that
    // matters.
    final sehri = status.sehriRemaining(now);
    final iftar = status.iftarRemaining(now);

    final (String label, String value) = switch (status.phase) {
      FastPhase.sehri when sehri != null => (
          AppLocalizations.of(context).calendarSehriEndsIn,
          formatCountdown(sehri),
        ),
      FastPhase.fasting when iftar != null => (
          AppLocalizations.of(context).calendarIftarIn,
          formatCountdown(iftar),
        ),
      _ => ('Taraweeh', AppLocalizations.of(context).calendarAfterIsha),
    };

    return _Strip(
      icon: Icons.nightlight_round,
      colour: theme.colorScheme.primary,
      title: AppLocalizations.of(context).calendarRamadanDay(status.dayOfRamadan),
      trailingLabel: label,
      trailingValue: value,
      // The last ten nights are worth calling out; the odd ones especially.
      footnote: status.isPossibleLaylatulQadr
          ? AppLocalizations.of(context).calendarOddNight
          : status.isLastTen
              ? AppLocalizations.of(context).calendarLastTen
              : null,
    );
  }
}

class _EidStrip extends StatelessWidget {
  const _EidStrip({required this.status});

  final EidStatus status;

  @override
  Widget build(BuildContext context) {
    return _Strip(
      icon: Icons.celebration_outlined,
      colour: AppColors.accent,
      title: status.name ?? 'Eid',
      trailingLabel: status.eidPrayerFrom == null ? null : AppLocalizations.of(context).calendarEidPrayer,
      trailingValue: status.eidPrayerFrom == null
          ? null
          : AppLocalizations.of(context).calendarAfterSunrise,
      footnote: status.callsForTakbeer ? 'Takbeer' : null,
    );
  }
}

class _OccasionStrip extends StatelessWidget {
  const _OccasionStrip({required this.occasion});

  final IslamicOccasion occasion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _Strip(
      icon: switch (occasion.kind) {
        OccasionKind.fasting => Icons.no_food_outlined,
        OccasionKind.night => Icons.star_outline,
        OccasionKind.eid => Icons.celebration_outlined,
        OccasionKind.observance => Icons.event_note_outlined,
      },
      colour: theme.colorScheme.primary,
      title: occasion.name,
      footnote: occasion.description,
    );
  }
}

/// One horizontal strip. Shared so every occasion reads the same way.
class _Strip extends StatelessWidget {
  const _Strip({
    required this.icon,
    required this.colour,
    required this.title,
    this.trailingLabel,
    this.trailingValue,
    this.footnote,
  });

  final IconData icon;
  final Color colour;
  final String title;
  final String? trailingLabel;
  final String? trailingValue;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colour),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(color: colour),
                ),
              ),
              if (trailingValue != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (trailingLabel != null)
                      Text(
                        trailingLabel!,
                        style: theme.textTheme.labelSmall,
                      ),
                    Text(
                      trailingValue!,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colour,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (footnote != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(footnote!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
