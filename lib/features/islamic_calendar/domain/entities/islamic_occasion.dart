/// Significant days in the Islamic year.
///
/// Everything here is derived from the Hijri date, so it inherits the ±1 day
/// caveat documented in `hijri_date.dart`. That is acceptable precisely because
/// none of these drive an obligation the app enforces: they change what the
/// dashboard says and which optional reminders appear. A prayer is never
/// scheduled, blocked or recorded on the strength of one.
///
/// Laylatul Qadr is the sharpest case. Its exact night is unknown — that is
/// the point of it — so the app marks the odd nights of the last ten as
/// *possible*, which is what the tradition actually says, rather than naming a
/// night it cannot know.
library;

import 'package:flutter/foundation.dart';

import 'hijri_date.dart';

/// What kind of day this is, for iconography and emphasis.
enum OccasionKind {
  /// Eid al-Fitr and Eid al-Adha.
  eid,

  /// A day of fasting — Ramadan, Ashura, Arafah, the White Days.
  fasting,

  /// A night of particular worth.
  night,

  /// Context only: a sacred month, the day of Hajj.
  observance,
}

/// One occasion falling on a particular Hijri date.
@immutable
class IslamicOccasion {
  const IslamicOccasion({
    required this.id,
    required this.name,
    required this.kind,
    required this.description,
    this.isEstimated = true,
  });

  final String id;
  final String name;
  final OccasionKind kind;

  /// One line the dashboard can show without the user needing to know more.
  final String description;

  /// Whether the date is an arithmetic estimate rather than a confirmed
  /// sighting. True for everything computed here — surfaced so the UI can say
  /// so rather than implying a certainty the calendar does not have.
  final bool isEstimated;

  @override
  bool operator ==(Object other) => other is IslamicOccasion && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

abstract final class IslamicOccasions {
  /// Every occasion falling on [date].
  ///
  /// A day can carry more than one — the 10th of Dhu al-Hijjah is both Eid
  /// al-Adha and within the days of Tashriq — so this returns a list rather
  /// than a single value.
  static List<IslamicOccasion> on(HijriDate date) {
    final found = <IslamicOccasion>[];

    // --- Ramadan --------------------------------------------------------
    if (date.month == HijriMonth.ramadan) {
      found.add(
        IslamicOccasion(
          id: 'ramadan_day_${date.day}',
          name: 'Ramadan',
          kind: OccasionKind.fasting,
          description: 'Day ${date.day} of Ramadan',
        ),
      );

      // The last ten nights. Odd nights are the ones the tradition singles out
      // for seeking Laylatul Qadr; naming one specific night would claim
      // knowledge nobody has.
      if (date.day >= 21 && date.day.isOdd) {
        found.add(
          const IslamicOccasion(
            id: 'laylatul_qadr_possible',
            name: 'Laylatul Qadr',
            kind: OccasionKind.night,
            description:
                'One of the odd nights of the last ten — seek it tonight',
          ),
        );
      }
    }

    // --- Eid al-Fitr ----------------------------------------------------
    if (date.month == HijriMonth.shawwal && date.day == 1) {
      found.add(
        const IslamicOccasion(
          id: 'eid_al_fitr',
          name: 'Eid al-Fitr',
          kind: OccasionKind.eid,
          description: 'Eid prayer in the morning. Eid Mubarak.',
        ),
      );
    }

    // --- Dhu al-Hijjah --------------------------------------------------
    if (date.month == HijriMonth.dhuAlHijjah) {
      if (date.day == 9) {
        found.add(
          const IslamicOccasion(
            id: 'arafah',
            name: 'Day of Arafah',
            kind: OccasionKind.fasting,
            description: 'Fasting today is recommended for those not on Hajj',
          ),
        );
      }
      if (date.day == 10) {
        found.add(
          const IslamicOccasion(
            id: 'eid_al_adha',
            name: 'Eid al-Adha',
            kind: OccasionKind.eid,
            description: 'Eid prayer in the morning. Eid Mubarak.',
          ),
        );
      }
      if (date.day >= 11 && date.day <= 13) {
        found.add(
          IslamicOccasion(
            id: 'tashriq_${date.day}',
            name: 'Days of Tashriq',
            kind: OccasionKind.observance,
            description: 'Takbeer continues through these days',
          ),
        );
      }
      if (date.day <= 9) {
        found.add(
          IslamicOccasion(
            id: 'first_ten_dhul_hijjah_${date.day}',
            name: 'First ten of Dhu al-Hijjah',
            kind: OccasionKind.observance,
            description: 'Day ${date.day} — among the best days of the year',
          ),
        );
      }
    }

    // --- Ashura ---------------------------------------------------------
    if (date.month == HijriMonth.muharram && date.day == 10) {
      found.add(
        const IslamicOccasion(
          id: 'ashura',
          name: 'Ashura',
          kind: OccasionKind.fasting,
          description: 'The 10th of Muharram',
        ),
      );
    }
    if (date.month == HijriMonth.muharram && date.day == 9) {
      found.add(
        const IslamicOccasion(
          id: 'tasua',
          name: "Tasu'a",
          kind: OccasionKind.fasting,
          description: 'The 9th of Muharram, fasted with Ashura',
        ),
      );
    }

    // --- White Days -----------------------------------------------------
    //
    // The 13th, 14th and 15th of any month, when the moon is full. Excluded in
    // Ramadan, where the whole month is already fasted, and during Tashriq,
    // when fasting is forbidden — surfacing "recommended fast" on a day it is
    // not permitted would be worse than showing nothing.
    if (date.day >= 13 &&
        date.day <= 15 &&
        date.month != HijriMonth.ramadan &&
        !(date.month == HijriMonth.dhuAlHijjah && date.day == 13)) {
      found.add(
        IslamicOccasion(
          id: 'white_day_${date.day}',
          name: 'White Days',
          kind: OccasionKind.fasting,
          description: 'The 13th to 15th — recommended days to fast',
        ),
      );
    }

    return List.unmodifiable(found);
  }

  /// Whether [date] falls in Ramadan.
  static bool isRamadan(HijriDate date) => date.month == HijriMonth.ramadan;

  /// Whether [date] is one of the two Eids.
  static bool isEid(HijriDate date) =>
      (date.month == HijriMonth.shawwal && date.day == 1) ||
      (date.month == HijriMonth.dhuAlHijjah && date.day == 10);

  /// The Eid falling on [date], or null.
  static IslamicOccasion? eidOn(HijriDate date) {
    for (final occasion in on(date)) {
      if (occasion.kind == OccasionKind.eid) return occasion;
    }
    return null;
  }

  /// Whether Takbeer is called for on [date].
  ///
  /// From Fajr on the Day of Arafah through the days of Tashriq, and on the
  /// morning of Eid al-Fitr.
  static bool callsForTakbeer(HijriDate date) {
    if (date.month == HijriMonth.shawwal && date.day == 1) return true;
    return date.month == HijriMonth.dhuAlHijjah &&
        date.day >= 9 &&
        date.day <= 13;
  }

  /// The Gregorian date Ramadan is estimated to begin in [hijriYear].
  static DateTime ramadanStart(int hijriYear) =>
      HijriDate(year: hijriYear, month: HijriMonth.ramadan, day: 1)
          .toGregorian();

  /// The Gregorian date of Eid al-Fitr in [hijriYear].
  static DateTime eidAlFitr(int hijriYear) =>
      HijriDate(year: hijriYear, month: HijriMonth.shawwal, day: 1)
          .toGregorian();

  /// The Gregorian date of Eid al-Adha in [hijriYear].
  static DateTime eidAlAdha(int hijriYear) =>
      HijriDate(year: hijriYear, month: HijriMonth.dhuAlHijjah, day: 10)
          .toGregorian();

  /// Days from [from] until the next occurrence of [target], or null when it
  /// is more than a year away — which should never happen but keeps the
  /// countdown from producing an absurd number if it does.
  static int? daysUntil(HijriDate from, HijriMonth target, int day) {
    for (var year = from.year; year <= from.year + 1; year++) {
      final occasion = HijriDate(year: year, month: target, day: day);
      final delta = occasion.toJdn() - from.toJdn();
      if (delta >= 0) return delta;
    }
    return null;
  }
}
