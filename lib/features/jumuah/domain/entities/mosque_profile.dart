/// A mosque the user prays Jumu'ah at.
///
/// This replaces the earlier two-value enum. That model was wrong in a way that
/// only shows up in real life: people pray Jumu'ah wherever they happen to be
/// on a Friday — the mosque near work, one near a relative's house, whatever is
/// closest while travelling — and each holds it at its own time. A fixed pair of
/// options forces everyone else to lie about where they are.
///
/// So a mosque is now a record with an identity, and the user may have as many
/// as they like. [MosqueKind] is a *label* for grouping and iconography, not a
/// constraint: nothing behaves differently because a mosque is tagged "travel",
/// and a user can have four workplace mosques if that is their life.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'jumuah_profile.dart' show LocalTimeOfDay;

/// What sort of place this is. Presentation only.
enum MosqueKind {
  home('home', 'Home Mosque'),
  university('university', 'University Mosque'),
  workplace('workplace', 'Workplace Mosque'),
  travel('travel', 'Travel Mosque'),
  custom('custom', 'Custom Mosque');

  const MosqueKind(this.wireValue, this.defaultName);

  final String wireValue;

  /// Used as the mosque's name when the user has not typed one.
  final String defaultName;

  static MosqueKind fromWire(String value) => MosqueKind.values.firstWhere(
        (kind) => kind.wireValue == value,
        orElse: () => MosqueKind.custom,
      );
}

/// Where a mosque is, when the user recorded it.
///
/// Optional throughout. A user who never grants location, or who simply does
/// not care, must be able to add a mosque with nothing but a name and a time.
@immutable
class MosqueCoordinates {
  const MosqueCoordinates({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  /// Rough great-circle distance in kilometres.
  ///
  /// Equirectangular rather than haversine: the app only ever asks "is this
  /// mosque near where I am now", where the answer is measured in kilometres
  /// and the approximation is accurate to well under a percent at those
  /// distances. Haversine's extra trigonometry buys nothing here.
  double distanceKmTo(MosqueCoordinates other) {
    const earthRadiusKm = 6371.0;
    const degreesToRadians = math.pi / 180.0;

    final meanLatitude =
        (latitude + other.latitude) / 2 * degreesToRadians;
    final deltaLat = (other.latitude - latitude) * degreesToRadians;
    final deltaLon = (other.longitude - longitude) * degreesToRadians;

    // cos() of the mean latitude corrects for meridians converging toward the
    // poles; without it, east-west distances are overstated everywhere but the
    // equator.
    final x = deltaLon * math.cos(meanLatitude);
    return earthRadiusKm * math.sqrt(deltaLat * deltaLat + x * x);
  }

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
      };

  factory MosqueCoordinates.fromJson(Map<String, dynamic> json) =>
      MosqueCoordinates(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is MosqueCoordinates &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

/// One mosque, with the Jumu'ah time it holds.
@immutable
class MosqueProfile {
  const MosqueProfile({
    required this.id,
    required this.kind,
    required this.name,
    required this.startsAt,
    required this.endsAt,
    this.address,
    this.notes,
    this.coordinates,
  });

  /// Stable identity. Survives renaming — the user's preference points at this,
  /// so a mosque they rename is still the one they chose.
  final String id;

  final MosqueKind kind;

  /// What the user calls it. Falls back to the kind's default when blank.
  final String name;

  final LocalTimeOfDay startsAt;
  final LocalTimeOfDay endsAt;

  final String? address;
  final String? notes;

  /// Where it is, if the user recorded it. Drives the "you seem to be in a
  /// different city" prompt, and nothing else.
  final MosqueCoordinates? coordinates;

  String get displayName => name.trim().isEmpty ? kind.defaultName : name.trim();

  Duration get duration {
    final minutes = endsAt.minutesSinceMidnight - startsAt.minutesSinceMidnight;
    return minutes <= 0 ? Duration.zero : Duration(minutes: minutes);
  }

  /// Whether this describes a usable window. An invalid profile is never
  /// applied — the scheduler falls back to ordinary Dhuhr.
  bool get isValid => endsAt.minutesSinceMidnight > startsAt.minutesSinceMidnight;

  /// "2:00 PM – 2:15 PM"
  String get formattedRange => '${startsAt.format()} – ${endsAt.format()}';

  MosqueProfile copyWith({
    MosqueKind? kind,
    String? name,
    LocalTimeOfDay? startsAt,
    LocalTimeOfDay? endsAt,
    String? address,
    String? notes,
    MosqueCoordinates? coordinates,
  }) =>
      MosqueProfile(
        id: id,
        kind: kind ?? this.kind,
        name: name ?? this.name,
        startsAt: startsAt ?? this.startsAt,
        endsAt: endsAt ?? this.endsAt,
        address: address ?? this.address,
        notes: notes ?? this.notes,
        coordinates: coordinates ?? this.coordinates,
      );

  /// Drop the recorded position without touching anything else.
  MosqueProfile withoutCoordinates() => MosqueProfile(
        id: id,
        kind: kind,
        name: name,
        startsAt: startsAt,
        endsAt: endsAt,
        address: address,
        notes: notes,
      );

  /// The set a fresh install starts with.
  ///
  /// Seeded rather than left empty so the first Friday has something to offer.
  /// The times are the ones from the product brief; every one is editable, and
  /// a user who only attends one mosque simply ignores the rest.
  static List<MosqueProfile> defaults() => const [
        MosqueProfile(
          id: 'home',
          kind: MosqueKind.home,
          name: 'Home Mosque',
          startsAt: LocalTimeOfDay(14, 0),
          endsAt: LocalTimeOfDay(14, 15),
        ),
        MosqueProfile(
          id: 'university',
          kind: MosqueKind.university,
          name: 'University Mosque',
          startsAt: LocalTimeOfDay(13, 15),
          endsAt: LocalTimeOfDay(13, 30),
        ),
        MosqueProfile(
          id: 'workplace',
          kind: MosqueKind.workplace,
          name: 'Workplace Mosque',
          startsAt: LocalTimeOfDay(13, 45),
          endsAt: LocalTimeOfDay(14, 0),
        ),
        MosqueProfile(
          id: 'travel',
          kind: MosqueKind.travel,
          name: 'Travel Mosque',
          startsAt: LocalTimeOfDay(13, 30),
          endsAt: LocalTimeOfDay(13, 45),
        ),
      ];

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.wireValue,
        'name': name,
        'startsAt': startsAt.toJson(),
        'endsAt': endsAt.toJson(),
        'address': address,
        'notes': notes,
        'coordinates': coordinates?.toJson(),
      };

  factory MosqueProfile.fromJson(Map<String, dynamic> json) {
    final kind = MosqueKind.fromWire(json['kind'] as String? ?? 'custom');

    return MosqueProfile(
      id: json['id'] as String? ?? kind.wireValue,
      kind: kind,
      name: json['name'] as String? ?? kind.defaultName,
      startsAt: json['startsAt'] is Map
          ? LocalTimeOfDay.fromJson(
              (json['startsAt'] as Map).cast<String, dynamic>())
          : const LocalTimeOfDay(14, 0),
      endsAt: json['endsAt'] is Map
          ? LocalTimeOfDay.fromJson(
              (json['endsAt'] as Map).cast<String, dynamic>())
          : const LocalTimeOfDay(14, 15),
      address: json['address'] as String?,
      notes: json['notes'] as String?,
      coordinates: json['coordinates'] is Map
          ? MosqueCoordinates.fromJson(
              (json['coordinates'] as Map).cast<String, dynamic>())
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MosqueProfile &&
      other.id == id &&
      other.kind == kind &&
      other.name == name &&
      other.startsAt == startsAt &&
      other.endsAt == endsAt &&
      other.address == address &&
      other.notes == notes &&
      other.coordinates == coordinates;

  @override
  int get hashCode => Object.hash(
        id,
        kind,
        name,
        startsAt,
        endsAt,
        address,
        notes,
        coordinates,
      );

  @override
  String toString() => 'MosqueProfile($displayName, $formattedRange)';
}
