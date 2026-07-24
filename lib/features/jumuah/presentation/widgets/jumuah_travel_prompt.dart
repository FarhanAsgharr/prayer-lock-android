/// "You seem to be near a different mosque today."
///
/// Distinct from [JumuahLocationPrompt], which asks the standing question of
/// where someone usually prays. This one is about a single Friday: the user is
/// travelling, and the mosque they normally attend is a few hundred kilometres
/// away.
///
/// Answering it applies to today only. Someone visiting family for a weekend
/// should not come home to find their usual mosque quietly replaced — the
/// prompt is a convenience, not a preference change, and it says so.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_theme.dart';
import '../providers/jumuah_providers.dart';

/// Whether the user has waved this Friday's suggestion away.
///
/// Session-scoped on purpose. Persisting a dismissal would mean remembering a
/// decision about a place the user is no longer in; forgetting it on relaunch
/// costs them one tap on the rare Friday they are away.
final _dismissedProvider = StateProvider<bool>((ref) => false);

class JumuahTravelPrompt extends ConsumerWidget {
  const JumuahTravelPrompt({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestion = ref.watch(mosqueSuggestionProvider);
    if (suggestion == null || ref.watch(_dismissedProvider)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final manager = ref.watch(jumuahManagerProvider);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.travel_explore_outlined,
                  size: 22,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Praying somewhere else today?',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              // Both distances, because the suggestion is only convincing if
              // the user can see the comparison that produced it.
              "You're about ${_km(suggestion.distanceKm)} from "
              '${suggestion.mosque.displayName}, and '
              '${_km(suggestion.selectedDistanceKm)} from your usual mosque.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              suggestion.mosque.formattedRange,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () =>
                      ref.read(_dismissedProvider.notifier).state = true,
                  child: const Text('No, stay as I am'),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: () async {
                    // For today only — see the note at the top of the file.
                    await manager.useMosqueForToday(suggestion.mosque.id);
                    ref.read(_dismissedProvider.notifier).state = true;
                  },
                  child: const Text('Use it today'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Whole kilometres below ten, otherwise rounded — a fix accurate to a
  /// kilometre does not support "18.4 km", and printing it would imply a
  /// precision this does not have.
  static String _km(double value) =>
      value < 10 ? '${value.round()} km' : '${(value / 5).round() * 5} km';
}
