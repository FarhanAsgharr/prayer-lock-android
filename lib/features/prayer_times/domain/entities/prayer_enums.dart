/// Domain enumerations for prayer scheduling.
///
/// The wire values must match the backend's PostgreSQL enum labels exactly.
/// A mismatch here surfaces as a deserialisation failure at runtime rather
/// than a compile error, so the parity tests in
/// test/unit/prayer_enums_test.dart pin every value.
library;

enum PrayerName {
  fajr('fajr'),
  dhuhr('dhuhr'),
  asr('asr'),
  maghrib('maghrib'),
  isha('isha');

  const PrayerName(this.wireValue);
  final String wireValue;

  static PrayerName fromWire(String value) => PrayerName.values.firstWhere(
        (prayer) => prayer.wireValue == value,
        orElse: () => throw ArgumentError('Unknown prayer name: $value'),
      );

  String get displayName => switch (this) {
        PrayerName.fajr => 'Fajr',
        PrayerName.dhuhr => 'Dhuhr',
        PrayerName.asr => 'Asr',
        PrayerName.maghrib => 'Maghrib',
        PrayerName.isha => 'Isha',
      };
}

enum PrayerStatus {
  pending('pending'),
  active('active'),
  completed('completed'),
  late('late'),
  missed('missed'),
  excused('excused');

  const PrayerStatus(this.wireValue);
  final String wireValue;

  static PrayerStatus fromWire(String value) => PrayerStatus.values.firstWhere(
        (status) => status.wireValue == value,
        orElse: () => throw ArgumentError('Unknown prayer status: $value'),
      );

  /// Whether this status means the obligation was discharged, on time or not.
  bool get isFulfilled =>
      this == PrayerStatus.completed ||
      this == PrayerStatus.late ||
      this == PrayerStatus.excused;
}

/// School of jurisprudence, as it affects prayer-time calculation.
///
/// Controls the Asr shadow ratio, and — for Ja'fari (Shia) — the Maghrib
/// definition, which is the disappearance of the sun's redness (~4 degrees of
/// depression) rather than sunset itself. [maghribAngle] is null for schools
/// that use plain sunset.
///
/// Wire values must match the backend's `madhab` PostgreSQL enum exactly.
enum Madhab {
  shafi('shafi', 1, null),
  hanafi('hanafi', 2, null),
  ahleHadith('ahle_hadith', 1, null),
  jafari('jafari', 1, 4.0);

  const Madhab(this.wireValue, this.shadowFactor, this.maghribAngle);

  final String wireValue;
  final int shadowFactor;

  /// Sun-depression angle at which Maghrib begins, or null to use sunset.
  final double? maghribAngle;

  static Madhab fromWire(String value) => Madhab.values.firstWhere(
        (madhab) => madhab.wireValue == value,
        orElse: () => throw ArgumentError('Unknown madhab: $value'),
      );

  String get displayName => switch (this) {
        Madhab.shafi => "Shafi'i, Maliki, Hanbali",
        Madhab.hanafi => 'Hanafi',
        Madhab.ahleHadith => 'Ahl-e-Hadith',
        Madhab.jafari => "Ja'fari (Shia)",
      };

  /// Short line explaining what this school changes, for the settings UI.
  String get description => switch (this) {
        Madhab.shafi =>
          'Asr begins when a shadow equals an object’s length',
        Madhab.hanafi =>
          'Asr begins when a shadow is twice an object’s length',
        Madhab.ahleHadith =>
          'Asr at the earlier time, following the majority position',
        Madhab.jafari =>
          'Earlier Asr, and Maghrib after the sun’s redness fades',
      };
}

/// Fajr/Isha solar-depression conventions used by major authorities.
enum CalculationMethod {
  muslimWorldLeague('muslim_world_league', 'Muslim World League'),
  egyptian('egyptian', 'Egyptian General Authority'),
  karachi('karachi', 'University of Islamic Sciences, Karachi'),
  ummAlQura('umm_al_qura', 'Umm al-Qura, Makkah'),
  dubai('dubai', 'Dubai'),
  qatar('qatar', 'Qatar'),
  kuwait('kuwait', 'Kuwait'),
  moonsightingCommittee('moonsighting_committee', 'Moonsighting Committee'),
  singapore('singapore', 'Singapore'),
  turkey('turkey', 'Diyanet, Turkey'),
  tehran('tehran', 'Institute of Geophysics, Tehran'),
  northAmerica('north_america', 'ISNA, North America');

  const CalculationMethod(this.wireValue, this.displayName);
  final String wireValue;
  final String displayName;

  static CalculationMethod fromWire(String value) =>
      CalculationMethod.values.firstWhere(
        (method) => method.wireValue == value,
        orElse: () => throw ArgumentError('Unknown calculation method: $value'),
      );
}

/// How to derive Fajr/Isha where the sun never reaches the required angle.
enum HighLatitudeRule {
  middleOfTheNight('middle_of_the_night', 'Middle of the night'),
  seventhOfTheNight('seventh_of_the_night', 'One seventh of the night'),
  twilightAngle('twilight_angle', 'Twilight angle');

  const HighLatitudeRule(this.wireValue, this.displayName);
  final String wireValue;
  final String displayName;

  static HighLatitudeRule fromWire(String value) =>
      HighLatitudeRule.values.firstWhere(
        (rule) => rule.wireValue == value,
        orElse: () => throw ArgumentError('Unknown high latitude rule: $value'),
      );
}

enum VerificationStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected'),
  error('error');

  const VerificationStatus(this.wireValue);
  final String wireValue;

  static VerificationStatus fromWire(String value) =>
      VerificationStatus.values.firstWhere(
        (status) => status.wireValue == value,
        orElse: () => throw ArgumentError('Unknown verification status: $value'),
      );
}
