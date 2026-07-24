/// User preferences governing calculation, notifications and enforcement.
///
/// Persisted locally as the source of truth: the app must be fully
/// configurable offline, and settings changes must take effect immediately
/// without waiting for a server round trip.
library;

import 'package:flutter/foundation.dart';

import '../../../../core/config/locale_config.dart';
import '../../../jumuah/domain/entities/jumuah_settings.dart';
import '../../../prayer_times/domain/entities/prayer_enums.dart';
import '../../../sections/domain/entities/islamic_section.dart';
import '../../../sections/domain/entities/prayer_grouping.dart';
import '../../../sections/domain/strategies/islamic_section_strategy.dart';

/// Warning ladder before each prayer: wrap up, get ready, apps about to lock.
///
/// Thirty minutes is the outermost rung offered, for users who want notice
/// before they commit to something they cannot leave.
const List<int> kDefaultReminderOffsets = [15, 10, 5];

/// Lead times the reminder picker offers.
const List<int> kReminderOffsetChoices = [0, 5, 10, 15, 20, 30, 45, 60];

@immutable
class PrayerLocation {
  const PrayerLocation({
    required this.latitude,
    required this.longitude,
    required this.timezone,
    this.label,
    this.isAutoDetected = true,
  });

  final double latitude;
  final double longitude;

  /// IANA timezone identifier, e.g. "Asia/Riyadh".
  final String timezone;

  final String? label;
  final bool isAutoDetected;

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'timezone': timezone,
        'label': label,
        'isAutoDetected': isAutoDetected,
      };

  factory PrayerLocation.fromJson(Map<String, dynamic> json) => PrayerLocation(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        timezone: json['timezone'] as String,
        label: json['label'] as String?,
        isAutoDetected: json['isAutoDetected'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      other is PrayerLocation &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.timezone == timezone;

  @override
  int get hashCode => Object.hash(latitude, longitude, timezone);
}

@immutable
class AppSettings {
  const AppSettings({
    this.location,
    this.section = SectionIdentity.fallback,
    this.calculationMethod = CalculationMethod.muslimWorldLeague,
    this.madhabOverride,
    this.prayerGroupingOverride,
    this.combinedVerification = true,
    this.highLatitudeRule = HighLatitudeRule.middleOfTheNight,
    this.adjustments = const {},
    this.reminderOffsetsMinutes = kDefaultReminderOffsets,
    this.adhanEnabled = true,
    this.blockingEnabled = true,
    this.lockGracePeriodMinutes = 5,
    this.morningProtectionEnabled = true,
    this.requireAiVerification = true,
    this.maxEmergencyUnlocksPerDay = 1,
    this.blockedPackages = const <String>{},
    this.onboardingComplete = false,
    this.unlockPolicy = UnlockPolicy.onVerification,
    this.blockUntilQazaCompleted = false,
    this.preferRemotePrayerTimes = true,
    this.notifyOnWindowEnd = true,
    this.language = AppLanguage.system,
    JumuahSettings? jumuah,
    this.hijriAdjustmentDays = 0,
    this.dhikrRemindersEnabled = false,
    this.quranRemindersEnabled = false,
  }) : jumuah = jumuah ?? const JumuahSettings();

  final PrayerLocation? location;

  /// The user's Islamic section, as they identify it.
  ///
  /// Supplies defaults for the settings below. It never overrides a choice the
  /// user has made — see [madhab] and [prayerGrouping].
  final SectionIdentity section;

  final CalculationMethod calculationMethod;

  /// Set only when the user has explicitly chosen an Asr convention that
  /// differs from what their section suggests.
  ///
  /// Nullable rather than always-populated so [madhab] cannot silently disagree
  /// with [section]. Selecting a section clears this; changing the Asr setting
  /// sets it. The alternative — two independent fields — lets the settings
  /// screen display one value while the calculator uses another.
  final Madhab? madhabOverride;

  /// Set only when the user has explicitly chosen a grouping. Same reasoning
  /// as [madhabOverride]: this is what makes "Shia sections suggest combining,
  /// and the user can still turn it off" expressible without the suggestion
  /// re-applying every time settings are saved.
  final PrayerGrouping? prayerGroupingOverride;

  /// Whether one verification discharges a whole combined slot.
  ///
  /// When false, each prayer in a combined pair is verified separately even
  /// though they share a window — some users combine the timing but want to
  /// confirm each prayer.
  final bool combinedVerification;

  final HighLatitudeRule highLatitudeRule;

  /// Per-prayer manual corrections in minutes, matching local mosque practice.
  final Map<PrayerName, int> adjustments;

  /// Minutes before each prayer at which to warn, largest first.
  ///
  /// A ladder rather than one reminder because the useful warnings are not
  /// equivalent: fifteen minutes is "start wrapping up", five is "apps are
  /// about to lock". Empty disables pre-prayer reminders entirely.
  final List<int> reminderOffsetsMinutes;

  final bool adhanEnabled;

  final bool blockingEnabled;

  /// Delay between the adhan and the lock engaging, so a user mid-conversation
  /// is not cut off without warning.
  final int lockGracePeriodMinutes;

  final bool morningProtectionEnabled;
  final bool requireAiVerification;
  final int maxEmergencyUnlocksPerDay;

  final Set<String> blockedPackages;

  final bool onboardingComplete;

  /// When apps are released after a prayer begins. See [UnlockPolicy].
  final UnlockPolicy unlockPolicy;

  /// Whether a prayer whose window closed unfulfilled keeps apps blocked until
  /// its qaza is made.
  ///
  /// Off by default and deliberately so: a missed Fajr under dynamic durations
  /// would otherwise block apps from sunrise to the following dawn. That is a
  /// legitimate thing to want, but not something to impose on someone who has
  /// only ever agreed to "block during prayer".
  final bool blockUntilQazaCompleted;

  /// Whether to fetch prayer times from the configured remote service when the
  /// network allows, rather than always computing them on-device.
  ///
  /// Both paths produce a complete schedule; this only decides which is
  /// authoritative. Turning it off makes the app fully self-contained.
  final bool preferRemotePrayerTimes;

  /// Whether to notify as a prayer window is about to close and when it does.
  final bool notifyOnWindowEnd;

  /// The language to render in, or [AppLanguage.system] to follow the device.
  final AppLanguage language;

  /// Friday Jumu'ah configuration: whether it replaces Dhuhr, where the user
  /// prays, and every mosque they have.
  final JumuahSettings jumuah;

  /// Days to shift the computed Hijri date by, from -2 to +2.
  ///
  /// The tabular calendar the app computes can differ from a local moon
  /// sighting by a day or so. Rather than pretend otherwise, the user can
  /// align it with whatever their community announced. Purely cosmetic — it
  /// never moves a prayer time, which is astronomical and exact.
  final int hijriAdjustmentDays;

  /// Whether to offer the tasbih after a completed prayer.
  final bool dhikrRemindersEnabled;

  /// Whether to offer a short Quran reading after a completed prayer.
  final bool quranRemindersEnabled;

  /// Whether enough is configured to compute a schedule.
  bool get isReady => location != null;

  /// The defaults the current section suggests.
  SectionDefaults get sectionDefaults =>
      IslamicSectionRegistry.instance.defaultsFor(section.section);

  /// The Asr convention in force: the user's explicit choice, or the section's.
  ///
  /// Derived rather than stored, so the value the calculator uses and the value
  /// the settings screen shows cannot drift apart.
  Madhab get madhab => madhabOverride ?? sectionDefaults.madhab;

  /// Which prayers are combined: the user's explicit choice, or the section's
  /// suggestion.
  PrayerGrouping get prayerGrouping =>
      prayerGroupingOverride ?? sectionDefaults.prayerGrouping;

  /// Whether the user has overridden what their section suggests.
  ///
  /// Surfaced so the settings screen can offer "reset to <section> defaults"
  /// only when there is something to reset.
  bool get hasSectionOverrides =>
      madhabOverride != null || prayerGroupingOverride != null;

  /// Whether a combined pair is discharged by a single verification.
  bool get usesCombinedVerification =>
      combinedVerification && prayerGrouping.combinesAnything;

  /// Reminder offsets, sanitised: positive, unique, descending.
  ///
  /// Done here rather than at every call site because a zero or negative offset
  /// would schedule a "reminder" at or after the adhan itself, and duplicates
  /// would stack two identical notifications on the same instant.
  List<int> get effectiveReminderOffsets {
    final cleaned = reminderOffsetsMinutes.where((m) => m > 0).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    return List.unmodifiable(cleaned);
  }

  /// The outermost rung of the reminder ladder, or 0 when reminders are off.
  ///
  /// Derived rather than stored. Holding it as its own field let the two
  /// disagree — a settings screen could write "30 minutes before" while the
  /// ladder that actually drives scheduling stayed at 15, and the setting would
  /// silently do nothing.
  int get reminderMinutesBefore {
    final offsets = effectiveReminderOffsets;
    return offsets.isEmpty ? 0 : offsets.first;
  }

  /// The ladder for a chosen outermost lead time.
  ///
  /// Zero disables reminders entirely. Otherwise the user's choice becomes the
  /// outermost rung and the two short rungs that matter once blocking is
  /// imminent are added beneath it.
  static List<int> reminderLadderFor(int leadMinutes) {
    if (leadMinutes <= 0) return const [];
    // 30 is included so a lead time above it still produces the "half an hour
    // out" warning rather than jumping straight to ten minutes.
    return <int>{leadMinutes, 30, 15, 10, 5}
        .where((m) => m > 0 && m <= leadMinutes)
        .toList()
      ..sort((a, b) => b.compareTo(a));
  }

  AppSettings copyWith({
    PrayerLocation? location,
    SectionIdentity? section,
    CalculationMethod? calculationMethod,
    Madhab? madhabOverride,
    PrayerGrouping? prayerGroupingOverride,
    bool? combinedVerification,
    HighLatitudeRule? highLatitudeRule,
    Map<PrayerName, int>? adjustments,
    List<int>? reminderOffsetsMinutes,
    bool? adhanEnabled,
    bool? blockingEnabled,
    int? lockGracePeriodMinutes,
    bool? morningProtectionEnabled,
    bool? requireAiVerification,
    int? maxEmergencyUnlocksPerDay,
    Set<String>? blockedPackages,
    bool? onboardingComplete,
    UnlockPolicy? unlockPolicy,
    bool? blockUntilQazaCompleted,
    bool? preferRemotePrayerTimes,
    bool? notifyOnWindowEnd,
    AppLanguage? language,
    JumuahSettings? jumuah,
    int? hijriAdjustmentDays,
    bool? dhikrRemindersEnabled,
    bool? quranRemindersEnabled,
  }) =>
      AppSettings(
        location: location ?? this.location,
        section: section ?? this.section,
        calculationMethod: calculationMethod ?? this.calculationMethod,
        madhabOverride: madhabOverride ?? this.madhabOverride,
        prayerGroupingOverride:
            prayerGroupingOverride ?? this.prayerGroupingOverride,
        combinedVerification: combinedVerification ?? this.combinedVerification,
        highLatitudeRule: highLatitudeRule ?? this.highLatitudeRule,
        adjustments: adjustments ?? this.adjustments,
        reminderOffsetsMinutes:
            reminderOffsetsMinutes ?? this.reminderOffsetsMinutes,
        adhanEnabled: adhanEnabled ?? this.adhanEnabled,
        blockingEnabled: blockingEnabled ?? this.blockingEnabled,
        lockGracePeriodMinutes:
            lockGracePeriodMinutes ?? this.lockGracePeriodMinutes,
        morningProtectionEnabled:
            morningProtectionEnabled ?? this.morningProtectionEnabled,
        requireAiVerification:
            requireAiVerification ?? this.requireAiVerification,
        maxEmergencyUnlocksPerDay:
            maxEmergencyUnlocksPerDay ?? this.maxEmergencyUnlocksPerDay,
        blockedPackages: blockedPackages ?? this.blockedPackages,
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
        unlockPolicy: unlockPolicy ?? this.unlockPolicy,
        blockUntilQazaCompleted:
            blockUntilQazaCompleted ?? this.blockUntilQazaCompleted,
        preferRemotePrayerTimes:
            preferRemotePrayerTimes ?? this.preferRemotePrayerTimes,
        notifyOnWindowEnd: notifyOnWindowEnd ?? this.notifyOnWindowEnd,
        language: language ?? this.language,
        jumuah: jumuah ?? this.jumuah,
        hijriAdjustmentDays: hijriAdjustmentDays ?? this.hijriAdjustmentDays,
        dhikrRemindersEnabled:
            dhikrRemindersEnabled ?? this.dhikrRemindersEnabled,
        quranRemindersEnabled:
            quranRemindersEnabled ?? this.quranRemindersEnabled,
      );

  /// Adopt [next] and take its suggested defaults.
  ///
  /// Clears both overrides, which `copyWith` cannot express — passing null
  /// there means "keep the existing value", so there would be no way to say
  /// "go back to what the section suggests". Selecting a section is precisely
  /// the moment the user has asked for its defaults, so this is the one place
  /// the suggestions are allowed to move settings the user may have changed.
  ///
  /// The calculation method moves too, because a section that implies a Maghrib
  /// definition implies a method that encodes it. The settings screen tells the
  /// user what changed, and every value remains editable afterwards.
  AppSettings withSection(SectionIdentity next) {
    final defaults = IslamicSectionRegistry.instance.defaultsFor(next.section);

    return AppSettings(
      location: location,
      section: next,
      calculationMethod: defaults.calculationMethod,
      madhabOverride: null,
      prayerGroupingOverride: null,
      combinedVerification: combinedVerification,
      highLatitudeRule: highLatitudeRule,
      adjustments: adjustments,
      reminderOffsetsMinutes: reminderOffsetsMinutes,
      adhanEnabled: adhanEnabled,
      blockingEnabled: blockingEnabled,
      lockGracePeriodMinutes: lockGracePeriodMinutes,
      morningProtectionEnabled: morningProtectionEnabled,
      requireAiVerification: requireAiVerification,
      maxEmergencyUnlocksPerDay: maxEmergencyUnlocksPerDay,
      blockedPackages: blockedPackages,
      onboardingComplete: onboardingComplete,
      unlockPolicy: unlockPolicy,
      blockUntilQazaCompleted: blockUntilQazaCompleted,
      preferRemotePrayerTimes: preferRemotePrayerTimes,
      notifyOnWindowEnd: notifyOnWindowEnd,
      language: language,
      jumuah: jumuah,
      hijriAdjustmentDays: hijriAdjustmentDays,
      dhikrRemindersEnabled: dhikrRemindersEnabled,
      quranRemindersEnabled: quranRemindersEnabled,
    );
  }

  /// Discard every override and return to the section's suggestions.
  AppSettings resetToSectionDefaults() => withSection(section);

  Map<String, dynamic> toJson() => {
        'location': location?.toJson(),
        'section': section.toJson(),
        'calculationMethod': calculationMethod.wireValue,
        'madhabOverride': madhabOverride?.wireValue,
        'prayerGroupingOverride': prayerGroupingOverride?.wireValue,
        'combinedVerification': combinedVerification,
        // Written for compatibility: a build that predates sections reads this
        // and gets the effective Asr convention rather than a missing key.
        'madhab': madhab.wireValue,
        'highLatitudeRule': highLatitudeRule.wireValue,
        'adjustments': adjustments.map((k, v) => MapEntry(k.wireValue, v)),
        // Written for compatibility: an install rolled back to a version that
        // predates the ladder still reads a sensible single lead time.
        'reminderMinutesBefore': reminderMinutesBefore,
        'reminderOffsetsMinutes': reminderOffsetsMinutes,
        'adhanEnabled': adhanEnabled,
        'blockingEnabled': blockingEnabled,
        'lockGracePeriodMinutes': lockGracePeriodMinutes,
        'morningProtectionEnabled': morningProtectionEnabled,
        'requireAiVerification': requireAiVerification,
        'maxEmergencyUnlocksPerDay': maxEmergencyUnlocksPerDay,
        'blockedPackages': blockedPackages.toList(),
        'onboardingComplete': onboardingComplete,
        'unlockPolicy': unlockPolicy.wireValue,
        'blockUntilQazaCompleted': blockUntilQazaCompleted,
        'preferRemotePrayerTimes': preferRemotePrayerTimes,
        'notifyOnWindowEnd': notifyOnWindowEnd,
        'language': language.wireValue,
        'jumuah': jumuah.toJson(),
        'hijriAdjustmentDays': hijriAdjustmentDays,
        'dhikrRemindersEnabled': dhikrRemindersEnabled,
        'quranRemindersEnabled': quranRemindersEnabled,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final rawAdjustments =
        (json['adjustments'] as Map?)?.cast<String, dynamic>() ?? const {};

    return AppSettings(
      location: json['location'] == null
          ? null
          : PrayerLocation.fromJson(
              (json['location'] as Map).cast<String, dynamic>()),
      calculationMethod: CalculationMethod.fromWire(
        json['calculationMethod'] as String? ?? 'muslim_world_league',
      ),
      section: _readSection(json),
      madhabOverride: _readMadhabOverride(json),
      prayerGroupingOverride: _readGroupingOverride(json),
      combinedVerification: json['combinedVerification'] as bool? ?? true,
      highLatitudeRule: HighLatitudeRule.fromWire(
        json['highLatitudeRule'] as String? ?? 'middle_of_the_night',
      ),
      adjustments: {
        for (final entry in rawAdjustments.entries)
          PrayerName.fromWire(entry.key): (entry.value as num).toInt(),
      },
      // Installs that predate the ladder carry only the single offset. Seeding
      // from it rather than from the default keeps a user who deliberately set
      // "30 minutes before" from silently being moved to 15.
      reminderOffsetsMinutes: (json['reminderOffsetsMinutes'] as List?)
              ?.map((value) => (value as num).toInt())
              .toList() ??
          reminderLadderFor(
            (json['reminderMinutesBefore'] as num?)?.toInt() ?? 15,
          ),
      adhanEnabled: json['adhanEnabled'] as bool? ?? true,
      blockingEnabled: json['blockingEnabled'] as bool? ?? true,
      lockGracePeriodMinutes:
          (json['lockGracePeriodMinutes'] as num?)?.toInt() ?? 5,
      morningProtectionEnabled:
          json['morningProtectionEnabled'] as bool? ?? true,
      requireAiVerification: json['requireAiVerification'] as bool? ?? true,
      maxEmergencyUnlocksPerDay:
          (json['maxEmergencyUnlocksPerDay'] as num?)?.toInt() ?? 1,
      blockedPackages:
          ((json['blockedPackages'] as List?) ?? const []).cast<String>().toSet(),
      onboardingComplete: json['onboardingComplete'] as bool? ?? false,
      unlockPolicy: UnlockPolicy.fromWire(
        json['unlockPolicy'] as String? ?? 'on_verification',
      ),
      blockUntilQazaCompleted:
          json['blockUntilQazaCompleted'] as bool? ?? false,
      preferRemotePrayerTimes:
          json['preferRemotePrayerTimes'] as bool? ?? true,
      notifyOnWindowEnd: json['notifyOnWindowEnd'] as bool? ?? true,
      language: AppLanguage.fromWire(json['language'] as String? ?? 'system'),
      jumuah: json['jumuah'] is Map
          ? JumuahSettings.fromJson(
              (json['jumuah'] as Map).cast<String, dynamic>())
          : null,
      // Clamped on read: a corrupted or hand-edited value must not shift the
      // calendar by a month.
      hijriAdjustmentDays:
          ((json['hijriAdjustmentDays'] as num?)?.toInt() ?? 0).clamp(-2, 2),
      dhikrRemindersEnabled: json['dhikrRemindersEnabled'] as bool? ?? false,
      quranRemindersEnabled: json['quranRemindersEnabled'] as bool? ?? false,
    );
  }

  /// The stored section, or one inferred from a pre-sections install.
  ///
  /// An upgrading user has a madhab but no section. Their madhab is a
  /// calculation setting, not an identity — a Shafi'i setting says nothing
  /// about whether someone identifies as Shafi'i, Maliki, Sufi or Salafi — so
  /// the only honest inference is the one case where the mapping is
  /// unambiguous in both directions:
  ///
  ///   hanafi      -> Hanafi        (only the Hanafi school uses shadow 2)
  ///   ahle_hadith -> Ahl-e-Hadith  (the value was added for that community)
  ///   jafari      -> Twelver       (the value was added for that community)
  ///   shafi       -> unresolved
  ///
  /// `shafi` covers Shafi'i, Maliki and Hanbali equally and was also the
  /// default nobody changed, so it is left as [IslamicSection.other] with the
  /// madhab preserved as an explicit override. The user is asked to pick a
  /// section, and until they do, nothing about their prayer times changes.
  static SectionIdentity _readSection(Map<String, dynamic> json) {
    final stored = json['section'];
    if (stored is Map) {
      return SectionIdentity.fromJson(stored.cast<String, dynamic>());
    }

    final legacy = json['madhab'] as String?;
    return switch (legacy) {
      'hanafi' => const SectionIdentity.of(IslamicSection.hanafi),
      'ahle_hadith' => const SectionIdentity.of(IslamicSection.ahleHadith),
      'jafari' => const SectionIdentity.of(IslamicSection.twelver),
      // Either 'shafi' or a fresh install. Both land on the fallback, whose
      // suggested madhab must equal what the old default computed — see the
      // migration test.
      _ => SectionIdentity.fallback,
    };
  }

  /// The stored override, or one reconstructed so an upgrade changes nothing.
  ///
  /// The invariant that matters: **an upgrading user's prayer times must not
  /// move.** If the legacy madhab differs from what their inferred section
  /// suggests, it is preserved as an explicit override rather than discarded.
  static Madhab? _readMadhabOverride(Map<String, dynamic> json) {
    final explicit = json['madhabOverride'] as String?;
    if (explicit != null) return Madhab.fromWire(explicit);

    // Already migrated: a stored section with no override means the user is on
    // their section's defaults deliberately.
    if (json['section'] is Map) return null;

    final legacy = json['madhab'] as String?;
    if (legacy == null) return null;

    final madhab = Madhab.fromWire(legacy);
    final inferred = IslamicSectionRegistry.instance
        .defaultsFor(_readSection(json).section)
        .madhab;

    return madhab == inferred ? null : madhab;
  }

  /// The stored grouping override, or one pinned so an upgrade changes nothing.
  ///
  /// The same invariant as [_readMadhabOverride], applied to combining. A user
  /// migrating from a build that predates sections has been praying five
  /// separate prayers; inferring a section for them must not also start
  /// combining their prayers. A Ja'fari user in particular would be inferred as
  /// Twelver, whose suggestion is to combine both pairs — turning that on
  /// unannounced would change how their phone locks and how many cards they
  /// see, on an app update they did not ask for.
  ///
  /// So the pre-existing behaviour is pinned as an explicit override. The
  /// prayer mode screen then offers combining as something to opt into.
  static PrayerGrouping? _readGroupingOverride(Map<String, dynamic> json) {
    final explicit = json['prayerGroupingOverride'] as String?;
    if (explicit != null) return PrayerGrouping.fromWire(explicit);

    // Already migrated: no override means the user is on their section's
    // suggestion deliberately.
    if (json['section'] is Map) return null;

    // A pre-sections install. Empty JSON is a fresh install, which has no
    // behaviour to preserve.
    if (json.isEmpty) return null;

    return PrayerGrouping.none;
  }
}
