/// Decides whether the user looks like they are somewhere other than their
/// usual mosque, and which one to offer instead.
///
/// The bar for asking is deliberately high. A prompt that appears whenever the
/// GPS wobbles trains people to dismiss it without reading, which costs more
/// than never asking would: the one Friday they really are travelling, they
/// will swipe it away out of habit. So the suggestion only appears when the
/// user is genuinely far from their selected mosque *and* meaningfully closer
/// to a different configured one.
library;

import '../entities/mosque_profile.dart';

/// A suggestion to pray somewhere other than the selected mosque.
class MosqueSuggestion {
  const MosqueSuggestion({
    required this.mosque,
    required this.distanceKm,
    required this.selectedDistanceKm,
  });

  /// The mosque to offer.
  final MosqueProfile mosque;

  /// How far the user is from [mosque], in kilometres.
  final double distanceKm;

  /// How far the user is from the mosque currently selected.
  final double selectedDistanceKm;
}

abstract final class MosqueProximityDetector {
  /// How far from the selected mosque counts as "not there".
  ///
  /// Fifteen kilometres is beyond any plausible walk or short drive to a local
  /// mosque, and beyond the error of a low-accuracy fix — which can be a
  /// kilometre or two indoors. Below this, the honest answer is that we do not
  /// know whether the user has travelled, and we say nothing.
  static const double awayThresholdKm = 15.0;

  /// How much nearer a rival mosque must be before it is worth offering.
  ///
  /// Without a margin, two mosques roughly equidistant from a hotel would flip
  /// the suggestion between them on successive fixes. Requiring the alternative
  /// to be at least this much closer makes the answer stable.
  static const double preferenceMarginKm = 5.0;

  /// The mosque worth offering, or null to stay quiet.
  ///
  /// Returns null — deliberately, and in each case because asking would be
  /// worse than not asking — when:
  ///
  ///   * the user turned smart prompts off;
  ///   * there is no current position, or the selected mosque has no
  ///     coordinates, so there is nothing to compare;
  ///   * the user is within [awayThresholdKm] of their selected mosque;
  ///   * no other mosque is itself within [awayThresholdKm] — being merely
  ///     *nearer* is not enough, or someone in Karachi would be told to pray
  ///     in Lahore because it is a little closer than Islamabad;
  ///   * the nearest one is not [preferenceMarginKm] closer than the selected.
  static MosqueSuggestion? suggestionFor({
    required List<MosqueProfile> mosques,
    required String? selectedMosqueId,
    required MosqueCoordinates? currentPosition,
    required bool smartPromptsEnabled,
  }) {
    if (!smartPromptsEnabled) return null;
    if (currentPosition == null) return null;

    final selected = _byId(mosques, selectedMosqueId);
    final selectedCoordinates = selected?.coordinates;

    // Nothing to measure against. Not a failure: a user who never recorded
    // where their mosque is has told us, implicitly, not to guess.
    if (selectedCoordinates == null) return null;

    final selectedDistance = currentPosition.distanceKmTo(selectedCoordinates);
    if (selectedDistance <= awayThresholdKm) return null;

    MosqueProfile? best;
    var bestDistance = double.infinity;

    for (final mosque in mosques) {
      if (mosque.id == selected?.id) continue;
      final coordinates = mosque.coordinates;
      if (coordinates == null) continue;

      final distance = currentPosition.distanceKmTo(coordinates);
      // The candidate has to be somewhere the user could actually pray, not
      // just the least distant of several unreachable options.
      if (distance > awayThresholdKm) continue;

      if (distance < bestDistance) {
        best = mosque;
        bestDistance = distance;
      }
    }

    if (best == null) return null;
    if (selectedDistance - bestDistance < preferenceMarginKm) return null;

    return MosqueSuggestion(
      mosque: best,
      distanceKm: bestDistance,
      selectedDistanceKm: selectedDistance,
    );
  }

  static MosqueProfile? _byId(List<MosqueProfile> mosques, String? id) {
    if (id == null) return null;
    for (final mosque in mosques) {
      if (mosque.id == id) return mosque;
    }
    return null;
  }
}
