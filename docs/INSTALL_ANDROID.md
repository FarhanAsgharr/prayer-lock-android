# Prayer Lock — install on Android

**Version 1.0.0** (versionCode 2001) · package `com.prayerlock.prayer_lock`
Requires **Android 7.0** or newer.

---

## Which file to download

| File | Size | Use it if |
| ---- | ---- | --------- |
| **`PrayerLock-1.0.0-arm64.apk`** | 26 MB | **Almost everyone.** Every Android phone sold since ~2017. |
| `PrayerLock-1.0.0-arm32.apk` | 22 MB | An older or very budget phone that rejects the arm64 file. |
| `PrayerLock-1.0.0-universal.apk` | 71 MB | You don't know the device, or the others refuse to install. Works everywhere. |

If in doubt, take **arm64**. If it will not install, take **universal** — it
contains every architecture and cannot pick wrong.

---

## Installing

1. Copy the `.apk` to the phone (USB, email, Drive, or a direct download link).
2. Tap the file. Android will say the app came from an unknown source.
3. Tap **Settings** in that prompt, and allow installs from whatever app you
   opened the file with (Files, Chrome, Gmail…).
4. Go back and tap **Install**.

This is normal for any app not installed from the Play Store.

---

## After installing — this part matters

The app blocks other apps during prayer. Android does not let it do that
without several permissions that **cannot** be granted by a normal pop-up.
Until they are granted, blocking silently does nothing.

The app walks you through these on first run. Grant all of them:

| Permission | Why it is needed | Where |
| ---------- | ---------------- | ----- |
| **Usage access** | To see which app is in the foreground. Without it, nothing can be blocked. | Settings → Apps → Special access → Usage access |
| **Display over other apps** | To show the prayer screen over a blocked app. | Settings → Apps → Special access → Display over other apps |
| **Alarms & reminders** | So the lock engages *at* the adhan rather than up to 20 minutes late. | Settings → Apps → Prayer Lock → Alarms & reminders |
| **Notifications** | Prayer reminders and the lock status notice. | Prompted on first run |
| **Location** | To calculate prayer times where you are. You can pick a city by hand instead. | Prompted on first run |
| **Battery optimisation: off** | Otherwise Android may freeze the blocking service and enforcement stops with no visible error. | Settings → Apps → Prayer Lock → Battery → Unrestricted |

On **Xiaomi, Huawei, Oppo, Vivo and Samsung**, battery management is more
aggressive than stock Android. Also enable "Autostart" / "Allow background
activity" for Prayer Lock, or the app will be killed overnight and Fajr will not
lock.

---

## Verifying the download

```
shasum -a 256 PrayerLock-1.0.0-arm64.apk
```

Compare against `SHA256SUMS.txt` in this folder.

---

## ⚠️ These builds are signed with the Android **debug** key

Read this before sending the file to anyone else.

The release build currently uses the debug signing key
(`CN=Android Debug`), which is a **publicly known key shipped with the Android
SDK**. Consequences:

- ✅ It installs and runs normally by sideloading.
- ❌ **It cannot be uploaded to the Google Play Store.** Play rejects
  debug-signed uploads outright.
- ❌ **It is not a proof of authorship.** Anyone can sign an APK with the same
  key, so the signature does not establish that a build came from you.
- ⚠️ **Updates will break across machines.** An APK built on a different
  computer has a different debug key, and Android refuses to install an update
  whose signature does not match. The user has to uninstall first, which
  **erases their prayer history**.

**The build is already wired for release signing** — you only need to supply the
key. `android/app/build.gradle.kts` reads `android/key.properties` if it exists
and signs with it; otherwise it falls back to the debug key. So switching to
your real key is **four values in one file, no code changes**:

```bash
# 1. Create your keystore (choose your own passwords):
keytool -genkeypair -v -keystore ~/prayer-lock-upload.jks \
  -alias upload -keyalg RSA -keysize 2048 -validity 10000

# 2. Fill in the four placeholders:
cd mobile/android && cp key.properties.example key.properties
#    edit key.properties → KEYSTORE_FILE, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD

# 3. Build — now signed with your key:
cd .. && flutter build appbundle --release
```

The full walkthrough, including how to verify the build is signed with your key
and not the debug key, is in **[RELEASE_SIGNING.md](RELEASE_SIGNING.md)**.

Keep the keystore and its passwords backed up. **If you lose them**, Play offers
an upload-key reset (recoverable); a self-signed distribution has no recovery,
and sideloaded users would have to uninstall and lose their data.

The keystore is deliberately not created for you — it is a private key, and you
should choose its password rather than inherit one.

---

## Known limits in this build

- **Blocking is Android-only.** iOS needs Apple's Family Controls entitlement.
- **Arabic and Urdu are partially translated.** The Islamic section and prayer
  mode screens, prayer names and grouping labels are translated, and the layout
  correctly flips right-to-left. The dashboard, settings, verification,
  onboarding, qaza and durations screens are still English.
- **The backend is not bundled.** Prayer times, blocking, verification prompts,
  history and statistics all work fully offline on-device. Only cloud sync and
  AI photo verification need a server, configured with
  `--dart-define=API_BASE_URL=…` at build time.

---

## Rebuilding

```bash
cd mobile
flutter pub get
flutter build apk --release                  # one universal APK
flutter build apk --release --split-per-abi  # smaller per-architecture APKs
```

Output lands in `mobile/build/app/outputs/flutter-apk/`.
