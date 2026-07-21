# Adhan audio

No adhan recording is bundled with the app. Recordings of the call to prayer
are typically copyrighted by the muezzin or publisher, so shipping one without
a licence would risk a takedown.

The playback code is complete. Until a licensed recording is added, the app
falls back to the device's default notification sound and states this honestly
rather than pretending an adhan will play.

## To add an adhan

1. Obtain a recording you have the right to distribute.
2. Place it here as `adhan.mp3` (Android) and, for iOS, add `adhan.caf` to the
   iOS project's resources.
3. Rebuild. The app detects the file at runtime and uses it automatically — no
   code change needed.

This file also keeps the `assets/audio/` directory present in git, which does
not track empty directories.
