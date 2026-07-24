# Islamic sections and prayer preferences

Every Muslim configures the app to their own practice. Nothing is hardcoded for
one community.

---

## The central design decision

**A section is an identity. It is not a calculation parameter.**

That distinction is load-bearing, and getting it wrong is the main way a feature
like this becomes disrespectful:

| Section | What it actually is | Does it determine prayer times? |
| ------- | ------------------- | ------------------------------- |
| Hanafi | A school of jurisprudence | Yes — Asr at a double shadow |
| Shafi'i, Maliki, Hanbali | Schools of jurisprudence | Yes — Asr at a single shadow |
| Barelvi, Deobandi | Movements whose adherents follow a school | Usually, not always |
| Salafi | A movement | Loosely |
| **Sufi** | A spiritual orientation practised **within all four Sunni schools** | **No — it implies nothing** |
| Twelver, Ismaili | Schools with their own timings | Yes — Maghrib after the redness fades |

Treating these as interchangeable would either compute wrong prayer times or
tell someone their identity implies a ruling it does not.

So the model is:

```
IslamicSection  ──suggests──▶  SectionDefaults { madhab, method, grouping }
                                        │
                                        ▼
                        AppSettings.madhab  =  madhabOverride ?? sectionDefaults.madhab
                        AppSettings.prayerGrouping = groupingOverride ?? sectionDefaults.grouping
```

Every default is a **starting point**. Selecting a section applies them; the
user can change any of them afterwards; and the app says so on screen. The Sufi
entry says outright that no Asr timing is assumed and asks the user to set it.

### Why overrides are nullable

`madhabOverride` and `prayerGroupingOverride` are `null` until the user changes
them, and `madhab` / `prayerGrouping` are **derived getters**. Two independent
fields would let them disagree — the settings screen could display one value
while the calculator used another. (That exact bug existed in this codebase
once, with `reminderMinutesBefore`; it is why the pattern is used here.)

It also makes "Shia sections suggest combining, and the user can still turn it
off" expressible: the suggestion applies while the override is null, and stops
applying the moment the user sets one.

---

## The strategy system

**Nothing in the codebase branches on a specific section.** There is no
`if (isShia)`, no `section == twelver` outside
`islamic_section_strategy.dart`. A section's entire behaviour is the
`SectionDefaults` its strategy returns.

```dart
// Adding a community is one line.
_ConstantSectionStrategy(
  IslamicSection.ibadi,
  SectionDefaults(
    madhab: Madhab.shafi,
    calculationMethod: CalculationMethod.muslimWorldLeague,
    prayerGrouping: PrayerGrouping.none,
    rationale: 'Five separate prayers with Asr at one shadow length.',
  ),
),
```

`IslamicSectionRegistry` is immutable and substitutable
(`registry.withStrategy(...)` returns a new one), so a regional build or a test
can extend the set without editing the file — and a test substitution cannot
leak into another test.

A section with no registered strategy falls back to neutral defaults rather than
throwing. A missing registration must not make the app unusable for whoever
selected it.

---

## Combined prayers

### The model

The key invariant: **combining changes presentation and enforcement, never the
obligation.**

```
                     five PrayerEntry  ← always. History, statistics, streak.
                            │
                     PrayerSlotBuilder │ applies the grouping
                            ▼
   PrayerGrouping.none  →  5 slots:  Fajr · Dhuhr · Asr · Maghrib · Isha
   PrayerGrouping.both  →  3 slots:  Fajr · Dhuhr+Asr · Maghrib+Isha
```

A `PrayerSlot` is a **view** over one or two entries. It is never the unit of
record: nothing persists "Dhuhr+Asr" as a thing that happened. Two prayers
happened, and they happened together.

This is what keeps a combining user's data comparable with everyone else's:

- Five prayers are still the denominator, so success rates mean the same thing.
- Switching modes **re-renders** the day rather than rewriting it.
- A single verification of a combined slot writes **two history rows**.
- Each prayer's on-time/qaza classification is decided against **its own**
  window. Praying Dhuhr and Asr together at 15:00 is on time for Asr and late
  for Dhuhr — recording both as on time would be a flattering fiction.

### The window

A combined window is the union of two adjacent windows, so combining changes how
many locks there are, not how long the phone is blocked:

```
Dhuhr 12:17 ─────────── Asr 15:42 ─────────── Maghrib 19:04
     └── separate: 3h 15m ──┘└── separate: 3h 22m ──┘
     └──────────── combined: 6h 37m ────────────────┘
```

### Consequences that had to be handled

| Area | Behaviour |
| ---- | --------- |
| **Lock** | Engages at Dhuhr, releases at Maghrib. **Does not release when Asr begins** — the failure this design exists to prevent. |
| **Grace period** | Granted **once**, at the slot's start. Not re-granted when the second prayer arrives. |
| **Emergency unlock** | Exempting either prayer releases the whole slot. Otherwise the user spends their single daily unlock and it re-engages moments later. |
| **Excused** | A slot is only released when **every** prayer in it is excused. |
| **Verification** | One confirmation discharges both — unless `combinedVerification` is off, in which case only the prayer whose window is open is discharged. |
| **Notifications** | One adhan, one reminder ladder, one window-end notice per slot. No second adhan mid-window announcing something that did not start. |
| **Alarms** | A pair contributes one start and one end. Asr's start is not armed — it would wake the device to discover nothing changed. |
| **Native mirror** | Mirrored as slots, so the native side cannot release at Asr and immediately re-engage. |
| **iOS budget** | Combining halves two of the day's units, buying back enough of the 64-notification cap to extend the horizon. |
| **Fajr** | Never combinable. Sunrise separates it from Dhuhr by hours. |

---

## Migration from the pre-sections model

**The invariant: an upgrading user's prayer times and lock behaviour must not
move.**

| Stored `madhab` | Inferred section | Why |
| --------------- | ---------------- | --- |
| `hanafi` | Hanafi | Only the Hanafi school uses shadow ratio 2 |
| `ahle_hadith` | Ahl-e-Hadith | The value was added for that community |
| `jafari` | Twelver | The value was added for that community |
| `shafi` | **unassigned** | Covers Shafi'i, Maliki *and* Hanbali equally — and was the default nobody changed |

Two protections:

1. **The Asr convention is pinned.** If the legacy madhab differs from what the
   inferred section suggests, it is preserved as an explicit override.

2. **Combining is pinned off.** Twelver *suggests* combining both pairs.
   Applying that on an app update would change how the phone locks and how many
   cards appear, without the user asking for anything. So the migration writes
   `prayerGroupingOverride: none`, and the prayer mode screen offers combining
   as something to opt into.

The default for a fresh install is `IslamicSection.other` with no label —
displayed as "Not set", never "Other", which would read as a decision the user
did not make. Its neutral defaults are exactly the values the app used before
sections existed, so nobody's schedule moves. Onboarding asks on its second page.

---

## Calculation methods

Twelve are offered, including **Ja'fari** (AlAdhan method `0`), added for this
feature. It is distinct from Tehran — a different authority with different
angles, despite both being used by Shia communities. Offering only Tehran would
make Shia users choose between two conventions neither of which is theirs.

| Method | Fajr | Isha | Maghrib |
| ------ | ---- | ---- | ------- |
| Ja'fari | 16° | 14° | 4° depression |
| Tehran | 17.7° | 14° | 4.5° depression |

Backend migration `7c1a3b8f42d9` adds the enum value plus the section, grouping
and `was_combined` columns.

---

## Localisation and RTL

| | |
| --- | --- |
| Languages | English, Arabic (العربية), Urdu (اردو) |
| Direction | Arabic and Urdu resolve to RTL through `Directionality` |
| Setting | Settings → Language, default "Match system" |
| Strings | `lib/l10n/app_{en,ar,ur}.arb`, generated by `flutter gen-l10n` |

The three `Global*Localizations` delegates are installed at the app root. Without
them the framework's own strings stay English **and text direction is not
resolved from the locale** — a half-translated app that still lays out left to
right.

Generated localisations are git-ignored and regenerated on build, so a stale
copy cannot drift from the ARB files.

**Scope limit — read this before shipping to Arabic or Urdu users.** The
infrastructure is complete and the Islamic section and prayer mode screens are
fully translated, along with prayer names and grouping labels. **The rest of the
app's UI strings are still English-only.** Retrofitting them is mechanical but
large; see "Remaining work" below.

---

## Database

Schema **v4** adds `prayer_history.was_combined`. It records whether a prayer was
joined with its neighbour *at the time it was logged*, rather than deriving it
from the current setting — so a user who switches modes does not retroactively
rewrite their own history into something that never happened. Existing rows
default to `0`, which is exactly what they were.

`CombinedPrayerCounts` reports combined vs separate separately from
`PrayerCounts`, because combining is orthogonal to the outcome: a combined
prayer can be on time, late or missed like any other. Folding them together
would make "completed" ambiguous about whether it meant a prayer or a pair.

---

## Testing

```bash
cd mobile && flutter test          # 435 tests
```

| Suite | Covers |
| ----- | ------ |
| `islamic_section_test.dart` | Catalogue, registry, defaults, identity, **migration** |
| `prayer_slot_test.dart` | Grouping arithmetic, slot construction, combined windows and phases |
| `combined_lock_decision_test.dart` | Enforcement under combining — the spec's 12:17 example |
| `combined_notifications_test.dart` | One notice set per slot; no mid-window adhan |
| `islamic_section_screen_test.dart` | Every section offered, nothing ranked, free-text path |
| `localization_test.dart` | RTL resolution, locale fallback, no untranslated keys |

Load-bearing assertions worth knowing about:

- *every prayer appears in exactly one slot, whatever the grouping* — combining
  is a partition, never a filter. A dropped prayer would be one the user is
  never shown and never asked to pray.
- *a Ja'fari user is NOT silently switched to combined prayers* — the migration
  guard.
- *total blocked time is unchanged by combining* — proves combining joins
  adjacent windows rather than extending them.
- *the neutral defaults match what the app used before sections* — the upgrade
  invariant.
- *does not present the title "Madhab"* — the product requirement.

---

## Remaining work

Stated plainly rather than left to be discovered:

- **UI translation is partial.** Sections, prayer modes, prayer names and
  grouping labels are translated. The dashboard, settings, verification,
  onboarding, qaza and durations screens are English-only. The infrastructure is
  in place; each remaining string needs an ARB key and a call site change.
- **Section is not yet synced to the backend.** The columns and migration exist;
  the sync payload does not carry them.
- **Statistics UI does not yet surface the combined breakdown.**
  `CombinedPrayerCounts` and `combinedCounts()` are implemented and tested, but
  no screen renders them.
- **Kotlin tests are unverified in this environment** (no JDK available).
  `PrayerScheduleTest.kt` covers the native decision logic and needs a run where
  Gradle can execute.
- **iOS** still enforces through DeviceActivity and needs Apple's Family
  Controls entitlement. Slots feed it, but the native scheduler is Android-only.
