/// Tests for Islamic sections and the strategy registry.
///
/// The properties that matter here are structural, not doctrinal. The app is
/// not in a position to assert what any community must do, so these assert that
/// every section is *representable*, that its defaults are *reachable* through
/// the registry rather than through a conditional, and — most importantly —
/// that nothing a section suggests is ever forced on the user.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/features/prayer_times/domain/entities/prayer_enums.dart';
import 'package:prayer_lock/features/sections/domain/entities/islamic_section.dart';
import 'package:prayer_lock/features/sections/domain/entities/prayer_grouping.dart';
import 'package:prayer_lock/features/sections/domain/strategies/islamic_section_strategy.dart';
import 'package:prayer_lock/features/settings/domain/entities/app_settings.dart';

void main() {
  group('the section catalogue', () {
    test('covers every section the product promises', () {
      // Named individually rather than by count, so removing one is a failure
      // rather than a silently smaller list.
      const expected = {
        IslamicSection.hanafi,
        IslamicSection.shafii,
        IslamicSection.maliki,
        IslamicSection.hanbali,
        IslamicSection.barelvi,
        IslamicSection.deobandi,
        IslamicSection.ahleHadith,
        IslamicSection.salafi,
        IslamicSection.sufi,
        IslamicSection.twelver,
        IslamicSection.ismaili,
        IslamicSection.zaydi,
        IslamicSection.ibadi,
        IslamicSection.other,
      };

      expect(IslamicSection.values.toSet(), expected);
    });

    test('wire values are unique and stable', () {
      // A collision would silently load one section as another; these strings
      // are persisted and uploaded, so they can never be reused.
      final wires = IslamicSection.values.map((s) => s.wireValue).toList();
      expect(wires.toSet().length, wires.length);
    });

    test('every section is grouped for display', () {
      final grouped = IslamicSection.grouped;
      final flattened = grouped.values.expand((list) => list).toSet();
      expect(flattened, IslamicSection.values.toSet());
    });

    test('an unknown wire value degrades rather than throwing', () {
      // A downgrade from a build with more sections must not crash on a
      // settings read.
      expect(IslamicSection.fromWire('zzz_unknown'), IslamicSection.other);
    });
  });

  group('the strategy registry', () {
    test('answers for every section', () {
      // A missing strategy would silently hand a community someone else's
      // defaults.
      for (final section in IslamicSection.values) {
        expect(
          IslamicSectionRegistry.instance.hasStrategyFor(section),
          isTrue,
          reason: '${section.defaultLabel} has no registered strategy',
        );
      }
    });

    test('every section has a rationale the user can read', () {
      for (final section in IslamicSection.values) {
        final rationale =
            IslamicSectionRegistry.instance.defaultsFor(section).rationale;
        expect(rationale, isNotEmpty);
      }
    });

    test('an unregistered section falls back rather than throwing', () {
      final empty = IslamicSectionRegistry(const []);
      final defaults = empty.defaultsFor(IslamicSection.twelver);

      expect(defaults.madhab, Madhab.shafi);
      expect(defaults.prayerGrouping, PrayerGrouping.none);
    });

    test('a strategy can be substituted without editing the registry', () {
      // The extension point that makes a regional build or a test possible.
      final custom = IslamicSectionRegistry.instance.withStrategy(
        const _StubStrategy(
          IslamicSection.sufi,
          SectionDefaults(
            madhab: Madhab.hanafi,
            calculationMethod: CalculationMethod.karachi,
            prayerGrouping: PrayerGrouping.none,
            rationale: 'stub',
          ),
        ),
      );

      expect(custom.defaultsFor(IslamicSection.sufi).madhab, Madhab.hanafi);
      // The instance registry is untouched, so one test cannot leak into
      // another.
      expect(
        IslamicSectionRegistry.instance.defaultsFor(IslamicSection.sufi).madhab,
        Madhab.shafi,
      );
    });
  });

  group('jurisprudential defaults', () {
    test('only Hanafi-following sections use the later Asr', () {
      // Shadow ratio 2 is the Hanafi position specifically. A section given it
      // by accident would shift Asr by up to an hour for that community.
      final laterAsr = IslamicSection.values.where(
        (section) =>
            IslamicSectionRegistry.instance
                .defaultsFor(section)
                .madhab
                .shadowFactor ==
            2,
      );

      expect(
        laterAsr,
        unorderedEquals([
          IslamicSection.hanafi,
          IslamicSection.barelvi,
          IslamicSection.deobandi,
        ]),
      );
    });

    test('Ja’fari sections delay Maghrib past sunset', () {
      for (final section in [IslamicSection.twelver, IslamicSection.ismaili]) {
        final madhab =
            IslamicSectionRegistry.instance.defaultsFor(section).madhab;
        expect(madhab.maghribAngle, isNotNull);
      }
    });

    test('Sufi assumes no Asr convention', () {
      // Sufism spans all four Sunni schools, so implying one would be a
      // category error. The rationale must say so rather than quietly
      // defaulting.
      final defaults =
          IslamicSectionRegistry.instance.defaultsFor(IslamicSection.sufi);
      expect(defaults.rationale.toLowerCase(), contains('school'));
      expect(defaults.madhab.shadowFactor, 1);
    });

    test('combining is suggested only where it is ordinary practice', () {
      final suggestsCombining = IslamicSection.values.where(
        (section) => IslamicSectionRegistry.instance
            .defaultsFor(section)
            .prayerGrouping
            .combinesAnything,
      );

      expect(
        suggestsCombining,
        unorderedEquals([IslamicSection.twelver, IslamicSection.ismaili]),
      );
    });

    test('the neutral defaults match what the app used before sections', () {
      // The upgrade invariant: a user who never picks a section must see
      // exactly the prayer times they saw before this feature shipped.
      final defaults = IslamicSectionRegistry.instance
          .defaultsFor(SectionIdentity.fallback.section);

      expect(defaults.madhab, Madhab.shafi);
      expect(defaults.calculationMethod, CalculationMethod.muslimWorldLeague);
      expect(defaults.prayerGrouping, PrayerGrouping.none);
    });
  });

  group('section identity', () {
    test('a standard section shows its own name', () {
      expect(
        const SectionIdentity.of(IslamicSection.maliki).displayName,
        'Maliki',
      );
    });

    test('a named section shows the name the user gave it', () {
      expect(SectionIdentity.custom('Ahmadi').displayName, 'Ahmadi');
    });

    test('an unnamed Other reads as unset rather than as a choice', () {
      // Labelling the not-yet-chosen state "Other" would read as a decision the
      // user never made.
      expect(SectionIdentity.fallback.displayName, 'Not set');
      expect(SectionIdentity.fallback.isChosen, isFalse);
      expect(SectionIdentity.fallback.needsLabel, isTrue);
    });

    test('a blank custom label is treated as no label', () {
      expect(SectionIdentity.custom('   ').customLabel, isNull);
      expect(SectionIdentity.custom('   ').needsLabel, isTrue);
    });

    test('a custom label is trimmed', () {
      expect(SectionIdentity.custom('  Ahmadi  ').customLabel, 'Ahmadi');
    });

    test('round-trips through JSON', () {
      final named = SectionIdentity.custom('My community');
      expect(SectionIdentity.fromJson(named.toJson()), named);

      const standard = SectionIdentity.of(IslamicSection.zaydi);
      expect(SectionIdentity.fromJson(standard.toJson()), standard);
    });

    test('a label attached to a standard section is discarded', () {
      // Otherwise a stale label would override a name the user did not choose.
      final restored = SectionIdentity.fromJson({
        'section': 'hanbali',
        'customLabel': 'left over',
      });
      expect(restored.displayName, 'Hanbali');
      expect(restored.customLabel, isNull);
    });
  });

  group('settings resolve section defaults', () {
    test('the Asr convention follows the section by default', () {
      const settings = AppSettings(
        section: SectionIdentity.of(IslamicSection.hanafi),
      );
      expect(settings.madhab, Madhab.hanafi);
      expect(settings.hasSectionOverrides, isFalse);
    });

    test('an explicit choice wins over the section', () {
      const settings = AppSettings(
        section: SectionIdentity.of(IslamicSection.hanafi),
        madhabOverride: Madhab.shafi,
      );
      expect(settings.madhab, Madhab.shafi);
      expect(settings.hasSectionOverrides, isTrue);
    });

    test('a suggested grouping is only a suggestion', () {
      const suggested = AppSettings(
        section: SectionIdentity.of(IslamicSection.twelver),
      );
      expect(suggested.prayerGrouping, PrayerGrouping.both);

      // The spec requirement: the user can still turn it off.
      const overridden = AppSettings(
        section: SectionIdentity.of(IslamicSection.twelver),
        prayerGroupingOverride: PrayerGrouping.none,
      );
      expect(overridden.prayerGrouping, PrayerGrouping.none);
    });

    test('selecting a section clears previous overrides', () {
      const before = AppSettings(
        section: SectionIdentity.of(IslamicSection.hanafi),
        madhabOverride: Madhab.jafari,
        prayerGroupingOverride: PrayerGrouping.both,
      );

      final after =
          before.withSection(const SectionIdentity.of(IslamicSection.shafii));

      expect(after.madhabOverride, isNull);
      expect(after.prayerGroupingOverride, isNull);
      expect(after.madhab, Madhab.shafi);
      expect(after.prayerGrouping, PrayerGrouping.none);
    });

    test('selecting a section keeps unrelated settings', () {
      // Choosing a section must not reset blocked apps or the unlock policy.
      const before = AppSettings(
        blockedPackages: {'com.instagram.android'},
        unlockPolicy: UnlockPolicy.fullDuration,
        lockGracePeriodMinutes: 12,
      );

      final after =
          before.withSection(const SectionIdentity.of(IslamicSection.ibadi));

      expect(after.blockedPackages, {'com.instagram.android'});
      expect(after.unlockPolicy, UnlockPolicy.fullDuration);
      expect(after.lockGracePeriodMinutes, 12);
    });

    test('resetting returns to the section defaults', () {
      const overridden = AppSettings(
        section: SectionIdentity.of(IslamicSection.twelver),
        madhabOverride: Madhab.hanafi,
        prayerGroupingOverride: PrayerGrouping.none,
      );

      final reset = overridden.resetToSectionDefaults();
      expect(reset.hasSectionOverrides, isFalse);
      expect(reset.madhab, Madhab.jafari);
      expect(reset.prayerGrouping, PrayerGrouping.both);
    });
  });

  group('migration from the pre-sections model', () {
    /// Settings as a build without sections would have written them.
    Map<String, dynamic> legacy(String madhab) => {
          'madhab': madhab,
          'calculationMethod': 'muslim_world_league',
          'blockedPackages': <String>['com.instagram.android'],
        };

    test('a Hanafi user keeps the later Asr', () {
      final settings = AppSettings.fromJson(legacy('hanafi'));
      expect(settings.section.section, IslamicSection.hanafi);
      expect(settings.madhab, Madhab.hanafi);
    });

    test('a Ja’fari user keeps their Maghrib definition', () {
      final settings = AppSettings.fromJson(legacy('jafari'));
      expect(settings.section.section, IslamicSection.twelver);
      expect(settings.madhab, Madhab.jafari);
    });

    test('a Ja’fari user is NOT silently switched to combined prayers', () {
      // Twelver suggests combining both pairs. Applying that on an app update
      // would change how the phone locks and how many cards appear, without
      // the user asking for anything.
      final settings = AppSettings.fromJson(legacy('jafari'));
      expect(settings.prayerGrouping, PrayerGrouping.none);
      expect(settings.prayerGroupingOverride, PrayerGrouping.none);
    });

    test('an Ahl-e-Hadith user is recognised', () {
      final settings = AppSettings.fromJson(legacy('ahle_hadith'));
      expect(settings.section.section, IslamicSection.ahleHadith);
      expect(settings.madhab, Madhab.ahleHadith);
    });

    test('a Shafi user is left unassigned rather than assumed', () {
      // "shafi" covered Shafi'i, Maliki and Hanbali equally, and was also the
      // default nobody changed. Inferring an identity from it would be putting
      // words in the user's mouth.
      final settings = AppSettings.fromJson(legacy('shafi'));
      expect(settings.section.isChosen, isFalse);
      expect(settings.madhab, Madhab.shafi);
    });

    test('every legacy madhab migrates without changing prayer times', () {
      // The invariant that makes this upgrade safe.
      for (final wire in ['shafi', 'hanafi', 'ahle_hadith', 'jafari']) {
        final settings = AppSettings.fromJson(legacy(wire));
        expect(
          settings.madhab,
          Madhab.fromWire(wire),
          reason: '$wire changed Asr timing on upgrade',
        );
        expect(
          settings.prayerGrouping,
          PrayerGrouping.none,
          reason: '$wire started combining prayers on upgrade',
        );
      }
    });

    test('unrelated legacy settings survive', () {
      final settings = AppSettings.fromJson(legacy('hanafi'));
      expect(settings.blockedPackages, {'com.instagram.android'});
    });

    test('a fresh install takes the neutral defaults', () {
      final settings = AppSettings.fromJson(const {});
      expect(settings.madhab, Madhab.shafi);
      expect(settings.prayerGrouping, PrayerGrouping.none);
      expect(settings.prayerGroupingOverride, isNull);
    });

    test('an already-migrated install is not re-migrated', () {
      const chosen = AppSettings(
        section: SectionIdentity.of(IslamicSection.twelver),
      );
      final restored = AppSettings.fromJson(chosen.toJson());

      // No pinned override, so the section's suggestion applies as intended.
      expect(restored.prayerGroupingOverride, isNull);
      expect(restored.prayerGrouping, PrayerGrouping.both);
    });

    test('settings round-trip through JSON', () {
      const original = AppSettings(
        section: SectionIdentity.of(IslamicSection.salafi),
        madhabOverride: Madhab.hanafi,
        prayerGroupingOverride: PrayerGrouping.maghribIsha,
        combinedVerification: false,
      );

      final restored = AppSettings.fromJson(original.toJson());
      expect(restored.section, original.section);
      expect(restored.madhabOverride, Madhab.hanafi);
      expect(restored.prayerGroupingOverride, PrayerGrouping.maghribIsha);
      expect(restored.combinedVerification, isFalse);
    });
  });
}

class _StubStrategy implements IslamicSectionStrategy {
  const _StubStrategy(this.section, this.defaults);

  @override
  final IslamicSection section;

  @override
  final SectionDefaults defaults;
}
