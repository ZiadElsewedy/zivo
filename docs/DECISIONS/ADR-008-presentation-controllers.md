# ADR-008 — A controller layer inside `presentation/`

**Status:** accepted · **Date:** 2026-09-01

## Context

ZIVO's feature layering (`presentation/` → `domain/` → `data/`) was only ever
enforced at the repository seam. Inside `presentation/` there was no seam at
all: a page was a `StatefulWidget`, and its `State` held both the screen and
everything the screen did.

That worked until three screens outgrew it.

- [`live_session_page.dart`](../../lib/features/workout/presentation/pages/live_session_page.dart)
  was **4,236 lines**: one `State` with three independent clocks (rest,
  warm-up, elapsed), a `SharedPreferences` countdown that survives an app
  kill, a debounced draft autosave, a history subscription and the
  set-resolution state machine — followed by ~30 private widget classes.
- [`ask_page.dart`](../../lib/features/ai/presentation/pages/ask_page.dart)
  was **3,061 lines**: optimistic-bubble/durable-message reconciliation,
  idempotency keys that survive retries, a per-frame streamed-reply pacer, a
  slow-turn admission, a landing watchdog, and the voice path.
- [`workout_plan_edit_page.dart`](../../lib/features/workout/presentation/pages/workout_plan_edit_page.dart)
  was **1,813 lines**, and hid the subtlest rule in the feature: a plan stores
  its rotation `cycleCursor` as an *index*, but the editor lets days be
  dragged, so the cursor has to be tracked by day *identity* through the edit
  and resolved back to an index on save. Get it wrong and the app silently
  offers you the wrong workout tomorrow. That rule was 30 lines inside a
  `_save` method.

Three concrete costs, not stylistic ones:

1. **The rules were only testable through a widget.** "A rest that expired
   while the app was backgrounded advances the set on resume" needed a
   `WidgetTester`, a fake clock and a key-based finder. So did "a retry reuses
   the turn id." These are statements about a session and a turn; nothing
   about them is visual.
2. **Private classes forced private coupling.** Thirty widgets in one file
   shared file-private helpers (`_trimWeight`, `_formatRest`) because a
   file-private function was the only thing thirty classes in one file *could*
   share. One test had to find a widget by matching `runtimeType.toString() ==
   '_RiseOnce'`, because there was no type to name.
3. **Mutable state was reachable from `build`.** "Is a rest running" was
   answerable from two places, and both could be written from inside a widget.

## Decision

Each large screen gets a **controller** in
`lib/features/<x>/presentation/controllers/`, a plain **`ChangeNotifier`** that
owns everything the screen *does*. The page keeps `build` and the state that is
genuinely about widgets on a screen.

Explicitly **not** a new state-management package. `AGENTS.md` requires an ADR
before `riverpod`/`bloc`/`provider`/`get_it` enter the codebase, and none of
the problems above is a dependency-injection problem — `AppScope` already
solves that. `LocaleController` and `MusicController` already established
`ChangeNotifier`/`ValueNotifier` as the app's notification material.

Three rules keep the seam honest:

- **A controller never navigates.** `finish`/`leave`/`discard` do their writes
  and return a bool; the page pops. A controller that could `Navigator.pop`
  would be back to knowing about widgets.
- **A controller never holds a `BuildContext`.** Where it must reach the
  screen it takes a callback (`onError`, `onContentGrew`). It tracks its own
  `_disposed` flag instead of asking whether a widget is `mounted`.
- **Genuinely visual state stays in the page.** Scroll position and
  auto-follow, entrance-animation ledgers, and "which bubble is mid-typewriter"
  are statements about a list of widgets. Moving them into a controller would
  have swapped one tangle for another.

Values the widget tree owns and the controller needs — a `TickerProvider`,
`MediaQuery`'s reduced-motion flag — are passed in as parameters.

Widgets that were private classes inside a page become real files under
`presentation/widgets/<screen>/`.

## Consequences

**Good.** `live_session_page.dart` is 4,236 → 519 lines,
`workout_plan_edit_page.dart` 1,813 → 416, and `ask_page.dart` 3,061 → 781,
with the logic in three controllers. 33 new unit tests assert session, turn and
plan-edit rules directly, with no widget tree, in under a second. All 992
pre-existing tests still pass unchanged, which is the evidence that the split
preserved behaviour.

Splitting also exposed duplication that had been invisible inside big files:
warm-up and rest were two ~90-line copies of a screen the code's own comments
called identical (now one `CountdownPhase`), and `trimWeight` existed twice
with identical bodies (now one `workout_format.dart`).

**Costs.** A controller and its page are two files to open instead of one, and
the callback seam (`onError`, `onContentGrew`) is indirection that a single
`State` did not need. Both are the price of the rules being assertable.

**Not done, deliberately.** Three screens were converted — the three whose
logic had genuinely outgrown a `State`. The other large files are large for a
different reason: `diet_plan_page.dart` (1,340 lines) and
`workout_progress_page.dart` (1,122) contain **zero** `setState` calls. They
are big *declarative* files, and a controller would give them nothing; what
they want is splitting into widget files.

**The threshold is not a line count.** Reach for a controller when a page's
rules are ones you would want to assert without pumping it. Measured crudely:
`setState` density plus owned `Timer`/`Stream`/`Ticker` lifetimes, not size.
