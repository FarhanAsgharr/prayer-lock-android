/// The single entry point for everything Jumu'ah.
///
/// Every other part of the app asks this class its questions — "is today
/// Jumu'ah?", "what should I call the Dhuhr slot?", "should I prompt for a
/// location?" — rather than checking the weekday itself. That is the whole
/// point: Friday logic exists in [FridayDetector] and [JumuahScheduler], and
/// nothing else in the codebase branches on a day of the week.
///
/// It is deliberately free of Riverpod, Flutter and I/O so the rules can be
/// tested directly. The provider layer wires it to real settings; tests hand it
/// a repository and a fixed clock.
library;

import '../../../prayer_times/domain/entities/prayer_window.dart';
import '../../data/repositories/jumuah_preference_repository.dart';
import '../entities/jumuah_settings.dart';
import '../entities/mosque_profile.dart';
import 'friday_detector.dart';
import 'jumuah_scheduler.dart';

/// What the UI needs to know about Jumu'ah right now.
class JumuahStatus {
  const JumuahStatus({
    required this.isFriday,
    required this.isActive,
    required this.needsLocationChoice,
    this.mosque,
  });

  /// Whether the local date is a Friday.
  final bool isFriday;

  /// Whether Jumu'ah is replacing Dhuhr today. False on non-Fridays, when the
  /// feature is off, and when no location has been chosen yet.
  final bool isActive;

  /// Whether to ask the user where they are praying.
  final bool needsLocationChoice;

  /// The mosque in force today, if any.
  final MosqueProfile? mosque;

  /// What to show under the Jumu'ah card.
  String? get mosqueName => mosque?.displayName;
}

class JumuahManager {
  JumuahManager(this._repository);

  final JumuahPreferenceRepository _repository;

  JumuahSettings get settings => _repository.read();

  /// Whether [date] is a Friday. Exposed so callers never import
  /// [FridayDetector] directly and start hand-rolling weekday checks.
  bool isFriday(DateTime date) => FridayDetector.isFriday(date);

  /// The Jumu'ah picture for [date].
  JumuahStatus statusFor(DateTime date) {
    final current = settings;
    final friday = FridayDetector.isFriday(date);

    return JumuahStatus(
      isFriday: friday,
      // Active only on a Friday, only when enabled, and only once a location
      // is chosen — a half-configured feature must not silently move Dhuhr.
      isActive: friday && current.isActive,
      // Asked only on the day it matters. Prompting on a Tuesday for a
      // decision that takes effect on Friday is noise.
      needsLocationChoice: friday && current.needsMosqueChoice,
      mosque: friday ? current.activeMosque : null,
    );
  }

  /// Apply the user's profile to a day's windows.
  ///
  /// A no-op on any day that is not a Friday, or when Jumu'ah is off, so
  /// callers can invoke it unconditionally and stay free of weekday logic.
  DailyPrayerWindows applyTo(
    DailyPrayerWindows windows, {
    required String timezone,
  }) =>
      JumuahScheduler.applyTo(
        windows: windows,
        settings: settings,
        timezone: timezone,
      );

  /// Apply, and report what happened — for the settings screen's warning when
  /// a configured time had to be clamped into Dhuhr's window.
  JumuahScheduleResult applyWithResult(
    DailyPrayerWindows windows, {
    required String timezone,
  }) =>
      JumuahScheduler.apply(
        windows: windows,
        settings: settings,
        timezone: timezone,
      );

  // -- preference changes -------------------------------------------------

  /// Record where the user prays. This is the answer to the first-Friday
  /// prompt, and it is remembered for every Friday after.
  Future<void> chooseMosque(String mosqueId) =>
      _repository.write(settings.selecting(mosqueId));

  /// Use a mosque for today only, leaving the standing preference alone.
  ///
  /// What the "you appear to be in a different city" prompt does — the user is
  /// elsewhere this week, not permanently.
  Future<void> useMosqueForToday(String mosqueId) =>
      _repository.write(settings.usingForToday(mosqueId));

  /// Add or update a mosque.
  Future<void> saveMosque(MosqueProfile mosque) =>
      _repository.write(settings.withMosque(mosque));

  /// Remove a mosque. The last one cannot be removed.
  Future<void> deleteMosque(String mosqueId) =>
      _repository.write(settings.withoutMosque(mosqueId));

  Future<void> setSilenceDuringJumuah(bool enabled) =>
      _repository.write(settings.copyWith(silenceDuringJumuah: enabled));

  Future<void> setSmartLocationPrompts(bool enabled) =>
      _repository.write(settings.copyWith(smartLocationPrompts: enabled));

  Future<void> setEnabled(bool enabled) =>
      _repository.write(settings.copyWith(enabled: enabled));

  /// Forget the chosen location so the prompt appears again next Friday.
  Future<void> resetSelection() =>
      _repository.write(settings.clearSelection());

  /// Restore the seeded mosques and their shipped times.
  ///
  /// Mosques the user added themselves are kept — resetting times should not
  /// silently delete a mosque they created.
  Future<void> resetSeededMosques() {
    var next = settings;
    for (final seeded in MosqueProfile.defaults()) {
      if (next.mosqueById(seeded.id) != null) next = next.withMosque(seeded);
    }
    return _repository.write(next);
  }
}
