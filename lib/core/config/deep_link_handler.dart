/// Receives navigation routes handed over from the native lock screen.
///
/// The lock screen runs in its own Flutter engine and cannot drive this app's
/// router directly. When the user taps "I completed my prayer" there, the
/// native layer opens the main app with a route; this handler delivers that
/// route to GoRouter.
///
/// Two paths are covered. A cold start (app was not running) buffers the route
/// natively until Flutter asks for it. A warm start (app already running,
/// brought to front) pushes the route immediately.
library;

import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class DeepLinkHandler {
  DeepLinkHandler(this._router, {MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'com.prayerlock/navigation';

  final GoRouter _router;
  final MethodChannel _channel;

  /// Begin listening, and drain any route captured before Flutter was ready.
  Future<void> start() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'navigate') {
        final route = call.arguments as String?;
        if (route != null && route.isNotEmpty) _router.push(route);
      }
      return null;
    });

    // A route from a cold start is buffered natively; ask for it once.
    try {
      final initial = await _channel.invokeMethod<String>('consumeInitialRoute');
      if (initial != null && initial.isNotEmpty) _router.push(initial);
    } on MissingPluginException {
      // Non-Android platform, or the native side is absent (tests). Nothing to
      // consume, which is not an error.
    }
  }
}
