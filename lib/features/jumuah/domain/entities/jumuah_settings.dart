/// The user's whole Jumu'ah configuration.
///
/// Holds a list of mosques rather than a fixed pair, plus which one is
/// selected. Selection is by **id**, not by index or by object, so renaming a
/// mosque or reordering the list cannot silently change which one is in force.
library;

import 'package:flutter/foundation.dart';

import 'jumuah_profile.dart' show JumuahLocation, LocalTimeOfDay;
import 'mosque_profile.dart';

@immutable
class JumuahSettings {
  const JumuahSettings({
    this.enabled = true,
    this.selectedMosqueId,
    this.lastUsedMosqueId,
    List<MosqueProfile>? mosques,
    this.silenceDuringJumuah = false,
    this.smartLocationPrompts = true,
  }) : _mosques = mosques;

  /// Null on a fresh install, which reads as "use the seeded set".
  ///
  /// Stored raw rather than normalised in the initialiser so this constructor
  /// can stay const — AppSettings is const-constructible and is built on every
  /// settings change, and losing that would make `const AppSettings()` illegal
  /// across the app and its tests.
  final List<MosqueProfile>? _mosques;

  /// Whether Jumu'ah replaces Dhuhr on Fridays at all.
  ///
  /// On by default. Someone for whom Jumu'ah is not obligatory, or who cannot
  /// attend, turns it off and gets ordinary Dhuhr every day.
  final bool enabled;

  /// The mosque in force, or null before the user has been asked.
  ///
  /// Null is meaningful, not missing: it is what triggers the first-Friday
  /// prompt. Defaulting it would answer a question on the user's behalf and
  /// then never ask.
  final String? selectedMosqueId;

  /// The last mosque actually used on a Friday.
  ///
  /// Distinct from [selectedMosqueId] because they diverge: a user who picks a
  /// different mosque for one travelling Friday has a *selection* for that day
  /// and a *habit* to fall back to. This is what "Last Used Mosque" means.
  final String? lastUsedMosqueId;

  /// Every mosque the user has. Never empty — falls back to the seeded set.
  List<MosqueProfile> get mosques {
    final stored = _mosques;
    return stored == null || stored.isEmpty
        ? MosqueProfile.defaults()
        : List.unmodifiable(stored);
  }

  /// Whether to silence the phone for the duration of the congregation.
  final bool silenceDuringJumuah;

  /// Whether to offer a different mosque when the user appears to be somewhere
  /// else on a Friday.
  final bool smartLocationPrompts;

  bool get needsMosqueChoice => enabled && selectedMosqueId == null;

  MosqueProfile? mosqueById(String? id) {
    if (id == null) return null;
    for (final mosque in mosques) {
      if (mosque.id == id) return mosque;
    }
    return null;
  }

  /// The mosque in force today.
  ///
  /// Falls back to the last used one when the selection points at a mosque that
  /// has since been deleted — losing a preference because a different mosque
  /// was removed would be baffling.
  MosqueProfile? get activeMosque =>
      mosqueById(selectedMosqueId) ?? mosqueById(lastUsedMosqueId);

  /// Whether Jumu'ah is configured enough to take effect on Fridays.
  bool get isActive {
    if (!enabled) return false;
    final mosque = activeMosque;
    return mosque != null && mosque.isValid;
  }

  List<MosqueProfile> mosquesOfKind(MosqueKind kind) =>
      mosques.where((mosque) => mosque.kind == kind).toList(growable: false);

  // -- transitions ---------------------------------------------------------

  /// Choose a mosque, recording it as the habit too.
  JumuahSettings selecting(String mosqueId) => _copy(
        selectedMosqueId: mosqueId,
        lastUsedMosqueId: mosqueId,
      );

  /// Use a mosque for today without changing the standing preference.
  ///
  /// This is what the "you appear to be in a different city" prompt does: the
  /// user is somewhere else this week, not permanently.
  JumuahSettings usingForToday(String mosqueId) =>
      _copy(selectedMosqueId: mosqueId);

  JumuahSettings withMosque(MosqueProfile mosque) {
    final existing = mosques.indexWhere((m) => m.id == mosque.id);
    final next = [...mosques];

    if (existing >= 0) {
      next[existing] = mosque;
    } else {
      next.add(mosque);
    }
    return _copy(mosques: next);
  }

  /// Remove a mosque, clearing any preference that pointed at it.
  ///
  /// The last mosque cannot be removed: an empty list would leave the Friday
  /// prompt with nothing to offer.
  JumuahSettings withoutMosque(String mosqueId) {
    if (mosques.length <= 1) return this;

    return JumuahSettings(
      enabled: enabled,
      selectedMosqueId:
          selectedMosqueId == mosqueId ? null : selectedMosqueId,
      lastUsedMosqueId:
          lastUsedMosqueId == mosqueId ? null : lastUsedMosqueId,
      mosques: mosques.where((m) => m.id != mosqueId).toList(),
      silenceDuringJumuah: silenceDuringJumuah,
      smartLocationPrompts: smartLocationPrompts,
    );
  }

  /// Forget the selection so the prompt appears again.
  ///
  /// The habit is deliberately kept: "ask me again" does not mean "forget
  /// everything you know about where I pray".
  JumuahSettings clearSelection() => JumuahSettings(
        enabled: enabled,
        selectedMosqueId: null,
        lastUsedMosqueId: lastUsedMosqueId,
        mosques: mosques,
        silenceDuringJumuah: silenceDuringJumuah,
        smartLocationPrompts: smartLocationPrompts,
      );

  JumuahSettings copyWith({
    bool? enabled,
    bool? silenceDuringJumuah,
    bool? smartLocationPrompts,
    List<MosqueProfile>? mosques,
  }) =>
      _copy(
        enabled: enabled,
        silenceDuringJumuah: silenceDuringJumuah,
        smartLocationPrompts: smartLocationPrompts,
        mosques: mosques,
      );

  JumuahSettings _copy({
    bool? enabled,
    String? selectedMosqueId,
    String? lastUsedMosqueId,
    List<MosqueProfile>? mosques,
    bool? silenceDuringJumuah,
    bool? smartLocationPrompts,
  }) =>
      JumuahSettings(
        enabled: enabled ?? this.enabled,
        selectedMosqueId: selectedMosqueId ?? this.selectedMosqueId,
        lastUsedMosqueId: lastUsedMosqueId ?? this.lastUsedMosqueId,
        mosques: mosques ?? this.mosques,
        silenceDuringJumuah: silenceDuringJumuah ?? this.silenceDuringJumuah,
        smartLocationPrompts:
            smartLocationPrompts ?? this.smartLocationPrompts,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'selectedMosqueId': selectedMosqueId,
        'lastUsedMosqueId': lastUsedMosqueId,
        'mosques': [for (final mosque in mosques) mosque.toJson()],
        'silenceDuringJumuah': silenceDuringJumuah,
        'smartLocationPrompts': smartLocationPrompts,
      };

  factory JumuahSettings.fromJson(Map<String, dynamic> json) {
    final stored = json['mosques'];

    final mosques = stored is List && stored.isNotEmpty
        ? stored
            .whereType<Map>()
            .map((m) => MosqueProfile.fromJson(m.cast<String, dynamic>()))
            .toList()
        : _migrateFromTwoLocationModel(json);

    return JumuahSettings(
      enabled: json['enabled'] as bool? ?? true,
      selectedMosqueId:
          json['selectedMosqueId'] as String? ?? _migrateSelection(json),
      lastUsedMosqueId: json['lastUsedMosqueId'] as String?,
      mosques: mosques,
      silenceDuringJumuah: json['silenceDuringJumuah'] as bool? ?? false,
      smartLocationPrompts: json['smartLocationPrompts'] as bool? ?? true,
    );
  }

  /// Rebuild the mosque list for an install that predates it.
  ///
  /// The earlier model stored exactly two profiles under `homeMosque` and
  /// `universityMosque`. Their *times* are the user's own configuration, so
  /// they are carried across onto the seeded mosques of the same id; anything
  /// they never touched keeps the shipped defaults.
  static List<MosqueProfile> _migrateFromTwoLocationModel(
    Map<String, dynamic> json,
  ) {
    final seeded = MosqueProfile.defaults();

    LocalTimeOfDay? timeAt(String profileKey, String field) {
      final profile = json[profileKey];
      if (profile is! Map) return null;
      final time = profile[field];
      if (time is! Map) return null;
      return LocalTimeOfDay.fromJson(time.cast<String, dynamic>());
    }

    return [
      for (final mosque in seeded)
        switch (mosque.id) {
          'home' => mosque.copyWith(
              startsAt: timeAt('homeMosque', 'startsAt') ?? mosque.startsAt,
              endsAt: timeAt('homeMosque', 'endsAt') ?? mosque.endsAt,
            ),
          'university' => mosque.copyWith(
              startsAt:
                  timeAt('universityMosque', 'startsAt') ?? mosque.startsAt,
              endsAt: timeAt('universityMosque', 'endsAt') ?? mosque.endsAt,
            ),
          _ => mosque,
        },
    ];
  }

  /// Map an old `selectedLocation` wire value onto the new mosque id.
  ///
  /// Returns null when nothing was selected, which correctly preserves the
  /// "still needs to be asked" state across the upgrade.
  static String? _migrateSelection(Map<String, dynamic> json) {
    final legacy = json['selectedLocation'] as String?;
    if (legacy == null) return null;

    return switch (JumuahLocation.fromWire(legacy)) {
      JumuahLocation.homeMosque => 'home',
      JumuahLocation.universityMosque => 'university',
    };
  }

  @override
  bool operator ==(Object other) =>
      other is JumuahSettings &&
      other.enabled == enabled &&
      other.selectedMosqueId == selectedMosqueId &&
      other.lastUsedMosqueId == lastUsedMosqueId &&
      other.silenceDuringJumuah == silenceDuringJumuah &&
      other.smartLocationPrompts == smartLocationPrompts &&
      listEquals(other.mosques, mosques);

  @override
  int get hashCode => Object.hash(
        enabled,
        selectedMosqueId,
        lastUsedMosqueId,
        silenceDuringJumuah,
        smartLocationPrompts,
        Object.hashAll(mosques),
      );
}
