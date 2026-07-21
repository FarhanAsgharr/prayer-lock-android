/// Settings state.
///
/// Everything downstream — the schedule, notifications, the blocked-app list —
/// derives from this provider, so a settings change propagates automatically
/// rather than requiring each consumer to be notified by hand.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../prayer_times/domain/entities/prayer_enums.dart';
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

  Future<void> setMadhab(Madhab madhab) =>
      _update(state.copyWith(madhab: madhab));

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

  Future<void> setReminderMinutes(int minutes) =>
      _update(state.copyWith(reminderMinutesBefore: minutes));

  Future<void> setAdhanEnabled(bool enabled) =>
      _update(state.copyWith(adhanEnabled: enabled));

  Future<void> setBlockingEnabled(bool enabled) =>
      _update(state.copyWith(blockingEnabled: enabled));

  Future<void> setGracePeriod(int minutes) =>
      _update(state.copyWith(lockGracePeriodMinutes: minutes));

  Future<void> setMorningProtection(bool enabled) =>
      _update(state.copyWith(morningProtectionEnabled: enabled));

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
