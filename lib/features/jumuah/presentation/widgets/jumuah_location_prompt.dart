/// AppLocalizations.of(context).jumuahWhereToday
///
/// Shown on the first Friday, once, and then never again — the answer is
/// remembered and reused every Friday after. That is the whole design: asking
/// weekly would be nagging about a decision that almost never changes, and
/// never asking would mean guessing which mosque someone attends.
///
/// The user can still change it from Settings, or ask to be prompted again.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_theme.dart';
import '../providers/jumuah_providers.dart';
import 'jumuah_icon.dart';

/// An inline card on the dashboard, shown only when a choice is needed.
///
/// Inline rather than a modal dialog: a dialog on launch blocks the whole
/// screen for something that is not urgent, and a user who wants to check the
/// Fajr time first should not have to dismiss a question to do it.
class JumuahLocationPrompt extends ConsumerWidget {
  const JumuahLocationPrompt({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(needsJumuahLocationProvider)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final manager = ref.watch(jumuahManagerProvider);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                JumuahIcon(size: 24, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).jumuahWhereToday,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              AppLocalizations.of(context).jumuahWhereTodayBody,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            for (final mosque in ref.watch(mosquesProvider)) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => manager.chooseMosque(mosque.id),
                  child: Column(
                    children: [
                      Text(mosque.displayName),
                      Text(
                        mosque.formattedRange,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}
