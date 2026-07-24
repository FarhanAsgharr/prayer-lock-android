/// Which prayers are treated as one unit.
///
/// Combining (jam') is practised by many Muslims — routinely in Shia
/// jurisprudence, and under travel, illness or hardship across Sunni schools.
/// The app supports it as an ordinary configuration rather than as a mode
/// bolted on for one community, because both the underlying obligation and the
/// user-facing behaviour differ in ways that touch every part of the product:
/// how many cards the dashboard shows, when a lock releases, what a single
/// verification discharges, and how a streak is counted.
///
/// Critically, combining changes *presentation and enforcement*, not the
/// obligation. Five prayers are still owed and still recorded individually, so
/// history, statistics and streaks stay comparable if a user changes this
/// setting — and a user who prays Dhuhr and Asr together still gets credit for
/// two prayers, not one.
library;

import '../../../prayer_times/domain/entities/prayer_enums.dart';

/// The prayers that may be joined, as pairs.
///
/// Fajr is absent deliberately: it is never combined with an adjacent prayer in
/// any school, because sunrise separates it from Dhuhr by several hours.
enum PrayerPair {
  dhuhrAsr(PrayerName.dhuhr, PrayerName.asr, 'Dhuhr + Asr'),
  maghribIsha(PrayerName.maghrib, PrayerName.isha, 'Maghrib + Isha');

  const PrayerPair(this.first, this.second, this.displayName);

  /// The earlier prayer, whose start opens the joined window.
  final PrayerName first;

  /// The later prayer, whose window end closes the joined window.
  final PrayerName second;

  final String displayName;

  List<PrayerName> get prayers => [first, second];

  bool contains(PrayerName prayer) => prayer == first || prayer == second;
}

/// Which pairs the user has chosen to join.
enum PrayerGrouping {
  /// Five independent prayers. The default for most users.
  none('none', 'Five separate prayers'),

  dhuhrAsr('dhuhr_asr', 'Combine Dhuhr and Asr'),

  maghribIsha('maghrib_isha', 'Combine Maghrib and Isha'),

  both('both', 'Combine both pairs');

  const PrayerGrouping(this.wireValue, this.displayName);

  final String wireValue;
  final String displayName;

  static PrayerGrouping fromWire(String value) =>
      PrayerGrouping.values.firstWhere(
        (grouping) => grouping.wireValue == value,
        orElse: () => PrayerGrouping.none,
      );

  /// The pairs joined under this grouping.
  Set<PrayerPair> get pairs => switch (this) {
        PrayerGrouping.none => const {},
        PrayerGrouping.dhuhrAsr => const {PrayerPair.dhuhrAsr},
        PrayerGrouping.maghribIsha => const {PrayerPair.maghribIsha},
        PrayerGrouping.both =>
          const {PrayerPair.dhuhrAsr, PrayerPair.maghribIsha},
      };

  bool get combinesAnything => pairs.isNotEmpty;

  /// The pair [prayer] belongs to under this grouping, or null when it stands
  /// alone.
  PrayerPair? pairFor(PrayerName prayer) {
    for (final pair in pairs) {
      if (pair.contains(prayer)) return pair;
    }
    return null;
  }

  /// How many units the user acts on per day: five, four, or three.
  int get slotCount => PrayerName.values.length - pairs.length;

  /// The result of turning [pair] on or off against this grouping.
  ///
  /// Expressed as a transition rather than as four assignments at the call site
  /// so the two independent toggles in the UI cannot produce a combination the
  /// enum cannot represent.
  PrayerGrouping toggle(PrayerPair pair, {required bool enabled}) {
    final next = {...pairs};
    if (enabled) {
      next.add(pair);
    } else {
      next.remove(pair);
    }

    if (next.isEmpty) return PrayerGrouping.none;
    if (next.length == 2) return PrayerGrouping.both;
    return next.single == PrayerPair.dhuhrAsr
        ? PrayerGrouping.dhuhrAsr
        : PrayerGrouping.maghribIsha;
  }

  bool includes(PrayerPair pair) => pairs.contains(pair);

  /// Short description for the settings screen.
  String get description => switch (this) {
        PrayerGrouping.none =>
          'Each prayer is tracked, blocked and verified on its own.',
        PrayerGrouping.dhuhrAsr =>
          'Dhuhr and Asr share one window, one lock and one verification.',
        PrayerGrouping.maghribIsha =>
          'Maghrib and Isha share one window, one lock and one verification.',
        PrayerGrouping.both =>
          'Dhuhr with Asr, and Maghrib with Isha, each share one window.',
      };
}
