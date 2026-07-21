/// A single prayer row on the dashboard.
///
/// The badge and countdown reflect the prayer's live phase: the on-time
/// window, the qaza window, or a settled outcome (verified / qaza / missed).
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/countdown_text.dart';
import '../../../prayer_times/domain/entities/prayer_day.dart';
import '../../../prayer_times/domain/entities/prayer_enums.dart';

class PrayerListTile extends StatelessWidget {
  const PrayerListTile({
    super.key,
    required this.entry,
    required this.now,
    required this.timezoneName,
    this.onTap,
  });

  final PrayerEntry entry;
  final DateTime now;
  final String timezoneName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phase = entry.phaseAt(now);
    final isActive = phase.isVerifiable;
    final remaining = entry.remainingWindow(now);

    return Semantics(
      label: '${entry.prayer.displayName}, '
          '${_formatTime(entry.scheduledAt)}, ${_phaseLabel(phase)}'
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
                        entry.prayer.displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight:
                              isActive ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                      if (phase != PrayerPhase.upcoming) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              _phaseLabel(phase),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: _phaseColor(phase, theme),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            // The countdown the spec requires: how long is left
                            // in the current on-time or qaza window.
                            if (remaining != null) ...[
                              Text(
                                ' · ${formatCountdown(remaining)} left',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: _phaseColor(phase, theme),
                                  fontSize: 13,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  _formatTime(entry.scheduledAt),
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

  static String _phaseLabel(PrayerPhase phase) => switch (phase) {
        PrayerPhase.upcoming => 'Upcoming',
        PrayerPhase.verifyOnTime => 'Verify now',
        PrayerPhase.qazaAvailable => 'Qaza available',
        PrayerPhase.verifiedOnTime => 'Verified on time',
        PrayerPhase.qazaCompleted => 'Qaza completed',
        PrayerPhase.missed => 'Missed',
        PrayerPhase.excused => 'Excused',
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
