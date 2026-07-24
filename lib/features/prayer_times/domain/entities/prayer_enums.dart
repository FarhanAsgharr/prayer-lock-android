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

/// The stored, persistent outcome of a prayer.
///
/// This is *what happened*, recorded once and immutable thereafter. The
/// time-derived "what can the user do now" state is [PrayerPhase], computed
/// from the clock — the two are deliberately separate so a recorded outcome
/// never silently changes as time passes.
///
/// `active` and `late` are legacy values kept only so rows written by earlier
/// versions still deserialise; the current model never produces them.
enum PrayerStatus {
  pending('pending'),
  completed('completed'), // verified within the 30-minute on-time window
  qazaCompleted('qaza_completed'), // verified within the 1-hour qaza window
  missed('missed'), // both windows expired without verification
  excused('excused'),
  active('active'), // legacy
  late('late'); // legacy

  const PrayerStatus(this.wireValue);
  final String wireValue;

  static PrayerStatus fromWire(String value) => PrayerStatus.values.firstWhere(
        (status) => status.wireValue == value,
        orElse: () => throw ArgumentError('Unknown prayer status: $value'),
      );

  /// Whether this status means the obligation was discharged — on time, as
  /// qaza, or excused. A fulfilled prayer keeps the streak and releases the
  /// lock; a missed one does neither.
  bool get isFulfilled =>
      this == PrayerStatus.completed ||
      this == PrayerStatus.qazaCompleted ||
      this == PrayerStatus.late || // legacy fulfilled
      this == PrayerStatus.excused;
}

/// When apps are released after a prayer begins.
///
/// The two modes exist because users want opposite things from the same
/// feature. One group wants the lock to be a nudge that ends the moment they
/// have prayed; the other wants it to be a commitment they cannot talk
/// themselves out of. Silently picking one would make the app useless to half
/// its users, so it is an explicit choice.
enum UnlockPolicy {
  /// Mode A — release as soon as the prayer is verified.
  ///
  /// The default. Under dynamic durations a Dhuhr window runs to Asr, which can
  /// be three and a half hours; blocking for all of it by default would be a
  /// surprise severe enough that most users would simply uninstall.
  onVerification('on_verification', 'Unlock after verification'),

  /// Mode B — keep apps blocked for the whole computed window, even after the
  /// prayer is verified.
  fullDuration('full_duration', 'Unlock when the prayer window ends'),

  /// Whichever comes first: verification, or the window ending.
  ///
  /// Distinct from [onVerification] only in that it is explicit about the
  /// window also releasing the lock, which is the behaviour users assume when
  /// they read "duration" in the settings.
  earliestOf('earliest_of', 'Unlock at verification or window end');

  const UnlockPolicy(this.wireValue, this.displayName);

  final String wireValue;
  final String displayName;

  static UnlockPolicy fromWire(String value) => UnlockPolicy.values.firstWhere(
        (policy) => policy.wireValue == value,
        orElse: () => UnlockPolicy.onVerification,
      );

  /// Whether verifying the prayer lifts the lock.
  bool get releasesOnVerification => this != UnlockPolicy.fullDuration;

  String get description => switch (this) {
        UnlockPolicy.onVerification =>
          'Apps unlock the moment you confirm you have prayed.',
        UnlockPolicy.fullDuration =>
          'Apps stay locked for the full prayer window, even after you pray.',
        UnlockPolicy.earliestOf =>
          'Apps unlock when you pray, or when the window ends — whichever is first.',
      };
}

/// Where a day's prayer times came from.
///
/// Recorded per cached day so the UI can say "showing offline times" honestly,
/// and so a day computed on-device is replaced by an authoritative one when the
/// network returns rather than being trusted forever.
enum PrayerTimeSource {
  /// Fetched from a remote prayer-time service.
  remote('remote'),

  /// Computed on-device by the built-in astronomical calculator.
  device('device'),

  /// Read back from the local cache, original source unknown.
  cache('cache');

  const PrayerTimeSource(this.wireValue);

  final String wireValue;

  static PrayerTimeSource fromWire(String value) =>
      PrayerTimeSource.values.firstWhere(
        (source) => source.wireValue == value,
        orElse: () => PrayerTimeSource.device,
      );

  /// Whether a day from this source should be refreshed when connectivity
  /// allows. A device-computed day is correct but not authoritative.
  bool get shouldRefreshWhenOnline => this != PrayerTimeSource.remote;
}

/// The time-derived state of a prayer: what the user can do about it right now.
///
/// Computed from the clock against the prayer's dynamic window, so it advances
/// automatically as the window opens and closes. The dashboard badges and the
/// lock logic both read this.
enum PrayerPhase {
  /// Before the prayer has begun.
  upcoming,

  /// Inside the prayer's own window — verifying now counts as on time.
  verifyOnTime,

  /// The window has closed unfulfilled, but qaza can still be made today.
  qazaAvailable,

  /// Verified within the on-time window.
  verifiedOnTime,

  /// Verified within the qaza window.
  qazaCompleted,

  /// Both windows expired without verification — permanently missed.
  missed,

  /// Marked exempt (travel, illness, menstruation).
  excused;

  /// Whether the user can still submit a verification photo in this phase.
  bool get isVerifiable =>
      this == PrayerPhase.verifyOnTime || this == PrayerPhase.qazaAvailable;

  /// Whether apps should be locked for a prayer in this phase.
  ///
  /// True only while a prayer is owed and still verifiable. Once verified,
  /// missed or excused, nothing more can be done, so the lock lifts.
  bool get requiresLock => isVerifiable;
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
  northAmerica('north_america', 'ISNA, North America'),
  // Ja'fari (Shia Ithna-Ashari): distinct from Tehran, which is a different
  // authority with different angles despite both being used by Shia
  // communities. Offered as its own method so users are not made to choose
  // between two conventions neither of which is theirs.
  jafari('jafari', "Ja'fari (Shia Ithna-Ashari)");

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
