/// Riverpod wiring for the Islamic calendar.
///
/// The Hijri date is derived from the *local* date at the user's configured
/// location, not the device's, so a traveller sees the day they are living in —
/// the same rule the prayer schedule follows.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../prayer_times/presentation/providers/prayer_times_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/hijri_date.dart';
import '../../domain/entities/islamic_occasion.dart';
import '../../domain/usecases/ramadan_status.dart';

/// Today's Hijri date.
final hijriDateProvider = Provider<HijriDate>((ref) {
  final adjustment = ref.watch(settingsProvider).hijriAdjustmentDays;

  // The user's nudge is applied to the Gregorian date before conversion, which
  // is the only place it can be applied without inventing a Hijri arithmetic
  // that disagrees with itself.
  final date = ref.watch(localDateProvider).add(Duration(days: adjustment));
  return HijriDate.fromGregorian(date);
});

/// Occasions falling today — Ramadan, an Eid, a White Day, and so on.
final todaysOccasionsProvider = Provider<List<IslamicOccasion>>(
  (ref) => IslamicOccasions.on(ref.watch(hijriDateProvider)),
);

/// Ramadan state, with Sehri and Iftar bound to today's computed prayer times.
final ramadanStatusProvider = Provider<RamadanStatus>((ref) {
  return IslamicDayStatus.ramadanAt(
    hijri: ref.watch(hijriDateProvider),
    windows: ref.watch(todayWindowsProvider),
    now: ref.watch(nowProvider),
  );
});

/// Eid state, including the countdown to the next one.
final eidStatusProvider = Provider<EidStatus>((ref) {
  return IslamicDayStatus.eid(
    hijri: ref.watch(hijriDateProvider),
    windows: ref.watch(todayWindowsProvider),
  );
});

/// Whether today is in Ramadan. Convenience for widgets that only need the flag.
final isRamadanProvider = Provider<bool>(
  (ref) => ref.watch(ramadanStatusProvider).isRamadan,
);

/// Whether today is an Eid.
final isEidProvider = Provider<bool>(
  (ref) => ref.watch(eidStatusProvider).isEid,
);
