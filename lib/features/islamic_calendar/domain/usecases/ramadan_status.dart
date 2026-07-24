/// Ramadan and Eid, bound to the day's actual prayer times.
///
/// The Hijri date says *whether* it is Ramadan; the prayer schedule says *when*
/// the fast begins and ends. Both are needed, and keeping them separate matters:
///
///   * **Sehri ends at Fajr.** Not at some fixed hour — at the computed Fajr
///     instant for the user's location, which moves daily.
///   * **Iftar is at Maghrib**, likewise computed.
///
/// So the countdowns here are exact even though the Hijri date driving them is
/// an estimate. A user whose local sighting differs by a day sees "Day 12"
/// instead of "Day 13", but never breaks their fast at the wrong time.
library;

import 'package:flutter/foundation.dart';

import '../../../prayer_times/domain/entities/prayer_enums.dart';
import '../../../prayer_times/domain/entities/prayer_window.dart';
import '../entities/hijri_date.dart';
import '../entities/islamic_occasion.dart';

/// Which part of a Ramadan day the user is in.
enum FastPhase {
  /// Before Fajr — the pre-dawn meal is still permitted.
  sehri,

  /// Between Fajr and Maghrib.
  fasting,

  /// After Maghrib.
  afterIftar,
}

/// Everything the dashboard needs about Ramadan today.
@immutable
class RamadanStatus {
  const RamadanStatus({
    required this.isRamadan,
    required this.dayOfRamadan,
    required this.phase,
    this.sehriEndsAt,
    this.iftarAt,
    this.taraweehFrom,
  });

  const RamadanStatus.notRamadan()
      : isRamadan = false,
        dayOfRamadan = 0,
        phase = FastPhase.afterIftar,
        sehriEndsAt = null,
        iftarAt = null,
        taraweehFrom = null;

  final bool isRamadan;

  /// 1–30. Zero outside Ramadan.
  final int dayOfRamadan;

  final FastPhase phase;

  /// When the pre-dawn meal must stop — the day's Fajr.
  final DateTime? sehriEndsAt;

  /// When the fast is broken — the day's Maghrib.
  final DateTime? iftarAt;

  /// When Taraweeh typically begins — after Isha.
  final DateTime? taraweehFrom;

  /// Time until Sehri ends, or null once it has.
  Duration? sehriRemaining(DateTime now) {
    final ends = sehriEndsAt;
    if (ends == null || !now.isBefore(ends)) return null;
    return ends.difference(now);
  }

  /// Time until Iftar, or null once the fast is broken.
  Duration? iftarRemaining(DateTime now) {
    final at = iftarAt;
    if (at == null || !now.isBefore(at)) return null;
    return at.difference(now);
  }

  /// Whether the last ten nights have begun.
  bool get isLastTen => isRamadan && dayOfRamadan >= 21;

  /// Whether tonight is one of the odd nights of the last ten.
  bool get isPossibleLaylatulQadr => isLastTen && dayOfRamadan.isOdd;
}

/// Everything the dashboard needs about an Eid.
@immutable
class EidStatus {
  const EidStatus({
    required this.isEid,
    this.occasion,
    this.eidPrayerFrom,
    this.eidPrayerUntil,
    required this.callsForTakbeer,
    this.daysUntilNextEid,
    this.nextEidName,
  });

  const EidStatus.none()
      : isEid = false,
        occasion = null,
        eidPrayerFrom = null,
        eidPrayerUntil = null,
        callsForTakbeer = false,
        daysUntilNextEid = null,
        nextEidName = null;

  final bool isEid;
  final IslamicOccasion? occasion;

  /// Earliest the Eid prayer is held — after sunrise.
  ///
  /// A window rather than a time, because unlike the five daily prayers the
  /// Eid prayer has no single moment: mosques hold it anywhere from shortly
  /// after sunrise until close to Dhuhr, and the app cannot know which.
  final DateTime? eidPrayerFrom;

  /// Latest the Eid prayer may be held — it must be before Dhuhr.
  final DateTime? eidPrayerUntil;

  final bool callsForTakbeer;

  final int? daysUntilNextEid;
  final String? nextEidName;

  String? get name => occasion?.name;
}

abstract final class IslamicDayStatus {
  /// The Ramadan picture for a day.
  ///
  /// [windows] supplies the exact Fajr and Maghrib the countdowns need. Without
  /// it — before the schedule has resolved — the day is still identified as
  /// Ramadan, just without times.
  static RamadanStatus ramadan({
    required HijriDate hijri,
    required DailyPrayerWindows? windows,
  }) {
    if (!IslamicOccasions.isRamadan(hijri)) {
      return const RamadanStatus.notRamadan();
    }

    if (windows == null) {
      return RamadanStatus(
        isRamadan: true,
        dayOfRamadan: hijri.day,
        phase: FastPhase.fasting,
      );
    }

    // Sehri ends when Fajr begins; the fast breaks when Maghrib does.
    final fajr = windows.windowFor(PrayerName.fajr).startsAt;
    final maghrib = windows.windowFor(PrayerName.maghrib).startsAt;
    final isha = windows.windowFor(PrayerName.isha).startsAt;

    return RamadanStatus(
      isRamadan: true,
      dayOfRamadan: hijri.day,
      // Resolved by the caller against the current instant; defaulted here to
      // the middle of the day so a status built without a clock is sensible.
      phase: FastPhase.fasting,
      sehriEndsAt: fajr,
      iftarAt: maghrib,
      taraweehFrom: isha,
    );
  }

  /// [ramadan], with the phase resolved against [now].
  static RamadanStatus ramadanAt({
    required HijriDate hijri,
    required DailyPrayerWindows? windows,
    required DateTime now,
  }) {
    final base = ramadan(hijri: hijri, windows: windows);
    if (!base.isRamadan) return base;

    final sehriEnds = base.sehriEndsAt;
    final iftar = base.iftarAt;
    if (sehriEnds == null || iftar == null) return base;

    return RamadanStatus(
      isRamadan: true,
      dayOfRamadan: base.dayOfRamadan,
      phase: now.isBefore(sehriEnds)
          ? FastPhase.sehri
          : now.isBefore(iftar)
              ? FastPhase.fasting
              : FastPhase.afterIftar,
      sehriEndsAt: sehriEnds,
      iftarAt: iftar,
      taraweehFrom: base.taraweehFrom,
    );
  }

  /// The Eid picture for a day.
  static EidStatus eid({
    required HijriDate hijri,
    required DailyPrayerWindows? windows,
  }) {
    final occasion = IslamicOccasions.eidOn(hijri);
    final takbeer = IslamicOccasions.callsForTakbeer(hijri);

    if (occasion == null) {
      // Not Eid: report how far away the next one is, so the dashboard can
      // count down to it.
      final untilFitr = IslamicOccasions.daysUntil(
        hijri,
        HijriMonth.shawwal,
        1,
      );
      final untilAdha = IslamicOccasions.daysUntil(
        hijri,
        HijriMonth.dhuAlHijjah,
        10,
      );

      final next = <(int, String)>[
        if (untilFitr != null) (untilFitr, 'Eid al-Fitr'),
        if (untilAdha != null) (untilAdha, 'Eid al-Adha'),
      ]..sort((a, b) => a.$1.compareTo(b.$1));

      return EidStatus(
        isEid: false,
        callsForTakbeer: takbeer,
        daysUntilNextEid: next.isEmpty ? null : next.first.$1,
        nextEidName: next.isEmpty ? null : next.first.$2,
      );
    }

    if (windows == null) {
      return EidStatus(
        isEid: true,
        occasion: occasion,
        callsForTakbeer: takbeer,
      );
    }

    // The prayer is held after sunrise and must finish before Dhuhr. Fifteen
    // minutes after sunrise is the conventional earliest — the sun must have
    // visibly risen.
    final sunrise = windows.sunrise;
    final dhuhr = windows.windowFor(PrayerName.dhuhr).startsAt;

    return EidStatus(
      isEid: true,
      occasion: occasion,
      eidPrayerFrom: sunrise.add(const Duration(minutes: 15)),
      eidPrayerUntil: dhuhr,
      callsForTakbeer: takbeer,
    );
  }
}
