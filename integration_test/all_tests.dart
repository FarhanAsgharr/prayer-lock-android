/// Runs every end-to-end suite in one binding.
///
/// `flutter test integration_test` discovers each `*_test.dart` file, but a
/// single entry point is what a CI job and `flutter drive` target, and it keeps
/// the whole suite runnable with one command against one device. Each imported
/// file registers its own tests when its `main()` is called.
library;

import 'app_startup_test.dart' as app_startup;
import 'blocking_verification_test.dart' as blocking;
import 'jumuah_flow_test.dart' as jumuah;
import 'onboarding_test.dart' as onboarding;
import 'settings_flows_test.dart' as settings;

void main() {
  app_startup.main();
  onboarding.main();
  settings.main();
  jumuah.main();
  blocking.main();
}
