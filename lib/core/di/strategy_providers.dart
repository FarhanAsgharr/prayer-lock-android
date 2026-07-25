/// One place where every strategy registry is bound.
///
/// The five registries are independent of each other, and each already has a
/// sensible default, so nothing here is required for the app to run. What it
/// buys is a single seam: a test, a regional build, or a future feature flag
/// substitutes an arrangement by overriding one provider, and every consumer
/// downstream sees the substitution without knowing it happened.
///
/// Kept in `core/di` rather than in each feature because the point is to be
/// able to see the whole set at once. A reader asking "what behaviour of this
/// app is pluggable" gets an answer in one screen.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/blocking/domain/strategies/blocking_strategy.dart';
import '../../features/prayer_times/domain/strategies/calculation_strategy.dart';
import '../../features/prayer_times/domain/strategies/prayer_mode_strategy.dart';
import '../../features/sections/domain/strategies/islamic_section_strategy.dart';
import '../../features/settings/presentation/providers/settings_provider.dart';
import '../notifications/strategies/notification_strategy.dart';

/// Per-section defaults.
final islamicSectionRegistryProvider = Provider<IslamicSectionRegistry>(
  (ref) => IslamicSectionRegistry.standard(),
);

/// How a day's prayers become slots.
final prayerModeRegistryProvider = Provider<PrayerModeRegistry>(
  (ref) => PrayerModeRegistry.standard(),
);

/// How each authority defines the times.
final calculationRegistryProvider = Provider<CalculationRegistry>(
  (ref) => CalculationRegistry.standard(),
);

/// What ends a lock.
final blockingRegistryProvider = Provider<BlockingRegistry>(
  (ref) => BlockingRegistry.standard(),
);

/// What each notice says.
final notificationRegistryProvider = Provider<NotificationRegistry>(
  (ref) => NotificationRegistry.standard(),
);

// -- resolved strategies -----------------------------------------------------
//
// Each of these watches the settings that select an arrangement, so a widget
// depending on one rebuilds when the user changes the relevant setting and not
// when they change anything else.

/// The arrangement in force for the user's current grouping.
final prayerModeStrategyProvider = Provider<PrayerModeStrategy>((ref) {
  final grouping = ref.watch(settingsProvider).prayerGrouping;
  return ref.watch(prayerModeRegistryProvider).forGrouping(grouping);
});

/// The authority in force for the user's current method.
final calculationStrategyProvider = Provider<CalculationStrategy>((ref) {
  final method = ref.watch(settingsProvider).calculationMethod;
  return ref.watch(calculationRegistryProvider).forMethod(method);
});

/// The unlock arrangement in force.
final blockingStrategyProvider = Provider<BlockingStrategy>((ref) {
  final policy = ref.watch(settingsProvider).unlockPolicy;
  return ref.watch(blockingRegistryProvider).forPolicy(policy);
});

/// The defaults for the user's selected section.
///
/// Returns null when no section has been chosen. Null is meaningful: it is the
/// difference between "this user follows a section whose defaults happen to
/// match ours" and "this user has not told us", and the settings screen shows
/// different text for each.
final islamicSectionStrategyProvider = Provider<IslamicSectionStrategy?>((ref) {
  final identity = ref.watch(settingsProvider).section;
  if (!identity.isChosen) return null;
  return ref.watch(islamicSectionRegistryProvider).forSection(identity.section);
});
