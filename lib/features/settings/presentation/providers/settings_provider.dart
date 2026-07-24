/// Settings state.
///
/// Everything downstream — the schedule, notifications, the blocked-app list —
/// derives from this provider, so a settings change propagates automatically
/// rather than requiring each consumer to be notified by hand.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/config/locale_config.dart';
import '../../../jumuah/domain/entities/jumuah_settings.dart';
import '../../../prayer_times/domain/entities/prayer_enums.dart';
import '../../../sections/domain/entities/islamic_section.dart';
import '../../../sections/domain/entities/prayer_grouping.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/entities/app_settings.dart';

/// Overridden in main() with the resolved instance, so the app never has to
/// render a loading state purely to read preferences.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main()',
  ),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(sharedPreferencesProvider)),
);

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(settingsRepositoryProvider).load();

  Future<void> _update(AppSettings next) async {
    state = next;
    await ref.read(settingsRepositoryProvider).save(next);
  }

  Future<void> setLocation(PrayerLocation location) =>
      _update(state.copyWith(location: location));

  Future<void> setCalculationMethod(CalculationMethod method) =>
      _update(state.copyWith(calculationMethod: method));

  /// Adopt an Islamic section and take its suggested defaults.
  ///
  /// This is the one action allowed to move settings the user may have changed,
  /// because selecting a section *is* asking for its defaults. Everything it
  /// changes remains editable afterwards, and the settings screen reports what
  /// moved rather than changing it silently.
  Future<void> setSection(SectionIdentity section) =>
      _update(state.withSection(section));

  /// Name a user-defined section without disturbing anything else.
  ///
  /// Distinct from [setSection] so renaming "Other" does not reset the Asr
  /// convention and grouping the user has already tuned.
  Future<void> setCustomSectionLabel(String label) => _update(
        state.copyWith(section: SectionIdentity.custom(label)),
      );

  /// Override the Asr convention the section suggests.
  Future<void> setMadhab(Madhab madhab) =>
      _update(state.copyWith(madhabOverride: madhab));

  /// Override which prayers are combined.
  Future<void> setPrayerGrouping(PrayerGrouping grouping) =>
      _update(state.copyWith(prayerGroupingOverride: grouping));

  /// Turn one pair on or off, leaving the other as it is.
  ///
  /// Expressed as a toggle so the two independent switches in the UI cannot
  /// produce a state the grouping enum has no value for.
  Future<void> togglePrayerPair(PrayerPair pair, {required bool enabled}) =>
      setPrayerGrouping(state.prayerGrouping.toggle(pair, enabled: enabled));

  /// Whether one verification discharges a whole combined pair.
  Future<void> setCombinedVerification(bool enabled) =>
      _update(state.copyWith(combinedVerification: enabled));

  /// Discard every override and return to what the section suggests.
  Future<void> resetToSectionDefaults() =>
      _update(state.resetToSectionDefaults());

  Future<void> setHighLatitudeRule(HighLatitudeRule rule) =>
      _update(state.copyWith(highLatitudeRule: rule));

  Future<void> setAdjustment(PrayerName prayer, int minutes) {
    final adjustments = Map<PrayerName, int>.from(state.adjustments);
    if (minutes == 0) {
      adjustments.remove(prayer);
    } else {
      adjustments[prayer] = minutes;
    }
    return _update(state.copyWith(adjustments: adjustments));
  }

  /// Set the outermost pre-prayer reminder, rebuilding the ladder beneath it.
  ///
  /// Zero switches pre-prayer reminders off entirely.
  Future<void> setReminderMinutes(int minutes) => _update(
        state.copyWith(
          reminderOffsetsMinutes: AppSettings.reminderLadderFor(minutes),
        ),
      );

  Future<void> setAdhanEnabled(bool enabled) =>
      _update(state.copyWith(adhanEnabled: enabled));

  Future<void> setBlockingEnabled(bool enabled) =>
      _update(state.copyWith(blockingEnabled: enabled));

  Future<void> setGracePeriod(int minutes) =>
      _update(state.copyWith(lockGracePeriodMinutes: minutes));

  Future<void> setMorningProtection(bool enabled) =>
      _update(state.copyWith(morningProtectionEnabled: enabled));

  /// Choose between unlocking on verification and holding for the full window.
  Future<void> setUnlockPolicy(UnlockPolicy policy) =>
      _update(state.copyWith(unlockPolicy: policy));

  /// Whether a missed prayer keeps apps blocked until its qaza is made.
  Future<void> setBlockUntilQazaCompleted(bool enabled) =>
      _update(state.copyWith(blockUntilQazaCompleted: enabled));

  /// Whether to confirm prayer times against the remote service.
  ///
  /// Turning this off does not disable anything: the on-device calculator
  /// produces a complete schedule either way. It only decides which source is
  /// authoritative when the two differ.
  Future<void> setPreferRemotePrayerTimes(bool enabled) =>
      _update(state.copyWith(preferRemotePrayerTimes: enabled));

  Future<void> setNotifyOnWindowEnd(bool enabled) =>
      _update(state.copyWith(notifyOnWindowEnd: enabled));

  /// Change the display language, or follow the device.
  ///
  /// Applied immediately: the app root watches the locale provider, so Arabic
  /// and Urdu flip the layout to right-to-left with no restart.
  Future<void> setLanguage(AppLanguage language) =>
      _update(state.copyWith(language: language));

  /// Replace the whole Jumu'ah preference.
  ///
  /// Written as one operation rather than a setter per field because
  /// [JumuahManager] owns the transitions — it computes the next JumuahSettings
  /// and hands it here, so the rules for "choosing a location clears nothing
  /// else" live in one place instead of being spread across setters.
  Future<void> setJumuahSettings(JumuahSettings jumuah) =>
      _update(state.copyWith(jumuah: jumuah));

  /// Nudge the Hijri date to match a local sighting announcement.
  Future<void> setHijriAdjustment(int days) =>
      _update(state.copyWith(hijriAdjustmentDays: days.clamp(-2, 2)));

  Future<void> setDhikrReminders(bool enabled) =>
      _update(state.copyWith(dhikrRemindersEnabled: enabled));

  Future<void> setQuranReminders(bool enabled) =>
      _update(state.copyWith(quranRemindersEnabled: enabled));

  Future<void> setRequireAiVerification(bool enabled) =>
      _update(state.copyWith(requireAiVerification: enabled));

  Future<void> setBlockedPackages(Set<String> packages) =>
      _update(state.copyWith(blockedPackages: packages));

  Future<void> toggleBlockedPackage(String packageName) {
    final packages = Set<String>.from(state.blockedPackages);
    if (!packages.remove(packageName)) packages.add(packageName);
    return _update(state.copyWith(blockedPackages: packages));
  }

  Future<void> completeOnboarding() =>
      _update(state.copyWith(onboardingComplete: true));
}
