import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_lock/features/jumuah/domain/entities/jumuah_profile.dart'
    show LocalTimeOfDay;
import 'package:prayer_lock/features/jumuah/domain/entities/mosque_profile.dart';
import 'package:prayer_lock/features/jumuah/domain/usecases/mosque_proximity_detector.dart';

/// When to offer a different mosque, and — more often — when to say nothing.
///
/// Most of these tests assert silence. That is the point: a travel prompt is
/// only useful if it is rare enough to still be read, so the cases where the
/// app must keep quiet are the ones worth pinning down.
void main() {
  // Two mosques about 340km apart, plus one near the second.
  const lahore = MosqueCoordinates(latitude: 31.5204, longitude: 74.3587);
  const islamabad = MosqueCoordinates(latitude: 33.6844, longitude: 73.0479);
  const rawalpindi = MosqueCoordinates(latitude: 33.5651, longitude: 73.0169);

  MosqueProfile mosque(
    String id, {
    MosqueCoordinates? at,
    MosqueKind kind = MosqueKind.custom,
  }) =>
      MosqueProfile(
        id: id,
        kind: kind,
        name: id,
        startsAt: const LocalTimeOfDay(13, 30),
        endsAt: const LocalTimeOfDay(14, 15),
        coordinates: at,
      );

  MosqueSuggestion? suggest({
    required List<MosqueProfile> mosques,
    required String? selected,
    MosqueCoordinates? position,
    bool enabled = true,
  }) =>
      MosqueProximityDetector.suggestionFor(
        mosques: mosques,
        selectedMosqueId: selected,
        currentPosition: position,
        smartPromptsEnabled: enabled,
      );

  group('offers an alternative', () {
    test('when the user is far from their mosque and near another', () {
      final suggestion = suggest(
        mosques: [
          mosque('home', at: lahore),
          mosque('university', at: islamabad),
        ],
        selected: 'home',
        position: rawalpindi,
      );

      expect(suggestion, isNotNull);
      expect(suggestion!.mosque.id, 'university');
      expect(suggestion.distanceKm, lessThan(15));
      expect(suggestion.selectedDistanceKm, greaterThan(250));
    });

    test('picks the nearest of several alternatives', () {
      final suggestion = suggest(
        mosques: [
          mosque('home', at: lahore),
          mosque('far', at: islamabad),
          mosque('near', at: rawalpindi),
        ],
        selected: 'home',
        position: rawalpindi,
      );

      expect(suggestion?.mosque.id, 'near');
    });
  });

  group('stays quiet', () {
    test('when the user turned smart prompts off', () {
      final suggestion = suggest(
        mosques: [
          mosque('home', at: lahore),
          mosque('university', at: islamabad),
        ],
        selected: 'home',
        position: islamabad,
        enabled: false,
      );

      expect(suggestion, isNull);
    });

    test('when there is no position fix', () {
      final suggestion = suggest(
        mosques: [
          mosque('home', at: lahore),
          mosque('university', at: islamabad),
        ],
        selected: 'home',
      );

      expect(suggestion, isNull);
    });

    test('when the selected mosque has no coordinates', () {
      // The user never recorded where their mosque is. Guessing they have
      // travelled from a place we do not know is not possible.
      final suggestion = suggest(
        mosques: [
          mosque('home'),
          mosque('university', at: islamabad),
        ],
        selected: 'home',
        position: islamabad,
      );

      expect(suggestion, isNull);
    });

    test('when the user is at their usual mosque', () {
      final suggestion = suggest(
        mosques: [
          mosque('home', at: lahore),
          mosque('university', at: islamabad),
        ],
        selected: 'home',
        position: lahore,
      );

      expect(suggestion, isNull);
    });

    test('when the user is away and no configured mosque is near either', () {
      // Karachi, with mosques saved in Lahore and Islamabad. Lahore happens to
      // be the nearer of the two, but "nearer" is not "near" — suggesting a
      // mosque a thousand kilometres away would be absurd.
      final suggestion = suggest(
        mosques: [
          mosque('home', at: lahore),
          mosque('university', at: islamabad),
        ],
        selected: 'university',
        position: const MosqueCoordinates(latitude: 24.86, longitude: 67.01),
      );

      expect(suggestion, isNull);
    });

    test('when the alternative is closer, but not by enough to be sure', () {
      // The user is just over the away threshold from their own mosque, and a
      // second one is a couple of kilometres nearer. Without the margin this
      // would flip between the two as the fix drifts across the boundary.
      const here = MosqueCoordinates(latitude: 33.0, longitude: 73.0);
      const selected = MosqueCoordinates(latitude: 33.15, longitude: 73.0);
      const rival = MosqueCoordinates(latitude: 33.126, longitude: 73.0);

      final suggestion = suggest(
        mosques: [mosque('a', at: selected), mosque('b', at: rival)],
        selected: 'a',
        position: here,
      );

      expect(suggestion, isNull);
    });

    test('when no mosque is selected', () {
      final suggestion = suggest(
        mosques: [mosque('home', at: lahore)],
        selected: null,
        position: islamabad,
      );

      expect(suggestion, isNull);
    });

    test('when the nearest alternative is itself too far to reach', () {
      // 40km from a mosque the user is not at, and 25km from another. Nearer,
      // but still not somewhere they are plausibly praying today.
      const here = MosqueCoordinates(latitude: 33.0, longitude: 73.0);
      const selected = MosqueCoordinates(latitude: 33.36, longitude: 73.0);
      const rival = MosqueCoordinates(latitude: 33.225, longitude: 73.0);

      final suggestion = suggest(
        mosques: [mosque('a', at: selected), mosque('b', at: rival)],
        selected: 'a',
        position: here,
      );

      expect(suggestion, isNull);
    });

    test('when the only alternatives have no coordinates', () {
      final suggestion = suggest(
        mosques: [mosque('home', at: lahore), mosque('somewhere')],
        selected: 'home',
        position: islamabad,
      );

      expect(suggestion, isNull);
    });

    test('when the selected mosque is the only one', () {
      final suggestion = suggest(
        mosques: [mosque('home', at: lahore)],
        selected: 'home',
        position: islamabad,
      );

      expect(suggestion, isNull);
    });
  });

  group('thresholds', () {
    test('just inside the away threshold says nothing', () {
      // ~11km north of the selected mosque: a long drive, but plausibly still
      // the same city and the same mosque.
      const nearby = MosqueCoordinates(latitude: 31.62, longitude: 74.3587);

      final suggestion = suggest(
        mosques: [
          mosque('home', at: lahore),
          mosque('other', at: islamabad),
        ],
        selected: 'home',
        position: nearby,
      );

      expect(suggestion, isNull);
    });

    test('the reported distances are the ones that drove the decision', () {
      final suggestion = suggest(
        mosques: [
          mosque('home', at: lahore),
          mosque('university', at: islamabad),
        ],
        selected: 'home',
        position: islamabad,
      )!;

      expect(suggestion.distanceKm, lessThan(1));
      expect(
        suggestion.selectedDistanceKm,
        greaterThan(MosqueProximityDetector.awayThresholdKm),
      );
    });
  });
}
