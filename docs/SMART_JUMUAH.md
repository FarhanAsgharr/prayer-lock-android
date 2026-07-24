# Smart Jumu'ah

On Fridays, Dhuhr is replaced by Jumu'ah at the time the user's mosque holds
it. Every other day is unchanged.

---

## The one idea that makes this small

Jumu'ah is unlike every other prayer this app schedules.

The other five are **astronomical**: they happen when the sun reaches an angle,
and no human decides otherwise. Jumu'ah happens when a **particular mosque
decides** to hold it — a wall-clock time set by people, different at every
mosque. So it is *configured*, not computed. This is the one place in the app
where a fixed time is correct rather than a bug.

That drives the whole design:

```
DailyPrayerWindows (astronomical)
        │
        ▼
   JumuahScheduler ── not Friday, or off, or unconfigured ──▶ unchanged
        │
        ▼  Friday + configured
DailyPrayerWindows with the Dhuhr window replaced,
carrying labelOverride: "Jumu'ah" and isJumuah: true
        │
        ▼
lock decision · notifications · alarms · native mirror · dashboard · history
   (none of which know what a Friday is)
```

**Friday logic exists in exactly two files** — `friday_detector.dart` and
`jumuah_scheduler.dart`. Nothing else in the codebase branches on a day of the
week. Everything downstream consumes the transformed windows.

---

## Why the Dhuhr window is *replaced*, not relabelled

Jumu'ah discharges the Dhuhr obligation. Under dynamic durations Dhuhr normally
runs until Asr — often three hours — but a congregation lasts a well-defined
half hour that the mosque decides.

Relabelling and keeping the long window would block apps for hours after the
khutbah ended. So the whole window becomes the profile's, and the prayer settles
when it closes.

## Two constraints a configured time must respect

A user can type anything into settings. Two possibilities are not merely odd but
wrong:

| Case | Why it's wrong | What happens |
|---|---|---|
| Start **before** Dhuhr | Jumu'ah replaces Dhuhr; before zawal it isn't Dhuhr's time at all | Clamped to Dhuhr's start |
| End **after** Asr | Would overlap Asr, breaking the "at most one slot open" invariant the lock decision relies on | Clamped to Dhuhr's end |
| Window entirely outside Dhuhr | Clamping collapses it | Falls back to ordinary Dhuhr |
| Start ≥ end | Runs backwards | Rejected; ordinary Dhuhr |
| Unknown timezone | Cannot resolve wall-clock to an instant | Falls back to ordinary Dhuhr |

Clamping is reported, not hidden: `JumuahApplication.appliedWithClamping` and
`invalidProfile` surface in the settings screen so a time that is being ignored
does not look identical to one that works.

---

## Friday detection

Two traps, both handled:

**Which clock?** `DateTime.now().weekday` reads the *device* timezone. A
traveller whose phone has switched zones can have a device weekday that differs
from the weekday where they pray. Friday resolves against the user's configured
location, exactly as `localDateProvider` resolves the calendar date.

```dart
// 2026-07-24 05:00 UTC
FridayDetector.isFridayAt(instant, 'Asia/Riyadh')     // true  (08:00 Friday)
FridayDetector.isFridayAt(instant, 'Pacific/Honolulu') // false (19:00 Thursday)
```

**Which Friday?** Jumu'ah is tied to the *civil* Friday, not the Islamic day that
begins at Maghrib. Thursday evening after sunset is Islamically Friday, but
nobody holds Jumu'ah then. The civil date is correct here and would be wrong
for, say, the start of Ramadan.

---

## Components

Each requested component exists as its own class:

| Component | File | Responsibility |
|---|---|---|
| `FridayDetector` | `domain/usecases/friday_detector.dart` | Is this a Friday, at which timezone |
| `JumuahScheduler` | `domain/usecases/jumuah_scheduler.dart` | Replace the Dhuhr window; clamp; report |
| `JumuahManager` | `domain/usecases/jumuah_manager.dart` | Facade — status, apply, preference changes |
| `JumuahPreferenceRepository` | `data/repositories/…` | Read/write the preference (interface + 2 impls) |
| `JumuahNotificationManager` | `domain/usecases/…` | Friday wording only — never *when* anything fires |
| `JumuahVerificationController` | `domain/usecases/…` | What verifying means; the record written |
| `MosqueProximityDetector` | `domain/usecases/mosque_proximity_detector.dart` | Whether to offer a different mosque today |
| `SilenceMemory` | `android/…/blocking/SilenceMemory.kt` | What the phone's sound state was before a prayer |
| `SilenceController` | `android/…/blocking/SilenceController.kt` | The Do Not Disturb calls themselves |
| `WidgetContent` | `android/…/widget/WidgetContent.kt` | What the home-screen widget says |
| `PrayerWidgetProvider` | `android/…/widget/PrayerWidgetProvider.kt` | Renders it; refreshed by the alarm chain |

`JumuahManager` and the rest are free of Riverpod, Flutter and I/O.
`jumuah_providers.dart` is the only place they meet the container, which is why
the tests need no `ProviderScope`.

---

## The memory system

```
first Friday          → prompt: "Where will you pray Jumu'ah today?"
user picks a mosque   → stored once
every Friday after    → used automatically, no prompt
Settings              → change mosque, edit times, or forget the choice
```

`selectedMosqueId` is **nullable, and null is meaningful** — it is what triggers
the prompt. Defaulting it to the first mosque would silently answer a question on
the user's behalf and then never ask. A test asserts null survives a JSON round
trip rather than becoming a mosque on restart.

`lastUsedMosqueId` is separate, and it is what makes "just for today" possible:
the travel prompt sets it without touching `selectedMosqueId`, so someone
visiting family for a weekend does not come home to find their usual mosque
quietly replaced.

The prompt is an inline dashboard card, not a modal. A dialog on launch blocks
the whole screen for something not urgent; a user who wants to check the Fajr
time first shouldn't have to dismiss a question to do it.

---

## Profiles

Five seeded kinds, plus any number the user adds. Each is fully editable —
name, times, address, notes, and optional coordinates.

| Kind | Seeded default |
|---|---|
| Home | 2:00 PM – 2:15 PM |
| University | 1:15 PM – 1:30 PM |
| Workplace | 1:00 PM – 1:20 PM |
| Travel | 1:30 PM – 1:45 PM |
| Custom | whatever the user enters |

Coordinates are optional and only ever used for the travel prompt below. A user
who never records one simply never sees that prompt.

Times are `LocalTimeOfDay` — a wall clock with no date and no zone. Deliberately
not `DateTime`: a Jumu'ah that starts "at 2pm" starts at 2pm every Friday
regardless of date or daylight saving, and storing an instant would silently
drift. Also not Material's `TimeOfDay`, which would put a widget dependency in
the domain layer.

The time picker keeps the window valid as you drag: moving the start past the
end pushes the end out rather than producing a negative window the scheduler
would discard silently.

---

## Integration with existing systems

| System | Friday behaviour |
|---|---|
| **Blocking** | Locks at khutbah start, releases at the profile's end — not at Asr |
| **Notifications** | Reminder ladder, start, ending and end fire against mosque times; Friday-specific wording |
| **Alarms / native mirror** | Congregation start and end are armed; the astronomical Dhuhr start is *not* — waking there would find nothing to do |
| **Combined prayers** | Jumu'ah is never absorbed into a pair. A 15-minute congregation cannot swallow Asr, and extending it to Maghrib isn't what combining means. Maghrib+Isha is unaffected |
| **Verification** | Same camera, same `PrayerStatus.completed` against `PrayerName.dhuhr` |
| **Statistics / streak** | Identical — Jumu'ah *is* the Dhuhr obligation. A sixth prayer would give Friday a different denominator from every other day |
| **Offline** | Entirely local. No network is involved at any point |

### Jumu'ah has no qaza

A missed Jumu'ah is **not** made up as Jumu'ah; the person prays Dhuhr instead.
`JumuahVerificationController.offersQaza()` returns false for a Jumu'ah slot and
the closing notification says "pray Dhuhr instead" rather than offering a
make-up. Telling a user they can pray Jumu'ah as qaza would be telling them
something untrue about their own obligation.

### The short-window warning

The default window is 15 minutes — shorter than the ordinary 15-minute
"window ends soon" lead. A naive implementation drops the warning entirely. The
lead scales to a third of the window (1–15 min), so a congregation still gets a
closing warning.

---

## Database

Schema **v5** adds three columns to `prayer_history`:

```sql
was_jumuah            INTEGER NOT NULL DEFAULT 0
jumuah_location       TEXT
jumuah_block_seconds  INTEGER
```

A Friday Dhuhr row is still a Dhuhr row — same prayer, same contribution to
statistics and the streak. These record that it was prayed as a congregation, at
which mosque, and how long apps were blocked.

Stored rather than derived from the weekday, because the user can switch mosques
or disable the feature and history must keep describing what actually happened.
Existing rows default to `0`/`NULL`, which is exactly what they were.

`jumuah_block_seconds` measures from the window opening to the moment of
verification — what the user actually lost, not the configured length.

---

## Testing

```bash
cd mobile && flutter test                      # 585 Dart tests
cd mobile/android && ./gradlew testDebugUnitTest  # 61 Kotlin tests
```

| Suite | Tests | Covers |
|---|---|---|
| `jumuah_test.dart` | 40 | Detection, replacement, profiles, clamping, memory, slots, verification |
| `jumuah_notifications_test.dart` | 15 | Friday-only firing, full notice set, wording |
| `jumuah_blocking_test.dart` | 9 | Lock engages/releases on mosque times, alarm transitions |
| `mosque_proximity_detector_test.dart` | 14 | When to offer another mosque — mostly when *not* to |
| `SilenceMemoryTest.kt` | 10 | Record-once / restore-exactly / always-forget |
| `WidgetContentTest.kt` | 12 | Which prayer the widget shows, and the empty cases |

Assertions worth knowing about:

- *no Jumu'ah notice lands on any other weekday* — plans a full week and checks
  every non-Friday day, which is the literal spec requirement
- *leaves the other four prayers alone on a Friday* — Jumu'ah touches Dhuhr only
- *resolves the weekday at the user location, not the device*
- *a missed Jumu'ah is not offered as qaza*
- *Jumu'ah is never absorbed into a combined pair*
- *every prayer still appears exactly once* under all four groupings
- *an unchosen mosque round-trips as unchosen* — the restart-recovery guarantee
- *the ordinary Dhuhr start is not armed on a Friday*

---

## Smart silence

Optional, off by default, and Android-only. When on, the phone goes to
`INTERRUPTION_FILTER_PRIORITY` for the Jumu'ah window and returns to **exactly**
what it was before.

Getting the restore wrong is far worse than never silencing: someone who misses
a call from their family because a prayer app left Do Not Disturb on will
uninstall, and they would be right to. So:

- the previous state is recorded **before** anything changes, and restore puts
  that back — not "off", which would unsilence a phone the user had silenced
  themselves;
- the record lives in SharedPreferences with `commit()`, not memory, so a
  restore still works after the process is killed mid-prayer;
- a second silence is refused rather than overwriting the record with the
  silenced state — that single bug is the one that strands DND on;
- the flag is cleared even when restoring *failed*, so one failure cannot
  quietly disable the feature for good;
- `AppBlockerService` calls restore in `stopLock` **and** `onDestroy`, so no
  path — including a low-memory kill — ends a lock without it.

It needs `ACCESS_NOTIFICATION_POLICY`, which Android only grants from a Settings
screen. The toggle is shown regardless, but says so and offers the way there
when access is missing: a switch that is on and does nothing is worse than one
that explains itself.

---

## Smart location

On a Friday, if the user is far from their selected mosque and near a different
one they have configured, the dashboard offers to use it **for today only**.

The bar is deliberately high, because a prompt that fires whenever GPS wobbles
trains people to dismiss it unread — and then the one Friday they really are
travelling, they swipe it away out of habit. So it stays silent unless:

- the user is more than 15 km from their selected mosque (beyond any plausible
  local journey, and beyond the error of a coarse fix);
- another configured mosque is itself **within** 15 km — merely being *nearer*
  is not enough, or someone in Karachi would be told to pray in Lahore;
- and that one is at least 5 km closer, so two roughly equidistant mosques do
  not flip between fixes.

The position fix is guarded just as hard: `_fridayPositionProvider` resolves to
null without touching the GPS unless it is Friday, the toggle is on, and at
least two mosques have coordinates. It never *requests* permission — a location
dialog appearing unbidden on a Friday would be alarming — it only uses the grant
already given for prayer times.

---

## Home-screen widget

Shows the next prayer and its time; on Fridays, Jumu'ah with the mosque name.

It reads a SharedPreferences mirror written by Dart on each schedule sync, not
Flutter: a widget is drawn by the launcher process, often while the app is not
running, so starting an engine to render it is not an option. The mirror is
separate from the enforcement one — that holds wire ids and policy, this holds
readable text and none — so a change to the widget's wording cannot alter what
gets blocked.

`updatePeriodMillis` is **0**. Android clamps its own updates to 30 minutes,
which would leave the wrong prayer on screen for up to half an hour after each
transition. Instead `PrayerAlarmReceiver` refreshes it, so it redraws at exactly
the instants its content changes and at no others — no polling, nothing running
when nothing is happening.

Durations are never shown in seconds. The widget only redraws at boundaries, so
a seconds-precision countdown would be visibly frozen and wrong; minutes are
honest at the refresh rate it actually has.

---

## Known limits

- **Not localized.** Jumu'ah strings are English-only, consistent with the rest
  of the app outside the section and prayer-mode screens.
- **The widget is Android-only.** iOS needs a WidgetKit extension, which is a
  separate target and cannot be built from this toolchain.
- **Widget colours are duplicated** in `res/values/colors.xml` rather than
  derived from the Flutter theme — a RemoteViews tree cannot read it — so the
  two are kept in step by hand.
- **Smart silence cannot restore** if the user revokes notification-policy
  access while a prayer is in progress. It logs this; nothing else can be done.
- **No integration tests.** Consistent with the rest of the project — the
  `integration_test` package is still not installed.
