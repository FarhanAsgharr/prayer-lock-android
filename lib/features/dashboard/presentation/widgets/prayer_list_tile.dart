/// A single row on the dashboard: one prayer, or a combined pair.
///
/// Renders a [PrayerSlot] rather than a [PrayerEntry], so the same widget
/// covers both modes. Under the default grouping every slot holds one prayer
/// and this is exactly a prayer row; under a combined grouping the Dhuhr+Asr
/// slot is one row with one window and one action.
///
/// The badge and countdown reflect the slot's live phase: its window, the
/// make-up period, or a settled outcome (verified / qaza / missed).
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/countdown_text.dart';
import '../../../prayer_times/domain/entities/prayer_enums.dart';
import '../../../prayer_times/domain/entities/prayer_slot.dart';
import '../../../prayer_times/domain/usecases/dynamic_duration_calculator.dart';

class PrayerListTile extends StatelessWidget {
  const PrayerListTile({
    super.key,
    required this.slot,
    required this.now,
    required this.timezoneName,
    this.onTap,
  });

  final PrayerSlot slot;
  final DateTime now;
  final String timezoneName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phase = slot.phaseAt(now);
    final isActive = phase.isVerifiable;
    final remaining = slot.remainingWindow(now);

    return Semantics(
      label: '${slot.displayName}, '
          '${_formatTime(slot.scheduledAt)}, ${_phaseLabel(context, phase)}'
          '${remaining != null ? ', ${formatCountdown(remaining)} left' : ''}',
      button: onTap != null,
      child: Material(
        color: isActive
            ? _phaseColor(phase, theme).withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                _PhaseIndicator(phase: phase),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        slot.displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight:
                              isActive ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                      // The window this prayer occupies. Shown for an upcoming
                      // prayer too, because the useful thing to know before
                      // Dhuhr begins is that it runs until Asr — over three
                      // hours — not merely that it is next.
                      const SizedBox(height: 2),
                      Text(
                        '${AppLocalizations.of(context).tileUntilBoundary(slot.window.boundary.displayName)} · '
      '${formatPrayerDurationShort(slot.duration)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                        ),
                      ),
                      if (phase != PrayerPhase.upcoming) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _phaseLabel(context, phase),
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: _phaseColor(phase, theme),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            // The countdown the spec requires: how long is left
                            // in the current on-time or qaza window.
                            if (remaining != null)
                              Flexible(
                                child: Text(
                                  ' · ${formatCountdown(remaining)} left',
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: _phaseColor(phase, theme),
                                    fontSize: 13,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  _formatTime(slot.scheduledAt),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: phase == PrayerPhase.missed
                        ? theme.textTheme.bodyMedium?.color
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime utcInstant) {
    try {
      final local = tz.TZDateTime.from(utcInstant, tz.getLocation(timezoneName));
      return DateFormat.jm().format(local);
    } on tz.LocationNotFoundException {
      return DateFormat.jm().format(utcInstant.toLocal());
    }
  }

  static String _phaseLabel(BuildContext context, PrayerPhase phase) =>
      switch (phase) {
        PrayerPhase.upcoming => AppLocalizations.of(context).tileUpcoming,
        PrayerPhase.verifyOnTime => AppLocalizations.of(context).tileVerifyNow,
        PrayerPhase.qazaAvailable => AppLocalizations.of(context).tileQazaAvailable,
        PrayerPhase.verifiedOnTime => AppLocalizations.of(context).tileVerifiedOnTime,
        PrayerPhase.qazaCompleted => AppLocalizations.of(context).tileQazaCompleted,
        PrayerPhase.missed => AppLocalizations.of(context).tileMissed,
        PrayerPhase.excused => AppLocalizations.of(context).tileExcused,
      };

  static Color _phaseColor(PrayerPhase phase, ThemeData theme) =>
      switch (phase) {
        PrayerPhase.verifyOnTime => theme.colorScheme.primary,
        PrayerPhase.qazaAvailable => AppColors.warning,
        PrayerPhase.verifiedOnTime => AppColors.success,
        PrayerPhase.qazaCompleted => AppColors.warning,
        PrayerPhase.missed => AppColors.danger,
        PrayerPhase.excused => AppColors.warning,
        PrayerPhase.upcoming => theme.textTheme.bodyMedium!.color!,
      };
}

class _PhaseIndicator extends StatelessWidget {
  const _PhaseIndicator({required this.phase});

  final PrayerPhase phase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (IconData icon, Color color) = switch (phase) {
      PrayerPhase.verifiedOnTime => (Icons.check_circle, AppColors.success),
      PrayerPhase.qazaCompleted => (Icons.history, AppColors.warning),
      PrayerPhase.missed => (Icons.remove_circle_outline, AppColors.danger),
      PrayerPhase.excused => (Icons.pause_circle_outline, AppColors.warning),
      PrayerPhase.verifyOnTime => (
          Icons.radio_button_checked,
          theme.colorScheme.primary,
        ),
      PrayerPhase.qazaAvailable => (Icons.timelapse, AppColors.warning),
      PrayerPhase.upcoming => (
          Icons.radio_button_unchecked,
          theme.dividerColor,
        ),
    };

    return ExcludeSemantics(child: Icon(icon, color: color, size: 26));
  }
}
