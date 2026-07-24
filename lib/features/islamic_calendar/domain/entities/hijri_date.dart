/// The Hijri (Islamic) calendar.
///
/// ## Which Hijri calendar this is, and why it matters
///
/// There is no single Hijri date. The calendar is lunar and, traditionally,
/// each month begins when the new crescent is *sighted* — which depends on
/// weather, on the observer's longitude, and on which authority is trusted.
/// Two Muslims in the same city can legitimately disagree by a day.
///
/// This implementation uses the **tabular Islamic calendar** (Kuwaiti
/// algorithm): pure arithmetic, no observation, no network. That choice has
/// consequences the UI must be honest about:
///
///   * It is deterministic and works offline forever, which is what an app
///     that must survive with no connectivity needs.
///   * It can differ from a local moon-sighting announcement by **±1 day**,
///     occasionally two.
///
/// So this is presented as an *estimate* everywhere it appears, and the user
/// can nudge it by a day. What it is emphatically not used for: deciding when
/// to pray. Prayer times are astronomical and exact; the Hijri date only drives
/// display and non-obligatory reminders, so a one-day error is a cosmetic
/// annoyance rather than a missed prayer.
library;

import 'package:flutter/foundation.dart';

/// Months of the Hijri year, in order.
enum HijriMonth {
  muharram(1, 'Muharram', 'المحرم'),
  safar(2, 'Safar', 'صفر'),
  rabiAlAwwal(3, "Rabi' al-Awwal", 'ربيع الأول'),
  rabiAlThani(4, "Rabi' al-Thani", 'ربيع الآخر'),
  jumadaAlUla(5, 'Jumada al-Ula', 'جمادى الأولى'),
  jumadaAlAkhirah(6, 'Jumada al-Akhirah', 'جمادى الآخرة'),
  rajab(7, 'Rajab', 'رجب'),
  shaban(8, "Sha'ban", 'شعبان'),
  ramadan(9, 'Ramadan', 'رمضان'),
  shawwal(10, 'Shawwal', 'شوال'),
  dhuAlQadah(11, "Dhu al-Qa'dah", 'ذو القعدة'),
  dhuAlHijjah(12, 'Dhu al-Hijjah', 'ذو الحجة');

  const HijriMonth(this.number, this.displayName, this.arabicName);

  final int number;
  final String displayName;
  final String arabicName;

  static HijriMonth fromNumber(int number) => HijriMonth.values.firstWhere(
        (month) => month.number == number,
        orElse: () => HijriMonth.muharram,
      );

  /// The four months in which fighting is forbidden. Shown as context, not as
  /// anything the app enforces.
  bool get isSacred =>
      this == HijriMonth.muharram ||
      this == HijriMonth.rajab ||
      this == HijriMonth.dhuAlQadah ||
      this == HijriMonth.dhuAlHijjah;
}

/// A date in the tabular Islamic calendar.
@immutable
class HijriDate implements Comparable<HijriDate> {
  const HijriDate({
    required this.year,
    required this.month,
    required this.day,
  });

  final int year;
  final HijriMonth month;
  final int day;

  /// Julian Day Number of the Islamic epoch, 1 Muharram 1 AH.
  ///
  /// Corresponds to 16 July 622 CE in the proleptic Julian calendar — the
  /// astronomical convention, which is what the arithmetic below assumes.
  static const int _islamicEpochJdn = 1948439;

  /// Convert a Gregorian date to Hijri.
  ///
  /// [date] is treated as a civil calendar date; the time and zone are ignored,
  /// because a Hijri date is a property of the day, not of an instant. Callers
  /// pass the *local* date at the user's configured location — the same value
  /// `localDateProvider` produces — so travellers get the day they are actually
  /// living in.
  factory HijriDate.fromGregorian(DateTime date) {
    final jdn = _gregorianToJdn(date.year, date.month, date.day);
    return HijriDate.fromJdn(jdn);
  }

  factory HijriDate.fromJdn(int jdn) {
    // Days elapsed since the epoch.
    final elapsed = jdn - _islamicEpochJdn;

    // 30-year cycles contain exactly 10631 days in the tabular calendar: 19
    // years of 354 days and 11 leap years of 355. That regularity is the whole
    // point of the tabular scheme.
    final cycle = (elapsed / 10631).floor();
    var remainder = elapsed - cycle * 10631;

    // Position within the cycle. Walking year by year rather than dividing,
    // because leap years are irregularly distributed inside the cycle.
    var yearInCycle = 1;
    while (yearInCycle <= 30) {
      final length = _isLeapYearInCycle(yearInCycle) ? 355 : 354;
      if (remainder < length) break;
      remainder -= length;
      yearInCycle++;
    }

    final year = cycle * 30 + yearInCycle;

    // Months alternate 30 and 29 days, with Dhu al-Hijjah gaining a day in a
    // leap year.
    var monthNumber = 1;
    while (monthNumber <= 12) {
      final length = _monthLength(monthNumber, yearInCycle);
      if (remainder < length) break;
      remainder -= length;
      monthNumber++;
    }

    return HijriDate(
      year: year,
      month: HijriMonth.fromNumber(monthNumber.clamp(1, 12)),
      day: remainder + 1,
    );
  }

  /// Convert back to a Gregorian date.
  ///
  /// Needed to answer "when does Ramadan start this year" in terms the rest of
  /// the app — which is entirely Gregorian — can schedule against.
  DateTime toGregorian() => _jdnToGregorian(toJdn());

  int toJdn() {
    final cycle = ((year - 1) / 30).floor();
    final yearInCycle = year - cycle * 30;

    var days = cycle * 10631;
    for (var y = 1; y < yearInCycle; y++) {
      days += _isLeapYearInCycle(y) ? 355 : 354;
    }
    for (var m = 1; m < month.number; m++) {
      days += _monthLength(m, yearInCycle);
    }

    return _islamicEpochJdn + days + day - 1;
  }

  /// Length of this date's month, in days.
  int get monthLength =>
      _monthLength(month.number, year - ((year - 1) / 30).floor() * 30);

  /// Whether this Hijri year has 355 days.
  bool get isLeapYear =>
      _isLeapYearInCycle(year - ((year - 1) / 30).floor() * 30);

  HijriDate addDays(int days) => HijriDate.fromJdn(toJdn() + days);

  /// The first day of a given month in this date's year.
  HijriDate firstOf(HijriMonth target) =>
      HijriDate(year: year, month: target, day: 1);

  /// "12 Ramadan 1447"
  String format() => '$day ${month.displayName} $year';

  /// "12 رمضان 1447 هـ"
  String formatArabic() => '$day ${month.arabicName} $year هـ';

  /// "1447 AH"
  String get formattedYear => '$year AH';

  @override
  int compareTo(HijriDate other) => toJdn().compareTo(other.toJdn());

  @override
  bool operator ==(Object other) =>
      other is HijriDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => format();

  // -- calendar arithmetic ------------------------------------------------

  /// Leap years within a 30-year cycle, under the Kuwaiti (and most common)
  /// variant. Other variants shift one or two of these, which is one source of
  /// the ±1 day disagreement noted at the top of this file.
  static const Set<int> _leapYearsInCycle = {
    2, 5, 7, 10, 13, 16, 18, 21, 24, 26, 29,
  };

  static bool _isLeapYearInCycle(int yearInCycle) =>
      _leapYearsInCycle.contains(yearInCycle);

  /// Odd months have 30 days, even months 29; Dhu al-Hijjah gets a 30th day in
  /// a leap year.
  static int _monthLength(int monthNumber, int yearInCycle) {
    if (monthNumber.isOdd) return 30;
    if (monthNumber == 12 && _isLeapYearInCycle(yearInCycle)) return 30;
    return 29;
  }

  /// Gregorian calendar date to Julian Day Number.
  static int _gregorianToJdn(int year, int month, int day) {
    final a = ((14 - month) / 12).floor();
    final y = year + 4800 - a;
    final m = month + 12 * a - 3;

    return day +
        ((153 * m + 2) / 5).floor() +
        365 * y +
        (y / 4).floor() -
        (y / 100).floor() +
        (y / 400).floor() -
        32045;
  }

  static DateTime _jdnToGregorian(int jdn) {
    final a = jdn + 32044;
    final b = ((4 * a + 3) / 146097).floor();
    final c = a - ((146097 * b) / 4).floor();
    final d = ((4 * c + 3) / 1461).floor();
    final e = c - ((1461 * d) / 4).floor();
    final m = ((5 * e + 2) / 153).floor();

    final day = e - ((153 * m + 2) / 5).floor() + 1;
    final month = m + 3 - 12 * (m / 10).floor();
    final year = 100 * b + d - 4800 + (m / 10).floor();

    return DateTime(year, month, day);
  }
}
