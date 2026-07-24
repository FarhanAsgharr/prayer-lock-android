/// Choosing an Islamic section.
///
/// The screen is deliberately quiet. It presents sections without ranking them,
/// describes what a choice changes rather than what it means, and never implies
/// that the app knows what anyone's community requires of them. Every default a
/// section supplies is stated plainly and remains editable afterwards.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/islamic_section.dart';
import '../../domain/strategies/islamic_section_strategy.dart';

class IslamicSectionScreen extends ConsumerWidget {
  const IslamicSectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).islamicSectionTitle),
      ),
      body: IslamicSectionPicker(
        selected: settings.section,
        onSelected: (identity) =>
            ref.read(settingsProvider.notifier).setSection(identity),
        onLabelChanged: (label) =>
            ref.read(settingsProvider.notifier).setCustomSectionLabel(label),
      ),
    );
  }
}

/// The picker itself, reusable by onboarding.
///
/// Extracted rather than duplicated so the onboarding step and the settings
/// screen cannot drift apart in what they offer or how they word it.
class IslamicSectionPicker extends StatelessWidget {
  const IslamicSectionPicker({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.onLabelChanged,
    this.showIntro = true,
  });

  final SectionIdentity selected;
  final ValueChanged<SectionIdentity> onSelected;
  final ValueChanged<String> onLabelChanged;
  final bool showIntro;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grouped = IslamicSection.grouped;

    // A single RadioGroup around the whole list, so selection is managed in one
    // place rather than by every tile individually.
    return RadioGroup<IslamicSection>(
      groupValue: selected.section,
      // Selecting "Other" keeps any name already entered, so re-picking it
      // after browsing the list does not wipe what the user typed.
      onChanged: (value) {
        if (value == null) return;
        onSelected(
          value.requiresCustomLabel && selected.customLabel != null
              ? SectionIdentity.custom(selected.customLabel!)
              : SectionIdentity.of(value),
        );
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          if (showIntro)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Text(
                AppLocalizations.of(context).islamicSectionIntro,
                style: theme.textTheme.bodyMedium,
              ),
            ),

          for (final family in grouped.keys) ...[
            _FamilyHeader(family: family),
            for (final section in grouped[family]!)
              _SectionTile(section: section, selected: selected),
          ],

          // Shown only once "Other" is chosen, so the field is never an
          // unexplained text box sitting under a list of options.
          if (selected.section.requiresCustomLabel)
            _CustomLabelField(
              initial: selected.customLabel,
              onChanged: onLabelChanged,
            ),

          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: _SelectedSummary(identity: selected),
          ),
        ],
      ),
    );
  }
}

class _FamilyHeader extends StatelessWidget {
  const _FamilyHeader({required this.family});

  final SectionFamily family;

  /// Section *names* are proper nouns and are left untranslated; the family
  /// headings are ordinary prose and are not.
  static String _label(AppLocalizations strings, SectionFamily family) =>
      switch (family) {
        SectionFamily.sunniTradition => strings.sectionFamilySunniTraditions,
        SectionFamily.sunniCommunity => strings.sectionFamilySunniCommunities,
        SectionFamily.shiaTradition => strings.sectionFamilyShiaTraditions,
        SectionFamily.otherCommunity => strings.sectionFamilyOtherCommunities,
        SectionFamily.custom => strings.sectionFamilyOther,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Text(
        _label(AppLocalizations.of(context), family),
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({required this.section, required this.selected});

  final IslamicSection section;
  final SectionIdentity selected;

  @override
  Widget build(BuildContext context) {
    final isSelected = selected.section == section;

    return RadioListTile<IslamicSection>(
      value: section,
      // The selected "Other" tile shows the user's own name for their section
      // rather than the generic label.
      title: Text(
        isSelected ? selected.displayName : section.defaultLabel,
      ),
      subtitle: Text(
        IslamicSectionRegistry.instance.defaultsFor(section).rationale,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      isThreeLine: true,
    );
  }
}

class _CustomLabelField extends StatefulWidget {
  const _CustomLabelField({required this.initial, required this.onChanged});

  final String? initial;
  final ValueChanged<String> onChanged;

  @override
  State<_CustomLabelField> createState() => _CustomLabelFieldState();
}

class _CustomLabelFieldState extends State<_CustomLabelField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: TextField(
        controller: _controller,
        // Bounded so the name stays renderable in a list tile and in a
        // notification, both of which have very little room.
        maxLength: 48,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: AppLocalizations.of(context).islamicSectionEnterOwn,
          helperText: AppLocalizations.of(context).islamicSectionEnterOwnHelp,
          border: const OutlineInputBorder(),
        ),
        // Saved as the user types rather than on submit: there is no confirm
        // button on this screen, and a name lost on back-navigation would be
        // both annoying and hard to notice.
        onChanged: widget.onChanged,
      ),
    );
  }
}

/// What the current selection implies, stated rather than hidden.
class _SelectedSummary extends StatelessWidget {
  const _SelectedSummary({required this.identity});

  final SectionIdentity identity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaults =
        IslamicSectionRegistry.instance.defaultsFor(identity.section);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            identity.needsLabel
                ? AppLocalizations.of(context).islamicSectionNameYours
                : AppLocalizations.of(context)
                    .islamicSectionSelected(identity.displayName),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          _SummaryRow(
            label: 'Prayer times',
            value: defaults.calculationMethod.displayName,
          ),
          _SummaryRow(label: 'Asr timing', value: defaults.madhab.displayName),
          _SummaryRow(
            label: 'Prayer grouping',
            value: defaults.prayerGrouping.displayName,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            AppLocalizations.of(context).islamicSectionEditable,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
