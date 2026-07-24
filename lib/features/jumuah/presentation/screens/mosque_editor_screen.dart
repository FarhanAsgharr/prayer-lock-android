/// Add or edit a mosque.
///
/// Only three fields are required — a name and the two times. Address, notes
/// and position are optional throughout, because a user who never grants
/// location, or who simply wants "the one near work, 1:45", must be able to
/// finish in ten seconds.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      helpText: isStart ? "Jumu'ah starts" : 'Verification closes',
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
        title: Text(_isEditing ? 'Edit mosque' : 'Add mosque'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            maxLength: 60,
            decoration: InputDecoration(
              labelText: 'Mosque name',
              hintText: _kind.defaultName,
              helperText: 'Shown on the Friday card and in notifications',
              border: const OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          DropdownButtonFormField<MosqueKind>(
            initialValue: _kind,
            decoration: const InputDecoration(
              labelText: 'Type',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final kind in MosqueKind.values)
                DropdownMenuItem(value: kind, child: Text(kind.defaultName)),
            ],
            onChanged: (kind) =>
                kind == null ? null : setState(() => _kind = kind),
          ),

          const SizedBox(height: AppSpacing.lg),

          Text("Jumu'ah time", style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pick(isStart: true),
                  child: Text('Starts ${_startsAt.format()}'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pick(isStart: false),
                  child: Text('Ends ${_endsAt.format()}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Apps stay blocked between these times, and this is the window in '
            'which you can confirm your prayer.',
            style: theme.textTheme.bodySmall,
          ),

          const SizedBox(height: AppSpacing.lg),

          Text('Optional', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),

          TextField(
            controller: _address,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Address',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: AppSpacing.sm),

          TextField(
            controller: _notes,
            maxLength: 200,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notes',
              hintText: 'Parking, which entrance, anything useful',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: AppSpacing.sm),

          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.my_location),
            title: Text(
              _coordinates == null
                  ? 'No position saved'
                  : 'Position saved',
            ),
            subtitle: Text(
              _coordinates == null
                  ? 'Used to offer this mosque when you are nearby'
                  : '${_coordinates!.latitude.toStringAsFixed(3)}, '
                      '${_coordinates!.longitude.toStringAsFixed(3)}',
            ),
            trailing: _coordinates == null
                ? TextButton(
                    onPressed: hasLocation ? _useCurrentLocation : null,
                    child: const Text('Use current'),
                  )
                : TextButton(
                    onPressed: () => setState(() => _coordinates = null),
                    child: const Text('Clear'),
                  ),
          ),
        ],
      ),
    );
  }
}
