# ADR-010 — Sleep: provenance as a first-class field

**Status:** accepted · 2026-09-07
**Context:** [`docs/SLEEP_SYSTEM.md`](../SLEEP_SYSTEM.md) ·
[`lib/features/sleep/`](../../lib/features/sleep/FEATURE.md)

## Context

Sleep is the missing number in ZIVO's coach: it explains a bad session and
gates progression, and it is the one recovery variable a user can act on.
Adding it means reading data ZIVO does not produce, from stores that mix
sources of wildly different reliability — an Apple Watch, an under-mattress
mat, a time somebody typed into Health last Tuesday — and presenting the
result as one number.

The platform research (SLEEP_SYSTEM §3–§7) turned up four facts that shape
everything else:

1. **HealthKit has no sleep session.** It stores overlapping interval samples;
   sessionising is the app's job. Health Connect stores real sessions.
2. **An iPhone with no watch produces no sleep data at all** since iOS 18
   removed "Track Time in Bed with iPhone".
3. **iOS never discloses a denied read.** Denied and empty are the same
   observation.
4. **Device activity is not available on iOS at all** (Screen Time data cannot
   leave its report extension's sandbox) and *is* available on Android.

## Decision

**1. Provenance is a stored field, set at ingest, on every session.**
`SleepMethod` (how it was produced) and `SleepConfidence` (how much we trust
this record) are separate axes; `completeness` is explicit. A wearable night
with 40% sample coverage is `measuredWearable` *and* `low`, and collapsing
those into one field would force a lie either way.

**2. Ranking is on method, never on provider.** "Apple Health data" is not a
tier, because Apple Health *contains* hand-typed entries. `methodFor` tests the
platform's manual flag **before** any device signal — tier 4 routinely arrives
dressed as tier 1.

**3. The copy contract lives in one file.** "Asleep 1:47 AM", "You logged 1:30
AM" and "Likely asleep around 1:45 AM" are three different claims, and which
one a screen may make is decided by `SleepMethod` in `sleep_labels.dart`.
Estimates round to the quarter hour there, because a hedge wrapped around a
minute digit contradicts itself.

**4. Conflicts are resolved by choosing, never by merging.** Losing candidates
are kept as alternates so the UI can show disagreement. An averaged night is
one no device measured and no algorithm validated.

**5. Gates are types.** `sleep_metrics.dart` returns `null` where a figure has
too few nights, and clock times are averaged with circular statistics.

**6. The AI interprets; it never computes.** It receives a fact sheet of
finished numbers plus an explicit list of what it may not discuss, and every
numeral it writes is checked against that sheet before display — on the server
and again on the client. Same posture as
[ADR-003](ADR-003-ai-mutations-v2.md): the model proposes, deterministic code
decides. Beneath it sits a deterministic tier that is always available, so the
feature never depends on a model round trip to say something true.

**7. Device activity is out of v1.** Not because Android cannot read it, but
because it exists on one platform only, and any product surface built on it is
a feature half the users can never have. It may return as an Android-only
assist to manual logging — never as a data source.

## Consequences we accepted

- **The `health` package (v13) is a new dependency.** It was chosen over a
  hand-rolled Pigeon channel for one reason that decided it: it already
  surfaces `sourceId`/`sourceName`/`sourceDeviceId`/`recordingMethod`, which is
  ZIVO's provenance model, and re-deriving that for both platforms is the
  expensive part. Its gaps are additive work behind `SleepSource`.
  **Migration trigger:** background delivery. `HKObserverQuery` +
  `com.apple.developer.healthkit.background-delivery` and
  `HKAnchoredObjectQuery` have no package equivalent, and the day sync should
  happen without the app being opened is the day a native layer is written —
  exposing `RawSleepRecord` plus an added/deleted delta, so nothing above the
  seam changes. (Health Connect change tokens the package *does* expose.)
- **Android `minSdk` rises 23 → 26.** Health Connect's client requires it and
  the manifest merger fails below it. The cost is Android 6.0–7.1; the
  alternative was no sleep data on Android at all.
- **Violet now also means night.** `train_tokens.dart` already bound violet to
  "the Today header's do-not-disturb/night chip", so Sleep is the full
  expression of an association the palette had rather than a fifth hue —
  which [ADR-006](ADR-006-one-design-system.md)'s four-hue system has no room
  for. Within Sleep the hue marks **measurement**, not "sleep": a typed guess
  gets neutral ink, because giving it the same colour as a wrist sensor would
  undo in one glance what the pipeline is for.
  - **Amended 2026-09-07 — Sleep takes the blue end of that hue.** The screen
    borrowed `violet`/`violetGlyph` directly, which is Ask's lavender at ~242°,
    and a night screen dressed in the assistant's colour read as the assistant.
    Sleep now has three named tones of its own — `sleepAccent` / `sleepGlyph` /
    `sleepWash`, at ~225° — and nothing on the screen takes `violet` directly.
    Still one hue, walked toward blue; the four-hue table is unchanged, so this
    is a shade rather than an ADR-006 amendment. The header's targets button was
    the visible cost of not having done this: it sat on `TrainHeaderAction`'s
    default **green** accent — training's colour — on a screen that measures
    neither training nor money, and it was the only warm thing on an otherwise
    cool page.
- **No correlations, in v1 or probably ever** as originally imagined. At n≈30
  nights, one user, no controls and confounded variables, a scan across
  candidate pairs surfaces spurious findings faster than real ones. If they
  ship it is with a pre-registered, fixed hypothesis set, a visible n, and
  explicitly observational language.

## Alternatives rejected

- **Rank by provider** (Health > manual). Rejected: promotes a typed guess in
  Apple Health above the user's own honest tap in ZIVO.
- **Merge overlapping sources into a consensus night.** Rejected as
  fabrication with two real numbers' credibility behind it.
- **A single `confidence` field.** Rejected: it cannot express "a real
  measurement we only half-covered".
- **Let the AI compute the metrics.** Rejected: it moves the one thing that
  must be deterministic into the one component that cannot be.
