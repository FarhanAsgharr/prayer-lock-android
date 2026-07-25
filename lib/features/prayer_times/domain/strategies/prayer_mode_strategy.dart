/// How a day's five prayers become the units the user actually acts on.
///
/// The five obligations never change. What changes is how many *windows*,
/// *locks* and *verifications* they present as: five for someone who prays each
/// at its own time, three for someone who joins Dhuhr with Asr and Maghrib with
/// Isha. That projection is what a "prayer mode" is.
///
/// Behind a strategy rather than a conditional for the same reason the section
/// defaults are: the moment `if (grouping == both)` appears in the lock logic,
/// the notification scheduler and the dashboard, adding a fourth arrangement
/// means auditing the whole app for places that assumed there were three. Here,
/// a new arrangement is one more strategy in the registry.
///
/// Combining is a settings choice, never a consequence of which section the
/// user selected. A section may *suggest* a mode — [PrayerModeRegistry] never
/// asks which section is in force.
library;

import '../../../sections/domain/entities/prayer_grouping.dart';
import '../entities/prayer_day.dart';
import '../entities/prayer_enums.dart';
import '../entities/prayer_slot.dart';

/// Projects a day into the slots one arrangement produces.
abstract interface class PrayerModeStrategy {
  /// The grouping this strategy answers for.
  PrayerGrouping get grouping;

  /// Name for the settings screen. A localisation key, resolved by the UI.
  String get labelKey;

  /// How many units the user acts on per day: five, four, or three.
  int get slotCount;

  /// Whether [prayer] shares its slot with another under this arrangement.
  bool joins(PrayerName prayer);

  /// The day's slots, in ascending order of start time.
  List<PrayerSlot> slotsFor(PrayerDay day);
}

/// The arrangement in which every prayer stands alone.
///
/// Not a special case of [_JoiningModeStrategy] with an empty pair set, even
/// though it would behave identically. Written out because it is the default
/// and by far the most common, and a reader tracing why five slots came back
/// should land on eleven obvious lines rather than on a loop that happens to
/// iterate zero times.
class SeparatePrayerModeStrategy implements PrayerModeStrategy {
  const SeparatePrayerModeStrategy();

  @override
  PrayerGrouping get grouping => PrayerGrouping.none;

  @override
  String get labelKey => 'prayerModeSeparate';

  @override
  int get slotCount => PrayerName.values.length;

  @override
  bool joins(PrayerName prayer) => false;

  @override
  List<PrayerSlot> slotsFor(PrayerDay day) => List.unmodifiable([
        for (final entry in day.entries) PrayerSlot.single(entry),
      ]);
}

/// The arrangement in which named pairs share one window.
///
/// One implementation serves all three joining arrangements: what differs
/// between them is only *which* pairs are named, and that is data, not
/// behaviour. Three near-identical classes would be three places to fix the
/// Jumu'ah rule below.
class _JoiningModeStrategy implements PrayerModeStrategy {
  const _JoiningModeStrategy(this.grouping, this.labelKey);

  @override
  final PrayerGrouping grouping;

  @override
  final String labelKey;

  @override
  int get slotCount => grouping.slotCount;

  @override
  bool joins(PrayerName prayer) => grouping.pairFor(prayer) != null;

  @override
  List<PrayerSlot> slotsFor(PrayerDay day) {
    final slots = <PrayerSlot>[];
    final consumed = <PrayerName>{};

    for (final entry in day.entries) {
      if (consumed.contains(entry.prayer)) continue;

      final pair = grouping.pairFor(entry.prayer);
      if (pair == null) {
        slots.add(PrayerSlot.single(entry));
        continue;
      }

      // Jumu'ah never joins a pair. Its window is a short, mosque-set slot —
      // typically half an hour — and absorbing Asr into it would either extend
      // the congregation to Maghrib or swallow Asr inside fifteen minutes.
      // Neither is what a user who combines Dhuhr with Asr is asking for, so
      // on Fridays the two stand alone.
      if (entry.window.isJumuah ||
          day.entries.any(
            (candidate) =>
                pair.contains(candidate.prayer) && candidate.window.isJumuah,
          )) {
        slots.add(PrayerSlot.single(entry));
        continue;
      }

      // Only the first prayer of a pair opens a slot; the second is absorbed.
      // Guarding on this rather than on position means a grouping naming a
      // pair whose prayers are not both present cannot produce a half-slot.
      if (entry.prayer != pair.first) {
        slots.add(PrayerSlot.single(entry));
        continue;
      }

      final second = day.entries
          .where((candidate) => candidate.prayer == pair.second)
          .firstOrNull;

      if (second == null) {
        slots.add(PrayerSlot.single(entry));
        continue;
      }

      slots.add(PrayerSlot(prayers: [entry, second], pair: pair));
      consumed.addAll([entry.prayer, second.prayer]);
    }

    return List.unmodifiable(slots);
  }
}

/// Resolves a grouping to the strategy that projects it.
///
/// A registry rather than a switch so a regional build or a test can substitute
/// an arrangement — for instance one that joins a pair only on travel days —
/// without editing any consumer.
class PrayerModeRegistry {
  PrayerModeRegistry(Iterable<PrayerModeStrategy> strategies)
      : _strategies = {
          for (final strategy in strategies) strategy.grouping: strategy,
        };

  /// The arrangements the app ships with.
  factory PrayerModeRegistry.standard() => PrayerModeRegistry(const [
        SeparatePrayerModeStrategy(),
        _JoiningModeStrategy(PrayerGrouping.dhuhrAsr, 'prayerModeDhuhrAsr'),
        _JoiningModeStrategy(
          PrayerGrouping.maghribIsha,
          'prayerModeMaghribIsha',
        ),
        _JoiningModeStrategy(PrayerGrouping.both, 'prayerModeBoth'),
      ]);

  final Map<PrayerGrouping, PrayerModeStrategy> _strategies;

  /// The strategy for [grouping].
  ///
  /// Falls back to the separate arrangement rather than throwing. A registry
  /// missing an entry is a programming error, but the recovery a user wants is
  /// their prayers shown unjoined — not a crash on the dashboard.
  PrayerModeStrategy forGrouping(PrayerGrouping grouping) =>
      _strategies[grouping] ?? const SeparatePrayerModeStrategy();

  /// Every registered arrangement, for the settings screen.
  List<PrayerModeStrategy> get all => List.unmodifiable(_strategies.values);

  /// A copy with [strategy] replacing whatever answered for its grouping.
  PrayerModeRegistry withStrategy(PrayerModeStrategy strategy) =>
      PrayerModeRegistry([
        ..._strategies.values.where((s) => s.grouping != strategy.grouping),
        strategy,
      ]);
}
