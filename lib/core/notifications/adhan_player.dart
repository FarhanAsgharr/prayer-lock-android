/// Adhan playback.
///
/// Two delivery paths exist, deliberately:
///
/// 1. The notification channel's own sound, used when the app is not running.
///    This is the path that matters most — the adhan must sound whether or not
///    the app happens to be open.
/// 2. This in-app player, used when the app is foregrounded at prayer time, so
///    the user gets a full-length adhan with a visible stop control rather
///    than a truncated notification tone.
///
/// Asset licensing: no adhan recording is bundled. Recordings of well-known
/// muezzins are typically copyrighted, and shipping one without a licence
/// would expose the project to a takedown. Supply a licensed recording as
/// described in [assetPath] and as `android/app/src/main/res/raw/adhan.mp3`.
/// Until then playback degrades to the system notification sound, which is
/// stated honestly in the UI rather than failing silently.
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

class AdhanPlayer {
  AdhanPlayer({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  /// Bundled adhan recording. Absent by default; see the library docs.
  static const String assetPath = 'audio/adhan.mp3';

  final AudioPlayer _player;
  bool? _assetAvailable;

  /// Whether a licensed adhan recording is bundled.
  ///
  /// Checked once and cached. The UI uses this to explain that the default
  /// notification sound will be used, rather than claiming an adhan will play
  /// and then playing nothing.
  Future<bool> isAdhanAvailable() async {
    final cached = _assetAvailable;
    if (cached != null) return cached;

    try {
      await rootBundle.load('assets/$assetPath');
      _assetAvailable = true;
    } on FlutterError {
      _assetAvailable = false;
    }
    return _assetAvailable!;
  }

  /// Play the adhan, if one is bundled.
  ///
  /// Returns false when no recording is available, so the caller can fall back
  /// rather than assume sound was produced.
  Future<bool> play() async {
    if (!await isAdhanAvailable()) return false;

    try {
      // Alarm context so the adhan is audible in Do Not Disturb, matching the
      // expectation that a call to prayer is not an ordinary notification.
      await _player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: true,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.alarm,
            audioFocus: AndroidAudioFocus.gainTransient,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {AVAudioSessionOptions.duckOthers},
          ),
        ),
      );

      await _player.play(AssetSource(assetPath));
      return true;
    } on Exception catch (error) {
      // Audio failure must never break the prayer flow; the notification has
      // already been delivered by this point.
      debugPrint('Adhan playback failed: $error');
      return false;
    }
  }

  Future<void> stop() => _player.stop();

  Stream<PlayerState> get stateStream => _player.onPlayerStateChanged;

  Future<void> dispose() => _player.dispose();
}
