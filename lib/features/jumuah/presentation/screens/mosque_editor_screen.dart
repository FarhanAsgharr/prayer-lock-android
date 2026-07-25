/// Add or edit a mosque.
///
/// Only three fields are required — a name and the two times. Address, notes
/// and position are optional throughout, because a user who never grants
/// location, or who simply wants "the one near work, 1:45", must be able to
/// finish in ten seconds.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/jumuah_profile.dart' show LocalTimeOfDay;
import '../../domain/entities/mosque_profile.dart';
import '../providers/jumuah_providers.dart';

class MosqueEditorScreen extends ConsumerStatefulWidget {
  const MosqueEditorScreen({super.key, this.mosque});

  /// Null when adding.
  final MosqueProfile? mosque;

  @override
  ConsumerState<MosqueEditorScreen> createState() => _MosqueEditorScreenState();
}

class _MosqueEditorScreenState extends ConsumerState<MosqueEditorScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.mosque?.name ?? '');
  late final TextEditingController _address =
      TextEditingController(text: widget.mosque?.address ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.mosque?.notes ?? '');

  late MosqueKind _kind = widget.mosque?.kind ?? MosqueKind.custom;
  late LocalTimeOfDay _startsAt =
      widget.mosque?.startsAt ?? const LocalTimeOfDay(13, 30);
  late LocalTimeOfDay _endsAt =
      widget.mosque?.endsAt ?? const LocalTimeOfDay(13, 45);
  late MosqueCoordinates? _coordinates = widget.mosque?.coordinates;

  bool get _isEditing => widget.mosque != null;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool isStart}) async {
    final current = isStart ? _startsAt : _endsAt;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      helpText: isStart ? AppLocalizations.of(context).jumuahStartsLabel : AppLocalizations.of(context).jumuahClosesLabel,
    );
    if (picked == null) return;

    setState(() {
      final next = LocalTimeOfDay(picked.hour, picked.minute);
      if (isStart) {
        _startsAt = next;
        // Keep the window valid as the user drags. A start past the end would
        // produce a window the scheduler discards silently, and the user would
        // see ordinary Dhuhr with no explanation.
        if (!(_endsAt > next)) _endsAt = next.plusMinutes(15);
      } else {
        _endsAt = next > _startsAt ? next : _startsAt.plusMinutes(15);
      }
    });
  }

  /// Record where the user is now as this mosque's position.
  ///
  /// Uses the location already configured for prayer times rather than asking
  /// for a fresh GPS fix: the user is almost always at or near the mosque they
  /// are adding, and a second permission prompt for an optional field would be
  /// disproportionate.
  void _useCurrentLocation() {
    final location = ref.read(settingsProvider).location;
    if (location == null) return;

    setState(() {
      _coordinates = MosqueCoordinates(
        latitude: location.latitude,
        longitude: location.longitude,
      );
    });
  }

  Future<void> _save() async {
    final manager = ref.read(jumuahManagerProvider);

    final mosque = MosqueProfile(
      // A new mosque gets an id derived from the moment it was created, which
      // is unique without needing a uuid dependency and is stable thereafter.
      id: widget.mosque?.id ??
          'mosque_${DateTime.now().microsecondsSinceEpoch}',
      kind: _kind,
      name: _name.text,
      startsAt: _startsAt,
      endsAt: _endsAt,
      address: _address.text.trim().isEmpty ? null : _address.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      coordinates: _coordinates,
    );

    await manager.saveMosque(mosque);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasLocation = ref.watch(settingsProvider).location != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? AppLocalizations.of(context).jumuahEditMosque : AppLocalizations.of(context).jumuahAddMosque),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(AppLocalizations.of(context).actionSave),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [LengthLimitingTextInputFormatter(60)],
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).jumuahMosqueName,
              hintText: _kind.defaultName,
              helperText: AppLocalizations.of(context).jumuahMosqueNameHelp,
              helperMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          DropdownButtonFormField<MosqueKind>(
            initialValue: _kind,
            // Without this the selected item sizes to its own text and
            // overflows the field on a narrow phone — by 2.5px in English, and
            // by more in any language whose words are longer.
            isExpanded: true,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).jumuahType,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final kind in MosqueKind.values)
                DropdownMenuItem(
                  value: kind,
                  child: Text(kind.defaultName, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (kind) =>
                kind == null ? null : setState(() => _kind = kind),
          ),

          const SizedBox(height: AppSpacing.lg),

          Text(AppLocalizations.of(context).jumuahTime, style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          // Stacked rather than side by side. Two time buttons on one row
          // overflow a narrow phone even in English, and every translation of
          // "Starts"/"Ends" is longer than the English.
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _pick(isStart: true),
              child: Text(
                AppLocalizations.of(context).jumuahStartsAt(_startsAt.format()),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _pick(isStart: false),
              child: Text(
                AppLocalizations.of(context).jumuahEndsAt(_endsAt.format()),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            AppLocalizations.of(context).jumuahTimeHelp,
            style: theme.textTheme.bodySmall,
          ),

          const SizedBox(height: AppSpacing.lg),

          Text(AppLocalizations.of(context).jumuahOptional, style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),

          TextField(
            controller: _address,
            inputFormatters: [LengthLimitingTextInputFormatter(120)],
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).jumuahAddress,
              border: const OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: AppSpacing.sm),

          TextField(
            controller: _notes,
            inputFormatters: [LengthLimitingTextInputFormatter(200)],
            maxLines: 2,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).jumuahNotes,
              hintText: AppLocalizations.of(context).jumuahNotesHint,
              border: const OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: AppSpacing.sm),

          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.my_location),
            title: Text(
              _coordinates == null
                  ? AppLocalizations.of(context).jumuahNoPosition
                  : AppLocalizations.of(context).jumuahPositionSaved,
            ),
            subtitle: Text(
              _coordinates == null
                  ? AppLocalizations.of(context).jumuahPositionHelp
                  : '${_coordinates!.latitude.toStringAsFixed(3)}, '
                      '${_coordinates!.longitude.toStringAsFixed(3)}',
            ),
          ),

          // Below the tile rather than in its trailing slot: a button beside
          // two lines of text overflows a narrow phone, and every translation
          // of "Use current" is longer than the English.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _coordinates == null
                ? TextButton(
                    onPressed: hasLocation ? _useCurrentLocation : null,
                    child: Text(AppLocalizations.of(context).jumuahUseCurrent),
                  )
                : TextButton(
                    onPressed: () => setState(() => _coordinates = null),
                    child: Text(AppLocalizations.of(context).actionClear),
                  ),
          ),
        ],
      ),
    );
  }
}
