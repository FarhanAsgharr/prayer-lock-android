# Dynamic prayer duration blocking

How long apps stay blocked is computed from the prayer schedule, every day, for
the user's location. Nothing is a configured constant.

```
Fajr      04:18  ->  Sunrise            1 hour 23 minutes
Dhuhr     12:17  ->  Asr                3 hours 37 minutes
Asr       15:54  ->  Maghrib            3 hours 18 minutes
Maghrib   19:12  ->  Isha               1 hour 29 minutes
Isha      20:41  ->  Fajr (next day)    computed
```

Those numbers are a Makkah example. In London in June the Isha window is a
fraction of that; inside the Arctic Circle it is different again. A single
hardcoded duration would be wrong for almost everyone.

---

## The window model

Each prayer occupies a window from its own start to the next boundary:

| Prayer  | Window ends at        | Why                                                    |
| ------- | --------------------- | ------------------------------------------------------ |
| Fajr    | Sunrise               | Praying Fajr after sunrise is qada, not adaa           |
| Dhuhr   | Asr                   | The next prayer begins                                  |
| Asr     | Maghrib               | The next prayer begins                                  |
| Maghrib | Isha                  | The next prayer begins                                  |
| Isha    | The *following* Fajr  | The night belongs to Isha                               |

**The windows are deliberately not contiguous.** Fajr ends at sunrise, and the
next window does not open until Dhuhr. The morning gap belongs to no prayer.
Treating the whole morning as one Fajr window would both be wrong and would
block apps for six hours.

Because Isha runs to the following Fajr, **computing any day's windows requires
two days of prayer times**. Every layer that builds windows resolves the next
day as well; the cache stores `next_day_fajr` alongside each row so a single
cached day can reconstruct its own Isha window.

### Ordering

At high latitudes the astronomical calculator, under some high-latitude fallback
rules, can return times that are not in ascending order — Isha pushed past the
following Fajr in midsummer, or Asr landing before Dhuhr. A window built naively
from those runs backwards, and a backwards window means a lock whose end is in
the past: it either never engages or never releases.

So boundaries are forced monotonic before any window is built, clamping
*upward*. Pulling a boundary earlier would end a window before its prayer began;
raising it merely collapses the offending window to zero length, which the lock
logic already treats as "nothing owed". Anything that had to move sets
`wasClamped`, so the condition is reported rather than silently corrected.

---

## Unlock policy

Two modes, because users want opposite things from the same feature.

| Mode                     | Behaviour                                             |
| ------------------------ | ----------------------------------------------------- |
| `onVerification`         | **Default.** Apps unlock the moment the prayer is verified |
| `fullDuration`           | Apps stay blocked for the whole window, even after praying  |
| `earliestOf`             | Verification or window end, whichever comes first          |

`onVerification` is the default deliberately. Under dynamic durations a Dhuhr
window runs to Asr — over three hours. Blocking for all of it by default would
be a surprise severe enough that most users would uninstall rather than find the
setting.

### Qaza enforcement

A prayer whose window closes unfulfilled becomes a qaza debt. Whether that debt
keeps apps blocked is a separate, **off-by-default** setting
(`blockUntilQazaCompleted`). With it on, a missed Fajr blocks apps from sunrise
until the following dawn. That is a legitimate thing to want; it is not
something to impose on someone who agreed to "block during prayer".

---

## Where prayer times come from

Resolution order for a single day:

1. **Local cache** — if it holds that day for the current location and
   calculation settings.
2. **Remote provider** (AlAdhan) — if the user prefers it and the network
   cooperates.
3. **On-device calculator** — which cannot fail once a location is set.

Step 3 is why no feature stops working offline. It is not a degraded mode: it
produces a complete, correct schedule. The difference between online and offline
is *which authority's conventions apply*, not whether the app functions.

A remote response is discarded in favour of the device calculation when it is
non-monotonic — a malformed response would produce backwards windows, and the
on-device answer is well-defined at every latitude.

### Adding a provider

Implement `PrayerTimeProvider` and swap one line in
`remotePrayerTimeProviderProvider`. Nothing above the repository — the
scheduler, the lock orchestrator, any screen — knows that AlAdhan exists.

```dart
final remotePrayerTimeProviderProvider = Provider<PrayerTimeProvider>(
  (ref) => AlAdhanPrayerTimeProvider(),
);
```

### Failure handling

- Retries use bounded exponential backoff with jitter (`RetryPolicy`).
- A failure marked non-retryable (unsupported location, bad configuration) is
  not retried at all — retrying identical bad input forever is a battery-drain
  bug.
- After any remote failure a 15-minute cooldown applies, so a device offline for
  a day does not attempt a fetch on every 30-second orchestrator tick.

---

## Staying correct over time

There is no midnight timer. A timer does not survive the process being killed,
does not fire in Doze, and fires at the wrong moment for a traveller. Instead
`DailyScheduleRefresher` compares a fingerprint every few minutes and refreshes
when any of these changed:

- the local calendar date;
- the location, or any calculation setting;
- the UTC offset (travel, or a DST transition);
- the app was resumed and the cached horizon had run down.

A location or calculation change invalidates the entire cache — those days were
computed for inputs that no longer apply. A date change does not: yesterday's
cached times are still correct for yesterday.

---

## Enforcement while the app is not running

This is the part that makes the feature real rather than a foreground demo.

```
Dart computes windows
  -> mirrored to native storage (PrayerScheduleStore)
     -> exact alarms armed at every transition (PrayerAlarmScheduler)
        -> alarm fires (PrayerAlarmReceiver)
           -> decide, start/stop the foreground service, re-arm the next batch
```

**Why a native mirror.** After a reboot, or after Android reclaims the process,
there is no Flutter engine and no Dart isolate. An alarm still has to fire,
decide, and act. Everything the decision needs is therefore mirrored into plain
SharedPreferences, and Dart pushes an update whenever the schedule or the user's
state changes. Dart remains the source of truth; the mirror holds only what
enforcement needs — times and package names, no prayer history.

The mirror covers **seven days**, so enforcement survives a week without the app
being opened.

**Why exact alarms.** A prayer window can be three and a half hours. Polling for
its end would burn battery for hours to observe one instant. `setAlarmClock` is
used because it is the only tier Android will not defer in Doze — a lock that
engages twenty minutes into a prayer has already missed the moment it existed
for. It degrades to `setAndAllowWhileIdle` if exact-alarm permission is revoked.

**Restart recovery.** `BootReceiver` handles `BOOT_COMPLETED`,
`MY_PACKAGE_REPLACED`, `TIME_SET`, `TIMEZONE_CHANGED` and the OEM quick-boot
variants. Android discards every pending alarm on reboot; without this a phone
restarted overnight has no armed transitions the next day, and the failure is
invisible until a prayer is missed.

**Repair.** The alarm chain is self-perpetuating, and self-perpetuating chains
have one failure mode: if a link is ever missed, nothing re-arms. A force-stop,
an aggressive OEM battery manager, or an alarm dropped under memory pressure all
do it. `ScheduleMaintenanceWorker` (WorkManager, every 6 hours) re-arms from the
mirror. WorkManager is used for the *repair* and never for the transitions
themselves — its minimum period is fifteen minutes and its timing is
approximate, which is useless for "lock at 12:17".

**Redundant release.** The blocking service also holds the window's end instant
and releases itself when it passes. Two independent mechanisms for *releasing* is
the right asymmetry: an over-eager release is mild, a stuck lock is severe. The
service-side check can only ever end a lock early, never extend one — extending
on the wall clock would let a user skip a window by moving their clock forward.

### Clock manipulation

`elapsedRealtime` counts since boot and cannot be set by the user. If the wall
clock has moved backwards relative to it by more than two minutes, the clock is
treated as tampered with and an existing lock is **held** rather than released.
The worst case of a genuine clock correction is a lock that persists until the
next honest transition; the alternative is a trivial bypass.

---

## Notifications

Per prayer, per day:

| Notification    | When                                | Setting               |
| --------------- | ----------------------------------- | --------------------- |
| Reminder ladder | 15, 10 and 5 minutes before         | `reminderOffsetsMinutes` |
| Adhan           | Window start                        | always                |
| Window ending   | 15 minutes before the window closes | `notifyOnWindowEnd`   |
| Window ended    | Window close                        | `notifyOnWindowEnd`   |

The reminder ladder is the single stored setting; the "N minutes before" value
shown in settings is *derived* from it. They were separate fields at one point,
which let them disagree — the settings screen could write "30 minutes" while the
ladder that actually drives scheduling stayed at 15, and the setting silently did
nothing.

iOS caps pending notifications at 64 and silently drops the *newest* past the
cap, so the scheduling horizon is derived from how many notices a day actually
produces rather than fixed at seven days.

---

## Data model

Two tables added in schema **v3**:

**`prayer_schedules`** — the offline cache. One row per
`(date, location, method, madhab, high-latitude rule)`, so a user who travels or
changes method gets a distinct row rather than a silently wrong one. Coordinates
are rounded to three decimal places (~110 m) in the key: finer and GPS jitter
would miss the cache constantly; coarser and a user could move far enough to
matter. Instants are epoch milliseconds in UTC. Retention is 120 days.

**`qaza_records`** — the ledger of outstanding make-up prayers. Kept separate
from `prayer_history` because history records what happened on a date and is
closed once written, whereas this records what is still *owed* and stays open
until discharged — possibly weeks later. The v3 migration backfills it from
prayers already recorded as missed.

---

## Backend

| Endpoint                        | Purpose                                       |
| ------------------------------- | --------------------------------------------- |
| `POST /prayer-times`            | Instants only (unchanged)                     |
| `POST /prayer-times/schedule`   | Instants **plus** the derived windows          |
| `POST /prayer-times/schedule/range` | Consecutive days, for offline prefetch    |

`app/services/prayer_windows.py` is a deliberate mirror of
`dynamic_duration_calculator.dart`. The duplication is the point: the app must
compute windows with no network, so the logic cannot live only on the server.
Both are pinned by parity test suites written case for case against each other
(`tests/test_prayer_windows.py` and `test/unit/dynamic_duration_calculator_test.dart`).

**If you change the rules on one side, change them on the other, and update both
test suites in the same commit.**

---

## Testing

```bash
# Flutter — 306 tests
cd mobile && flutter test

# Backend window logic (needs no database)
cd backend && .venv/bin/python -m pytest tests/test_prayer_windows.py --noconftest

# Android native decision logic (JVM, no emulator)
cd mobile/android && ./gradlew :app:testDebugUnitTest
```

The Kotlin tests pin the *same rules* as the Dart lock-decision tests. The two
implementations must agree: if they disagree, a lock engaged by an alarm is
released by the next Dart tick and the user watches apps flicker.

### Where the important coverage is

| Suite                                  | Covers                                             |
| -------------------------------------- | -------------------------------------------------- |
| `dynamic_duration_calculator_test.dart`| Boundaries, durations, clamping, extreme latitudes  |
| `prayer_day_test.dart`                 | Phases, qaza, aggregates, state preservation        |
| `lock_decision_test.dart`              | Both unlock modes, grace, qaza, transition instants  |
| `prayer_schedule_repository_test.dart` | Offline fallback, cache, malformed responses         |
| `timezone_dst_test.dart`               | DST transitions, travel, year and leap boundaries    |
| `aladhan_provider_test.dart`           | Request shape, post-midnight Isha, failure classes   |
| `retry_policy_test.dart`               | Backoff bounds, permanent-failure short-circuit      |
| `PrayerScheduleTest.kt`                | The native mirror of the lock decision               |

---

## Known limits

- **iOS enforcement** still runs through DeviceActivity windows and requires
  Apple's Family Controls entitlement. The dynamic durations feed it, but the
  native scheduler described above is Android-only.
- **The native mirror holds seven days.** Beyond that, enforcement is inert
  until the app is next opened. `ScheduleMaintenanceWorker` logs loudly when the
  mirror is exhausted, because that state otherwise looks like "blocking stopped
  working for no reason".
- **`isCleanSoFar` now judges a day at its end**, not prayer by prayer, because
  the qaza opportunity runs to the end of the prayer day. This is intended — the
  user has the whole day to make something up — but it does mean the streak does
  not break the moment a single window closes.
