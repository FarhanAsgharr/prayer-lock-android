/// A single prayer row on the dashboard.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../../shared/theme/app_theme.dart';
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
    final status = entry.statusAt(now);
    final isActive = status == PrayerStatus.active;

    return Semantics(
      // Screen readers get the full picture in one utterance rather than
      // three disconnected labels.
      label: '${entry.prayer.displayName}, '
          '${_formatTime(entry.scheduledAt)}, ${_statusLabel(status)}',
      button: onTap != null,
      child: Material(
        color: isActive
            ? theme.colorScheme.primary.withValues(alpha: 0.08)
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
                _StatusIndicator(status: status),
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
                      if (status != PrayerStatus.pending) ...[
                        const SizedBox(height: 2),
                        Text(
                          _statusLabel(status),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _statusColor(status, theme),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  _formatTime(entry.scheduledAt),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: status == PrayerStatus.missed
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

  String _statusLabel(PrayerStatus status) => switch (status) {
        PrayerStatus.pending => 'Upcoming',
        PrayerStatus.active => 'Now',
        PrayerStatus.completed => 'Completed',
        PrayerStatus.late => 'Completed late',
        PrayerStatus.missed => 'Missed',
        PrayerStatus.excused => 'Excused',
      };

  Color _statusColor(PrayerStatus status, ThemeData theme) => switch (status) {
        PrayerStatus.completed => AppColors.success,
        PrayerStatus.late => AppColors.warning,
        PrayerStatus.missed => AppColors.danger,
        PrayerStatus.active => theme.colorScheme.primary,
        _ => theme.textTheme.bodyMedium!.color!,
      };
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.status});

  final PrayerStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (IconData icon, Color color) = switch (status) {
      PrayerStatus.completed => (Icons.check_circle, AppColors.success),
      PrayerStatus.late => (Icons.check_circle_outline, AppColors.warning),
      PrayerStatus.missed => (Icons.remove_circle_outline, AppColors.danger),
      PrayerStatus.excused => (Icons.pause_circle_outline, AppColors.warning),
      PrayerStatus.active => (Icons.radio_button_checked, theme.colorScheme.primary),
      PrayerStatus.pending => (
          Icons.radio_button_unchecked,
          theme.dividerColor,
        ),
    };

    // Excluded from semantics: the parent Semantics already conveys status in
    // words, and a screen reader announcing an icon name adds nothing.
    return ExcludeSemantics(child: Icon(icon, color: color, size: 26));
  }
}
