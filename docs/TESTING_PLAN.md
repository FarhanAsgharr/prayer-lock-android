# Prayer Lock AI — Testing Plan

How to verify every feature on Android and iOS before release.

This plan is ordered by **cost of failure**, not by convenience. The things
that would most damage a user if broken — a missed Fajr, a phone that stays
locked, a wrongly rejected verification — are tested first and hardest.

---

## 0. Test environment setup

### Prerequisites

```bash
# Backend
cd backend
python3 -m venv .venv && ./.venv/bin/pip install -e ".[dev]"
brew services start postgresql@16 redis
createdb prayerlock && createdb prayerlock_test
./.venv/bin/alembic upgrade head

# Mobile
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
flutter config --jdk-dir /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
cd mobile && flutter pub get
```

### Environments

| Environment | Backend | Vision provider | Purpose |
|---|---|---|---|
| Local | `localhost:8000` | `stub` (always approves) | Fast iteration, flow testing |
| Staging | Deployed | Real provider, test key | Pre-release, real AI behaviour |
| Production | Deployed | Real provider | Live |

> **Never test with `VISION_PROVIDER=stub` against staging or production.**
> The stub approves everything. `build_vision_provider()` refuses to construct
> it when `ENVIRONMENT=production`, but staging is not protected — check it.

---

## 1. Automated tests (run these first, every time)

These are the tests that already exist and pass. Run them before any manual
testing; if they are red, manual testing is a waste of time.

```bash
# Backend: 97 tests
cd backend && ./.venv/bin/pytest tests/ -v

# Backend lint
./.venv/bin/ruff check app tests

# Schema drift — MUST produce an empty migration
./.venv/bin/alembic revision --autogenerate -m "drift-check"
# Inspect the generated file: upgrade() must contain only `pass`, then delete it.

# Mobile: cross-implementation parity, 61 tests
cd mobile && flutter test

# Regenerate parity fixtures after ANY change to either prayer engine
cd backend && ./.venv/bin/python scripts/generate_parity_fixtures.py
cd ../mobile && flutter test test/unit/prayer_time_parity_test.dart
```

### Why the parity test matters more than it looks

The app computes prayer times on-device (offline requirement); the server
computes them to schedule push reminders. **If they disagree by even a minute,
the user gets a notification at one time and a device lock at another.** The
parity suite runs 60 city/date/method combinations through both
implementations and fails if any differ by more than one second.

**Run it after any change to either engine. Never edit the fixture JSON by
hand** — it is generated output, and editing it defeats the check entirely.

---

## 2. Prayer time accuracy (test this before anything else)

Wrong prayer times make every other feature worthless. A beautiful app that
locks your phone at the wrong time is worse than no app.

### 2.1 Verify against local authority

For each test city, compare the app's output against the **local mosque or
national authority** timetable — not against another app, which may share the
same bug.

| City | Authority to check against | Method | Tolerance |
|---|---|---|---|
| Makkah | Umm al-Qura published table | `umm_al_qura` | ±1 min |
| Cairo | Egyptian General Authority | `egyptian` | ±1 min |
| Karachi | Auqaf Pakistan | `karachi` | ±1 min |
| Istanbul | Diyanet | `turkey` | ±2 min |
| New York | ISNA | `north_america` | ±2 min |
| London | East London Mosque | `muslim_world_league` | ±3 min* |

\* Wider tolerance at high latitude is expected — authorities disagree with
each other there, because the geometric definition genuinely breaks down.

### 2.2 Madhab check (30 seconds, catches a whole class of bug)

Set madhab to **Shafi**, note Asr. Switch to **Hanafi**. Asr must move
**later** — typically 45–90 minutes depending on latitude and season. Every
other prayer must be **identical**.

If Hanafi Asr is earlier, or if other prayers moved, the shadow factor is
wired backwards.

### 2.3 High-latitude and polar cases

These are where naive implementations produce nonsense, and where real users
in Scandinavia, Scotland and Canada actually live.

**Manual location** → set each of these and inspect:

| Location | Date | Expected behaviour |
|---|---|---|
| London (51.5°N) | 21 June | Fajr uses fallback rule; must NOT be null or 00:00 |
| Edinburgh (55.9°N) | 21 June | Switching high-latitude rule visibly changes Fajr |
| Tromsø (69.6°N) | 20 July | Polar day → nearest-latitude fallback, times still ordered |
| Tromsø | 15 December | Polar night → same fallback, no crash |
| Reykjavík (64.1°N) | Both solstices | Times ordered, no NaN |

**Pass criteria:** every prayer time is non-null, chronologically ordered, and
falls within the correct calendar day. There is no "correct" answer at these
latitudes — there is only "sane" versus "broken".

### 2.4 DST transitions

Set device timezone to `Europe/London`, then check across the transition:

- **28 March** (day before) — Dhuhr around 12:0x local
- **30 March** (day after) — Dhuhr around 13:0x local
- The **UTC instant** should barely move (< 5 minutes)

Repeat for `America/New_York` (different transition date) and a
**non-observing** zone like `Asia/Riyadh` as a control — nothing should shift.

### 2.5 Travel / timezone change

1. Set schedule in Karachi, note times
2. Change device timezone to `Europe/London` **without** changing location
3. Times should re-render in London clock time but represent the **same UTC
   instants** — the schedule follows the saved location, not the device clock
4. Now change **location** to London — times should fully recalculate

**Critically:** past prayer history must **not** change. History stores
`scheduled_at` denormalized precisely so a location change cannot retroactively
rewrite whether you prayed on time in March.

---

## 3. Android app blocking

The highest-risk feature technically, and the one most likely to be broken by
OEM behaviour rather than by our code.

### 3.1 Permission setup flow

Fresh install → the app must **refuse to start a lock** without permissions,
with a specific message, not a silent no-op.

```bash
# Verify permission state from the host
adb shell appops get com.prayerlock.prayer_lock GET_USAGE_STATS
adb shell appops get com.prayerlock.prayer_lock SYSTEM_ALERT_WINDOW
adb shell dumpsys deviceidle whitelist | grep prayerlock
```

| Test | Steps | Expected |
|---|---|---|
| No usage-stats | Deny, try to start lock | Error `MISSING_USAGE_STATS`, routed to Settings |
| No overlay | Grant usage-stats only, start lock | Error `MISSING_OVERLAY`, routed to Settings |
| Both granted | Grant both | Lock starts, persistent notification appears |
| Revoked mid-lock | Revoke usage access during lock | App detects on next check and warns |

**This must never fail silently.** A user who believes they are protected but
is not is the worst outcome — worse than a visible error.

### 3.2 Interception behaviour

With a lock active and Instagram in the blocked list:

| Test | Expected |
|---|---|
| Open Instagram from launcher | Lock screen within ~1 second |
| Open Instagram from recents | Lock screen appears |
| Open via notification tap | Lock screen appears |
| Press Back on lock screen | Nothing happens (swallowed) |
| Press Home | Home works (deliberately not blocked) |
| Reopen Instagram after Home | Lock screen again |
| Open a **non-blocked** app | Opens normally, no interference |
| Open the dialer | **Opens normally — never blocked** |
| Open Settings | **Opens normally — never blocked** |

```bash
# Watch interception live
adb logcat -s AppBlockerService:I

# Force-launch a blocked app to test
adb shell monkey -p com.instagram.android 1
```

### 3.3 Emergency access (safety-critical — test every release)

**This is the test I would not ship without.** Someone may need emergency
services during a lock.

| Test | Expected |
|---|---|
| Dial 999/911 during active lock | **Works, unimpeded** |
| Open dialer during lock | **Works** |
| Open Settings during lock | **Works** |
| Open Messages during lock | **Works** (emergency SMS for deaf/HoH users) |
| Emergency unlock button | Confirms, then unlocks all apps |
| Second emergency unlock same day | Refused, with explanation |
| Emergency unlock at 23:59, retry 00:01 | New day → allowed again |

Test the dialer case on a **real device with a real SIM**, not an emulator.

### 3.4 Service survival (where OEMs break things)

The polling service must survive real-world conditions:

| Test | How | Expected |
|---|---|---|
| Screen off 30 min | Lock phone, wait | Service alive, blocking still works |
| Doze mode | `adb shell dumpsys deviceidle force-idle` | Service survives |
| Low memory | `adb shell am kill-all` | `START_STICKY` restarts it |
| Reboot mid-lock | Reboot during a lock | Lock state restored (or cleanly cleared) |
| Battery saver on | Enable in Settings | Service alive, or user warned |
| App swiped from recents | Swipe away | Foreground service continues |

**OEM-specific:** Xiaomi (MIUI), Huawei (EMUI), Oppo (ColorOS), Vivo and
Samsung all kill background services aggressively, beyond stock Android
behaviour. Test on at least **one Xiaomi and one Samsung device.** The
battery-optimisation prompt exists specifically for these.

### 3.5 Morning protection (Fajr gate)

1. Set Fajr to 2 minutes from now
2. Lock phone, wait for Fajr
3. Unlock the phone

**Expected:** "Good Morning — please offer Fajr prayer first", blocked apps
remain inaccessible until verification.

Test the awkward variants:
- Phone already unlocked and in use when Fajr arrives
- Phone unlocked by fingerprint vs PIN vs face
- Alarm going off at the same moment

### 3.6 Device matrix

Minimum before release:

| Android version | Device type | Why |
|---|---|---|
| Android 10 | Any | Older `appops` API path |
| Android 12 | Any | Overlay behaviour changed |
| Android 13 | Any | `POST_NOTIFICATIONS` runtime permission |
| Android 14 | Any | `foregroundServiceType` enforcement |
| Android 15/16 | Any | Current target |
| Any | Samsung | OEM service killing |
| Any | Xiaomi | Most aggressive OEM killing |

---

## 4. iOS

### What actually works on iOS

Apple does **not** permit arbitrary app blocking. The Screen Time API
(`FamilyControls` / `ManagedSettings` / `DeviceActivity`) does permit it, but
**requires a distribution entitlement granted by Apple on written application**
— which takes weeks and may be refused.

Test both paths, because you may ship before the entitlement arrives:

| Feature | Without entitlement | With entitlement |
|---|---|---|
| Prayer times | Full | Full |
| Notifications | Full | Full |
| Prayer tracking | Full | Full |
| AI verification | Full | Full |
| App blocking | **Not available** | Full via `ManagedSettings` |
| Focus mode | Suggestion only | Suggestion only |

### 4.1 Capability honesty test

On iOS **without** the entitlement, the app must **clearly state** that app
blocking is unavailable on this platform. It must not imply protection it
cannot deliver.

Verify: `BlockingPlatformChannel.isSupported` returns `false`, every method
no-ops rather than throwing, and the UI shows an explanatory state rather than
a broken button.

### 4.2 iOS-specific

| Test | Expected |
|---|---|
| Notification permission denied | App works, explains what is lost |
| Background app refresh off | Local notifications still fire |
| Low Power Mode | Notifications still delivered |
| Force-quit app | Scheduled local notifications still fire |
| Time zone change | Schedule recalculates |
| Screen Time authorization revoked | Detected, user informed |

**Note:** iOS local notifications are capped at **64 pending**. Five prayers
plus reminders is 10/day, so schedule about 6 days ahead and refresh on launch.
Verify you are not silently exceeding the cap and losing the tail.

---

## 5. Notifications

| Test | Android | iOS |
|---|---|---|
| Reminder fires N min before prayer | ✓ | ✓ |
| Adhan plays at prayer time | ✓ | ✓ |
| Fires with app force-quit | ✓ | ✓ |
| Fires in Doze / Low Power | ✓ | ✓ |
| Fires with screen off | ✓ | ✓ |
| Silent mode respected | ✓ | ✓ |
| Tapping opens correct screen | ✓ | ✓ |
| No duplicates with 2 devices | ✓ | ✓ |
| Survives reboot | ✓ | ✓ |
| DST transition day correct | ✓ | ✓ |

```bash
# Android: inspect scheduled alarms
adb shell dumpsys alarm | grep -A5 prayerlock

# Trigger FCM manually
adb shell am broadcast -a com.google.android.c2dm.intent.RECEIVE -n com.prayerlock.prayer_lock/...
```

**Timing precision:** verify the reminder fires within **±30 seconds**. Use
exact alarms (already declared in the manifest). A prayer reminder ten minutes
late is not a reminder.

---

## 6. AI prayer verification

### 6.1 Functional cases

| Input | Expected |
|---|---|
| Clear prayer mat photo | Approved, apps unlock |
| Photo of a wall | Rejected, "Prayer mat not detected" |
| Dark / blurry photo | Rejected with a helpful message |
| Photo of a mat **on a screen** | Rejected (prompt asks for this) |
| Same photo twice | Second flagged `is_suspected_replay` |
| Corrupted image data | Handled gracefully, no crash |

### 6.2 Failure and fairness cases (test these — they protect real users)

| Scenario | Expected | Why it matters |
|---|---|---|
| Vision API down | **Approves**, `status=error` | User already prayed; our outage must not trap them |
| Vision API timeout | Approves after timeout | Same |
| 3 failed attempts | **Released**, `released_without_detection=true` | Nobody gets permanently locked out of their own phone |
| No internet | Queued, lock releases locally | Offline requirement |
| Prayer already verified | 409 Conflict | No double-counting |
| Another user's prayer ID | **404, not 403** | Must not leak which IDs exist |

**Test the fail-open path deliberately** — block the API host at the firewall
and confirm the user is released. This is the difference between a reminder
app and a hostage situation.

### 6.3 Real-provider testing

Run against a **real** OpenAI/Gemini key in staging with real photographs:

- 20 genuine prayer mat photos in varied lighting → measure false-reject rate
- 20 non-mat photos (rugs, carpets, towels, blankets) → measure false-accept rate
- Prayer mats of different colours, patterns, and cultural styles

> **Bias check, and I would treat this as release-blocking.** Vision models are
> trained on skewed data. Verify the model does not systematically reject
> prayer mats common in some regions while accepting those common in others.
> A user in Indonesia and a user in Morocco must have the same experience. If
> the false-reject rate differs materially by mat style, lower the confidence
> threshold or add region-specific prompt examples before shipping.

### 6.4 Privacy verification

Confirm — by inspecting the database directly — that **no image is stored**:

```sql
SELECT column_name FROM information_schema.columns
WHERE table_name = 'prayer_verifications';
-- Must contain image_phash. Must NOT contain any image/blob/bytea column.
```

Then confirm no image data appears in logs:

```bash
grep -ri "base64\|image_data" backend/logs/ | head
# Should return nothing. The logging redactor strips image_base64.
```

---

## 7. Backend APIs

### 7.1 Automated coverage (already passing)

97 tests. Notable ones to keep green:

- Token type confusion — refresh token rejected as access token
- `alg: none` downgrade attack rejected
- Expired and tampered tokens rejected
- Validation errors do **not** echo the submitted image payload
- Another user's prayer returns 404, not 403

### 7.2 Manual API verification

```bash
# Health (also checks the database)
curl -s localhost:8000/health | jq

# Unauthenticated → 401
curl -s -o /dev/null -w "%{http_code}\n" -X POST localhost:8000/api/v1/prayer-times -d '{}'

# Prayer times with a real token
curl -s -X POST localhost:8000/api/v1/prayer-times \
  -H "Authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"latitude":21.4225,"longitude":39.8262,"timezone":"Asia/Riyadh"}' | jq
```

### 7.3 Rate limiting

```bash
# Auth bucket: 10 per 60s → the 11th must return 429
for i in $(seq 1 12); do
  curl -s -o /dev/null -w "%{http_code} " -X POST localhost:8000/api/v1/auth/refresh \
    -H 'content-type: application/json' -d '{"refresh_token":"invalid-but-long-enough-value"}'
done; echo
```

Then **stop Redis** and repeat: requests must still be **served**, not
rejected. The limiter fails open by design — a limiter outage must not take
down the API.

### 7.4 Security checklist

| Check | How |
|---|---|
| No secrets in repo | `git grep -iE "sk-|AIza|BEGIN PRIVATE KEY"` → empty |
| `.env` ignored | `git check-ignore .env` → matches |
| TLS enforced | Staging/prod reject plain HTTP |
| Certificate pinning | Test with an intercepting proxy — connection must fail |
| JWT secret set | Prod refuses to boot with the default (validator enforces this) |
| Docs disabled in prod | `/docs` returns 404 when `ENVIRONMENT=production` |
| SQL injection | Parameterised via SQLAlchemy; spot-check any raw SQL |

---

## 8. Offline mode

The app must be **fully usable** with no network. This is not a degraded mode;
it is the primary mode for prayer times.

| Test | Steps | Expected |
|---|---|---|
| Cold start offline | Airplane mode, force-quit, launch | Prayer times shown, computed on-device |
| Full day offline | Airplane mode 24h | All 5 prayers fire; locks engage |
| Verify offline | Complete prayer offline | Queued; lock releases locally |
| Reconnect | Restore network | Queue syncs; no duplicates |
| Conflict | Same prayer verified on 2 devices | Resolves without double-counting |
| Airplane mode mid-lock | Toggle during lock | Lock unaffected |
| Clock changed manually | Move device clock forward | Schedule recalculates sensibly |

**The critical assertion:** with the backend completely unreachable, the user
can still see prayer times, get notified, be locked, verify, and be unlocked.
Verification falls back to a local approval that syncs later.

---

## 9. Pre-release device testing

### Minimum before submitting to either store

- [ ] 2+ physical Android devices (one Samsung/Xiaomi), 2+ Android versions
- [ ] 2+ physical iPhones, 2+ iOS versions
- [ ] Full 24-hour cycle on a real device, real SIM, normal daily use
- [ ] Battery drain measured over 24h (target: **< 3%** attributable to us)
- [ ] Tested in at least 2 timezones, including one high-latitude
- [ ] Tested across a DST transition (or with the clock set across one)
- [ ] Emergency dial verified on a device with a real SIM
- [ ] Fresh-install onboarding walked by someone who has never seen the app

### Battery measurement

```bash
adb shell dumpsys batterystats --reset
# ... 24 hours of normal use with locks active ...
adb shell dumpsys batterystats com.prayerlock.prayer_lock > battery.txt
```

If drain exceeds ~5%, raise `POLL_INTERVAL_MS` in `AppBlockerService`. Users
uninstall battery hogs regardless of how much they want the feature.

### Accessibility

- [ ] TalkBack (Android) and VoiceOver (iOS) can complete the full flow
- [ ] Lock screen is readable and actionable via screen reader
- [ ] Text scales to 200% without clipping
- [ ] Contrast meets WCAG AA
- [ ] **Emergency unlock is reachable via screen reader** — a blind user must
      not be trapped

---

## 10. Store submission

### Google Play

The **highest-risk item in this entire document.** Play policy heavily
restricts apps that monitor or restrict other apps.

- [ ] Declare `PACKAGE_USAGE_STATS` with a clear justification
- [ ] Declare `SYSTEM_ALERT_WINDOW` usage
- [ ] Declare the `specialUse` foreground service type + subtype justification
- [ ] Confirm **no `AccessibilityService`** anywhere in the codebase
- [ ] Data safety form: declare camera use, and that **images are not stored**
- [ ] Privacy policy URL, live and accurate
- [ ] Demo video showing the prayer-time use case explicitly

> Expect questions from review. The single strongest argument is that this is a
> **self-imposed, user-configured** restriction with a documented emergency
> exit — not surveillance and not parental control.

### Apple App Store

- [ ] `NSCameraUsageDescription` explaining prayer verification specifically
- [ ] `NSLocationWhenInUseUsageDescription` explaining prayer-time calculation
- [ ] Family Controls entitlement **applied for** (weeks of lead time)
- [ ] If not yet granted: app must not claim blocking it cannot do
- [ ] Privacy nutrition labels accurate
- [ ] Religious content guidelines reviewed

---

## 11. Regression suite (run before every release)

```bash
#!/bin/bash
set -e
cd backend
./.venv/bin/pytest tests/ -q
./.venv/bin/ruff check app tests
./.venv/bin/python scripts/generate_parity_fixtures.py
cd ../mobile
flutter analyze
flutter test
flutter build apk --release
echo "All automated checks passed."
```

Then manually, every release, without exception:

1. Emergency dial during an active lock
2. Fail-open when the vision provider is unreachable
3. Attempt-limit release after 3 failed verifications
4. A full offline day
5. Fajr morning protection

These five are the ones where failure causes real harm to a real person. Every
other test can slip a release. **These cannot.**
