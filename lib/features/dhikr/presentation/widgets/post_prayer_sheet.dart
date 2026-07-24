/// What the app offers after a prayer is confirmed.
///
/// Both offers are **opt-in and dismissible**. An app that blocks your phone
/// for prayer has already spent most of the goodwill a user will extend it;
/// following that with an unasked-for religious prompt every single time would
/// spend the rest. So neither is enabled by default, and both can be waved away
/// without completing them.
///
/// The tasbih is a counter rather than a checklist because that is how it is
/// actually done — you count, you do not tick boxes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../settings/presentation/providers/settings_provider.dart';

/// One phrase of the tasbih after prayer.
class DhikrPhrase {
  const DhikrPhrase({
    required this.arabic,
    required this.transliteration,
    required this.meaning,
    required this.count,
  });

  final String arabic;
  final String transliteration;
  final String meaning;
  final int count;

  /// The tasbih of Fatimah, as it is most commonly counted.
  static const List<DhikrPhrase> afterPrayer = [
    DhikrPhrase(
      arabic: 'سُبْحَانَ اللَّه',
      transliteration: 'SubhanAllah',
      meaning: 'Glory be to Allah',
      count: 33,
    ),
    DhikrPhrase(
      arabic: 'الْحَمْدُ لِلَّه',
      transliteration: 'Alhamdulillah',
      meaning: 'All praise is for Allah',
      count: 33,
    ),
    DhikrPhrase(
      arabic: 'اللَّهُ أَكْبَر',
      transliteration: 'Allahu Akbar',
      meaning: 'Allah is the greatest',
      count: 34,
    ),
  ];
}

/// Show the post-prayer offers, if any are enabled.
///
/// Returns immediately when both are off, so the caller can invoke it
/// unconditionally after recording a prayer.
Future<void> showPostPrayerSheet(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsProvider);
  if (!settings.dhikrRemindersEnabled && !settings.quranRemindersEnabled) {
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _PostPrayerSheet(),
  );
}

class _PostPrayerSheet extends ConsumerStatefulWidget {
  const _PostPrayerSheet();

  @override
  ConsumerState<_PostPrayerSheet> createState() => _PostPrayerSheetState();
}

class _PostPrayerSheetState extends ConsumerState<_PostPrayerSheet> {
  /// Which phrase is being counted, and how far through it.
  int _phraseIndex = 0;
  int _count = 0;

  void _tap() {
    final phrase = DhikrPhrase.afterPrayer[_phraseIndex];

    setState(() {
      if (_count + 1 < phrase.count) {
        _count++;
        return;
      }
      // Phrase complete — advance, or finish.
      if (_phraseIndex + 1 < DhikrPhrase.afterPrayer.length) {
        _phraseIndex++;
        _count = 0;
      } else {
        _count = phrase.count;
      }
    });
  }

  bool get _isComplete =>
      _phraseIndex == DhikrPhrase.afterPrayer.length - 1 &&
      _count >= DhikrPhrase.afterPrayer.last.count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final phrase = DhikrPhrase.afterPrayer[_phraseIndex];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Prayer recorded', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.lg),

            if (settings.dhikrRemindersEnabled) ...[
              Text(
                phrase.arabic,
                style: theme.textTheme.headlineMedium,
                textDirection: TextDirection.rtl,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(phrase.transliteration, style: theme.textTheme.titleSmall),
              Text(phrase.meaning, style: theme.textTheme.bodySmall),

              const SizedBox(height: AppSpacing.md),

              // A large tap target rather than a small button: this is tapped
              // a hundred times, often without looking.
              InkWell(
                onTap: _isComplete ? null : _tap,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: Container(
                  width: 140,
                  height: 140,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.primary.withValues(alpha: 0.10),
                    border: Border.all(
                      color: theme.colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$_count',
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      Text(
                        'of ${phrase.count}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.sm),
              Text(
                _isComplete
                    ? 'Tasbih complete'
                    : 'Tap to count',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            if (settings.quranRemindersEnabled) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Read the Quran for five minutes?',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      // The app does not ship a mushaf and does not pretend to.
                      // It nudges and gets out of the way.
                      'Open your usual Quran app or copy — this is just a '
                      'reminder while you are still sitting.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
