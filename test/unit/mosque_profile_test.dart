/// Tests for the mosque profile model and its migration.
///
/// The migration matters most: an existing user had exactly two mosques with
/// times they may have edited, and an upgrade must not lose either the times or
/// the fact that they had chosen one.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/features/jumuah/domain/entities/jumuah_profile.dart';
import 'package:prayer_lock/features/jumuah/domain/entities/jumuah_settings.dart';
import 'package:prayer_lock/features/jumuah/domain/entities/mosque_profile.dart';

void main() {
  group('the seeded set', () {
    test('covers every kind the product promises', () {
      final kinds = MosqueProfile.defaults().map((m) => m.kind).toSet();
      expect(kinds, containsAll([
        MosqueKind.home,
        MosqueKind.university,
        MosqueKind.workplace,
        MosqueKind.travel,
      ]));
    });

    test('ships the times from the brief', () {
      final byId = {for (final m in MosqueProfile.defaults()) m.id: m};

      expect(byId['home']!.startsAt, const LocalTimeOfDay(14, 0));
      expect(byId['home']!.endsAt, const LocalTimeOfDay(14, 15));
      expect(byId['university']!.startsAt, const LocalTimeOfDay(13, 15));
      expect(byId['university']!.endsAt, const LocalTimeOfDay(13, 30));
    });

    test('every seeded mosque is usable', () {
      for (final mosque in MosqueProfile.defaults()) {
        expect(mosque.isValid, isTrue, reason: mosque.id);
        expect(mosque.duration, greaterThan(Duration.zero));
      }
    });

    test('ids are unique', () {
      final ids = MosqueProfile.defaults().map((m) => m.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('a mosque', () {
    test('falls back to its kind name when unnamed', () {
      const unnamed = MosqueProfile(
        id: 'x',
        kind: MosqueKind.workplace,
        name: '   ',
        startsAt: LocalTimeOfDay(13, 0),
        endsAt: LocalTimeOfDay(13, 20),
      );
      expect(unnamed.displayName, 'Workplace Mosque');
    });

    test('an inverted window is invalid rather than negative', () {
      const inverted = MosqueProfile(
        id: 'x',
        kind: MosqueKind.custom,
        name: 'Broken',
        startsAt: LocalTimeOfDay(14, 0),
        endsAt: LocalTimeOfDay(13, 0),
      );
      expect(inverted.isValid, isFalse);
      expect(inverted.duration, Duration.zero);
    });

    test('round-trips through JSON with every optional field', () {
      const full = MosqueProfile(
        id: 'custom_1',
        kind: MosqueKind.custom,
        name: 'Masjid al-Noor',
        startsAt: LocalTimeOfDay(13, 20),
        endsAt: LocalTimeOfDay(13, 50),
        address: '12 High Street',
        notes: 'Park behind',
        coordinates: MosqueCoordinates(latitude: 21.42, longitude: 39.83),
      );

      expect(MosqueProfile.fromJson(full.toJson()), full);
    });

    test('measures distance between coordinates', () {
      // Makkah to Madinah is roughly 340 km.
      const makkah = MosqueCoordinates(latitude: 21.4225, longitude: 39.8262);
      const madinah = MosqueCoordinates(latitude: 24.4672, longitude: 39.6111);

      expect(makkah.distanceKmTo(madinah), closeTo(340, 25));
      expect(makkah.distanceKmTo(makkah), closeTo(0, 0.01));
    });
  });

  group('settings', () {
    test('an unconfigured install has mosques but no selection', () {
      const settings = JumuahSettings();

      expect(settings.mosques, isNotEmpty);
      expect(settings.selectedMosqueId, isNull);
      expect(settings.needsMosqueChoice, isTrue);
      expect(settings.isActive, isFalse);
    });

    test('selecting records both the choice and the habit', () {
      final settings = const JumuahSettings().selecting('university');

      expect(settings.selectedMosqueId, 'university');
      expect(settings.lastUsedMosqueId, 'university');
      expect(settings.isActive, isTrue);
    });

    test('using a mosque for today leaves the habit alone', () {
      // The travelling case: elsewhere this week, not permanently.
      final settings =
          const JumuahSettings().selecting('home').usingForToday('travel');

      expect(settings.selectedMosqueId, 'travel');
      expect(settings.lastUsedMosqueId, 'home');
    });

    test('adding a mosque appends it', () {
      const custom = MosqueProfile(
        id: 'custom_1',
        kind: MosqueKind.custom,
        name: 'Masjid al-Noor',
        startsAt: LocalTimeOfDay(13, 0),
        endsAt: LocalTimeOfDay(13, 20),
      );

      final settings = const JumuahSettings().withMosque(custom);
      expect(settings.mosqueById('custom_1'), custom);
      expect(settings.mosques.length, MosqueProfile.defaults().length + 1);
    });

    test('saving an existing mosque replaces rather than duplicates', () {
      final edited = MosqueProfile.defaults()
          .first
          .copyWith(startsAt: const LocalTimeOfDay(12, 45));

      final settings = const JumuahSettings().withMosque(edited);

      expect(settings.mosques.length, MosqueProfile.defaults().length);
      expect(
        settings.mosqueById(edited.id)!.startsAt,
        const LocalTimeOfDay(12, 45),
      );
    });

    test('deleting clears a preference pointing at it', () {
      final settings =
          const JumuahSettings().selecting('home').withoutMosque('home');

      expect(settings.mosqueById('home'), isNull);
      expect(settings.selectedMosqueId, isNull);
      expect(settings.needsMosqueChoice, isTrue);
    });

    test('the last mosque cannot be deleted', () {
      // An empty list would leave the Friday prompt with nothing to offer.
      var settings = const JumuahSettings();
      for (final mosque in MosqueProfile.defaults()) {
        settings = settings.withoutMosque(mosque.id);
      }

      expect(settings.mosques, hasLength(1));
    });

    test('a selection pointing at a deleted mosque falls back to the habit', () {
      // Losing your preference because a *different* mosque was removed would
      // be baffling.
      final settings = const JumuahSettings()
          .selecting('home')
          .usingForToday('travel')
          .withoutMosque('travel');

      expect(settings.activeMosque?.id, 'home');
    });

    test('clearing the selection keeps the habit', () {
      // "Ask me again" is not "forget everything you know about me".
      final settings = const JumuahSettings().selecting('home').clearSelection();

      expect(settings.selectedMosqueId, isNull);
      expect(settings.lastUsedMosqueId, 'home');
      expect(settings.needsMosqueChoice, isTrue);
    });

    test('round-trips through JSON', () {
      final original = const JumuahSettings()
          .selecting('university')
          .withMosque(
            const MosqueProfile(
              id: 'custom_1',
              kind: MosqueKind.custom,
              name: 'Masjid al-Noor',
              startsAt: LocalTimeOfDay(13, 0),
              endsAt: LocalTimeOfDay(13, 20),
            ),
          );

      expect(JumuahSettings.fromJson(original.toJson()), original);
    });
  });

  group('migration from the two-location model', () {
    /// Settings as the previous build wrote them.
    Map<String, dynamic> legacy({
      String? selected,
      Map<String, dynamic>? homeTimes,
    }) =>
        {
          'enabled': true,
          'selectedLocation': ?selected,
          'homeMosque': {
            'location': 'home_mosque',
            'startsAt': homeTimes?['startsAt'] ?? {'hour': 14, 'minute': 0},
            'endsAt': homeTimes?['endsAt'] ?? {'hour': 14, 'minute': 15},
          },
          'universityMosque': {
            'location': 'university_mosque',
            'startsAt': {'hour': 13, 'minute': 15},
            'endsAt': {'hour': 13, 'minute': 30},
          },
        };

    test('produces the full seeded set', () {
      final settings = JumuahSettings.fromJson(legacy());
      expect(settings.mosques.length, MosqueProfile.defaults().length);
    });

    test('carries across times the user had edited', () {
      // These are the user's own configuration and must not be reset.
      final settings = JumuahSettings.fromJson(
        legacy(
          homeTimes: {
            'startsAt': {'hour': 13, 'minute': 45},
            'endsAt': {'hour': 14, 'minute': 5},
          },
        ),
      );

      expect(
        settings.mosqueById('home')!.startsAt,
        const LocalTimeOfDay(13, 45),
      );
      expect(settings.mosqueById('home')!.endsAt, const LocalTimeOfDay(14, 5));
    });

    test('maps the old selection onto the new id', () {
      expect(
        JumuahSettings.fromJson(legacy(selected: 'home_mosque'))
            .selectedMosqueId,
        'home',
      );
      expect(
        JumuahSettings.fromJson(legacy(selected: 'university_mosque'))
            .selectedMosqueId,
        'university',
      );
    });

    test('an unchosen legacy install still needs to be asked', () {
      // Inventing a selection during migration would answer a question the
      // user never answered, and then never ask it.
      final settings = JumuahSettings.fromJson(legacy());

      expect(settings.selectedMosqueId, isNull);
      expect(settings.needsMosqueChoice, isTrue);
    });

    test('mosques the user never touched keep the shipped times', () {
      final settings = JumuahSettings.fromJson(legacy());

      expect(
        settings.mosqueById('workplace')!.startsAt,
        const LocalTimeOfDay(13, 45),
      );
    });

    test('an already-migrated install is not re-migrated', () {
      final migrated = const JumuahSettings().selecting('travel');
      final restored = JumuahSettings.fromJson(migrated.toJson());

      expect(restored.selectedMosqueId, 'travel');
      expect(restored, migrated);
    });
  });
}
