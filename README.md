# Prayer Lock — Android

Pray on time, with fewer distractions. Prayer Lock detects your prayer times,
temporarily pauses the apps you choose during each prayer, and releases them
once you confirm you have prayed.

This repository is the **Android** app. The iPhone version lives in a separate
repository.

---

## Install it on your phone (easiest)

1. Go to the **[Releases](../../releases)** page of this repository.
2. Download the latest **`PrayerLock.apk`**.
3. Open the file on your Android phone. When it warns about an unknown source,
   tap **Settings → Allow from this source → Install**.
4. Open Prayer Lock and follow the setup.

That's it — no accounts or servers required. Prayer times, reminders, blocking,
verification and statistics all work fully offline on the phone.

## First-time setup

The app walks you through it:

- **Location** — detected automatically or picked from a city list.
- **School** — Hanafi, Shafi'i/Maliki/Hanbali, Ahl-e-Hadith, or Ja'fari (Shia).
- **Calculation method** — match your local mosque.
- **Permissions for blocking** — *Usage access* and *Display over other apps*.
  Without these, blocking cannot work; the app tells you rather than pretending.

## Features

- Accurate prayer times for 12 calculation methods and all four schools
- Reminders before each prayer, and the adhan at prayer time
- App blocking during prayer, released after photo verification
- "Good morning" Fajr protection
- Prayer tracking: streaks, completion rate, weekly/monthly charts
- Works completely offline; data is stored encrypted on the device

---

## Build it yourself

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install)
(3.44+) and the Android SDK.

```bash
flutter pub get

# Debug build and run on a connected device or emulator
flutter run

# Release APK (what the Releases page publishes)
flutter build apk --release
# output: build/app/outputs/flutter-apk/app-release.apk
```

To point the app at a hosted backend (optional — the app is fully functional
offline without one):

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://your-backend.example.com
```

## Automatic releases

Pushing a tag like `v1.0.0` triggers the workflow in
`.github/workflows/release.yml`, which builds the release APK and attaches it to
a GitHub Release automatically. Users then download it from the Releases page.

```bash
git tag v1.0.0
git push origin v1.0.0
```

## Signing for production

The build is signed with debug keys out of the box so `flutter run` works. For a
Play Store or public release, create an upload keystore and reference it from
`android/key.properties` — see
[Flutter's signing guide](https://docs.flutter.dev/deployment/android#signing-the-app).
Never commit the keystore or `key.properties`; both are git-ignored.

## Tests

```bash
flutter test        # Dart unit and widget tests
cd android && ./gradlew test   # Kotlin unit tests (blocking policy, safety allowlist)
```
