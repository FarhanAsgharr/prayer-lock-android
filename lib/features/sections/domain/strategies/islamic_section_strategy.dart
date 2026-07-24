/// Per-section defaults, resolved through a strategy rather than a conditional.
///
/// The rule this design exists to enforce: **nothing in the codebase branches on
/// a specific section**. There is no `if (isShia)`, no `section == twelver`
/// outside this file. A section's behaviour is entirely described by the
/// [SectionDefaults] its strategy returns, so supporting a new community is a
/// matter of registering one more strategy — not auditing the app for places
/// that assumed there were only two kinds of Muslim.
///
/// That matters beyond tidiness. A conditional scattered across the lock logic,
/// the notification scheduler and the dashboard is how an app ends up
/// *insisting* that someone's community prays a particular way. Confining it to
/// a lookup keeps every default overridable and every assumption visible in one
/// place.
///
/// All defaults here are starting points, chosen to match the most common
/// practice within each section. They are not rulings, they are not enforced,
/// and the settings screen tells the user so.
library;

import '../../../prayer_times/domain/entities/prayer_enums.dart';
import '../entities/islamic_section.dart';
import '../entities/prayer_grouping.dart';

/// Supplies the defaults for one section.
abstract interface class IslamicSectionStrategy {
  /// The section this strategy answers for.
  IslamicSection get section;

  /// Starting values applied when the user selects this section.
  SectionDefaults get defaults;
}

/// A strategy defined entirely by its constant defaults.
///
/// Every section registered today is of this shape. The interface stays open so
/// a section needing genuinely computed defaults — say, one whose convention
/// varies by region — can be added without changing anything that consumes it.
class _ConstantSectionStrategy implements IslamicSectionStrategy {
  const _ConstantSectionStrategy(this.section, this.defaults);

  @override
  final IslamicSection section;

  @override
  final SectionDefaults defaults;
}

/// Resolves a section to its defaults.
///
/// A registry rather than a switch so a host application, a regional build, or
/// a test can substitute or extend the set without editing this file.
class IslamicSectionRegistry {
  IslamicSectionRegistry(Iterable<IslamicSectionStrategy> strategies)
      : _strategies = {
          for (final strategy in strategies) strategy.section: strategy,
        };

  final Map<IslamicSection, IslamicSectionStrategy> _strategies;

  /// The registry the app runs on.
  static final IslamicSectionRegistry instance =
      IslamicSectionRegistry(_builtInStrategies);

  /// Defaults for [section].
  ///
  /// A section with no registered strategy falls back to the neutral defaults
  /// rather than throwing: a missing registration must not make the app
  /// unusable for whoever happened to select it.
  SectionDefaults defaultsFor(IslamicSection section) =>
      _strategies[section]?.defaults ?? _neutralDefaults;

  bool hasStrategyFor(IslamicSection section) =>
      _strategies.containsKey(section);

  /// Register or replace a strategy. Returns a new registry; the instance is
  /// immutable so a test cannot leak a substitution into another test.
  IslamicSectionRegistry withStrategy(IslamicSectionStrategy strategy) =>
      IslamicSectionRegistry([..._strategies.values, strategy]);
}

/// What a user gets when their section says nothing in particular.
///
/// Also what [IslamicSection.other] gets: someone who named their own section
/// has told us their identity, not their Asr convention, so assuming one would
/// be inventing information.
const SectionDefaults _neutralDefaults = SectionDefaults(
  madhab: Madhab.shafi,
  calculationMethod: CalculationMethod.muslimWorldLeague,
  prayerGrouping: PrayerGrouping.none,
  rationale: 'Standard settings. Adjust anything below to match your practice.',
);

/// One entry per section. Adding a community means adding a line here.
const List<IslamicSectionStrategy> _builtInStrategies = [
  // --- Sunni traditions --------------------------------------------------
  //
  // These are schools of jurisprudence, so their Asr convention is a genuine
  // consequence of the selection rather than an assumption about the user.
  _ConstantSectionStrategy(
    IslamicSection.hanafi,
    SectionDefaults(
      // The Hanafi school begins Asr when a shadow is twice an object's length.
      madhab: Madhab.hanafi,
      calculationMethod: CalculationMethod.karachi,
      prayerGrouping: PrayerGrouping.none,
      rationale: 'Asr begins at twice an object’s shadow, following the '
          'Hanafi school.',
    ),
  ),
  _ConstantSectionStrategy(
    IslamicSection.shafii,
    SectionDefaults(
      madhab: Madhab.shafi,
      calculationMethod: CalculationMethod.muslimWorldLeague,
      prayerGrouping: PrayerGrouping.none,
      rationale: 'Asr begins at one shadow length, following the Shafi’i '
          'school.',
    ),
  ),
  _ConstantSectionStrategy(
    IslamicSection.maliki,
    SectionDefaults(
      madhab: Madhab.shafi,
      calculationMethod: CalculationMethod.muslimWorldLeague,
      prayerGrouping: PrayerGrouping.none,
      rationale: 'Asr begins at one shadow length, following the Maliki school.',
    ),
  ),
  _ConstantSectionStrategy(
    IslamicSection.hanbali,
    SectionDefaults(
      madhab: Madhab.shafi,
      calculationMethod: CalculationMethod.muslimWorldLeague,
      prayerGrouping: PrayerGrouping.none,
      rationale:
          'Asr begins at one shadow length, following the Hanbali school.',
    ),
  ),

  // --- Sunni communities -------------------------------------------------
  //
  // These are movements, not schools. Their adherents follow a school, and the
  // defaults below reflect the most common pairing — but the Asr setting stays
  // separately adjustable precisely because the pairing is a tendency, not a
  // rule.
  _ConstantSectionStrategy(
    IslamicSection.barelvi,
    SectionDefaults(
      // Predominantly Hanafi in fiqh across South Asia.
      madhab: Madhab.hanafi,
      calculationMethod: CalculationMethod.karachi,
      prayerGrouping: PrayerGrouping.none,
      rationale: 'Hanafi Asr timing and the Karachi convention, as commonly '
          'followed. Change either below if yours differs.',
    ),
  ),
  _ConstantSectionStrategy(
    IslamicSection.deobandi,
    SectionDefaults(
      madhab: Madhab.hanafi,
      calculationMethod: CalculationMethod.karachi,
      prayerGrouping: PrayerGrouping.none,
      rationale: 'Hanafi Asr timing and the Karachi convention, as commonly '
          'followed. Change either below if yours differs.',
    ),
  ),
  _ConstantSectionStrategy(
    IslamicSection.ahleHadith,
    SectionDefaults(
      madhab: Madhab.ahleHadith,
      calculationMethod: CalculationMethod.karachi,
      prayerGrouping: PrayerGrouping.none,
      rationale: 'Asr at the earlier time, following the majority position.',
    ),
  ),
  _ConstantSectionStrategy(
    IslamicSection.salafi,
    SectionDefaults(
      madhab: Madhab.shafi,
      calculationMethod: CalculationMethod.ummAlQura,
      prayerGrouping: PrayerGrouping.none,
      rationale: 'Asr at the earlier time, with the Umm al-Qura convention.',
    ),
  ),
  _ConstantSectionStrategy(
    IslamicSection.sufi,
    SectionDefaults(
      // Sufism is a spiritual orientation practised within all four Sunni
      // schools, so it implies no Asr convention at all. The neutral default
      // is used and the rationale says plainly that the user should set it.
      madhab: Madhab.shafi,
      calculationMethod: CalculationMethod.muslimWorldLeague,
      prayerGrouping: PrayerGrouping.none,
      rationale: 'Sufi practice spans all four schools, so no Asr timing is '
          'assumed. Set the Asr calculation below to match your school.',
    ),
  ),

  // --- Shia traditions ---------------------------------------------------
  _ConstantSectionStrategy(
    IslamicSection.twelver,
    SectionDefaults(
      // Ja'fari: Asr at one shadow length, and Maghrib delayed until the sun's
      // redness fades — roughly four degrees of depression rather than sunset.
      madhab: Madhab.jafari,
      calculationMethod: CalculationMethod.jafari,
      // Combining Dhuhr with Asr and Maghrib with Isha is ordinary practice.
      // Suggested, never imposed: the user can separate them below.
      prayerGrouping: PrayerGrouping.both,
      rationale: 'Ja’fari timings, with Maghrib after the sun’s redness fades. '
          'Dhuhr with Asr and Maghrib with Isha are combined by default.',
    ),
  ),
  _ConstantSectionStrategy(
    IslamicSection.ismaili,
    SectionDefaults(
      madhab: Madhab.jafari,
      calculationMethod: CalculationMethod.jafari,
      prayerGrouping: PrayerGrouping.both,
      rationale: 'Ja’fari timings, with Dhuhr and Asr, and Maghrib and Isha, '
          'combined by default.',
    ),
  ),
  _ConstantSectionStrategy(
    IslamicSection.zaydi,
    SectionDefaults(
      // Zaydi practice is closer to Sunni norms here: prayers are generally
      // kept separate and Maghrib is at sunset.
      madhab: Madhab.shafi,
      calculationMethod: CalculationMethod.muslimWorldLeague,
      prayerGrouping: PrayerGrouping.none,
      rationale: 'Five separate prayers with Maghrib at sunset, as commonly '
          'practised. Combine prayers below if you prefer.',
    ),
  ),

  // --- Other communities -------------------------------------------------
  _ConstantSectionStrategy(
    IslamicSection.ibadi,
    SectionDefaults(
      madhab: Madhab.shafi,
      calculationMethod: CalculationMethod.muslimWorldLeague,
      prayerGrouping: PrayerGrouping.none,
      rationale: 'Five separate prayers with Asr at one shadow length.',
    ),
  ),

  // --- User-named --------------------------------------------------------
  _ConstantSectionStrategy(IslamicSection.other, _neutralDefaults),
];
