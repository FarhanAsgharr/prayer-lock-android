/// Provider overrides that let a screen be pumped without a device.
///
/// `sharedPreferencesProvider` deliberately throws when it has not been
/// overridden, so that a missing override in `main()` fails loudly rather than
/// silently reading nothing. That same guard makes every widget test need this
/// one line, which is better here than repeated in each file.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prayer_lock/features/settings/presentation/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<Override> settingsOverrides(SharedPreferences preferences) => [
      sharedPreferencesProvider.overrideWithValue(preferences),
    ];
