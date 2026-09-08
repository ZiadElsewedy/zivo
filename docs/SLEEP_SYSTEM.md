# SLEEP_SYSTEM — design

> **Deep doc for `lib/features/sleep/`.** Design intent + the platform research it rests
> on. Current status lives in [`STATE.md`](STATE.md); the decisions are pinned in
> [ADR-010](DECISIONS/ADR-010-sleep-provenance.md).
>
> **Every platform claim in §3–§5 was verified against vendor documentation in
> September 2026.** Where a capability does not exist, this doc says so rather than
> proposing a workaround that reads like one. Sources are listed in §21.

---

## 1. Product concept

**Sleep is a recovery input to training, not a second app.** ZIVO's positioning
([`PRODUCT.md`](PRODUCT.md), [ADR-004](DECISIONS/ADR-004-scope-specialization.md)) is a
fitness-first personal OS built around a coach that knows your numbers. Sleep earns its
place because it is the missing number: it explains a bad session, it gates progression,
and it is the one recovery variable a user can actually act on. Framed as "a sleep
tracker bolted on", it competes with AutoSleep and Oura on their turf and loses. Framed
as "the coach now knows you slept 5h10 for four nights before the squat session that
stalled", it is something neither of those apps can say.

Everything below is designed so that sentence is **true**, not plausible.

### The one principle

> Real data > inferred data > assumptions. A number we cannot source, we do not show.

Operationally that means three commitments the architecture enforces rather than hopes for:

1. **Every stored sleep value carries how it was produced** — a `SleepMethod` enum set at
   ingest from platform metadata, never guessed later (§10, §11).
2. **The words change with the method.** "Asleep 1:47 AM" and "You logged 1:30 AM" and
   "Last phone use 1:30 AM" are three different sentences and the UI picks between them
   from one table, not from ad-hoc widget copy (§11).
3. **"Not enough data" is a first-class state** with its own rendering, reached by
   explicit numeric gates (§16) — not an empty chart, not a zero.

---

## 2. What we collect, and from where

The table is the contract. Anything not on it, we do not store — including several things
that are technically available (§7) and several that merely sound useful.

| Datum | iOS source | Android source | Stored? | Why |
|---|---|---|---|---|
| Sleep start / end (instant, UTC) | HealthKit `sleepAnalysis` samples, stitched | Health Connect `SleepSessionRecord` | **yes** | the product |
| UTC offset + tz id at start/end | device tz at ingest | `startZoneOffset` / `endZoneOffset` | **yes** | §17 tz/DST |
| In-bed interval | `inBed` samples | `STAGE_TYPE_AWAKE_IN_BED` + session span | **yes, nullable** | enables efficiency |
| Sleep stages | `asleepCore` / `asleepDeep` / `asleepREM` | `STAGE_TYPE_LIGHT` / `DEEP` / `REM` | **yes, nullable** | drives confidence, shown only when present |
| Awake bouts inside the night | `awake` samples | `STAGE_TYPE_AWAKE` | **yes, nullable** | interruptions + efficiency |
| Efficiency | derived | derived | **derived, nullable** | asleep ÷ in-bed; `null` when in-bed unknown, never 100% |
| Writing app id + name | `sourceRevision.source.bundleIdentifier` / `.name` | `metadata.dataOrigin.packageName` | **yes** | provenance |
| Device kind (watch/ring/phone/mat) | `HKSample.device` + `sourceRevision.productType` | `metadata.device.type` | **yes** | tiering (§9) |
| Measured vs typed | `metadata[HKMetadataKeyWasUserEntered]` | `metadata.recordingMethod` | **yes** | the load-bearing flag (§9) |
| Upstream record id | `HKObject.uuid` | `metadata.id` + `clientRecordId` | **yes** | dedup + deletion sync |
| Target bedtime / wake / duration | user setting | user setting | **yes** | adherence |
| User-reported sleep/wake marks | in-app | in-app | **yes** | §12 fallback |

**Deliberately not stored in v1** — all of these are real and readable, and each is
excluded because it has no v1 product use, and collecting health data with no use is a
privacy cost with no return:

- heart rate, resting HR, HRV during sleep
- respiratory rate, SpO2, wrist temperature, breathing disturbances, sleep-apnea events
- any vendor "sleep score" (see §6 — Samsung's is real; Apple has none to give)
- screen/app-usage history (§7 — Android-only, and see the argument there)

Each moves to v2 **only** attached to a stated product question (§20).

---

## 3. iOS — what HealthKit actually gives us

### The type
One type: `HKCategoryType(.sleepAnalysis)`. Samples are intervals carrying an
`HKCategoryValueSleepAnalysis`:

| value | since | meaning |
|---|---|---|
| `inBed` | iOS 8 | in bed, not necessarily asleep |
| `awake` | iOS 8 | awake (during a sleep period) |
| `asleepUnspecified` | iOS 8 | asleep, stage unknown (`.asleep` is the deprecated spelling) |
| `asleepCore` | **iOS 16** | light / intermediate |
| `asleepDeep` | **iOS 16** | deep |
| `asleepREM` | **iOS 16** | REM |

### The trap: HealthKit has no sleep session
This is the single most important iOS fact and the one most integrations get wrong.
HealthKit stores a **cloud of overlapping interval samples**, not nights. One night from
an Apple Watch is dozens of adjacent samples; a user with a Watch *and* Oura *and* a
manual entry has three overlapping clouds in the same hours. There is no session object,
no "main sleep" flag, and **no sleep score**. Turning samples into nights is *our*
algorithm (§12), and it is where accuracy is won or lost.

Android does not have this problem — Health Connect stores real sessions. Normalising
that asymmetry is the platform layer's main job (§17).

### Provenance — good, and sufficient
Per sample: `sourceRevision.source.name` and `.bundleIdentifier`, `.version`,
`.productType` (e.g. `Watch6,1`), `.operatingSystemVersion`; `HKSample.device`
(name/manufacturer/model/hardware/software); and
`metadata[HKMetadataKeyWasUserEntered] == true` for hand-typed entries. That is enough to
build §9's tiering honestly.

### Who actually writes sleep on iOS
- **Apple Watch (watchOS 9+)** — stages + awake + in-bed. The good data.
- **iPhone alone — effectively nothing, since iOS 18.** Apple removed the *Track Time in
  Bed with iPhone* option. A Sleep Focus schedule does **not** write asleep samples. So an
  iPhone-only, no-wearable user has **no automatic sleep data at all**. This is not a gap
  we can engineer around; it is why manual logging (§12) is core, not a fallback.
- **Third-party** — Oura, Whoop, Eight Sleep, Withings, Garmin, AutoSleep, Pillow, Sleep
  Cycle all write to HealthKit when the user enables it, each under its own bundle id.

### Permissions
`HealthKit` capability + `com.apple.developer.healthkit` entitlement;
`NSHealthShareUsageDescription` in `Info.plist`. We request **read-only** — no
`NSHealthUpdateUsageDescription`, no write scope. Nothing ZIVO computes belongs in the
user's medical record.

**Read denial is undetectable — by design.** Apple: *"HealthKit does not tell you when
the user denies your app permission to query data."* `authorizationStatus(for:)` is
meaningful for write only. A denied read is indistinguishable from an empty store.

> **Consequence, and it is a product one:** ZIVO may never render "you have no sleep
> data." The honest string is *"No sleep data visible to ZIVO"* with a route to Health
> settings. This is exactly the class of false statement §11 exists to prevent.

### Background
`HKObserverQuery` + `enableBackgroundDelivery(for:frequency:)`, which **requires the
`com.apple.developer.healthkit.background-delivery` entitlement** (iOS 15+). Frequency
(`.immediate`/`.hourly`/`.daily`/`.weekly`) is a **ceiling, not a promise** — the system
throttles on battery and device state. Incremental sync is `HKAnchoredObjectQuery` with a
persisted `HKQueryAnchor`, which returns **additions and deletions** — deletions matter,
because a user deleting a night in Health must delete it in ZIVO.

### iOS limitations to design around
- No session objects, no score, no efficiency — all ours to compute.
- Read denial invisible.
- Data requires the device to be **unlocked** at least once since boot.
- Watch→iPhone sync is not instant; a night can land hours late. Sync must be idempotent.

---

## 4. Android — Health Connect

### The type
`SleepSessionRecord`: `startTime`, `endTime`, `startZoneOffset`, `endZoneOffset`,
`title`, `notes`, `stages: List<Stage>`, `metadata`. Stage types:
`UNKNOWN`, `AWAKE`, `SLEEPING`, `OUT_OF_BED`, `LIGHT`, `DEEP`, `REM`, `AWAKE_IN_BED`.

Real sessions, pre-sessionised, with zone offsets baked in. Structurally better than iOS.

### Provenance — better than iOS
`metadata.dataOrigin.packageName`, `metadata.device` (`type` = `TYPE_WATCH` /
`TYPE_RING` / `TYPE_PHONE` / …, manufacturer, model), `metadata.clientRecordId` +
`clientRecordVersion` (dedup), `metadata.lastModifiedTime`, and —

**`metadata.recordingMethod` ∈ {`UNKNOWN`, `ACTIVELY_RECORDED`, `AUTOMATICALLY_RECORDED`,
`MANUAL_ENTRY`}.** A first-class, platform-guaranteed "was this measured or typed" flag.
iOS's `WasUserEntered` metadata key is the equivalent but is optional and less reliably
set. §9 leans on both.

### Permissions
- `android.permission.health.READ_SLEEP` — manifest + granted in Health Connect's own UI.
- `android.permission.health.READ_HEALTH_DATA_HISTORY` — **required for anything older
  than 30 days**; without it, such a read *errors*. Needed for the 90-day backfill.
- `android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND` — required to read while
  backgrounded; gate on the Feature Availability API, it is not universally present.
- Play Console: the health-permissions declaration form is required at publish time.

### Availability
Android 14+ (API 34): part of the framework. Android 13 and below: a Play Store APK that
**may not be installed**. Always branch on `HealthConnectClient.getSdkStatus()` →
`SDK_UNAVAILABLE` / `SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED` / `SDK_AVAILABLE`, and
degrade to manual-only rather than erroring.

### Incremental sync
`getChangesToken()` → `getChanges(token)` returns `UpsertionChange` and
**`DeletionChange`**. Tokens expire after **30 days**; on `ChangesTokenExpiredException`,
fall back to a full time-range read and take a fresh token. Same shape as iOS's anchor.

### Samsung
- **Galaxy Watch → Samsung Health → Health Connect.** Sleep sessions with stages arrive
  through the standard path. **No Samsung SDK is required for the core product.**
- **Samsung Health Data SDK** additionally exposes what Health Connect does not model:
  Samsung's **sleep score**, snoring, blood-oxygen and skin-temperature during sleep.
  Reading it in development needs only Developer Mode, but **shipping it requires a
  Samsung partnership** — a business-process gate, not an engineering one. Out of MVP
  (§20); re-open only if Galaxy Watch users turn out to be a large share.
- **Samsung Privileged Health SDK** (raw wearable sensors) requires partner approval and
  a companion Wear OS app. Out of scope.

---

## 5. Wearables

We integrate with wearables **through the platform stores, never directly.** No Oura API,
no Whoop OAuth, no Fitbit Web API in v1. Rationale: each is a separate OAuth integration,
separate rate limits, separate ToS, separate breakage — for data the user has usually
already routed into HealthKit / Health Connect. One integration covers all of them, and
the user stays in control of the sharing in one place.

What each contributes when present: Apple Watch, Galaxy Watch, Fitbit, Garmin, Withings →
stages + awake bouts. Oura, Ultrahuman (rings) → stages, often the most accurate onset.
Eight Sleep, Withings Sleep Mat (under-mattress) → real measurement, weaker staging.
Whoop → stages; note Whoop's HealthKit export has historically been partial.

The **direct-API case** is only worth revisiting for a metric no store carries (Whoop
recovery, Oura readiness) and only with a product question attached.

---

## 6. Phone activity — the honest answer

The user asked whether device behaviour can be a supporting signal. Verified answer:

### iOS: **no. Not possible with public APIs.**
- **Screen on/off, lock/unlock:** no third-party API. `UIScreen`/`UIApplication`
  notifications only fire while your app is running in the foreground.
- **Screen Time / app usage:** the `DeviceActivity` framework requires the
  `com.apple.developer.family-controls` entitlement *and* — decisively — usage data can
  only be read inside a `DeviceActivityReportExtension` that runs in a sandbox with **no
  network access and no App Group writes**. The data can be *drawn*; it cannot be
  *retrieved*. Apple built it this way on purpose. Screen Time is unusable as a data
  source, full stop.
- **Charging state:** `UIDevice.batteryState` works only while the app is executing. No
  background wake on plug-in.
- **Focus mode:** `INFocusStatusCenter` yields a single boolean "is in *some* focus",
  needs the Communication Notifications entitlement, and cannot identify Sleep Focus.
- **Notifications to other apps:** no.
- **Genuine but weak:** `CMMotionActivityManager.queryActivityStarting(from:to:)` returns
  ~7 days of historical activity states (stationary/walking/…) with confidence, under
  Motion & Fitness permission. It measures **the phone**, not the person — a phone on a
  desk at noon is as "stationary" as a phone on a nightstand at 3am.

### Android: **yes, partially — and that asymmetry is itself the argument against it.**
- **`UsageStatsManager.queryEvents()`** with the special `PACKAGE_USAGE_STATS` access
  (granted in Settings, not a runtime dialog) yields `SCREEN_INTERACTIVE` /
  `SCREEN_NON_INTERACTIVE` and per-app foreground events, **retrospectively** — no
  foreground service needed. Real "last device interaction" data.
- **`ACTION_SCREEN_ON/OFF`** broadcasts: runtime-registration only ⇒ a persistent
  foreground service. Battery and Play-policy cost for information `queryEvents` already
  provides after the fact. Not worth it.
- **`ACTION_POWER_CONNECTED/DISCONNECTED`**: manifest-registerable. Weak signal.
- **Bedtime mode (Digital Wellbeing):** no public API. **DND/zen:** needs notification
  policy access and only observable while a component is alive.
- **Android Sleep API** (`ActivityRecognitionClient` + `SleepSegmentRequest`, Play
  services, `ACTIVITY_RECOGNITION` permission, API 29+): delivers `SleepSegmentEvent`
  (one per day after a confident wake, with start/end + status) and `SleepClassifyEvent`
  (~every 10 min: confidence 0–100, light level, motion). This is **Google's estimate
  from the phone's light sensor and accelerometer — an inference, not a measurement.** The
  codelab is marked deprecated (the API reference is not), and availability depends on
  Play services. It maps to method `deviceEstimated` and to **no other tier, ever**.

### The rule this produces
> Screen OFF is not sleep. Screen ON is not wake. A device signal may **never** promote a
> record's method, may never originate a sleep time, and may only ever be shown under its
> own literal label — *"Last phone use 1:30 AM"* — never re-worded into a sleep claim.

### Recommendation: leave phone activity out of v1 entirely
Not because it's unavailable on Android, but because:
1. It exists on **one platform only**, so any product surface built on it is a feature
   half the users can never have.
2. `PACKAGE_USAGE_STATS` is a Settings-deep-link ask that reads as invasive, spent on a
   signal that cannot by itself produce a sleep time.
3. Its only honest uses are two, and both are cheap to add later behind the same seam:
   a prefill hint for the manual logger, and a nudge ("you were on your phone until
   1:30 — want to log a sleep time?").

Ship it in v2 as an **Android-only assist to manual logging**, never as a data source.

---

## 7. Not accessible — the explicit list

So this is never re-litigated:

| Wanted | Verdict |
|---|---|
| Screen on/off on iOS | **Impossible.** No public API. |
| Screen Time / app usage on iOS | **Impossible to retrieve.** Extension sandbox blocks network and App Groups. |
| Which Focus mode is on (iOS) | **Not available.** Boolean "any focus" only, entitlement-gated. |
| Continuous background charging state (iOS) | **Not available.** |
| Knowing the user denied HealthKit read | **Not available by design.** |
| Real-time sleep detection from an iPhone alone | **Not available.** Removed by Apple in iOS 18. |
| An Apple sleep score / quality number | **Does not exist.** Apple ships none. |
| Bedtime mode state on Android | **No public API.** |
| Raw Galaxy Watch sensors | Partner-approval only. |
| Samsung sleep score | Samsung Health Data SDK + **partnership to ship**. |
| Health data >30 days on Android | Requires `READ_HEALTH_DATA_HISTORY`. |
| Guaranteed background delivery timing | **Neither platform guarantees it.** |

---

## 8. Source hierarchy

The user's proposed order — wearable → health platform → user-reported → device estimate —
is close, but it conflates two independent axes, and the conflation is exactly where
accuracy leaks:

- **Provider** — *which app/device wrote it* (Apple Health, Oura, ZIVO).
- **Method** — *how it was produced* (measured by a sensor / typed by a human / inferred).

"Apple Health data" is not a tier, because **Apple Health contains hand-typed entries.** A
manual entry that arrives *through* HealthKit is still manual — the transport is not the
method. Ranking by provider would promote a typed guess above a user's own honest tap in
ZIVO, which is worse than not ranking at all.

So we rank on method + sensor proximity, and record provider separately:

| # | `SleepMethod` | What qualifies | Confidence ceiling |
|---|---|---|---|
| 1 | `measuredWearable` | body-worn sensor: watch / ring / band. iOS: device or `productType` says watch, or a known wearable bundle id. Android: `device.type ∈ {WATCH, RING, FITNESS_BAND}` **and** `recordingMethod == AUTOMATICALLY_RECORDED` | high |
| 2 | `measuredNearable` | real sensor, not worn: under-mattress mats, sonar/mic apps | medium |
| 3 | `platformDerived` | a genuine platform record we cannot attribute to a sensor class — unknown writer, no device metadata, `asleepUnspecified` only | medium |
| 4 | `userReported` | ZIVO's own sleep/wake marks, a user edit, **or** any platform record flagged `WasUserEntered` / `MANUAL_ENTRY` | low |
| 5 | `deviceEstimated` | Android Sleep API segment; any inference of ours | low |
| 6 | `none` | nothing for this night | — |

**Tier 4 routinely arrives dressed as tier 1.** The manual-entry flag is the only thing
that separates them, and it is read on every single ingest. That check is the highest-value
twenty lines in the feature.

---

## 9. Data model

```
SleepNight                       // one sleep-day — the unit the UI renders
  sleepDay          Date         // local calendar date, doc id (yyyy-MM-dd)
  main              SleepSession?// the resolved main sleep; null ⇒ no data
  naps              [SleepSession]
  alternates        [SleepSession]  // losing candidates, kept — never merged, never deleted
  resolution        SleepResolution // why `main` won (§12), for the "why this number?" sheet
  targets           SleepTargets?   // snapshot at the time, so history stays honest
  createdAt/updatedAt

SleepSession                     // one continuous sleep episode from one provider
  id                String
  startAt / endAt   DateTime     // UTC INSTANTS. always. see §17
  startOffsetMin / endOffsetMin  Int      // local UTC offset as lived
  tzId              String?      // e.g. "Africa/Cairo"
  inBedStartAt / inBedEndAt      DateTime?  // null when unknown — never defaulted to startAt
  stages            [SleepStageSegment]     // empty when the source has none
  interruptions     [SleepInterruption]     // awake bouts inside the span
  provenance        SleepProvenance
  spansDstChange    bool

SleepStageSegment { startAt, endAt, stage: core|deep|rem|awake|asleepUnspecified|inBed|outOfBed }
SleepInterruption { startAt, endAt }        // derived from `awake` runs ≥ 5 min

SleepProvenance
  method            SleepMethod  // §8 — set at ingest, never recomputed from UI state
  providerId        String       // bundle id / package name / "zivo.manual"
  providerName      String       // "Apple Health", "Oura", "You"
  deviceKind        watch|ring|band|phone|mat|unknown
  recordingMethod   auto|active|manual|unknown   // the raw platform flag, preserved
  confidence        high|medium|low              // §11, deterministic
  completeness      double       // 0..1 — share of [start,end] backed by real samples
  rawRefs           [String]     // upstream uuids — dedup + deletion sync
  ingestedAt        DateTime

SleepTargets { bedtimeLocal: TimeOfDay, wakeLocal: TimeOfDay, durationMinutes: int }

SleepMark                        // §12 manual logging, open until closed
  { id, kind: sleep|wake, atUtc, offsetMin, tzId, note? }
```

**Derived, never stored:** duration, time-in-bed, efficiency, midpoint, all weekly
statistics. They are pure functions of the above, so a fix to the maths retro-corrects
every past night instead of leaving a stratum of wrong stored numbers.

**Firestore layout** — `users/{uid}/sleepNights/{yyyy-MM-dd}`, one doc per sleep-day. The
deterministic id **is** the cross-device dedup mechanism: two phones syncing the same
night converge on the same document instead of racing to create two.
`users/{uid}/sleepSettings/main` holds targets. Both need a `firestore.rules` block **and**
a rules test, per the golden rules.

---

## 10. Provenance in practice

Per the user's sketch, resolved:

```json
{ "sleepStart": "2026-09-06T22:47:00Z", "method": "measuredWearable",
  "providerName": "Apple Watch", "providerId": "com.apple.health",
  "deviceKind": "watch", "recordingMethod": "auto",
  "confidence": "high", "completeness": 0.97 }

{ "sleepStart": "2026-09-06T22:30:00Z", "method": "userReported",
  "providerName": "You", "providerId": "zivo.manual",
  "recordingMethod": "manual", "confidence": "low", "completeness": 1.0 }

{ "sleepStart": "2026-09-06T22:45:00Z", "method": "deviceEstimated",
  "providerName": "Android Sleep API", "recordingMethod": "auto",
  "confidence": "low", "completeness": 0.6,
  "basedOn": ["sleepSegmentEvent"] }
```

Two changes from the sketch, both deliberate: `confidence` is a **separate axis** from
method (a wearable night with 40 % coverage is `measuredWearable` + `low`), and
`completeness` is explicit — it is what stops a sparse sample cloud (half-hour samples
every 75 minutes, stitched into one 5½-hour session under §12.1's gap rule) from being
presented as 5½ hours of measured sleep. Samples spaced *wider* than the gap rule split
instead, so the two mechanisms cover the span between them.

---

## 11. Accuracy rules — enforced, not documented

### Confidence is computed, never authored
```
high   : measuredWearable ∧ stages present ∧ completeness ≥ 0.90 ∧ single source
medium : measuredWearable without stages, or measuredNearable,
         or platformDerived with completeness ≥ 0.80
low    : userReported, deviceEstimated, or completeness < 0.80
```

### The copy contract
One function, `sleepPhrasing(method) → (verb, precision)`, consumed by every surface. No
widget writes its own sentence.

| method | onset reads | precision | badge |
|---|---|---|---|
| `measuredWearable` | **Asleep 1:47 AM** | exact minute | Apple Watch |
| `measuredNearable` | **Asleep 1:47 AM** | exact minute | Eight Sleep |
| `platformDerived` | **Sleep recorded 1:47 AM** | exact minute | Apple Health |
| `userReported` | **You logged 1:30 AM** | exact minute | You |
| `deviceEstimated` | **Likely asleep around 1:45 AM** | **nearest 15 min** | Estimate |
| device activity | **Last phone use 1:30 AM** | nearest 5 min | — never a sleep time |

**Rounding is part of the accuracy claim.** Rendering an estimate as "1:47 AM" is false
precision even though the sentence hedges — the minute digit asserts a resolution the
method does not have. Estimates round to 15 minutes and always carry "around". This is
enforced in the formatter, so it cannot be bypassed by a widget.

### Prohibitions, testable
- Never average two sources' times. Averaging invents a night nobody measured (§12).
- Never fill a null with a default. No in-bed data ⇒ no efficiency, not 100 %.
- Never render a missing night as a zero-height bar. Zero means "slept 0 h".
- Never say "you have no sleep data" on iOS (read denial is invisible — §3).
- Never let an AI-authored sentence contain a numeral absent from its input (§15).

---

## 12. Sessionising and conflict resolution

Four ordered rules. All pure functions in `domain/` — no I/O, fully unit-testable, which
is the point.

**1 · Stitch within a provider.** iOS delivers fragments. Samples sharing a
`providerId`, ordered by time, join into one session when the gap between them is
**≤ 60 min**; a longer gap splits the night. (60 min is the standard sleep-research wake
bout threshold.) Android sessions arrive pre-stitched and skip this step.

**2 · Assign to a sleep-day.** Sleep-day *D* = the local window **[12:00 on D−1,
12:00 on D)**; a session belongs to *D* if its **midpoint** falls inside. Noon-to-noon is
the sleep-research convention and is what makes "the night of the 6th" mean the sleep you
woke from on the 6th. Within a window the **main sleep is the longest episode**;
everything else is a nap. Consequence, stated because it surprises people: a 3 pm nap
falls into *tomorrow's* window. Naps are stored, shown, and **excluded from v1 metrics**.

**3 · Choose, do not merge.** With candidates from several providers for one night, sort
by `(method tier asc, completeness desc, stage richness desc, lastModified desc)` and take
the first. Losers are kept in `alternates`. The UI can then say *"Oura and Apple Watch
disagree by 34 min — showing Oura"* and offer a switch.

> **Merging across providers is fabrication.** Two providers' intervals spliced together
> produce a night that no device measured and no algorithm validated. We never do it.

**4 · A user edit always wins**, is stored as `userReported`, and records
`supersedes: <previous session id>`. The measured record stays in `alternates` — the user
overrode it; we did not delete it.

**Deletions** propagate: an upstream record vanishing (HK anchor / HC `DeletionChange`)
removes it from `rawRefs` and re-runs resolution for that night, which may promote an
alternate or empty the night entirely.

---

## 13. Daily UX

One screen, top to bottom, answering "how did I sleep?" before the user has to think:

1. **Duration**, large, Azeret Mono (ADR-009), e.g. `6h 52m`. Directly beneath it, always,
   the **source chip**: `Apple Watch · measured` / `You · logged` / `Estimate`. The chip is
   not optional chrome; it is what makes the number honest.
2. **The night bar** — one horizontal bar on a local-time axis: in-bed → asleep → awake
   bouts (notched) → wake. Times at each end, phrased per §11. Stages colour the bar
   **only when present**; otherwise it is one solid run, which correctly communicates
   "we know when, not what kind".
3. **Target vs actual** — a signed delta, not a grade: `+22 min vs your 7h30 target`,
   `bed 47 min later than target`. No score, no ring "closing", no green tick for a good
   night. ZIVO does not know if the night was good; it knows how long it was.
4. **Consistency line** — one sentence from the 7-day window, gated by §16.
5. **Why this number?** — a tap-through sheet: the winning source, the alternates and
   their disagreement, completeness, and the raw span. This sheet is what turns "trust us"
   into "here's the receipt", and it is cheap to build once §9 exists.

**No data:** one honest line + the single action that fixes it — *Connect Apple Health* /
*Log last night*. Never a zero, never an empty chart, never "0h 0m".

**Today tab:** one glance row that mirrors the hero — duration, source chip, delta —
following the existing reactive-glance pattern, hidden entirely when the night is empty.

---

## 14. Weekly UX — the raster

The user asked for a timeline where drift is obvious. The right chart is a **raster
plot** — the standard chronobiology visualisation — not a bar chart of durations:

```
        6pm    9pm    12am    3am    6am    9am   12pm
 Mon                   ▐████████████████▌
 Tue                     ▐███████████████▌
 Wed                        ▐███████████████▌
 Thu                          ▐██████████████▌
 Fri                              ▐███████████████▌
 Sat     · · · · · · · · no data · · · · · · · ·
 Sun                   ▐███████████████▌
                    ┊target bed              ┊target wake
```

Seven rows, **one shared local-time x-axis** (18:00 → 12:00), each row a bar from bedtime
to wake. Drift becomes a staircase — visible instantly, and impossible to see in a
duration bar chart. Design rules:

- **Method is encoded as fill**, not hue: measured = solid, user-reported = outlined,
  estimated = hatched. One glance says how much of the week is real measurement.
- **Missing nights are an empty row with a hairline and the word "no data"** — never a
  zero bar.
- Two faint verticals for target bedtime and target wake; adherence is then *seen*, not
  computed in the reader's head.
- Awake bouts notch the bar where the data supports it.

Below the raster, three numbers, each carrying its **n**: average duration `6h 41m (6
nights)`, midpoint variability `±48 min`, target adherence `4 of 7`. Week-over-week deltas
appear only when §16's gates pass.

---

## 15. AI layer

The pipeline the user specified, with the guard that makes it safe:

```
raw platform records
  → validation + sessionise + resolve      (§12, pure Dart, on device)
  → deterministic metrics                  (§16, pure Dart)
  → FACT SHEET                             (typed JSON, numbers only)
  → model                                  (functions/ai/ — interpretation only)
  → NUMERAL GATE                           (deterministic, post-model)
  → typed insights → UI
```

**The model never computes.** It receives a fact sheet — every metric as
`{id, value, unit, n, method, confidence}` plus an explicit `insufficient: [...]` list of
metrics that failed their gate and **must not be discussed**. It gets no raw sessions.

**The numeral gate is the load-bearing control.** After generation, extract every numeral
and time from the output and assert each appears in the fact sheet (within rendering
tolerance). Any orphan numeral ⇒ reject and regenerate once, then fall back to the
deterministic sentence. A model cannot hallucinate "you slept 34 minutes more" past a
filter that has the real delta. This is the same posture as ZIVO's confirm-gated AI
writes ([ADR-003](DECISIONS/ADR-003-ai-mutations-v2.md)): the model proposes, deterministic
code decides.

Output is typed, not prose: `{kind, text, basedOn: [metricIds], n}` — so every insight can
render its own provenance footnote, and an insight with no `basedOn` cannot be displayed.

Prompt rules (in `functions/ai/chat/prompt/sections/`): every number must appear verbatim
in the input; never infer cause from co-occurrence; when a metric is in `insufficient`,
say so plainly — *"Not enough nights yet to say"* — and never soften it into a hedged
claim. Two to three sentences, no medical advice, no diagnosis.

Insights worth generating (all computable): duration change vs last week, bedtime
consistency direction, target adherence pattern, weekday/weekend split once ≥ 2 weekends
exist, and — ZIVO's actual differentiator — **sleep against training load**, since the
workout repositories are right there.

---

## 16. Minimum data — the gates

Statistics on 2 nights are decoration. Hard gates, checked before anything renders:

| Output | Requires |
|---|---|
| a single night | 1 resolved session |
| 7-day average duration | **≥ 3 nights** in the window |
| average bedtime / wake | **≥ 3 nights** (circular mean — see below) |
| variability / consistency | **≥ 5 nights** |
| week-over-week change | **≥ 5 nights in each week** AND \|Δ\| ≥ **15 min** |
| trend | **≥ 14 nights spanning ≥ 21 days** |
| weekday vs weekend | ≥ 3 weekdays AND ≥ 2 weekend nights |
| any correlation claim | ≥ 21 paired observations — **and still not shipped in v1** |

**Circular statistics are mandatory for clock times.** The arithmetic mean of 23:40 and
00:20 is 12:00 — noon — which is the classic sleep-app bug. Bedtimes, wake times and
midpoints are angles on a 24-hour circle: average the unit vectors, take the resultant
angle; variability is the circular SD, reported in minutes. `sleep_metrics.dart` exposes
`circularMeanMinutes` / `circularSdMinutes` and nothing else may average a clock time.

**Trend** uses a **Theil–Sen** slope, not least squares — one all-nighter should not flip
a fortnight's direction.

**The minimum-detectable-difference rule.** With n≈6 nights per week and a nightly SD of
~45 min, the standard error of a weekly mean is ~18 min. A 10-minute week-over-week
"improvement" is noise. Hence the 15-minute floor: below it, the honest output is *"about
the same as last week"* — which is a real finding, not a failure to find one.

### On correlations — a recommendation against
The brief asks whether we can find correlations between device behaviour and sleep.
Honestly: at n≈30 nights, one user, no controls, and heavily confounded variables, a
scan across many candidate pairs will surface spurious findings faster than real ones,
and presenting them as findings is precisely the failure mode this design exists to
prevent. Recommendation: **no correlations in v1.** If ever, they ship with a
pre-registered, fixed, small hypothesis set (never a pairwise fishing expedition), a
visible n, and language that is explicitly observational — *"these moved together; that
isn't cause"*. Flagging this because the brief's own first principle demands it.

---

## 17. Flutter architecture

Following ZIVO's layering exactly — `presentation/` → `domain/` → `data/`, repository
seam, `AppScope` wiring, no new state framework.

```
lib/features/sleep/
  FEATURE.md
  domain/
    sleep_session.dart        entity · stages · interruptions
    sleep_provenance.dart     method · confidence · completeness · methodFor
    sleep_night.dart          sleep-day rollup + resolution record
    sleep_targets.dart
    sleep_repository.dart     persistence seam + SleepMark (manual logging)
    sleep_source.dart         THE PLATFORM SEAM (SleepSource · RawSleepRecord)
    sleep_sessionizer.dart    pure: raw records → sessions        (§12.1)
    sleep_resolver.dart       pure: candidates → night            (§12.2–4)
    sleep_metrics.dart        pure: circular stats + SleepGates    (§16)
    sleep_insight.dart        fact sheet · numeral gate · deterministic drafts
    sleep_service.dart        the ingest pipeline + manual logging
  data/
    firestore_sleep_repository.dart   users/{uid}/sleepNights/{yyyy-MM-dd}
    in_memory_sleep_repository.dart   offline/test fallback, starts EMPTY
    sleep_night_codec.dart            the Firestore wire format
    health_sleep_source.dart          HealthKit + Health Connect (+ Unsupported)
  presentation/
    controllers/sleep_controller.dart  ADR-008 controller — the window arithmetic
    pages/sleep_page.dart              last night · week · insights, one scroll
    widgets/                           axis · bar · raster · chip · why/edit/targets sheets
    sleep_labels.dart                  THE COPY CONTRACT (never in domain/)
    sleep_insight_labels.dart          insight drafts → sentences
```

**One page, not two.** The daily view and the weekly raster answer each other —
"6h 52m" means little until the raster shows it is the shortest of six nights —
so putting a navigation layer between them would separate a number from its
context. Drill-downs are sheets: *why this number?*, *edit this night*,
*targets*.

**The platform seam.** `SleepSource` returns a **normalised, platform-independent**
`List<SleepSession>` — every iOS/Android difference (samples vs sessions, stage
vocabularies, metadata shapes) is absorbed in `health_sleep_source.dart` and never leaks
upward. The sessionizer runs on iOS records only; Android skips it. Everything above the
seam sees one model.

**Recommended implementation of that seam:** the `health` package (v13.x) — the deciding
factor is that it already exposes `sourceId` / `sourceName` / `sourceDeviceId` /
`recordingMethod`, which is exactly §9's provenance, and re-deriving that from scratch in
Pigeon is the expensive part. It also wraps Health Connect's changes-token API
(`getChangesToken` / `getChanges`), so Android incremental sync needs no native work at
all. Its real gaps are on iOS — no `HKAnchoredObjectQuery`, no background delivery — and
those are **additive native work behind the same interface**, so choosing it now does not
foreclose the custom path (§20). The alternative, a full Pigeon channel, buys anchored
sync and background delivery immediately at roughly 3× the work and a re-implementation
of provenance mapping.

**Two limits of the package, recorded because they are the migration trigger, not
oversights:** it does not surface Health Connect's `Metadata.device.type`, so on Android
`deviceKind` is `unknown` and tiering falls to the writing package name plus
`recordingMethod` (which is why §8's rules lean on both); and it returns plain
`DateTime`s rather than the stored zone offsets, so a night is rendered in the offset this
device would apply to that instant — correct for anyone sleeping in their own time zone,
and off for a night slept abroad and reviewed at home.

**Sync.** v1: foreground — on app open, on resume after > 30 min, and pull-to-refresh.
Backfill 90 days on first grant (Android needs `READ_HEALTH_DATA_HISTORY` for >30 days).
Idempotent by construction: deterministic doc ids + `rawRefs` dedup, so re-syncing the
same night converges instead of duplicating. v2 adds background delivery and true
incremental anchors.

**Time zones and DST — the part that is usually wrong.** Store UTC instants **plus** the
local offset and tz id as lived. Compute **duration from the instants, never from wall
clock** — a night spanning a DST change has a real duration that differs from the
clock-face difference by an hour, and computing 23:00→07:00 as 8 h across a spring-forward
is a wrong number that looks right. Render bedtime/wake in the offset that was recorded,
so a night in Tokyo reads as it was lived rather than shifted into home time. Flag
`spansDstChange` so the UI can annotate instead of confusing. Travel across zones shifts
the sleep-day boundary; the noon-to-noon window uses the local offset at the session
midpoint.

**Error handling.** Every failure mode has a named state and a rendering: provider absent,
permission denied (or invisible-denied on iOS), zero records, records but all failing
completeness, conflicting sources, a token/anchor expiry, and offline. None of them may
render as a zero or a spinner that never resolves.

---

## 18. Permissions

**iOS** — `HealthKit` capability, `com.apple.developer.healthkit`,
`NSHealthShareUsageDescription`, read-only scope on `sleepAnalysis`. v2 adds
`com.apple.developer.healthkit.background-delivery`. No Motion & Fitness in v1 (nothing
uses it — §6).

**Android** — `android.permission.health.READ_SLEEP`; plus
`READ_HEALTH_DATA_HISTORY` (>30-day backfill) and, in v2,
`READ_HEALTH_DATA_IN_BACKGROUND` (feature-gated). Health Connect also requires the
`ACTION_SHOW_PERMISSIONS_RATIONALE` intent filter and the Android 14+
`VIEW_PERMISSION_USAGE` activity-alias, plus a `<queries>` entry for
`com.google.android.apps.healthdata` — **without these the permission sheet does not
appear at all**, which presents as "the user refused" rather than as a manifest bug. Play
Console health-permissions declaration at publish. `ACTIVITY_RECOGNITION` and
`PACKAGE_USAGE_STATS` only if §6's v2 assists ship — both deferred.

**`minSdk` rises 23 → 26.** Health Connect's client library requires API 26 and the
manifest merger fails below it. The cost is Android 6.0–7.1; the alternative was no sleep
data on Android at all. Recorded in [ADR-010](DECISIONS/ADR-010-sleep-provenance.md).

**Asking well.** Request at the moment of value (the user opened Sleep), after one screen
explaining what ZIVO reads and that it never writes. Because iOS read-denial is invisible,
the empty state must always offer the Health-settings route rather than asserting there is
no data.

---

## 19. Platform limitations — consolidated

Beyond §7's impossible list, the things that shape the build: HealthKit has no sessions
and no score (we sessionise); iOS read-denial is invisible (never assert emptiness);
iPhone-alone yields nothing since iOS 18 (manual logging is core); background delivery is
throttled on both platforms (never promise freshness); Health Connect may be absent below
Android 14 (branch on `getSdkStatus`); Health Connect hides data >30 days without an extra
permission; HC change tokens expire at 30 days (full-read fallback); Watch→phone sync
lags (idempotent sync); Samsung's richest data needs a partnership; and every device
signal on iOS is closed to us.

---

## 20. MVP, and what comes later

**MVP — ships the principle, not just the feature**
1. `SleepSource` seam + `health`-backed implementation (HealthKit + Health Connect), 90-day backfill, foreground sync.
2. Sessionizer + resolver + provenance + confidence (§8–§12) — pure, heavily unit-tested.
3. Manual logging: "I'm going to sleep" / "I'm awake", plus edit a night. Always `userReported`.
4. Targets (bedtime, wake, duration).
5. Daily: hero + night bar + source chip + delta + **why-this-number** sheet.
6. Weekly: the raster + three gated numbers.
7. Deterministic metrics with circular stats and the §16 gates.
8. AI insights with the numeral gate.
9. Firestore persistence + rules + rules tests; en/ar strings; Today glance.
10. Every empty/denied/conflicting state rendered honestly.

**Next (in order of value)**
- Background delivery (iOS entitlement + native `HKAnchoredObjectQuery`; HC changes-token + background permission) — turns "sync when you open it" into "already there".
- Sleep × training: sleep before/after sessions, sleep vs stalled progression. **The differentiator**, and it needs only data we already have.
- Naps in metrics; weekday/weekend split; social jetlag.
- Android-only manual-log assist from usage stats (§6), clearly labelled.
- Android Sleep API as an explicit `deviceEstimated` fallback for phone-only Android users.
- Sleep-adjacent metrics (HR, HRV, SpO2, temperature) — each only with a stated question.
- Samsung Health Data SDK (needs partnership) for sleep score / snoring.
- Sleep Regularity Index (needs epoch-level data).
- Correlations — only under §16's constraints, if ever.

---

## 21. Sources

Verified September 2026.

- HealthKit sleep values — https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis
- HealthKit read-permission privacy — https://developer.apple.com/documentation/healthkit/hkhealthstore/authorizationstatus(for:)
- Background-delivery entitlement — https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.healthkit.background-delivery
- `enableBackgroundDelivery` — https://developer.apple.com/documentation/HealthKit/HKHealthStore/enableBackgroundDelivery(for:frequency:withCompletion:)
- DeviceActivity report extension sandbox — https://developer.apple.com/documentation/deviceactivity/deviceactivityreportextension
- Family Controls entitlement — https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement
- iOS 18 removal of iPhone-only time-in-bed — https://developer.apple.com/forums/thread/761477
- Health Connect sleep — https://developer.android.com/health-and-fitness/health-connect/experiences/sleep
- Health Connect sleep sessions — https://developer.android.com/health-and-fitness/health-connect/features/sleep-sessions
- Health Connect availability — https://developer.android.com/health-and-fitness/health-connect/availability
- Health Connect background/history permissions — https://android-developers.googleblog.com/2025/03/health-connect-jetpack-sdk-now-in-beta.html
- Health Connect differential changes — https://developer.android.com/health-and-fitness/health-connect/sync-data
- Android Sleep API — https://developers.google.com/location-context/sleep
- `UsageStatsManager` — https://developer.android.com/reference/android/app/usage/UsageStatsManager
- Samsung Health Data SDK access — https://developer.samsung.com/health/data/guide/features/data-access.html
- Samsung sleep via Health Connect — https://developer.samsung.com/health/blog/en/managing-sleep-data-with-samsung-health-and-health-connect
- `health` Flutter package — https://pub.dev/packages/health
