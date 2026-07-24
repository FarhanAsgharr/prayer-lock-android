/// What the rest of the app is allowed to ask for about prayer schedules.
///
/// Deliberately narrow. Callers ask for a day's windows; they never choose a
/// provider, decide whether the cache is fresh, or know that AlAdhan exists.
/// That is what lets the resolution strategy change — a new authority, a
/// different prefetch horizon — without touching the scheduler, the lock
/// orchestrator, or any screen.
library;

import '../entities/prayer_day.dart';
import '../entities/prayer_enums.dart';
import '../entities/prayer_window.dart';

/// A resolved day, with provenance.
class ResolvedPrayerDay {
  const ResolvedPrayerDay({
    required this.windows,
    required this.source,
    required this.isStale,
  });

  final DailyPrayerWindows windows;

  /// Where these times came from.
  final PrayerTimeSource source;

  /// Whether a better version could be obtained with connectivity. Surfaced so
  /// the UI can say "offline times" honestly instead of implying authority it
  /// does not have.
  final bool isStale;
}

abstract interface class PrayerScheduleRepository {
  /// The day's windows for [date], from cache, network or on-device
  /// calculation — whichever answers first under the current settings.
  ///
  /// Never throws for an ordinary failure such as being offline: with a
  /// location configured there is always an answer, because the on-device
  /// calculator is the floor. It throws only when no location is set, which is
  /// a programming error at the call site rather than a runtime condition.
  Future<ResolvedPrayerDay> resolveDay(DateTime date);

  /// [resolveDay] with recorded outcomes merged in, ready for the lock logic.
  Future<PrayerDay> prayerDay(DateTime date);

  /// Ensure the next [days] days are cached, fetching what is missing.
  ///
  /// Returns the number of days newly written. Safe to call repeatedly: days
  /// already cached are not refetched unless [force] is set.
  Future<int> prefetch({
    required DateTime from,
    int days,
    bool force,
  });

  /// Drop cached days that no longer apply — after a location change, a
  /// calculation-method change, or travel across timezones.
  Future<void> invalidate();

  /// Remove cached days past their retention horizon.
  Future<void> evictExpired({DateTime? today});
}
