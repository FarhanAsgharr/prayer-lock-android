# Release signing

Everything here is **copy-paste ready**. It requires exactly one thing that
cannot be done for you: **you** must create the private keystore and choose its
passwords. A private signing key is yours alone — anyone who has it can publish
updates to your app as you, so it is deliberately never generated, stored, or
committed by anyone but you.

Once the keystore exists, switching the build from the debug key to your real
upload key is **four values in one file. No code changes.**

---

## How it works

`android/app/build.gradle.kts` reads `android/key.properties` if that file
exists:

- **File present** → the release build (`flutter build appbundle --release`,
  `flutter build apk --release`) is signed with your upload key.
- **File absent** → the release build falls back to the debug key, so a fresh
  clone, CI without secrets, and `flutter run --release` all still work.

`key.properties` is git-ignored in three places (repo root `.gitignore`,
`android/.gitignore`, and the exported-repo template), and a pre-push secret
scan checks for it. It cannot be committed by accident.

---

## Step 1 — Create your upload keystore

Run this once. Replace the passwords with your own; keep them somewhere you will
not lose them (a password manager). `keytool` ships with the JDK.

```bash
keytool -genkeypair -v \
  -keystore ~/prayer-lock-upload.jks \
  -alias upload \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storetype JKS \
  -dname "CN=Prayer Lock, O=Your Name Or Org, C=US"
```

It will prompt for a keystore password (and, if you omit `-storepass`, a key
password — pressing Enter reuses the keystore password, which is fine).

- `-alias upload` is the key alias you will put in `KEY_ALIAS`.
- `-validity 10000` is ~27 years; Play requires a key valid past 2033.
- Store the `.jks` file **outside the repository** (e.g. `~/`), so it can never
  be committed.

> **Play App Signing note.** Google re-signs your app with a key it manages;
> the key above is your *upload* key, which only proves the upload is from you.
> If you ever lose it you can request an upload-key reset from Play — you do
> **not** lose your app. Losing the Google-managed app-signing key is the
> unrecoverable case, and that key never leaves Google.

---

## Step 2 — Point the build at it

```bash
cd mobile/android
cp key.properties.example key.properties   # template → real file (git-ignored)
```

Edit `mobile/android/key.properties` and fill in the four values:

```properties
KEYSTORE_FILE=/Users/you/prayer-lock-upload.jks
KEYSTORE_PASSWORD=the-store-password-you-chose
KEY_ALIAS=upload
KEY_PASSWORD=the-key-password-you-chose
```

`KEYSTORE_FILE` may be absolute (recommended) or relative to `mobile/android/`.

---

## Step 3 — Build and verify

```bash
cd mobile
flutter build appbundle --release        # the AAB you upload to Play
flutter build apk --release              # optional, for sideload testing
```

Confirm it is signed with **your** key, not the debug key:

```bash
# Point APKSIGNER at your installed build-tools version.
APKSIGNER=$(ls "$ANDROID_HOME"/build-tools/*/apksigner | sort -V | tail -1)
"$APKSIGNER" verify --print-certs \
  build/app/outputs/flutter-apk/app-release.apk | grep "certificate DN"
```

- **Correct:** `certificate DN: CN=Prayer Lock, O=Your Name...`
- **Still debug:** `certificate DN: CN=Android Debug` → `key.properties` was not
  found or a value is wrong. Re-check the path in `KEYSTORE_FILE`.

---

## What must never happen

- **Never commit `key.properties` or the `.jks` file.** Both are git-ignored;
  do not force-add them.
- **Never lose the keystore or its passwords.** Back them up. Without the upload
  key you must go through Play's upload-key reset flow to publish an update.
- **Never change the keystore between releases** unless you have deliberately
  reset the upload key in the Play Console. An app signed with a different key
  than the installed version **will not install as an update** — the user would
  have to uninstall, erasing their prayer history.
