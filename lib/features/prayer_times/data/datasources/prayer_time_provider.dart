/// The contract every prayer-time source implements.
///
/// Two implementations ship today — the AlAdhan web service and the on-device
/// astronomical calculator — and the repository above them cannot tell which it
/// is talking to. That is the point: adding a third authority, or swapping the
/// default for a region where a local ministry publishes official times, must
/// not require touching the scheduling, blocking or caching layers.
///
/// Every provider returns instants in UTC. Local wall-clock time is a
/// presentation concern; storing or comparing it would make DST transitions and
/// travel into correctness bugs rather than formatting ones.
library;

import 'package:flutter/foundation.dart';

import '../../../settings/domain/entities/app_settings.dart';
import '../../domain/entities/prayer_enums.dart';

/// One day's prayer instants as returned by a provider, before windows are
/// derived from them.
@immutable
class RawPrayerTimes {
  const RawPrayerTimes({
    required this.date,
    required this.fajr,
    required this.sunrise,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
    required this.source,
    required this.method,
    required this.latitude,
    required this.longitude,
    required this.timezone,
    this.city,
    this.country,
    this.fetchedAt,
  });

  /// Local calendar date, at midnight with no offset applied.
  final DateTime date;

  final DateTime fajr;
  final DateTime sunrise;
  final DateTime dhuhr;
  final DateTime asr;
  final DateTime maghrib;
  final DateTime isha;

  final PrayerTimeSource source;
  final CalculationMethod method;

  final double latitude;
  final double longitude;

  /// IANA timezone identifier the times were computed for.
  final String timezone;

  final String? city;
  final String? country;

  /// When this record was obtained, for cache staleness decisions.
  final DateTime? fetchedAt;

  /// Whether the six instants are in ascending order.
  ///
  /// A provider that returns them out of order — which AlAdhan does at extreme
  /// latitudes, and which a malformed response can also produce — would yield
  /// negative-length windows. The repository checks this before trusting a
  /// remote result over a locally computed one.
  bool get isMonotonic {
    final instants = [fajr, sunrise, dhuhr, asr, maghrib, isha];
    for (var i = 1; i < instants.length; i++) {
      if (instants[i].isBefore(instants[i - 1])) return false;
    }
    return true;
  }

  RawPrayerTimes copyWith({
    PrayerTimeSource? source,
    DateTime? fetchedAt,
  }) =>
      RawPrayerTimes(
        date: date,
        fajr: fajr,
        sunrise: sunrise,
        dhuhr: dhuhr,
        asr: asr,
        maghrib: maghrib,
        isha: isha,
        source: source ?? this.source,
        method: method,
        latitude: latitude,
        longitude: longitude,
        timezone: timezone,
        city: city,
        country: country,
        fetchedAt: fetchedAt ?? this.fetchedAt,
      );
}

/// Raised when a provider cannot produce times for a request.
///
/// Carries [isRetryable] so the repository can distinguish "the network is
/// down, try again later" from "this location is not supported, never retry" —
/// retrying the latter forever is how apps drain batteries.
class PrayerTimeProviderException implements Exception {
  const PrayerTimeProviderException(
    this.message, {
    this.isRetryable = true,
    this.cause,
  });

  final String message;
  final bool isRetryable;
  final Object? cause;

  @override
  String toString() => 'PrayerTimeProviderException: $message';
}

/// A source of prayer times.
abstract interface class PrayerTimeProvider {
  /// Stable identifier, persisted alongside cached days so a schedule can be
  /// attributed to the authority that produced it.
  String get id;

  /// Human-readable name for the settings screen.
  String get displayName;

  /// Whether this provider needs the network. Offline-capable providers are
  /// used as the fallback when a network provider fails.
  bool get requiresNetwork;

  /// Prayer times for [date] under [settings].
  ///
  /// Throws [PrayerTimeProviderException] rather than returning null, so a
  /// failure carries a reason the caller can log and act on.
  Future<RawPrayerTimes> fetch({
    required DateTime date,
    required AppSettings settings,
  });

  /// Prayer times for a contiguous run of days starting at [from].
  ///
  /// Separate from [fetch] because a network provider can usually serve a whole
  /// month in one request, and issuing thirty round trips to prefetch a month
  /// would be both slow and rude to the service.
  Future<List<RawPrayerTimes>> fetchRange({
    required DateTime from,
    required int days,
    required AppSettings settings,
  });
}
