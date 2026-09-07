# sleep — feature map

> Sleep as a **recovery input to training**, read from Apple Health / Health
> Connect and logged by hand, with every number carrying how it was produced.
> Design + the platform research behind it: [`docs/SLEEP_SYSTEM.md`](../../../docs/SLEEP_SYSTEM.md).
> The decisions: [ADR-010](../../../docs/DECISIONS/ADR-010-sleep-provenance.md).

## The one rule

A number ZIVO cannot source is a number ZIVO does not show. Three mechanisms
enforce it, and none of them is a convention someone has to remember:

1. **`SleepMethod` is set at ingest from platform metadata**, never guessed
   later (`domain/sleep_provenance.dart`). By the time a session reaches a
   widget, an Apple Watch measurement and a hand-typed entry look identical.
2. **The words change with the method.** `presentation/sleep_labels.dart` is
   the only place a sleep sentence is built, so a widget cannot make a stronger
   claim than its data supports.
3. **Gates return null.** `domain/sleep_metrics.dart` yields `null` where a
   figure has too few nights, so the type system carries the gate.

## Start here

| File | What it is |
|---|---|
| `domain/sleep_provenance.dart` | `SleepMethod` · `confidenceFor` · **`methodFor`** — the tiering rules |
| `domain/sleep_session.dart` | one episode from one provider; UTC instants + lived offsets |
| `domain/sleep_night.dart` | one sleep-day: chosen main + naps + alternates + why |
| `domain/sleep_sessionizer.dart` | pure: raw records → sessions (stitches iOS fragments) |
| `domain/sleep_resolver.dart` | pure: candidates → a night (chooses, never merges) |
| `domain/sleep_metrics.dart` | pure: circular stats + the `SleepGates` thresholds |
| `domain/sleep_insight.dart` | the AI fact sheet, the numeral gate, deterministic drafts |
| `domain/sleep_service.dart` | the ingest pipeline + manual logging |
| `domain/sleep_source.dart` | **the platform seam** (`SleepSource`, `RawSleepRecord`) |
| `data/health_sleep_source.dart` | HealthKit + Health Connect, via the `health` package |
| `data/sleep_night_codec.dart` | the Firestore wire format — the durability boundary |
| `presentation/sleep_labels.dart` | **the copy contract** |
| `presentation/pages/sleep_page.dart` | the whole screen: tonight · last night · week · insights, over a docked action |
| `presentation/widgets/sleep_about_sheet.dart` | what the feature does, for a user who has never seen it |

## Wiring

- Built in [`app.dart`](../../app/app.dart), exposed as `AppScope.sleep` /
  `AppScope.sleepService` (both nullable; read via `requireSleep` /
  `requireSleepService`).
- Firestore: `users/{uid}/sleepNights/{yyyy-MM-dd}` +
  `users/{uid}/sleepSettings/main`. Rules + rules tests exist for both.
- Entry points: the Hub's Sleep card, and `SleepGlanceSection` on Today.
- Backend: `functions/ai/sleep_insights.js` — prompt, numeral gate, validation.
  **Not yet wired to a callable**; the client runs the deterministic tier.

## Gotchas

- **iOS has no sleep sessions.** HealthKit stores overlapping interval samples
  and one night is dozens of them. `sleep_sessionizer.dart` stitches; Health
  Connect records skip it via `RawSleepRecord.preSessionized`.
- **An iPhone with no watch produces nothing.** iOS 18 removed time-in-bed
  tracking. Manual logging is core, not a fallback.
- **iOS never reports a denied read.** Denied and empty are indistinguishable,
  so the UI may never say "you have no sleep data" — see
  `SleepController.canAssertNoData`.
- **A manual entry can arrive through Apple Health carrying watch metadata.**
  `methodFor` tests `recordingMethod == manual` *first*, before any device
  signal. Moving that check breaks the whole tiering.
- **Never average two providers.** The resolver picks one and keeps the rest as
  alternates. An averaged night is one nobody measured.
- **Never fill a null.** No in-bed data means no efficiency, not 100%.
- **Clock times are averaged on a circle.** `circularMeanMinutes` is the only
  sanctioned way; the arithmetic mean of 23:40 and 00:20 is noon.
- **Durations come from UTC instants, never wall clock** — a DST-spanning night
  is an hour off otherwise, and looks right.
- **A user edit must survive the next sync.** `_resolveAndStore` feeds stored
  user sessions back in as candidates; a plain overwrite silently undoes every
  correction an hour later (`test/sleep/sleep_service_test.dart`).
- **`SleepService.syncState` is a `ValueNotifier`, not a stream.** A fast sync
  emitted its terminal state into the window between `listen()` and an
  `async*` generator actually subscribing, and the UI never saw it.
- Android's `health` package does not expose Health Connect's
  `Metadata.device.type`, so `deviceKind` is `unknown` there and tiering falls
  to `kWearableProviderPrefixes` + `recordingMethod`.
- **The state a tap creates must be visible from where the tap happened.**
  "I'm going to sleep" used to be the last widget in the scroll and the open
  session rendered *in its place*, at the bottom of a page long enough to push
  the result below the fold — so the screen's only control looked inert. The
  action is docked below the list now and the session is announced at the top
  (`_SessionCard`), so one tap changes two places and neither can be
  off-screen. `sleep_page_test.dart` asserts the card's *position*, not just
  its presence.
- **Every repository subscription carries an `onError`.** `_hasLoaded` used to
  flip only in the data handler, so a refused read left the headline rendering
  its not-yet-loaded placeholder for the life of the screen, with the week and
  the insights below it looking healthy. `SleepController.loadFailed` is the
  third state, and `retryLoad` **re-subscribes** — a Firestore snapshot
  listener that errored is finished, so re-reading the health store alone
  would fix nothing.
- **Nothing on this screen takes `TrainColors.violet` directly.** Sleep has its
  own three tones (`sleepAccent`/`sleepGlyph`/`sleepWash`) — same hue, walked
  toward blue so the night screen is not the assistant's lavender. ADR-010's
  amendment has the reasoning.
- **The insights section is Manrope, not `AppText.aside`.** The one sanctioned
  exception to ADR-009's italic-serif rule; the note is in that ADR.
