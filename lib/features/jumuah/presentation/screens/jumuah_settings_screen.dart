/// Jumu'ah settings: mosques, times, and the Friday behaviours.
///
/// Every time here is a wall-clock time set by a mosque, not something the app
/// can compute, so this screen is where the user tells it what their mosques
/// actually do. It shows the consequence of each choice — and warns when a
/// configured time falls outside Dhuhr and had to be clamped — because a
/// Jumu'ah time that is silently ignored looks identical to one that works.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../blocking/data/datasources/blocking_platform_channel.dart';
import '../../../prayer_times/presentation/providers/prayer_times_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/jumuah_profile.dart' show LocalTimeOfDay;
import '../../domain/entities/mosque_profile.dart';
import '../../domain/usecases/friday_detector.dart';
import '../../domain/usecases/jumuah_scheduler.dart';
import '../providers/jumuah_providers.dart';
import '../widgets/jumuah_icon.dart';
import 'mosque_editor_screen.dart';

class JumuahSettingsScreen extends ConsumerWidget {
  const JumuahSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(jumuahManagerProvider);
    final status = ref.watch(jumuahStatusProvider);
    final jumuah = ref.watch(settingsProvider).jumuah;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).jumuahTitle)),
      floatingActionButton: jumuah.enabled
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(context),
              icon: const Icon(Icons.add),
              label: Text(AppLocalizations.of(context).jumuahAddMosque),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl * 2),
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              AppLocalizations.of(context).jumuahIntro,
              style: theme.textTheme.bodyMedium,
            ),
          ),

          SwitchListTile(
            secondary: const JumuahIcon(size: 24),
            title: Text(AppLocalizations.of(context).jumuahSmart),
            subtitle: Text(
              jumuah.enabled
                  ? AppLocalizations.of(context).jumuahReplacesDhuhr
                  : AppLocalizations.of(context).jumuahDhuhrEveryDay,
            ),
            value: jumuah.enabled,
            onChanged: manager.setEnabled,
          ),

          if (jumuah.enabled) ...[
            _SectionHeader(AppLocalizations.of(context).jumuahYourMosques),

            if (jumuah.needsMosqueChoice)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Text(
                  AppLocalizations.of(context).jumuahChooseMosque,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.warning),
                ),
              ),

            RadioGroup<String>(
              groupValue: jumuah.selectedMosqueId,
              onChanged: (id) => id == null ? null : manager.chooseMosque(id),
              child: Column(
                children: [
                  for (final mosque in jumuah.mosques)
                    _MosqueTile(
                      mosque: mosque,
                      // The last mosque cannot be deleted — an empty list
                      // would leave the Friday prompt with nothing to offer.
                      canDelete: jumuah.mosques.length > 1,
                      onEdit: () => _openEditor(context, mosque: mosque),
                      onDelete: () => manager.deleteMosque(mosque.id),
                    ),
                ],
              ),
            ),

            _SectionHeader(AppLocalizations.of(context).jumuahFridayBehaviour),

            const _SilenceTile(),

            SwitchListTile(
              secondary: const Icon(Icons.travel_explore_outlined),
              title: Text(AppLocalizations.of(context).jumuahAskWhenTravel),
              subtitle: Text(
                AppLocalizations.of(context).jumuahAskWhenTravelBody,
              ),
              value: jumuah.smartLocationPrompts,
              onChanged: manager.setSmartLocationPrompts,
            ),

            _SectionHeader(AppLocalizations.of(context).jumuahReset),

            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: Text(AppLocalizations.of(context).jumuahResetTimes),
              subtitle: Text(AppLocalizations.of(context).jumuahResetTimesBody),
              onTap: manager.resetSeededMosques,
            ),

            ListTile(
              leading: const Icon(Icons.help_outline),
              title: Text(AppLocalizations.of(context).jumuahForget),
              subtitle: Text(AppLocalizations.of(context).jumuahForgetBody),
              enabled: jumuah.selectedMosqueId != null,
              onTap: jumuah.selectedMosqueId == null
                  ? null
                  : manager.resetSelection,
            ),

            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: _TodayPreview(isFriday: status.isFriday),
            ),
          ],
        ],
      ),
    );
  }

  static void _openEditor(BuildContext context, {MosqueProfile? mosque}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MosqueEditorScreen(mosque: mosque),
      ),
    );
  }
}

class _MosqueTile extends StatelessWidget {
  const _MosqueTile({
    required this.mosque,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
  });

  final MosqueProfile mosque;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RadioListTile<String>(
      value: mosque.id,
      title: Text(mosque.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(mosque.formattedRange),
          if (mosque.address != null && mosque.address!.trim().isNotEmpty)
            Text(
              mosque.address!,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      isThreeLine: mosque.address != null && mosque.address!.trim().isNotEmpty,
      secondary: PopupMenuButton<String>(
        onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          if (canDelete)
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}

/// What today actually looks like under the current configuration.
class _TodayPreview extends ConsumerWidget {
  const _TodayPreview({required this.isFriday});

  final bool isFriday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final date = ref.watch(localDateProvider);

    if (!isFriday) {
      final next = FridayDetector.nextFridayOnOrAfter(date);
      final days = next.difference(date).inDays;

      return Text(
        days == 1
            ? AppLocalizations.of(context).jumuahNextFridayTomorrow
            : AppLocalizations.of(context).jumuahNextFridayDays(days),
        style: theme.textTheme.bodySmall,
      );
    }

    final windows = ref.watch(todayWindowsProvider);
    final timezone = ref.watch(settingsProvider).location?.timezone;

    if (windows == null || timezone == null) {
      return Text(AppLocalizations.of(context).jumuahTodayIsFriday, style: theme.textTheme.bodySmall);
    }

    final result = ref
        .watch(jumuahManagerProvider)
        .applyWithResult(windows, timezone: timezone);

    return Text(
      switch (result.application) {
        JumuahApplication.applied => AppLocalizations.of(context).jumuahAppliedToday,
        JumuahApplication.appliedWithClamping =>
          AppLocalizations.of(context).jumuahAppliedClamped,
        JumuahApplication.invalidProfile =>
          AppLocalizations.of(context).jumuahOutsideDhuhr,
        JumuahApplication.notApplied => AppLocalizations.of(context).jumuahNotActive,
      },
      style: theme.textTheme.bodySmall?.copyWith(
        color: result.application == JumuahApplication.invalidProfile
            ? AppColors.danger
            : null,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      );
}

/// Shared time-of-day picker used by the mosque editor.
Future<LocalTimeOfDay?> pickLocalTime(
  BuildContext context, {
  required LocalTimeOfDay initial,
  required String helpText,
}) async {
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    helpText: helpText,
  );
  if (picked == null) return null;
  return LocalTimeOfDay(picked.hour, picked.minute);
}

/// The silence toggle, plus the permission it depends on.
///
/// Changing Do Not Disturb needs notification-policy access, which Android
/// only grants from a system Settings screen. The toggle is shown either way —
/// the user's intent is worth recording before the permission exists — but
/// when access is missing it says so and offers the way to fix it, rather than
/// sitting on and doing nothing.
class _SilenceTile extends ConsumerStatefulWidget {
  const _SilenceTile();

  @override
  ConsumerState<_SilenceTile> createState() => _SilenceTileState();
}

class _SilenceTileState extends ConsumerState<_SilenceTile>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user grants access in system Settings, so the answer can only have
    // changed while we were backgrounded. Re-asking on resume is what makes
    // the warning disappear by itself once they come back.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(silencePermissionProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(jumuahManagerProvider);
    final enabled = ref.watch(settingsProvider).jumuah.silenceDuringJumuah;
    final granted = ref.watch(silencePermissionProvider).valueOrNull ?? true;
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.volume_off_outlined),
          title: Text(AppLocalizations.of(context).jumuahSilence),
          subtitle: Text(
            AppLocalizations.of(context).jumuahSilenceBody,
          ),
          value: enabled,
          onChanged: manager.setSilenceDuringJumuah,
        ),
        if (enabled && !granted)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            // The action sits on its own line, left-aligned. Beside the text it
            // ends up under the AppLocalizations.of(context).jumuahAddMosque FAB, which is bottom-right — a
            // button the user cannot reach is worse than no button.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context).jumuahSilenceNeedsAccess,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.lg),
                  child: TextButton(
                    onPressed: () =>
                        BlockingPlatformChannel().requestSilencePermission(),
                    child: Text(AppLocalizations.of(context).jumuahGrantAccess),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
