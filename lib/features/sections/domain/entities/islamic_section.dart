/// The user's Islamic section, as they identify it.
///
/// This is an *identity*, not a calculation parameter, and the distinction is
/// load-bearing. "Hanafi" is a school of jurisprudence and does determine the
/// Asr shadow ratio. "Sufi" is a spiritual orientation that cuts across all
/// four Sunni schools and determines nothing about prayer times. "Salafi",
/// "Barelvi" and "Deobandi" are movements whose adherents follow a school —
/// usually, but not always, a predictable one.
///
/// Treating those as if they were interchangeable would either compute wrong
/// prayer times or tell a user their identity implies a ruling it does not. So
/// a section supplies *defaults* — an Asr convention, a suggested calculation
/// method, a suggested prayer grouping — and every one of them stays
/// independently overridable. The app never tells anyone what their section
/// requires of them; it starts them somewhere sensible and gets out of the way.
///
/// Adding a section is a matter of adding a value here. Nothing branches on
/// specific sections anywhere in the codebase — see [IslamicSectionStrategy].
library;

import 'package:flutter/foundation.dart';

import '../../../prayer_times/domain/entities/prayer_enums.dart';
import 'prayer_grouping.dart';

/// How sections are grouped in the picker.
///
/// Presentation only. No behaviour keys off the family — a rule that applied to
/// "all Shia sections" would be exactly the hardcoding this design exists to
/// avoid.
enum SectionFamily {
  sunniTradition('Sunni traditions'),
  sunniCommunity('Sunni communities'),
  shiaTradition('Shia traditions'),
  otherCommunity('Other Muslim communities'),
  custom('Other');

  const SectionFamily(this.displayName);

  final String displayName;
}

/// A section the user can identify with.
///
/// Wire values are stable and must never be reused for a different meaning:
/// they are persisted locally and uploaded with the user's profile.
enum IslamicSection {
  // --- Sunni traditions (schools of jurisprudence) ----------------------
  hanafi('hanafi', 'Hanafi', SectionFamily.sunniTradition),
  shafii('shafii', "Shafi'i", SectionFamily.sunniTradition),
  maliki('maliki', 'Maliki', SectionFamily.sunniTradition),
  hanbali('hanbali', 'Hanbali', SectionFamily.sunniTradition),

  // --- Sunni communities and movements ----------------------------------
  barelvi('barelvi', 'Barelvi', SectionFamily.sunniCommunity),
  deobandi('deobandi', 'Deobandi', SectionFamily.sunniCommunity),
  ahleHadith('ahle_hadith', 'Ahl-e-Hadith', SectionFamily.sunniCommunity),
  salafi('salafi', 'Salafi', SectionFamily.sunniCommunity),
  sufi('sufi', 'Sufi', SectionFamily.sunniCommunity),

  // --- Shia traditions ---------------------------------------------------
  twelver('twelver', 'Twelver (Ithna Ashari)', SectionFamily.shiaTradition),
  ismaili('ismaili', 'Ismaili', SectionFamily.shiaTradition),
  zaydi('zaydi', 'Zaydi', SectionFamily.shiaTradition),

  // --- Other communities -------------------------------------------------
  ibadi('ibadi', 'Ibadi', SectionFamily.otherCommunity),

  // --- Anything else -----------------------------------------------------
  //
  // Not a catch-all for the obscure: a deliberate escape hatch so nobody is
  // forced to pick a label that misrepresents them. The free-text name they
  // enter is used everywhere their section is shown.
  other('other', 'Other', SectionFamily.custom);

  const IslamicSection(this.wireValue, this.defaultLabel, this.family);

  final String wireValue;

  /// The name shown when no custom label applies.
  final String defaultLabel;

  final SectionFamily family;

  static IslamicSection fromWire(String value) =>
      IslamicSection.values.firstWhere(
        (section) => section.wireValue == value,
        // An unknown value means a downgrade from a build that had more
        // sections. Falling back keeps the app usable rather than crashing on
        // a settings read; the user can re-pick.
        orElse: () => IslamicSection.other,
      );

  /// Whether this section carries a user-supplied name.
  bool get requiresCustomLabel => this == IslamicSection.other;

  /// Sections grouped for the picker, in display order.
  static Map<SectionFamily, List<IslamicSection>> get grouped {
    final result = <SectionFamily, List<IslamicSection>>{};
    for (final section in IslamicSection.values) {
      result.putIfAbsent(section.family, () => []).add(section);
    }
    return result;
  }
}

/// The user's section together with the name they gave it.
///
/// A value object rather than two loose fields, because a custom label without
/// [IslamicSection.other] is meaningless and [IslamicSection.other] without a
/// label leaves the UI with nothing to render. Keeping them together makes both
/// states unrepresentable.
@immutable
class SectionIdentity {
  const SectionIdentity._(this.section, this.customLabel);

  /// A standard section.
  const SectionIdentity.of(IslamicSection section)
      : section = section,
        customLabel = null;

  /// A user-named section.
  factory SectionIdentity.custom(String label) {
    final trimmed = label.trim();
    return SectionIdentity._(
      IslamicSection.other,
      trimmed.isEmpty ? null : trimmed,
    );
  }

  final IslamicSection section;

  /// Only ever set for [IslamicSection.other].
  final String? customLabel;

  /// The identity of someone who has not chosen one.
  ///
  /// Deliberately *not* a real section. Picking a popular school as the default
  /// would assert an identity on the user's behalf, and — because a section
  /// carries an Asr convention — would silently change prayer times for anyone
  /// who never opened the picker. [IslamicSection.other] with no label carries
  /// the neutral defaults, which are exactly the values the app used before
  /// sections existed, so nobody's schedule moves.
  ///
  /// Onboarding asks on its second page, so this is normally transient.
  static const SectionIdentity fallback =
      SectionIdentity.of(IslamicSection.other);

  /// Whether the user has actually chosen a section.
  bool get isChosen => !(section.requiresCustomLabel && customLabel == null);

  /// What to show the user. Never empty.
  String get displayName {
    final custom = customLabel;
    if (custom != null && custom.isNotEmpty) return custom;
    // An unnamed "Other" is the not-yet-chosen state, and labelling it "Other"
    // would read as a decision the user never made.
    if (section.requiresCustomLabel) return 'Not set';
    return section.defaultLabel;
  }

  /// True when the user chose "Other" but has not yet named their section.
  bool get needsLabel => section.requiresCustomLabel && customLabel == null;

  SectionIdentity withLabel(String label) => SectionIdentity.custom(label);

  Map<String, dynamic> toJson() => {
        'section': section.wireValue,
        'customLabel': customLabel,
      };

  factory SectionIdentity.fromJson(Map<String, dynamic> json) {
    final section = IslamicSection.fromWire(json['section'] as String? ?? '');
    final label = (json['customLabel'] as String?)?.trim();

    // A label attached to a standard section is dropped rather than shown: it
    // would override a name the user did not choose.
    if (!section.requiresCustomLabel) return SectionIdentity.of(section);

    return SectionIdentity._(
      section,
      label == null || label.isEmpty ? null : label,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SectionIdentity &&
      other.section == section &&
      other.customLabel == customLabel;

  @override
  int get hashCode => Object.hash(section, customLabel);

  @override
  String toString() => 'SectionIdentity($displayName)';
}

/// The defaults a section suggests.
///
/// Every field is a *starting point*. None is enforced, and the settings screen
/// says so — the app is not in a position to issue rulings, and a user who
/// disagrees with a default must be able to change it without being told they
/// are configuring their own identity incorrectly.
@immutable
class SectionDefaults {
  const SectionDefaults({
    required this.madhab,
    required this.calculationMethod,
    required this.prayerGrouping,
    required this.rationale,
  });

  /// Supplies the Asr shadow ratio and any Maghrib delay.
  final Madhab madhab;

  final CalculationMethod calculationMethod;

  /// Whether prayers are suggested to be combined, and which.
  final PrayerGrouping prayerGrouping;

  /// One line explaining why these defaults were chosen, shown when a section
  /// is selected. Users are entitled to know why the app moved their settings.
  final String rationale;
}
