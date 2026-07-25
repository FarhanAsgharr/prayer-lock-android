/// Diagnostic logging that compiles out of release builds.
///
/// Every diagnostic in this app is for a developer watching a debug run — the
/// schedule that was written, the notification that could not be scheduled, the
/// error a background path swallowed. None of it is wanted in a release build:
/// there is no log sink a user's device reports back to, so in production these
/// lines would only leak internal detail to logcat and cost cycles formatting
/// strings nobody reads.
///
/// `kDebugMode` is a compile-time constant, so in a release build the call and
/// its string interpolation are tree-shaken away entirely — not merely skipped
/// at runtime. Use this instead of `debugPrint`/`print` for anything
/// diagnostic.
library;

import 'package:flutter/foundation.dart';

/// Log a diagnostic line in debug builds; a no-op in release.
void logDiagnostic(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}
