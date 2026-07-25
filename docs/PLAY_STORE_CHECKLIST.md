# Play Store publishing checklist

Everything Google requires for the store listing and compliance sections. Each
item says what it is, what state it is in, and — where the app can answer it —
the exact answer to give. Items marked **⇒ you** need a decision or an asset
only you can provide (your words, your account, your legal pages).

Legend: ✅ ready in the repo · ⇒ you must supply · ⚙ generate from listed source

---

## Store listing

### App name  ✅
- **Value:** `Prayer Lock`
- Matches `android:label` in the manifest and the launcher label. Max 30 chars;
  this is 11. No change needed.

### Short description  ⇒ you (draft provided)
- Max 80 characters. Shown under the icon in search.
- **Suggested:** `Block distracting apps during prayer. Unlock them once you've prayed.` (68 chars)
- Adjust to your voice; keep it under 80.

### Full description  ⇒ you (draft provided)
- Max 4000 characters. A ready starting draft:

  > **Prayer Lock helps you pray on time by pausing the apps that pull you away.**
  >
  > At each prayer time, the apps you choose are locked. They unlock once you
  > confirm you've prayed — by photo verification or a tap, your choice. Phone,
  > messages and settings are never blocked, so you can always reach anyone.
  >
  > • **Accurate prayer times** — 14 calculation methods, works fully offline,
  >   automatic location.
  > • **Your tradition, your way** — choose your Islamic section; combine Dhuhr
  >   with Asr and Maghrib with Isha if you follow that practice.
  > • **Smart Jumu'ah** — on Fridays, Dhuhr becomes Jumu'ah at your mosque's
  >   time, with a Friday reminder and an optional silent mode for the khutbah.
  > • **Make-up prayers** — missed a prayer? Track and clear your qaza.
  > • **Ramadan & the Islamic calendar** — Sehri and Iftar countdowns, Eid,
  >   sacred days, and a Hijri date you can adjust to your local sighting.
  > • **Private by design** — verification photos are analysed and discarded,
  >   never stored or shared. Your data is yours.
  > • **English, العربية, and اردو**, with full right-to-left support.

### Languages  ✅
- The app ships **English, Arabic, Urdu**. List all three in the listing's
  translations if you want localised store text (the app UI is already
  translated; store copy is separate and ⇒ you).

---

## Graphics assets

### App icon (512×512, 32-bit PNG)  ⚙ from `mobile/assets/branding/app_icon.png`
- Play requires a 512×512 hi-res icon. The source is 1024×1024; downscale it:
  ```bash
  cd "mobile"
  python3 -c "from PIL import Image; Image.open('assets/branding/app_icon.png').resize((512,512), Image.LANCZOS).save('assets/branding/play_icon_512.png')"
  ```
- The launcher icon on-device (all densities, adaptive, monochrome) is already
  generated and verified.

### Feature graphic (1024×500, PNG/JPG)  ⇒ you
- Required. Shown at the top of the listing. No text-heavy design (it is cropped
  on some surfaces). A simple composition of the mosque-and-keyhole mark on the
  brand green (`#1B5E4A`) works. This is a marketing asset — supply your own or
  have one designed; the app cannot generate a compliant one for you.

### Phone screenshots (min 2, up to 8; 16:9 or 9:16)  ⚙ capture from the app
- Required: at least 2. Capture the real screens:
  ```bash
  # With the app running on a device/emulator:
  adb exec-out screencap -p > screenshot-dashboard.png
  ```
- Recommended set: dashboard (prayer list), a prayer countdown / lock screen,
  the Jumu'ah card, settings (sections/modes), analytics. All are built and
  render in three languages.

### Tablet screenshots (optional)  ⇒ optional
- Only if you want the app featured on tablets. Not required.

---

## Privacy & compliance

### Privacy Policy  ⇒ you (required, URL)
- **Required** for any app, and doubly so because this app requests sensitive
  permissions (usage access, camera). You must host a privacy policy at a public
  URL and enter it in the Console.
- What it must state, based on how the app actually behaves (all verifiable in
  the source):
  - Verification photos are **analysed and immediately discarded** — never
    stored on-device, uploaded to storage, or shared.
  - App-usage access is used **only** to detect which app is foreground during a
    prayer lock; the list of blocked apps stays on-device.
  - Prayer history and settings are stored **encrypted** (SQLCipher) on-device,
    and backed up via the user's own Google account (excluding the encryption
    key).
  - If you deploy the backend: what it stores (account, prayer records for
    sync), where, and how to request deletion.
- A template you can adapt is out of scope here, but the factual claims above
  are accurate to the implementation.

### Terms & Conditions  ⇒ you (recommended, URL)
- Not strictly required by Play, but recommended for a published app. Host at a
  URL; link from the listing and optionally in-app.

### Data safety form  ⇒ you (answers provided)
- Play's mandatory questionnaire. Answer it from the app's real behaviour:

  | Question | Answer |
  |---|---|
  | Does the app collect or share user data? | **Depends on backend.** Offline-only build: **No**. With sync backend: collects account + prayer records. |
  | Is data encrypted in transit? | **Yes** — HTTPS only (`network_security_config.xml`, cleartext denied). |
  | Is data encrypted at rest? | **Yes** — on-device SQLCipher. |
  | Can users request deletion? | **Yes** if backend is deployed (provide the mechanism); offline build stores nothing remotely. |
  | Photos/camera data | Used for prayer verification, **analysed then discarded**, **not** stored or shared. Declare accordingly. |
  | Location | Used to compute prayer times. Declare as collected-not-shared if the backend logs it; on-device only otherwise. |

  The exact selections depend on whether you ship the backend. Answer for the
  build you actually publish.

### Content rating  ⇒ you (answers provided)
- Complete Play's IARC questionnaire. This app has **no** violence, sexual
  content, profanity, gambling, or user-generated content. Expected rating:
  **Everyone / PEGI 3**. Answer "no" to all objectionable-content questions;
  declare that it is a reference/lifestyle app.

### Target audience & content  ⇒ you
- Target age group: **13+** (general audience; not directed at children).
  Do **not** select the "designed for children" / Families program — the app is
  not a children's app, and that program adds obligations that do not fit.

### Ads  ✅ (answer: No)
- The app contains **no ads**. Declare "No ads" in the Console.

### Government / financial / health declarations  ✅ (answer: No)
- None apply. It is a personal productivity / religious lifestyle app.

---

## Technical (all ✅ — verified in the repo)

| Item | State | Where |
|---|---|---|
| Application ID | `com.prayerlock.prayer_lock` | `build.gradle.kts`, manifest |
| Version name / code | `1.0.0` / `1` | `pubspec.yaml` → Gradle |
| Target SDK | Flutter's latest | `build.gradle.kts` |
| Min SDK | 24 (Android 7) | `build.gradle.kts` |
| Adaptive icon | foreground + green background + monochrome | `mipmap-anydpi-v26/`, `drawable-*/` |
| Notification icon | white silhouette vector | `drawable/ic_notification.xml` |
| Permissions | usage access, overlay, exact alarm, camera, location, notifications, DND — each justified | manifest + comments |
| Network security | HTTPS-only, cleartext denied | `network_security_config.xml` |
| Backup rules | history/settings backed up; key excluded | `backup_rules.xml`, `data_extraction_rules.xml` |
| Code shrinking | R8 minify + resource shrink on release | `build.gradle.kts` |
| ProGuard keep rules | Room, WorkManager, Gson, SQLCipher, reflection | `proguard-rules.pro` |
| Release AAB | builds and validated | `flutter build appbundle --release` |
| Foreground service type | `specialUse` with justification for review | manifest `<service>` |

### Permissions — reviewer justification
Play flags several of these. Each has a manifest comment; the short version for
the "sensitive permissions" declaration form:

- **Usage access (PACKAGE_USAGE_STATS):** to detect the foreground app during a
  prayer lock. The app deliberately does **not** use AccessibilityService (Play
  restricts that to genuine accessibility use).
- **Exact alarms (SCHEDULE_EXACT_ALARM/USE_EXACT_ALARM):** a prayer reminder ten
  minutes late is useless; the block must engage at the exact prayer time.
- **Foreground service (specialUse):** to enforce the block while other apps are
  open. Subtype justification is in the manifest.
- **Camera:** optional prayer-mat photo verification; photos are discarded.
- **DND access (ACCESS_NOTIFICATION_POLICY):** optional silent mode during
  Jumu'ah; user-granted in Settings.

---

## Pre-submission gate

Do not submit until every ⇒ item is done:

- [ ] Short description (≤80 chars)
- [ ] Full description
- [ ] Feature graphic (1024×500)
- [ ] ≥2 phone screenshots
- [ ] 512×512 icon uploaded
- [ ] Privacy policy URL live
- [ ] Terms URL (recommended)
- [ ] Data safety form completed
- [ ] Content rating questionnaire completed
- [ ] Target audience set (13+)
- [ ] Signed with your upload key (see RELEASE_SIGNING.md)
- [ ] AAB uploaded to Internal testing first
