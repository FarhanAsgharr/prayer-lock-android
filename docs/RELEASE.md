# Release guide

Production build, publish, versioning, and recovery procedures for the Android
app. Signing is covered separately in [RELEASE_SIGNING.md](RELEASE_SIGNING.md);
the Play Store listing checklist is in
[PLAY_STORE_CHECKLIST.md](PLAY_STORE_CHECKLIST.md).

Every command assumes you are in the `mobile/` directory unless stated.

---

## Building

### Release APK (for sideloading / direct download)

```bash
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
```

A single universal APK (~77 MB). Good for a direct download link or testing on a
device. **Not** the artifact you upload to Play.

Split per-ABI APKs (smaller downloads, if you distribute APKs yourself):

```bash
flutter build apk --release --split-per-abi
# → app-armeabi-v7a-release.apk, app-arm64-v8a-release.apk, app-x86_64-release.apk
```

### Release AAB (for the Play Store)

```bash
flutter build appbundle --release
# → build/app/outputs/bundle/release/app-release.aab
```

The Android App Bundle (~69 MB). Google generates per-device APKs from it, so
each user downloads far less than the universal APK. **This is what Play
accepts.**

### Verify a build before shipping

```bash
# 1. It is signed with YOUR key (not CN=Android Debug) — see RELEASE_SIGNING.md.
# 2. It installs and launches:
adb install build/app/outputs/flutter-apk/app-release.apk
adb shell am start -n com.prayerlock.prayer_lock/.MainActivity
adb logcat -d | grep -i "FATAL"     # must print nothing
```

---

## Versioning

The single source of truth is **one line** in `mobile/pubspec.yaml`:

```yaml
version: 1.0.0+1
#        ^^^^^ ^
#        name  code
```

- **versionName** (`1.0.0`) — the human version shown to users. Use semantic
  versioning: `MAJOR.MINOR.PATCH`.
- **versionCode** (`+1`) — an integer Play uses to order releases. **It must
  increase on every upload.** Play rejects an AAB whose versionCode is ≤ the
  highest already uploaded.

Gradle reads both from Flutter automatically (`flutter.versionName`,
`flutter.versionCode`); you never edit `build.gradle.kts` for a version bump.

**Bump procedure for each release:**

```yaml
# Patch release:   1.0.0+1  → 1.0.1+2
# Minor release:   1.0.1+2  → 1.1.0+3
# Major release:   1.1.0+3  → 2.0.0+4
```

Always increment the `+code` even for a re-upload of the same version name.

---

## Play Store upload

1. Complete [PLAY_STORE_CHECKLIST.md](PLAY_STORE_CHECKLIST.md) (listing, data
   safety, content rating) — required before the first release.
2. Build the AAB (above) with your real signing key.
3. Play Console → your app → **Production** (or Internal testing first) →
   **Create new release**.
4. Upload `app-release.aab`.
5. Fill in the release notes, review, and roll out.

**First upload:** enable **Play App Signing** when prompted — Google manages the
distribution key and your upload key only authenticates uploads. This is the
recommended, near-universal default.

**Recommended path:** Internal testing → Closed testing → Production, so a bad
build reaches you before it reaches everyone.

---

## Updating existing users

Users update through the Play Store automatically once you roll out a release
with a higher versionCode. Two rules keep updates non-destructive:

1. **Same signing key every time.** An APK/AAB signed with a different key than
   the installed version will not install as an update — Android treats it as a
   different app. With Play App Signing this is handled for you as long as you
   keep uploading with the same upload key.
2. **Additive database migrations only.** The on-device SQLCipher schema is
   versioned (`_schemaVersion` in `app_database.dart`) with numbered migrations.
   Adding columns/tables is safe; never rename or drop a column a shipped
   version reads, or an in-place update will crash on first launch. New
   migrations are applied automatically on update — no user action.

Staged rollout (Play Console → release → **rollout percentage**) is recommended
for anything beyond a trivial change: ship to 10–20% first, watch the crash
rate, then expand.

---

## Backup

Two independent things are backed up, on different schedules:

### The user's on-device data (automatic)

Android Auto Backup covers prayer history and settings, governed by
`android/app/src/main/res/xml/backup_rules.xml` and `data_extraction_rules.xml`.
Deliberately **excluded** from backup:

- the SQLCipher database key (in `flutter_secure_storage`) — backing up the key
  would defeat encrypting the database;
- the native schedule mirror — a disposable projection Dart rebuilds on launch.

The user needs no action. On a new device, Play restores history and settings;
the database key is re-derived on first launch.

### Your release artifacts and signing key (manual — do this)

- **Keystore + passwords:** back up `prayer-lock-upload.jks` and its passwords
  to a password manager and a second offline location. Losing them means an
  upload-key reset (recoverable) or, for a self-signed distribution, an
  unrecoverable inability to update. **This is the single most important thing
  to back up.**
- **Each shipped AAB:** keep the exact `app-release.aab` for every published
  versionCode, so you can re-list or diagnose a specific release. Play retains
  them too, but a local copy is cheap insurance.

---

## Restore

| To restore… | Do this |
|---|---|
| A user's data on a new phone | Nothing — Play Auto Backup restores it on install. History and settings return; the DB key re-derives. |
| Your ability to publish after losing the upload key | Play Console → App integrity → **request upload key reset**. Google issues a new upload certificate; your app and its users are unaffected. |
| A specific past release | Re-upload the retained AAB for that versionCode, or roll back (below). |

---

## Disaster recovery

| Scenario | Impact | Recovery |
|---|---|---|
| **A release crashes on launch** | Users on that version cannot open the app. | Play Console → **halt rollout** immediately. Then either roll back (below) or ship a fixed build with a higher versionCode. A staged rollout limits blast radius to the rollout %. |
| **You lose the upload key** | Cannot publish updates. | Play upload-key reset (see Restore). Users are unaffected in the meantime. |
| **You lose the Google-managed app-signing key** | Only possible if you opted out of Play App Signing. Unrecoverable — you would have to publish a new app listing. | **Prevention is the only cure: use Play App Signing.** |
| **Backend is down** | Prayer times fall back to on-device calculation; verification fails open (the prayer is recorded, confirmed later). The app keeps working offline. | Fix the backend (see [BACKEND_DEPLOYMENT.md](BACKEND_DEPLOYMENT.md)); no app release needed. |
| **A bad on-device migration ships** | App crashes on update for users on the old schema. | Ship a hotfix migration that repairs the state, higher versionCode. Prevention: migrations are additive-only and covered by tests. |

### Rolling back a release

Play does not let you re-activate an old AAB directly. To "roll back":

1. Halt the bad rollout.
2. Take the previous good release's source (git tag), **bump the versionCode
   above the bad one** (e.g. bad was `+5`, ship `+6`), rebuild, and upload.
3. Roll out. Users move forward onto the known-good code with a new versionCode.

This is why every published versionCode's source should be tagged in git:

```bash
git tag -a v1.0.0 -m "Play release 1.0.0 (versionCode 1)"
git push origin v1.0.0
```
