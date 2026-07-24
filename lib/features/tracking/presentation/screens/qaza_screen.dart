/// Outstanding make-up prayers.
///
/// A prayer whose window closed unfulfilled does not stop mattering when the
/// day ends. This screen is where that debt is visible and dischargeable —
/// which is the difference between an app that tells someone off and one that
/// helps them put it right.
///
/// The tone is deliberate. Nothing here counts failures or uses language of
/// guilt: it lists what is owed, oldest first, and offers a single action.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../data/repositories/qaza_repository.dart';
import '../providers/tracking_providers.dart';

class QazaScreen extends ConsumerWidget {
  const QazaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(qazaLedgerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Make-up prayers')),
      body: ledger.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          onRetry: () => ref.invalidate(qazaLedgerProvider),
        ),
        data: (records) => records.isEmpty
            ? const _ClearState()
            : _Ledger(records: records),
      ),
    );
  }
}

class _Ledger extends ConsumerWidget {
  const _Ledger({required this.records});

  final List<QazaRecord> records;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xxl,
      ),
      children: [
        Text(
          records.length == 1
              ? 'One prayer to make up'
              : '${records.length} prayers to make up',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Pray them when you can, then mark them here. The oldest is first.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        for (final record in records) ...[
          _QazaTile(record: record),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _QazaTile extends ConsumerStatefulWidget {
  const _QazaTile({required this.record});

  final QazaRecord record;

  @override
  ConsumerState<_QazaTile> createState() => _QazaTileState();
}

class _QazaTileState extends ConsumerState<_QazaTile> {
  /// Guards against a double tap booking the same prayer twice while the write
  /// is in flight.
  bool _isSubmitting = false;

  Future<void> _complete() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      final cleared = await ref.read(prayerTrackerProvider).completeQaza(
            date: widget.record.date,
            prayer: widget.record.prayer,
          );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cleared
                ? '${widget.record.prayer.displayName} marked as made up.'
                // Already cleared elsewhere — reporting success twice for one
                // prayer would misrepresent the record.
                : 'That prayer was already marked as made up.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final record = widget.record;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.prayer.displayName,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat.yMMMEd().format(record.date),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: _isSubmitting ? null : _complete,
            child: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Prayed'),
          ),
        ],
      ),
    );
  }
}

class _ClearState extends StatelessWidget {
  const _ClearState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Nothing to make up', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Every prayer whose window has closed was accounted for.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Your make-up prayers could not be loaded.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
