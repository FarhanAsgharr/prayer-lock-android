/// Offline city catalogue for manual location selection.
///
/// Bundled rather than fetched: location selection is the first thing a user
/// does, and requiring a network call to complete setup would break the
/// offline-first promise at the worst possible moment.
///
/// It also supplies the IANA timezone for a coordinate, which the OS position
/// does not carry. A full reverse-geocode service would be more precise, but
/// prayer times vary by under a minute across a metropolitan area, so nearest-
/// city resolution is accurate enough and costs no network round trip.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

@immutable
class City {
  const City({
    required this.name,
    required this.country,
    required this.latitude,
    required this.longitude,
    required this.timezone,
  });

  final String name;
  final String country;
  final double latitude;
  final double longitude;
  final String timezone;
}

abstract final class CityCatalog {
  /// Selected for population and for spread across timezones and latitudes,
  /// including high-latitude cities where the calculation is hardest.
  static const List<City> cities = [
    // Middle East
    City(name: 'Makkah', country: 'Saudi Arabia', latitude: 21.4225, longitude: 39.8262, timezone: 'Asia/Riyadh'),
    City(name: 'Madinah', country: 'Saudi Arabia', latitude: 24.5247, longitude: 39.5692, timezone: 'Asia/Riyadh'),
    City(name: 'Riyadh', country: 'Saudi Arabia', latitude: 24.7136, longitude: 46.6753, timezone: 'Asia/Riyadh'),
    City(name: 'Jeddah', country: 'Saudi Arabia', latitude: 21.4858, longitude: 39.1925, timezone: 'Asia/Riyadh'),
    City(name: 'Dubai', country: 'UAE', latitude: 25.2048, longitude: 55.2708, timezone: 'Asia/Dubai'),
    City(name: 'Abu Dhabi', country: 'UAE', latitude: 24.4539, longitude: 54.3773, timezone: 'Asia/Dubai'),
    City(name: 'Doha', country: 'Qatar', latitude: 25.2854, longitude: 51.5310, timezone: 'Asia/Qatar'),
    City(name: 'Kuwait City', country: 'Kuwait', latitude: 29.3759, longitude: 47.9774, timezone: 'Asia/Kuwait'),
    City(name: 'Manama', country: 'Bahrain', latitude: 26.2285, longitude: 50.5860, timezone: 'Asia/Bahrain'),
    City(name: 'Muscat', country: 'Oman', latitude: 23.5880, longitude: 58.3829, timezone: 'Asia/Muscat'),
    City(name: 'Baghdad', country: 'Iraq', latitude: 33.3152, longitude: 44.3661, timezone: 'Asia/Baghdad'),
    City(name: 'Amman', country: 'Jordan', latitude: 31.9454, longitude: 35.9284, timezone: 'Asia/Amman'),
    City(name: 'Beirut', country: 'Lebanon', latitude: 33.8938, longitude: 35.5018, timezone: 'Asia/Beirut'),
    City(name: 'Damascus', country: 'Syria', latitude: 33.5138, longitude: 36.2765, timezone: 'Asia/Damascus'),
    City(name: 'Jerusalem', country: 'Palestine', latitude: 31.7683, longitude: 35.2137, timezone: 'Asia/Jerusalem'),
    City(name: 'Tehran', country: 'Iran', latitude: 35.6892, longitude: 51.3890, timezone: 'Asia/Tehran'),

    // South Asia
    City(name: 'Karachi', country: 'Pakistan', latitude: 24.8607, longitude: 67.0011, timezone: 'Asia/Karachi'),
    City(name: 'Lahore', country: 'Pakistan', latitude: 31.5204, longitude: 74.3587, timezone: 'Asia/Karachi'),
    City(name: 'Islamabad', country: 'Pakistan', latitude: 33.6844, longitude: 73.0479, timezone: 'Asia/Karachi'),
    City(name: 'Peshawar', country: 'Pakistan', latitude: 34.0151, longitude: 71.5249, timezone: 'Asia/Karachi'),
    City(name: 'Delhi', country: 'India', latitude: 28.6139, longitude: 77.2090, timezone: 'Asia/Kolkata'),
    City(name: 'Mumbai', country: 'India', latitude: 19.0760, longitude: 72.8777, timezone: 'Asia/Kolkata'),
    City(name: 'Hyderabad', country: 'India', latitude: 17.3850, longitude: 78.4867, timezone: 'Asia/Kolkata'),
    City(name: 'Dhaka', country: 'Bangladesh', latitude: 23.8103, longitude: 90.4125, timezone: 'Asia/Dhaka'),
    City(name: 'Chittagong', country: 'Bangladesh', latitude: 22.3569, longitude: 91.7832, timezone: 'Asia/Dhaka'),
    City(name: 'Kabul', country: 'Afghanistan', latitude: 34.5553, longitude: 69.2075, timezone: 'Asia/Kabul'),
    City(name: 'Colombo', country: 'Sri Lanka', latitude: 6.9271, longitude: 79.8612, timezone: 'Asia/Colombo'),

    // Southeast Asia
    City(name: 'Jakarta', country: 'Indonesia', latitude: -6.2088, longitude: 106.8456, timezone: 'Asia/Jakarta'),
    City(name: 'Surabaya', country: 'Indonesia', latitude: -7.2575, longitude: 112.7521, timezone: 'Asia/Jakarta'),
    City(name: 'Bandung', country: 'Indonesia', latitude: -6.9175, longitude: 107.6191, timezone: 'Asia/Jakarta'),
    City(name: 'Kuala Lumpur', country: 'Malaysia', latitude: 3.1390, longitude: 101.6869, timezone: 'Asia/Kuala_Lumpur'),
    City(name: 'Singapore', country: 'Singapore', latitude: 1.3521, longitude: 103.8198, timezone: 'Asia/Singapore'),
    City(name: 'Manila', country: 'Philippines', latitude: 14.5995, longitude: 120.9842, timezone: 'Asia/Manila'),
    City(name: 'Bangkok', country: 'Thailand', latitude: 13.7563, longitude: 100.5018, timezone: 'Asia/Bangkok'),
    City(name: 'Brunei', country: 'Brunei', latitude: 4.9031, longitude: 114.9398, timezone: 'Asia/Brunei'),

    // Africa
    City(name: 'Cairo', country: 'Egypt', latitude: 30.0444, longitude: 31.2357, timezone: 'Africa/Cairo'),
    City(name: 'Alexandria', country: 'Egypt', latitude: 31.2001, longitude: 29.9187, timezone: 'Africa/Cairo'),
    City(name: 'Casablanca', country: 'Morocco', latitude: 33.5731, longitude: -7.5898, timezone: 'Africa/Casablanca'),
    City(name: 'Rabat', country: 'Morocco', latitude: 34.0209, longitude: -6.8416, timezone: 'Africa/Casablanca'),
    City(name: 'Algiers', country: 'Algeria', latitude: 36.7538, longitude: 3.0588, timezone: 'Africa/Algiers'),
    City(name: 'Tunis', country: 'Tunisia', latitude: 36.8065, longitude: 10.1815, timezone: 'Africa/Tunis'),
    City(name: 'Tripoli', country: 'Libya', latitude: 32.8872, longitude: 13.1913, timezone: 'Africa/Tripoli'),
    City(name: 'Khartoum', country: 'Sudan', latitude: 15.5007, longitude: 32.5599, timezone: 'Africa/Khartoum'),
    City(name: 'Lagos', country: 'Nigeria', latitude: 6.5244, longitude: 3.3792, timezone: 'Africa/Lagos'),
    City(name: 'Kano', country: 'Nigeria', latitude: 12.0022, longitude: 8.5920, timezone: 'Africa/Lagos'),
    City(name: 'Nairobi', country: 'Kenya', latitude: -1.2921, longitude: 36.8219, timezone: 'Africa/Nairobi'),
    City(name: 'Mogadishu', country: 'Somalia', latitude: 2.0469, longitude: 45.3182, timezone: 'Africa/Mogadishu'),
    City(name: 'Dakar', country: 'Senegal', latitude: 14.7167, longitude: -17.4677, timezone: 'Africa/Dakar'),
    City(name: 'Johannesburg', country: 'South Africa', latitude: -26.2041, longitude: 28.0473, timezone: 'Africa/Johannesburg'),
    City(name: 'Cape Town', country: 'South Africa', latitude: -33.9249, longitude: 18.4241, timezone: 'Africa/Johannesburg'),

    // Europe
    City(name: 'Istanbul', country: 'Türkiye', latitude: 41.0082, longitude: 28.9784, timezone: 'Europe/Istanbul'),
    City(name: 'Ankara', country: 'Türkiye', latitude: 39.9334, longitude: 32.8597, timezone: 'Europe/Istanbul'),
    City(name: 'London', country: 'United Kingdom', latitude: 51.5074, longitude: -0.1278, timezone: 'Europe/London'),
    City(name: 'Birmingham', country: 'United Kingdom', latitude: 52.4862, longitude: -1.8904, timezone: 'Europe/London'),
    City(name: 'Manchester', country: 'United Kingdom', latitude: 53.4808, longitude: -2.2426, timezone: 'Europe/London'),
    City(name: 'Glasgow', country: 'United Kingdom', latitude: 55.8642, longitude: -4.2518, timezone: 'Europe/London'),
    City(name: 'Paris', country: 'France', latitude: 48.8566, longitude: 2.3522, timezone: 'Europe/Paris'),
    City(name: 'Marseille', country: 'France', latitude: 43.2965, longitude: 5.3698, timezone: 'Europe/Paris'),
    City(name: 'Berlin', country: 'Germany', latitude: 52.5200, longitude: 13.4050, timezone: 'Europe/Berlin'),
    City(name: 'Frankfurt', country: 'Germany', latitude: 50.1109, longitude: 8.6821, timezone: 'Europe/Berlin'),
    City(name: 'Amsterdam', country: 'Netherlands', latitude: 52.3676, longitude: 4.9041, timezone: 'Europe/Amsterdam'),
    City(name: 'Brussels', country: 'Belgium', latitude: 50.8503, longitude: 4.3517, timezone: 'Europe/Brussels'),
    City(name: 'Stockholm', country: 'Sweden', latitude: 59.3293, longitude: 18.0686, timezone: 'Europe/Stockholm'),
    City(name: 'Oslo', country: 'Norway', latitude: 59.9139, longitude: 10.7522, timezone: 'Europe/Oslo'),
    City(name: 'Copenhagen', country: 'Denmark', latitude: 55.6761, longitude: 12.5683, timezone: 'Europe/Copenhagen'),
    City(name: 'Helsinki', country: 'Finland', latitude: 60.1699, longitude: 24.9384, timezone: 'Europe/Helsinki'),
    City(name: 'Moscow', country: 'Russia', latitude: 55.7558, longitude: 37.6173, timezone: 'Europe/Moscow'),
    City(name: 'Sarajevo', country: 'Bosnia', latitude: 43.8563, longitude: 18.4131, timezone: 'Europe/Sarajevo'),
    City(name: 'Tromsø', country: 'Norway', latitude: 69.6492, longitude: 18.9553, timezone: 'Europe/Oslo'),
    City(name: 'Reykjavík', country: 'Iceland', latitude: 64.1466, longitude: -21.9426, timezone: 'Atlantic/Reykjavik'),

    // Americas
    City(name: 'New York', country: 'United States', latitude: 40.7128, longitude: -74.0060, timezone: 'America/New_York'),
    City(name: 'Chicago', country: 'United States', latitude: 41.8781, longitude: -87.6298, timezone: 'America/Chicago'),
    City(name: 'Houston', country: 'United States', latitude: 29.7604, longitude: -95.3698, timezone: 'America/Chicago'),
    City(name: 'Detroit', country: 'United States', latitude: 42.3314, longitude: -83.0458, timezone: 'America/Detroit'),
    City(name: 'Los Angeles', country: 'United States', latitude: 34.0522, longitude: -118.2437, timezone: 'America/Los_Angeles'),
    City(name: 'Toronto', country: 'Canada', latitude: 43.6532, longitude: -79.3832, timezone: 'America/Toronto'),
    City(name: 'Montreal', country: 'Canada', latitude: 45.5017, longitude: -73.5673, timezone: 'America/Toronto'),
    City(name: 'Edmonton', country: 'Canada', latitude: 53.5461, longitude: -113.4938, timezone: 'America/Edmonton'),

    // Oceania
    City(name: 'Sydney', country: 'Australia', latitude: -33.8688, longitude: 151.2093, timezone: 'Australia/Sydney'),
    City(name: 'Melbourne', country: 'Australia', latitude: -37.8136, longitude: 144.9631, timezone: 'Australia/Melbourne'),
    City(name: 'Perth', country: 'Australia', latitude: -31.9505, longitude: 115.8605, timezone: 'Australia/Perth'),
    City(name: 'Auckland', country: 'New Zealand', latitude: -36.8485, longitude: 174.7633, timezone: 'Pacific/Auckland'),
  ];

  /// Cities matching [query] by name or country, case-insensitively.
  static List<City> search(String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return cities;

    return cities
        .where((city) =>
            city.name.toLowerCase().contains(trimmed) ||
            city.country.toLowerCase().contains(trimmed))
        .toList(growable: false);
  }

  /// The catalogue entry closest to a coordinate.
  ///
  /// Used to resolve a GPS fix to an IANA timezone. Distance is computed with
  /// the haversine formula rather than naive Pythagoras, which would be badly
  /// wrong at high latitudes where a degree of longitude is far shorter than a
  /// degree of latitude — exactly where our users have the most trouble.
  static City nearest(double latitude, double longitude) {
    City? closest;
    double smallestDistance = double.infinity;

    for (final city in cities) {
      final distance =
          _haversineKm(latitude, longitude, city.latitude, city.longitude);
      if (distance < smallestDistance) {
        smallestDistance = distance;
        closest = city;
      }
    }

    // The catalogue is a non-empty compile-time constant, so this is
    // unreachable; the assertion documents the invariant.
    assert(closest != null, 'City catalogue must not be empty');
    return closest!;
  }

  static double _haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadiusKm = 6371.0;

    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180.0;
}
