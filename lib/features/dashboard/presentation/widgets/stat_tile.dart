/// Compact statistic tiles for the analytics screen.
library;

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_theme.dart';

/// A single headline figure with a label and optional icon.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.accent,
  });

  final String value;
  final String label;
  final IconData? icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = accent ?? theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, color: accentColor, size: 20),
            const SizedBox(height: AppSpacing.sm),
          ],
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: accentColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// A labelled horizontal progress bar, e.g. per-prayer success rate.
class RateBar extends StatelessWidget {
  const RateBar({
    super.key,
    required this.label,
    required this.rate,
    required this.detail,
  });

  final String label;

  /// 0.0 - 1.0.
  final double rate;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Colour by health: strong green when high, amber mid, red low. The
    // thresholds are generous — this is encouragement, not a report card.
    final Color color;
    if (rate >= 0.8) {
      color = AppColors.success;
    } else if (rate >= 0.5) {
      color = AppColors.warning;
    } else {
      color = AppColors.danger;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Semantics(
        label: AppLocalizations.of(context).statPercentDetail(label, (rate * 100).round(), detail),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: theme.textTheme.titleMedium),
                Text(detail, style: theme.textTheme.bodyMedium),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: rate,
                minHeight: 8,
                backgroundColor: theme.dividerColor,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
