# STATE — where ZIVO is right now

> **The single source of truth for "current state."** Small on purpose. Read it every
> session; update it when you finish a task. For *what ZIVO is + what makes it different*
> see [`PRODUCT.md`](PRODUCT.md); for *how the code is organized* see
> [`/AGENTS.md`](../AGENTS.md) and each feature's `FEATURE.md`; for *why* decisions were
> made, see [`DECISIONS/`](DECISIONS). The **code is the ultimate source of truth** — if
> this file disagrees with the code, fix this file.

**Last updated:** 2026-09-11 · **Active branch:** `feature/theme-modes`
(cut from `feature/sleep`, which is 60 commits ahead of `version-1`)
(`version-1` is 51 commits ahead of `main` — worth a merge).

---

## Positioning (current)

**AI-powered gym / training tracker** — built around an AI coach that knows your numbers,
not a log with a chatbot bolted on. Full positioning + differentiation: [`PRODUCT.md`](PRODUCT.md).

## The app in one paragraph (current)

Firebase-backed Flutter app (`USE_FIRESTORE` defaults **true**; in-memory repos are the
offline/test fallback). **Dark and light** (`ThemeMode` — dark · light · match the
phone; defaults to dark, device-local, [ADR-011](DECISIONS/ADR-011-light-mode.md)).
Shell is a 4-tab
`IndexedStack`: **Today · Hub · Ask · You** with a floating "island" bottom bar and a
center capture FAB. Sign-in gate is [`AuthGate`](../lib/features/auth/presentation/auth_gate.dart).
Live feature set: **workout, diet, expenses, moments, ai (Ask), music (Spotify companion),
auth/profile, home/Today, hub, capture, device (steps), sleep, reminders (local
notifications)**.

## Scope (standing decisions)

- **In scope:** fitness-first personal OS — workout · diet · expenses · moments · Ask AI ·
  music companion. See [ADR-004](DECISIONS/ADR-004-scope-specialization.md).
- **Removed for good (do not resurrect without the owner asking):** Schedule, Tasks,
  University, Notes (removed 2026-08-24).
- **One design system, two skins** (dark 2026-08-29, light 2026-09-08). ADR-006's
  *one system* stands; its *dark-only* half is superseded by
  [ADR-011](DECISIONS/ADR-011-light-mode.md). The values live in `ZivoPalette.dark` /
  `.light`; `TrainColors` keeps its exact API as getters over whichever is active, and
  `ZivoTheme.use()` swaps it at the root *and repaints the whole tree* — nothing is
  subscribed to the palette, so a `const` screen would otherwise keep the skin it was
  first built in (that shipped broken once; see the ADR).
  Light also forced two fixes the dark skin was hiding: the sleep axis labelled
  seven clock times into a chart with room for four hours, and the weekly card
  captioned six gated figures "1 of 3 nights" under a header reading
  "1 of 7 nights".
  **The rule this adds: never cache a token** —
  not in a field, not in a `static final`, not in `initState`. A `static` field is
  evaluated once and pins the app to whichever skin drew first. A new colour must be
  added to *both* palettes (the constructor requires every field, so this is a compile
  error, not a review catch).
- **One dark system, app-wide** (done 2026-08-29, audit C1 + the v2-flow redress). Recorded
  as [ADR-006](DECISIONS/ADR-006-one-design-system.md) — read that for the rationale and the
  rules future work must follow.
  Everything dresses from `TrainColors`. `AppShadows` is **deleted** — the v2 elevation
  system is gone; depth comes from light (identity §5), and the only shadows left are the
  coloured `TrainColors.actionGlow` under primary pills. `AppColors` survives in exactly
  **one** file, `category_hue_colors.dart`, which feeds the add-category colour picker's
  swatches; it goes when that picker's fate is decided (see C2's consequence below).
  The two foundational edits did the most work: `AppText`'s default ink and
  `AppTheme`'s `scaffoldBackgroundColor` were warm, so every screen that didn't override
  them inherited a warm cast — including the cool handoff ones.
- **One type system, app-wide** (done 2026-09-01). Recorded as
  [ADR-009](DECISIONS/ADR-009-one-type-system.md). ADR-006 unified colour but left
  typography split: `AppText` was still Brand v2's **Bricolage Grotesque / Hanken Grotesk /
  Fraunces** — three faces chosen for the deleted warm off-white skin — while `TrainType`
  carried the handoff's **Azeret Mono / Manrope / Instrument Serif**. Five families, two
  systems, meeting on 14 files (`today_page.dart` included). Now **three families, named in
  exactly one file** (`train_tokens.dart`): Manrope = text/prose/titles/chrome, Azeret Mono =
  numbers/timers/micro-labels (tabular, never prose), Instrument Serif italic = ZIVO
  speaking — **italic in Latin only**; see the Arabic pass below for why RTL gets the
  same face upright. `AppText` survives as the **named ladder** built on those builders — its ~500
  call sites are untouched — because `AppText.rowTitle` (what a thing *is*) and
  `TrainType.mono(size: 54)` (a size) answer different questions. `GoogleFonts` is called in
  one file. Deliberate visual changes: display steps up one weight, `body` w400→w500 (45%
  ink on near-black), `heroNumber`/`amount` to mono, and `aside` to Instrument Serif — which
  fixes a rule that was inverted in practice (the "reserved" serif had 1 call site while
  Fraunces did the same job at 24). `AppText.dateLabel` was dead and is deleted.
  **Follow-up not done:** the three families are still fetched at runtime by `google_fonts`;
  bundling them in `pubspec.yaml` would remove the first-launch fallback-then-reflow.
- **Hue discipline: hold the rule strictly** (owner decision, 2026-08-29, audit C2 —
  **implemented**; rationale in [ADR-006](DECISIONS/ADR-006-one-design-system.md)). A hue appears only where it means its thing: green = training/state,
  ember = the single committing action, amber = money, violet = system/meta. Grids
  differentiate **by icon**, not colour. In practice: the Hub's module grid and Recent rows
  lead with `TrainColors.neutralMark` (no hue owns "Diet" or "Moments"); every Workout
  stat tile and drill-down accent is green (they all measure training — Duration was violet
  and Usual-start was amber); account rows on You/Settings are violet, with ember left for
  Delete account alone; and Expenses is all-amber, bars and spines included.
- **Music/Spotify is IN** — it was briefly deleted in that same pass but the owner
  restored it (reshaped as a workout companion). Treat it as a first-class feature.

## Recently landed (verified in code on `version-1`)

- **Reminders v2 — kinds, an iOS wheel picker, a de-purpled premium UI, and plan
  sync** (2026-09-11, on `feature/reminders-sync`, cut from
  `feature/workout-analysis-redesign`). Owner wanted the basic reminders feature to
  feel premium and actually pull from the user's plans.
  - **Kinds are now General · Meal · Workout** — `ReminderKind.other` → `general`
    (reordered first). Legacy stored `"other"` folds into `general` on decode, so no
    migration. Default new-reminder kind is `general`.
  - **iPhone-style time wheel.** The Material `showTimePicker` dialog is replaced by
    a `CupertinoDatePicker` wheel in a `showZivoSheet`, themed to both skins and
    honouring the locale's 24h setting.
  - **No more purple.** The whole area drops `violet`/`violetGlyph` for a monochrome
    segmented look (solid ink-fill selected chips, hue-less `neutralMark` accents,
    native adaptive switches, ember only on Save, neutral `hubTint` screen wash) —
    respects ADR-006 hue discipline (no area invents a hue).
  - **Sync.** New optional `ReminderSync` on a reminder (nullable, back-compatible
    codec). **`MealSync`** — "Sync from your plan" pulls the meal scheduled for the
    day from the active diet plan, the user picks which one, then adds/removes items;
    stored as a snapshot and listed in the notification body. Editing there **never
    touches the diet plan or food log.** **`WorkoutSync`** — a "Sync with my plan"
    toggle links the reminder to the active plan; its notification text is
    re-resolved to the current next-up rotation day (name + short exercise line)
    every reschedule. `app.dart` now watches `workoutPlans.watchActivePlan()`
    alongside `reminders.watch()` and passes a `ReminderContext`, with a **dedupe
    guard** so unrelated plan writes don't churn the platform channel (also the main
    perf win here). Notifications now carry a **body**, not just a title.
  - **Honest caveat** (owner-chosen "smart/auto-refresh"): a `WorkoutSync`
    notification's text is fresh as of the last reschedule (app open/resume or plan
    change) — the OS fires pre-scheduled alarms and can't recompute the rotation at
    fire time. [ADR-013](DECISIONS/ADR-013-local-notifications.md) unchanged (still
    local-only, inexact).
  - **Cover:** +9 reminders tests (sync codec + legacy-kind decode, meal/workout
    body resolution via `ReminderContext`, the Cupertino wheel opening, a synced
    row), whole suite **1548** green, `flutter analyze` clean, 10 new ARB keys in
    both languages.
  - **⚠ OWNER ACTIONS.** (1) ~10 new Arabic strings are mine, not a native
    speaker's — worth a check. (2) On-device confirmation that reminders fire and
    that a workout-synced reminder reflects the next-up day (unchanged from ADR-013).

- **The profile avatar moved to Firebase Storage; moments stay on Drive**
  (2026-09-11, on `feature/workout-analysis-redesign`). Owner report: an avatar
  set on one device didn't appear on another. Root cause was structural — the
  avatar rode the `core/media` local-first + Google Drive pipeline (like a
  moment), so only its store *ref* synced (`UserProfile.photoPath`); the bytes
  reached a second device only if the same Drive account was connected there.
  Correct for a bulk moment, wrong for identity. **Decision
  [ADR-014](DECISIONS/ADR-014-avatar-firebase-storage.md):** the avatar's bytes
  now go to **Firebase Storage** at `avatars/{uid}`, with the download URL in
  `users/{uid}.photoUrl` — syncs everywhere the profile doc does, no Drive
  needed. **Moments are unchanged** and still live in each user's own Drive
  (off ZIVO's bill). New seam `AvatarStorage` (`profile/domain`) +
  `FirebaseAvatarStorage` (`profile/data`) + a fake, wired through
  `AppScope.avatarStorage`. `UserProfile` gains `photoUrl`; legacy `photoPath`
  still renders on a device that holds it but is cleared on the next avatar
  change (old local/Drive copy deleted). New dep `firebase_storage: ^13`; new
  `storage.rules` (owner-write, image + 5 MB cap, authed-read) wired into
  `firebase.json`; `firestore.rules` `users/{uid}` now pins `photoUrl`
  (+3 rules tests). `flutter analyze` clean, profile tests green. **⚠ OWNER
  ACTIONS:** `flutter pub get`; iOS `pod install` (adds the `firebase_storage`
  pod); and `firebase deploy --only firestore:rules,storage` — until the
  storage rules deploy, avatar upload is denied and the original bug persists.

- **Local reminders — the notification system** (2026-09-11, on
  `feature/ask-elicitation`). The simplest practical version the owner asked
  for: the user schedules a local notification for a meal, a workout, or any
  other activity and the OS fires it at that time. **Local only** — no push, no
  backend ([ADR-013](DECISIONS/ADR-013-local-notifications.md)). New
  `features/reminders/`: one flat `Reminder` (`label · kind · time · repeat-days
  · on/off`) covers all three cases; one **Reminders** page reached from
  Settings; storage in one schema-free doc `users/{uid}/settings/reminders`
  (`RemindersRepository`, Firestore/in-memory — **no rules change**); and a
  `NotificationScheduler` seam (`flutter_local_notifications` +
  `timezone`/`flutter_timezone`, or a no-op offline/in-tests). The OS's
  scheduled set is a pure mirror of the stored reminders, kept in sync at app
  root off `reminders.watch()`. Scheduling is **inexact** (no
  `SCHEDULE_EXACT_ALARM`); permission is asked on first enable, not at launch.
  Three new deps (justified in `pubspec.yaml` + the ADR). Platform config added
  (`AndroidManifest`: POST_NOTIFICATIONS/RECEIVE_BOOT_COMPLETED + two receivers;
  `AppDelegate.swift`: the `UNUserNotificationCenter` delegate); `minSdk` 26
  already covers the plugin. Cover: 17 new reminders tests (codec/logic, repo,
  the pure `reminderOccurrences` plan, page) + the 3 app-boot tests now inject
  the no-op scheduler; whole suite **1539** green, analyze clean. **Owner
  action: only a real device can confirm a reminder actually fires at its set
  time and that the iOS/Android permission prompts appear.**

- **Single-device session enforcement — one account = one active device**
  (2026-09-10, on `feature/ask-elicitation`). The same account signed in on two
  devices was corrupting Google Drive / Moments sync. Now a sign-in *or* app
  launch/restore **claims** the account: `DeviceSessionGuard`
  ([`lib/features/auth/data/device_session_guard.dart`](../lib/features/auth/data/device_session_guard.dart))
  writes a fresh `sessionId` to the server-owned ledger
  `users/{uid}/session/current` (an atomic replace, `DeviceSessionRepository` →
  Firestore/in-memory) and watches that doc in real time. The moment the stored
  `sessionId` is no longer this device's, the device signs out of Firebase Auth
  (the gate returns to `AuthPage`) and shows *"Your account was signed in on
  another device."* Firebase Auth alone can't do this — it keeps every device's
  token valid independently — so the ledger is the source of truth; the realtime
  listener is what makes the takeover immediate. Once signed out the stale device
  is `request.auth == null` and fails `canWrite` on every collection, so it can no
  longer touch account-level Drive/Moments data. Wired in
  [`app.dart`](../lib/app/app.dart)'s `_authSub` (claim/teardown) and exposed via
  `AppScope.deviceSession`. New `firestore.rules` block `users/{userId}/session/{docId}`
  (owner-only, shape-pinned, `isOwner` not `canWrite` so unverified accounts are
  still enforced); covered by `firestore-tests` (171 pass) and
  `test/auth/device_session_guard_test.dart` (4 pass). **Owner action: rules deploy
  — see below.**

- **Bottom sheets are opaque again** (2026-09-10, on `feature/theme-modes`). Owner
  review: most sheets "looked transparent" — the launching screen showed straight
  through them. Two causes: `SheetShell` (the plan-edit sheets: Edit exercise / day /
  default-rest) and `workout_capture_page`'s exercise sheet painted their whole ground
  with `sectionFill` (~3% opacity on dark) — a tint token meant to sit *on top of* a
  surface; and every other sheet used `raised` (~94%), a faint but real bleed. Fix: a
  dedicated **opaque** `sheetSurface` token (dark `0xFF141514`, light `0xFFFFFFFF` —
  `raised`'s tone without the alpha), in both skins per ADR-011, exposed on `TrainColors`
  and painted by `ZivoSheetSurface`, `SheetShell`, and the ~13 sheets that grounded
  themselves directly. Cards keep `raised`; translucent depth stays the `glass*` tokens'
  job. Profile's `_EditTextSheet` was the last translucent one — a `BackdropFilter`
  frosted card — and is now solid too (blur dropped, since it does nothing behind an
  opaque surface). Every bottom sheet is now an opaque `sheetSurface`.

- **Sleep split into a dashboard and a history view, and its freshness fixed**
  (2026-09-08, on `feature/sleep`). Owner review: the dashboard was confusing,
  the numbers did not obviously relate to each other, and the data looked
  stale. The audit found the engine sound — the sessionizer, resolver, metrics
  and codec all do what `SLEEP_SYSTEM.md` says — and the defects concentrated
  in the last two layers.
  - **The screen carried five time bases at once.** Last night's hero sat
    directly above a seven-row raster, three weekly averages and a comparison
    to a *different* week. `sleep_page.dart` is now the dashboard — one night,
    in five bands: the figure, its stages, its measured detail, its target,
    what it means. Every window figure moved to the new
    `sleep_week_page.dart`, reached from a row at the foot. **Not** added to
    app Settings: that page is app behaviour, and this is content.
  - **"Last night" was said about nights that were not last night.** The
    headline showed the most recent night with data, undated, however old.
    `SleepController.latestNight` / `isLatestNightStale` now date it ("3 nights
    ago") and say so under the figure; the Today glance carries the same
    qualifier.
  - **The trend gate could never open.** Every automatic sync read
    `refreshDays` (7) while the trend wants 14 nights across 21 days;
    `backfillDays` (90) was reachable only from `requestAccess`. The first sync
    of a process now backfills when stored history is shallower than that.
  - **Nothing outside the Sleep page ever read the health store.** Today's
    glance and the Hub card render the Firestore mirror, so a user who did not
    open Sleep saw whatever was written the last time they did. `app.dart`
    syncs on sign-in and on resume, throttled in the service so all callers
    share one budget; the page re-syncs on resume too.
  - **Stages were ingested, ranked on, persisted — and never drawn.** New
    `sleep_stage_breakdown.dart` (pure, and null far more readily than a sum:
    no graded stages, under 60% coverage, or overlapping samples) plus
    `sleep_stage_split.dart`. Weekly averages count staged nights only and
    print that denominator.
  - **Window arithmetic was re-derived per caller.** `sleep_window.dart` is now
    the single definition; the controller, the history pager and the
    comparison all read it.
  - **Coverage:** 106 sleep tests (up from 76) across three new files
    (`sleep_stage_breakdown_test`, `sleep_freshness_test`,
    `sleep_week_page_test`); whole suite green (1338).
  - **Not verified on device** — owner is testing it.

- **The streak became one engine with a rule, and a session's duration became a
  measurement** (2026-09-08, on `feature/theme-modes`).
  [ADR-012](DECISIONS/ADR-012-streaks-and-session-duration.md) has the full
  reasoning; the short version:
  - **Two streak engines disagreed, and both broke on DST.**
    `training_dashboard_stats.dart` bucketed by `startedAt`,
    `today_pulse.dart` by `completedAt ?? startedAt`, and both walked the
    calendar with `Duration(days: 1)`. Verified in `Africa/Cairo`: stepping
    back from `2026-04-25 00:00` lands on `2026-04-23 23:00`, skipping 24 April
    entirely — **the day streak zeroed itself twice a year**. Now one engine
    (`workout/domain/training_streak.dart`, Today delegates) over
    `core/util/calendar.dart`, which is DST-proof by construction.
  - **The rule changed from "every day" to "at least every 3 days"**
    (`kStreakMaxGapDays`). A day counts on one **completed working set**, so a
    partly-logged session counts in full — and counts whether or not Finish was
    ever tapped. Two sessions in a day are one day.
  - **Missed-day reasons and streak restores** land in a new
    `trainingDayMarks/{yyyy-MM-dd}` collection. A reason is context and never
    moves the number; a restore bridges a gap, is rationed (1 per 30 days,
    reaching back 7), adds no trained day, and is excluded from the all-time
    best. Kept out of the sessions store on purpose.
  - **`LoggedSet.resolvedAt`** makes duration a measurement. A session left
    open is closed at its last logged set (real 62 minutes, not 19 hours),
    never capped, and records `DurationSource.unknown` rather than guessing when
    there is nothing to close at. Staleness needs past-the-maximum AND 30 min of
    silence, so a genuinely long workout is never closed mid-set.
  - **The maximum is a user setting** (`settings/workout`, default 3h, clamped
    30 min–12 h), with a Training settings page under Workout → More.
  - **Implausible durations are excluded and flagged, not averaged.** The
    drill-down says "over 23 of 24"; correcting one is an amendment
    (`correctedDurationMinutes` + `DurationSource`) that never rewrites the
    timestamps and structurally cannot touch a set.
  - **Finish now** ends a session with sets outstanding — pending sets stay
    pending, nothing is invented. Background time past the grace window is
    folded into `pausedAccumMs` instead of counting as training.
  - **A stale session no longer hijacks Up Next**, and `SessionMaintenance`
    (wired at app root on sign-in + resume, like `SleepService`) closes it —
    deferring to whatever session a live screen has open.
  - **A session that recorded work is voided, not deleted** (`SessionStatus.voided`
    + `VoidReason`). Swipe-to-delete in History and Delete on Session details are
    gone; hard delete survives only for a session with nothing logged.
  - **Backend mirrors the gate**: `functions/ai/tools.js` honours a correction
    and withholds an implausible/unknown duration from the coach.
  - Cover: Flutter **1499** green, analyze clean. New suites:
    `test/core/calendar_test.dart` (19 — incl. a DST group that *discovers* the
    ambient zone's real transitions, so it is meaningful in any DST zone and
    skips cleanly in none), `test/workout/training_streak_test.dart` (39, with
    its own DST group), `session_duration_test.dart` (37),
    `session_maintenance_test.dart` (13), `workout_streak_page_test.dart` (3),
    plus Finish-now and background-clock groups in
    `live_session_controller_test.dart` and a stale-session regression in
    `workout_plan_page_test.dart`. Fixtures moved to the shared
    `test/support/workout_fixtures.dart`, which gives every session a real
    completed working set — the old `exercises: const []` sessions read like
    trained days and are not. Rules suite **167** green (new `trainingDayMarks`
    block + `voided`/corrected-duration validation). Functions **442** green.
  - The three tests that boot the real `ZivoApp` now inject the two new
    repositories, for the reason already commented there: an un-injected
    default is Firestore-backed and reaches Firebase at construction.
  - **Owner action:** `firestore.rules` changed — needs a deploy
    (`trainingDayMarks` is denied by the catch-all until then, so restores and
    missed-day reasons will fail to save on device).

- **The Sleep page redesigned, and two of its silences fixed** (2026-09-07, on
  `claude/sleep-page-redesign`). Owner review of the shipped screen: "the
  overall visual quality feels poor", the one control appeared to do nothing,
  and the feature was not self-explanatory. Four of the five findings turned
  out to have a mechanism behind them rather than a taste problem.
  - **Tapping "I'm going to sleep" really did look inert.** The pill was the
    last widget in the scroll and the open session rendered *in its place* —
    at the bottom of a page long enough to push the result below the fold. So
    the button you just pressed scrolled out of view and a line of grey text
    took its place where nobody was looking. The action is **docked** below
    the list now, and the session it opens is announced at the **top** of the
    scroll as its own card (elapsed so far, since when, and what actually
    records the night). One tap, two visible changes, neither off-screen.
    `sleep_page_test.dart` asserts the card's *position* relative to the week
    — presence alone would have passed on the old layout too.
  - **A read that failed rendered as nothing at all.** `SleepController`'s
    three subscriptions carried no `onError`, and `hasLoaded` only ever
    flipped in the nights *data* handler — so a refused Firestore read (or an
    undecodable snapshot) left the headline showing its not-yet-loaded
    placeholder **forever**: a silent 120px void between the title and the
    week, with everything below it looking perfectly healthy. There is now a
    third state (`loadFailed`) with its own card and a retry that
    **re-subscribes** — an errored snapshot listener is finished, so
    re-reading the health store alone would have fixed nothing — and the
    loading state is a skeleton rather than a gap. Covered by a repository
    whose `watchNights()` errors.
  - **The green button.** The header's targets action sat on
    `TrainHeaderAction`'s *default* accent, which is green — training's hue —
    on a screen that measures neither training nor money, and it was the only
    warm thing on a cool page. Sleep also borrowed `violet`/`violetGlyph`
    wholesale, i.e. Ask's lavender. Sleep now has three tones of its own
    (`sleepAccent`/`sleepGlyph`/`sleepWash`) at ~225° against Ask's ~242°, and
    a cooler screen wash. **Same hue, walked toward blue — not a fifth hue**,
    so ADR-006's table is untouched; ADR-010 carries the amendment.
  - **The italic serif is out of the insights section** (owner decision).
    `AppText.aside` at 21px italic over a paragraph on near-black was the
    least readable text on the screen, and it was carrying the screen's
    conclusions. That section is Manrope now. **Sleep only** — the ~25 other
    `aside` call sites are untouched and ADR-009's rule stands, with this
    logged there as its one exception.
  - **The rest of the redesign.** Sections are cards (hairline over a top-lit
    gradient — the house depth language) instead of content floating on the
    raw background; the three weekly figures went from three near-identical
    full-width grey sentences ("Not enough nights yet — 0 of 3", three times)
    to a three-up strip where a gated figure is an em dash over "0 of 3
    nights", with the window's own n moved once into the section label; the
    week-over-week line is labelled so it stops reading as a fourth stray
    figure; and "Why this number" / "Edit this night" are glass pills at a
    real touch target rather than 13px coloured captions.
  - **New: a "How Sleep works" sheet** behind an info button in the header —
    what a session is, what ZIVO reads and when, why every number names its
    source, why some figures are deliberately blank, and that there is no
    score. Sleep is the one feature here whose behaviour is not guessable from
    its screen: a tap opens something that records nothing until a second tap
    closes it.
  - **Coverage:** 76 sleep tests (up from 74), the whole suite green (1300),
    `flutter analyze` clean, 27 new ARB keys in both languages.
  - **⚠ OWNER ACTION.** The two symptoms above are consistent with
    `firestore.rules` **not being deployed** for the sleep collections — a
    denied read on `sleepNights` produces exactly the blank headline, and a
    denied write on `sleepSettings/main` produces exactly the "nothing
    happens" tap. The rules and their tests are in the repo and have been
    since the feature landed. Worth running `firebase deploy --only
    firestore:rules` and re-checking; the client now *reports* both failures
    instead of swallowing them, so it will say so if that is what it is.

- **Spotify syncs automatically; it no longer *launches* automatically** (2026-09-07,
  owner report). Opening ZIVO dragged the Spotify app on screen and started playing —
  and quitting Spotify just made it come back, so the only way to stop it was
  Settings → Disconnect. Cause: `spotify_sdk` spells two different things "connect", and
  the auto-reconnect at launch/resume/backoff was calling the wrong one.
  `connectToSpotifyRemote()` with no access token becomes iOS's `authorizeAndPlayURI`,
  which opens Spotify **and starts playback**; with a token it becomes
  `SPTAppRemote.connect`, which attaches to a running Spotify and fails harmlessly when
  there isn't one. `SpotifyMusicController` now keeps the two apart: every automatic
  attempt takes the silent path and **does nothing at all** when it has no token to take
  it with, while the authorizing path is reachable only from the user's own Connect tap
  (which itself tries the silent attach first). The token that makes silence possible is
  persisted by `SpotifyLinkStore`, whose doc no longer claims to hold no credential —
  see it for what the token is (App Remote scope, ~1h, no refresh token) and the
  Keychain upgrade path if that bar needs raising. Also: the connection-status channel is
  now subscribed for the controller's lifetime rather than only inside a successful
  connect (so a late or missed handshake self-corrects), a drop clears the track it was
  carrying, and the 2s→5s→12s→30s backoff is one 2s retry — a silent attach can't
  conjure a player the user has closed. Net behaviour: **Spotify playing → ZIVO syncs
  with no tap; Spotify closed → ZIVO stays disconnected; close Spotify → ZIVO stops
  syncing; Connect Spotify is a button.** Held by
  `test/music/spotify_music_controller_test.dart`, which asserts on the platform channel
  because both spellings look identical from Dart.

- **…and then the same sweep across the rest of the app** (2026-09-07). The
  Ask pass produced five recurring shapes; each was grepped for app-wide and
  the hits confirmed on a simulator in Arabic before being touched.
  - **The list divider inset was wrong on every card in the app.**
    `TrainListRow.dividerInset` was applied as a physical `left`, so in Arabic
    the hairline ran *under* the leading icon column and stopped short of the
    title it is documented to start at. One-line fix in `train_surfaces.dart`
    and `settings_row.dart`; visible on Settings, You, and every list surface.
  - **Four more composed runs were never pinned**: `~21` rendered `21~` on
    Today's next-workout card, `-2:47` rendered `2:47-` on Settings' Spotify
    card, and the live session's ± weight chips and progress percentage the
    same. `ltrFor` on the numeric skeleton only — the translated word beside it
    stays unpinned, per `core/util/bidi.dart`.
  - **Media controls do not mirror, everywhere** — not just the nav lozenge.
    The four `spotify_strip` densities and the full player's transport had the
    identical flip, and the scrubber's timecodes sat under the wrong ends of a
    bar that is positioned physically (raw `dx`, `Positioned.left`) and so
    always ran left-to-right. Track titles across the music surfaces now pick
    their own direction.
  - **English still on Arabic screens.** Today's diet glance was two
    interpolated sentences — and the meals half already had an ARB key the
    widget never read. Also the whole default-rest control on plan edit, the
    add-day sheet, `shortest`/`longest` on the session-length page, and two
    `domain/` label functions (`consumedBasisShortLabel`, `findingKindLabel`)
    rendered straight onto the diet plan and Today's Read cards. The domain
    halves stay where they are — the coaching engine splices them into
    generated English prose — and got presentation twins in `diet_labels.dart`.
  - **The standing guard has a hole worth knowing about.**
    `test/shell/rtl_layout_test.dart` boots the whole app in both languages and
    fails on any layout error, which is why none of this was caught: not one of
    these bugs throws. A mirrored control, a backwards run and an untranslated
    string all lay out perfectly. The new tests assert *position* (previous is
    left of next) and *content* (no English in an Arabic tree) instead — the
    transport one is verified to fail without its fix.
  - **The alignment sites were then swept too** (same day), all ~65 audited
    individually. About half were `LinearGradient(begin: topLeft, end:
    bottomRight)` — decorative diagonal sheen, deliberately left physical, as
    a gradient carries no reading order. Of the rest, seventeen `Align`s were
    genuinely leading/trailing chrome and moved to `AlignmentDirectional`: back
    chips on three auth screens and the live session, the profile's Settings
    button, "forgot password", the full player's close button, two generic
    progress fills (a *task* bar mirrors, unlike a media playhead), and two
    more swipe-to-delete reveals with the identical bug the sessions sheet had
    — `endToStart` paired with a physical `centerRight`, so the bin sat on the
    side the swipe never uncovers. Three `Positioned` badges (the avatar's
    camera, a stat tile's sparkline, the Spotify mark) became
    `PositionedDirectional`; twelve asymmetric `EdgeInsets.fromLTRB` and
    nineteen `EdgeInsets.only(left:/right:)` became directional, including one
    more divider inset on the expenses list.
  - **Two more surfaces needed pinning, not mirroring.** The expense and wallet
    amount entries are `[digits][caret]` rows: mirrored, the caret landed on
    the far side of the figure, reading as though typing ran backwards. Both
    are now `Directionality(ltr)`, for the same reason the transports are.
  - **Two more English leaks, both with ARB keys that already existed** and
    were simply never read: the Moments filter bar (All/Photos/Notes/Camera/
    Library) and — found in the same pass — a moment's caption inheriting the
    UI direction, so an English note in an Arabic gallery right-aligned with
    its full stop at the start of the last line. Captions now use
    `directionOfFor`, like chat messages and track titles.
  - **Still deliberately physical**, each with a comment saying why: the
    scrubber's track (raw `dx`, `Positioned.left`), the lozenge playhead, the
    rest ring's fractional-seconds suffix (it trails an always-LTR numeral),
    and every decorative gradient.

- **Ask reads properly in Arabic** (2026-09-07, on `feature/sleep`). A pass
  over the Ask screen after the owner shot it in Arabic. Same lesson as the
  sleep bugs above — the suite asserts in English, where most of this is a
  no-op — so every fix landed with a test that pumps `Locale('ar')`.
  - **A message now reads in ITS OWN language, not the app's.** The worst one:
    ZIVO answering in English inside an Arabic UI inherited the app's RTL
    paragraph, so the reply right-aligned and its closing full stop was laid
    out at the paragraph's end — the LEFT edge: `.answer using your real ZIVO
    data`. Direction for a whole block is a property of the **content**, so
    `bidi.dart` gained `directionOf`/`directionOfFor` (first-strong, falling
    back to the ambient direction) and each bubble asks its own text. This is
    the paragraph-level counterpart to the existing `isolate`/`ltrFor`, which
    are for a run *inside* a sentence; it also fixes which end
    `TextOverflow.ellipsis` eats, so a Latin track title stopped truncating as
    `…Fixture Track Th`. The bubble's *side* still follows the UI — that says
    who is speaking, not what language they said it in.
  - **Media controls do not mirror.** The now-playing strip's transport had
    flipped to `next · ⏸ · previous` while the glyphs (painted, not flipped)
    kept pointing their own way, so the pair aimed away from each other with
    the two actions swapped under the thumb; the playhead drained right-to-left
    as the track advanced. Both are pinned LTR now — a track's timeline runs
    one way in every language. Same reasoning the nav island already documents
    for opting out of mirroring. This is shell chrome, so it lands app-wide.
  - **Three English strings were still hardcoded on this screen.** The
    reply-style menu (`Concise/Balanced/Detailed`) came from `domain/`, which
    is Flutter-free and so has no context to translate from — moved to
    `presentation/ai_labels.dart`, the split `diet_labels.dart` already uses.
    `timeAgo`'s four words (`now`, `5m`, `3h`, `2d`) were literals in a shared
    util; it now takes a context, which touched its 4 callers in workout and
    moments. And a proposal chip printed the gateway's raw `"eaten"`/`"not
    eaten"` — read as a flag now, worded by the app.
  - **The physical-edge bugs**, all `EdgeInsets`/`Alignment` that should have
    been directional: the composer's hint had no leading inset in Arabic (18px
    of padding sat on the trailing side); the header's wide screen inset went
    to the buttons and the narrow one to the title; the user bubble's tail
    corner stayed bottom-right while the pill moved to the left edge, pointing
    into the middle of the screen; the swipe-to-delete reveal put its bin on
    the side the `endToStart` swipe never uncovers; and the thinking rail's
    slow-turn line indented from the wrong edge.
  - **ZIVO's voice loses its slant in Arabic** (owner's call). Instrument Serif
    is Latin-only, so asking it for italic over Arabic got no Arabic italic —
    there is none, and no such tradition — and the shaper **synthesised** the
    slant onto the system's upright fallback. The greeting was rendering as an
    obliqued أهلًا. `TrainType.serifVoice(context, …)` drops the italic when
    the paragraph is RTL; the gate is direction rather than a language list,
    since Hebrew, Farsi and Urdu are in the same position. Arabic keeps the
    serif — one reserved face, still only where ZIVO speaks, just upright.
    English is byte-identical. This made `AppText.aside` take a `BuildContext`
    (alone on that ladder), which rippled to its 24 call sites and
    `AuthHeader.asideStyle`. **Giving Arabic a voice marker of its own means an
    Arabic display face — a fourth family, so an ADR** (ADR-009).
  - **Not done:** the mixed greeting picks one style for the whole line, so
    "ZIVO" inside the Arabic sentence goes upright too — a `TextStyle` applies
    to the whole span. Splitting it would need `Text.rich` per script.

- **Sleep landed as a full feature** (2026-09-07, on `feature/sleep`). Reads
  Apple Health / Health Connect, logs by hand, and carries **provenance on
  every number**. Design + the platform research behind it:
  [`SLEEP_SYSTEM.md`](SLEEP_SYSTEM.md); the decisions:
  [ADR-010](DECISIONS/ADR-010-sleep-provenance.md).
  - **The four platform facts that shaped it**, all verified against vendor
    docs rather than assumed: HealthKit has **no sleep session** (it stores
    overlapping samples; `sleep_sessionizer.dart` stitches them, Health
    Connect records skip it); **an iPhone with no watch produces no sleep data
    at all** since iOS 18 removed time-in-bed tracking, which is why manual
    logging is core and not a fallback; **iOS never discloses a denied read**,
    so the UI may never say "you have no sleep data"; and **iOS Screen Time
    cannot leave its report extension's sandbox**, so device activity is an
    Android-only signal and is deliberately out of v1.
  - **Ranking is on method, never on provider.** "Apple Health data" is not a
    tier — Apple Health *contains* hand-typed entries — so `methodFor` tests
    the platform's manual flag **before** any device signal. Tier 4 routinely
    arrives wearing tier 1's device metadata.
  - **Choose, never merge.** Two providers disagreeing about one night is
    settled by picking one and keeping the rest as alternates; the night
    detail sheet shows the disagreement. An averaged night is one nobody
    measured.
  - **Circular statistics.** The arithmetic mean of 23:40 and 00:20 is noon;
    `circularMeanMinutes` is now the only sanctioned way to average a clock
    time in this codebase. Trends use Theil–Sen so one all-nighter cannot flip
    a fortnight.
  - **The AI interprets, never computes.** It gets a fact sheet of finished
    numbers plus an explicit list of what it may not discuss, and every
    numeral it writes is checked against that sheet — `functions/ai/
    sleep_insights.js` on the server, `groundedNumerals` again on the client.
    Beneath it is a deterministic tier that is always available, so the
    feature never needs a model round trip to say something true.
  - **Three more bugs, found by running it on a simulator rather than by the
    suite** (same day). The worst was the Arabic hero rendering `س12د7`:
    `sleepDurationText` pinned the localized string with `ltrFor`, but
    `7س 12د` is not a composed numeric run — `س`/`د` are abbreviated words,
    strong RTL, so forcing LTR interleaved the two number+unit pairs.
    `core/util/bidi.dart` already states the rule; the pinning is gone from
    every string carrying translated words, and clock times keep theirs.
    The Today glance was over-stuffed and ellipsised **both** the source chip
    and the delta, leaving a duration with no provenance — the delta moved to
    the Sleep page. The week figures wrapped `16س`/`51د` onto two lines. And a
    full week against an empty previous one read "not enough nights yet —
    5 of 5"; it now reports the weaker week. **The suite was blind to all of
    it**: the widget tests assert on English, where `ltrFor` is a deliberate
    no-op. `test/sleep/sleep_labels_test.dart` now pins the rule in both
    languages.
  - **Two regressions worth remembering.** (1) `SleepService.syncState` is a
    `ValueNotifier`, not a stream: a fast sync emitted its terminal state into
    the window between `listen()` and an `async*` generator subscribing, so an
    "unavailable" host rendered the "nothing recorded yet" screen. (2) Every
    test that boots the real `ZivoApp` now injects `sleep:`/`sleepSource:` —
    the Firestore default resolves its uid through FirebaseAuth at
    construction, and `rtl_layout_test` hung for ten minutes on it.
  - **Coverage:** 74 sleep tests (sessionizer, resolver, circular stats,
    gates, codec round-trip, the numeral gate, and the page's *claims* — that
    a typed night says "You logged" and never "Asleep"), plus 9 new Firestore
    rules tests and 15 backend tests. `flutter analyze` clean; the Android
    release build compiles.
  - **⚠ OWNER ACTIONS — five.**
    1. **`minSdk` rose 23 → 26** (`android/app/build.gradle.kts`). Health
       Connect's client requires it and the manifest merger fails below it.
       Drops Android 6.0–7.1. Reversible only by dropping Android sleep.
    2. **New dependency: `health: ^13.3.1`.** Justified in `pubspec.yaml` and
       ADR-010; the migration trigger to a native layer is background delivery.
    3. **iOS needs the HealthKit capability enabled in Xcode** — the
       entitlement is in `Runner.entitlements`, but the capability has to be
       added to the App ID in the developer portal, which needs your account.
    4. **Play Console health-permissions declaration** is required before an
       Android build using `READ_SLEEP` can ship.
    5. **`assets/hub/sleep.jpg` does not exist** — the Hub card falls back to
       a violet wash, which is correct but not the design. Add the photo.
  - **Not done (deliberate, listed in SLEEP_SYSTEM §20):** background delivery
    on either platform, the Android Sleep API estimate path, Samsung Health
    Data SDK (needs a partnership), sleep-adjacent metrics (HR/HRV/SpO2/temp),
    naps in metrics, and correlations. `functions/ai/sleep_insights.js` is
    written and tested but **not yet wired to a callable** — the client runs
    the deterministic tier until it is.

- **The Arabic copy pass finished the app-facing surfaces** (2026-09-06, on
  `core-edits`). **1144 keys** in both languages, up from 344 — the en/ar gap
  test is green and every `@description` is filled in.
  - **Done this pass:** Storage & Sync, the whole of **auth** (settings, sign-in,
    sign-up, verify-email, forgot/change password, delete-account, the password
    checklist), **moments** (capture, timeline, viewer, the photo-metadata
    sheet), **music** (player, compact strip, lozenge), the **workout
    drill-downs** (session details, splits, dashboard, plan editor, exercise
    sheet, workout capture), the **import/describe flows** (file picking,
    backend error mapping, progress lines, the add-a-plan sheet), plus the
    Today pulse card, expenses list and the diet leftovers.
  - **Three more domain→presentation splits**, all the same shape as
    `workout_labels.dart`: `PasswordRule` now carries a **`PasswordRuleId`** with
    its sentences in `presentation/password_rule_labels.dart`; `CaptureSource`
    lost its `label` getter to `core/media/presentation/capture_source_labels.dart`
    (it is persisted by `name`, so it is an id); and `importProgressLine` takes an
    **`ImportItemKind`** instead of an English `itemNoun` it pluralised by
    appending an "s" — which Arabic cannot do. A `domain/` enum that is written
    to Firestore must never carry copy.
  - **Bidi pins went in with the strings, not after them.** Every composed
    numeric run these screens show is now wrapped: session clocks and rest
    countdowns, the `12/15` sets ratio, `RPE 8.5`, photo dimensions and file
    sizes, `UTC+03:00`, the `-2:41` track countdown, signed weight/volume
    deltas, and the `~1270` kcal figures. User-typed text — plan names, split
    names, section headings out of an imported PDF, a moment's location —
    is wrapped with **first-strong** `isolate()` instead, because its direction
    is the user's to decide, not ours.
  - **English copy is unchanged.** Two regressions caught by the suite proved
    the rule worth stating: keying a string is not licence to reword it
    ("3 tries left" had become "3 attempts left"; an import caption lost its
    " total"). `ltrFor` is a no-op under LTR for the same reason.
  - **New test helper:** `test/support/bidi_finders.dart` →
    `findTextIgnoringBidi`, for asserting on a string composed from user data.
    Plain app copy should keep using `find.text`, which stays stricter.
  - **Owner check wanted:** ~365 new Arabic strings are mine, not a native
    speaker's. The plural forms especially — Arabic's dual and few/many
    categories are used throughout (`مجموعتان`, `صورتان`, `{count} صور` vs
    `{count} صورة`) and are easy to get subtly wrong.
  - **The privacy policy is translated too** (owner's call, after I flagged the
    legal risk). All 15 sections + the four "short version" bullets, at
    [`privacy_page.dart`](../lib/features/auth/presentation/pages/privacy_page.dart).
    `kPrivacySections` was a `const` list of English and is now
    **`privacySections(BuildContext)`**; `_SectionBlock` takes its index rather
    than looking itself up by `indexOf`, which a per-locale list breaks. The
    revision date is a `DateTime` run through `formatFullDateLong`, so it reads
    "August 25, 2026" / "٢٥ أغسطس ٢٠٢٦" instead of an English month baked into
    a translated sentence, and the contact address is a placeholder wrapped in
    `isolate()` so bidi cannot break it apart around the `@`.
    `test/auth/privacy_page_l10n_test.dart` asserts both languages have the
    same 15 sections with the same bullet counts, that no Arabic section is
    left in English (allowing the proper nouns), and that the address survives.
    - **⚠ OWNER ACTION — two of them.** (1) **zzivo.com/privacy still shows the
      English-only policy.** The file's own doc comment says the app and the web
      page are one document and must be updated together; they are now out of
      sync until the public page carries the Arabic. (2) **This is a legal
      document translated by an AI, not a lawyer or a native speaker.** It is a
      faithful rendering of the English as far as I can make it, but the
      consent it describes is a legal instrument and should be reviewed before
      it ships to Arabic users.
  - **Still English:** roughly 230 literals, nearly all of them numeric
    interpolations the bidi pass has already handled rather than prose —
    plus `exercise_analysis_page`, `workout_stats_pages` and
    `workout_progress_page`, whose remaining strings are chart axis labels
    and units.

- **Arabic RTL: the bottom bar, the Hub, and the bidi rule that was missing**
  (2026-09-06, on `core-edits`). Three separate bugs, one root cause each.
  - **The nav capsule was mirrored.** `ZivoBottomBar` drew its tabs in a `Row`
    (which reverses under RTL) but positioned the ember capsule with
    `Positioned(left:)` (which does not), so in Arabic the capsule sat under the
    mirror image of the selected tab — tapping اليوم lit حسابي. Now
    `PositionedDirectional(start:)`, defined against the same axis as the row.
  - **Tab order is now pinned LTR in every language** — Today · Hub · Ask · You,
    left to right, **at the owner's explicit call**. This is a deliberate
    exception to platform mirroring (iOS/Android both mirror a tab bar under
    RTL): the reasoning is that the four destinations are a fixed row of
    hardware-like buttons a thumb learns by position, and moving them because
    the language changed costs more than reading order gains. Implemented as one
    `Directionality(textDirection: ltr)` around the strip's *geometry* only —
    labels are still Arabic and still shape RTL. Deleting that one widget
    reverts to mirroring; the capsule needs no change either way.
    `test/shell/bottom_bar_rtl_test.dart` covers capsule/tab agreement in both
    languages and pins the order decision so a later RTL sweep can't "fix" it by
    accident.
  - **New rule — `core/util/bidi.dart`, and it is not a translation gap.**
    A line like `3 × 8–10 · rest 1:30` is digits and bidi-*neutral* characters
    end to end, so an Arabic paragraph laid it out right-to-left and it rendered
    as `rest 1:30 · 10–8 × 3`: the pre-workout screen was advertising a rep range
    of **10–8**. No `.arb` key fixes that — the same thing happens inside a
    perfectly translated sentence. Three tools now: **`ltrFor(context, s)`** for a
    composed numeric run (a no-op under LTR, so English strings stay
    byte-identical — that gate matters, an unconditional wrap splits
    `rest 3:00` for every `find.textContaining` in the suite); **`isolate(s)`**
    (first-strong) for text ZIVO did not write — a plan name, an exercise name —
    whose direction is the user's, not ours; and **`stripBidi`** for tests.
    Applied to every planned-set spec, the Today pulse card's signed deltas
    (`+4%` was rendering as `4%+`), and the day-details caption.
  - **`workout_plan_format.dart` split.** Grouping stayed in `domain/`
    (`collapsedSetGroups` returns groups, not prose); every reader-facing string
    moved to **`presentation/workout_labels.dart`**, which takes a `BuildContext`
    — same shape as `diet_labels.dart`. `weightText` joined `workout_format.dart`
    rather than becoming a second home for how a weight is written. Six call
    sites follow; `workout_labels_test.dart` asserts the English wording is
    byte-for-byte unchanged **and** that Arabic keeps `8–10` ascending and
    isolated.
  - **The Hub speaks Arabic.** Its title, the Connected band label, all four tile
    stat lines and both service states were hardcoded English — which in RTL did
    not merely stay English, it scrambled (`0 of 3 · 1270 kcal` rendered as
    `OF 3 · 1270 KCAL 0`). ~25 new keys, `hubMomentsCount`/`workoutSetCount` as
    real ICU plurals with Arabic's dual form.
  - **Owner check wanted:** the ~25 new Arabic strings are mine, not a native
    speaker's. `مجموعتان`/`تمارين`/`حتى الفشل`/`أسبوعيًا` especially.
  - **Still English + still scrambling in Arabic** (the remaining copy pass, now
    the *bigger* half of the RTL problem since untranslated text actively
    reorders): workout drill-downs (analysis, stats, history, splits, PDF import,
    plan editor, session details), auth, moments, music, and the exercise-name
    column on every workout surface.

- **The Hub's Drive row follows the connection instead of remembering it**
  (2026-09-06, on `core-edits`). Connecting Google Drive left the Hub's Connected
  band reading "NOT CONNECTED" until the app restarted: the row was a one-shot
  `FutureBuilder`, and the Hub is a tab inside the shell's `IndexedStack` — built
  once, never rebuilt on tab switch or on return from Storage & Sync.
  `MediaService` now publishes `backupConnected` (a `ValueNotifier`, updated by
  every path that decides the answer, including the cross-account fail-closed
  check), and the row watches it, seeds itself with one read on mount, and
  re-reads on return from Storage & Sync — so a manual refresh control on that
  band would have nothing left to do. `test/hub/hub_drive_row_test.dart` connects
  the service without rebuilding the page and asserts the row moves.

- **Changing today's workout can now SWAP instead of skip — the cycle closes**
  (2026-09-06, on `core-edits`). Training out of rotation cost a day its turn:
  finishing advances the cursor **past what was actually trained**
  (`advanceToAfterDay`), so picking Arms while Legs was due left Legs dropped
  from the cycle and a week meant to cover the whole body didn't.
  - The change-workout sheet now asks a second question — **Swap** (default) or
    **Skip** — above the day list, with a line naming what happens to the due
    day. The one-tap-starts contract is untouched: the toggle only decides what
    happens to the day the pick displaced.
  - **Swap** is `WorkoutPlan.swapDays(aId, bId)`: the two days trade `order`
    and the cursor is deliberately *not* moved (it stores an `order`, so it
    keeps pointing at the same position, which now holds the picked day).
    `slot` stays with its day — it is identity ("Day B is Arms"), not position,
    matching what the editor's drag-reorder already does. Written to the repo
    **before** the session starts, so the card behind reads the new rotation
    and an abandoned session still leaves the cycle whole.
  - **Skip** is the old behaviour, kept for days you genuinely want to drop.
  - Fixed alongside: the sheet computed a `resumable` session for the
    in-progress day, showed its "In progress" badge, popped it — and the caller
    threw it away, starting a *second* session over the first. Picking that day
    now resumes.
  - Domain rules in `test/workout/workout_plan_domain_test.dart`, the flow (both
    modes + the resume fix) in `test/home/today_page_test.dart`.

- **Drive backup is account-aware — a file id now carries the account that minted
  it** (2026-09-06, on `core-edits`). Production bug: a photo backed up to Drive
  account #1 became permanently unreachable after the user connected Drive #2 —
  the Moment, caption and date all survived, the image did not.
  - **Root cause.** `MediaObject` stored `remoteId` and nothing saying *which*
    Drive account issued it, while the module's only ownership gate
    (`_backupConnectionValidForCurrentAccount`) compares **ZIVO uids** — which
    do not change when the Drive account does. The check passed, and Drive #1's
    ids went on being issued against Drive #2.
  - **Why it never healed.** Reads returned `cloudOnly` ("on its way") for bytes
    that were never coming; `pendingBackups()` filtered out anything marked
    `done`, so "Back up now" said *"Everything is already backed up"* over an
    empty Drive #2 folder, leaving the local copy as the only copy; and every
    retry passed the stale id as `replaceRemoteId`, which 404'd with **no
    fallback to `files.create`** — a permanently poisoned record.
  - **The fix stores the pair and makes "backed up" a claim about a
    destination.** `MediaObject.remoteAccountKey` beside `remoteId` (Firestore
    `driveAccountKey`, `schemaVersion` **2**); `MediaBackupProvider` gains
    `liveAccountKey`/`connectedAccountKey()`, a required `expectedAccountKey` on
    download+deleteRemote and `replaceInAccountKey` on upload — enforced at the
    **seam**, so no call site can forget and a mid-flight account swap fails
    loudly; `pendingBackups({forAccountKey})` so connecting a new account
    re-protects the whole library from local bytes; `files.create` fallback;
    `restoreSession` refuses an account other than the recorded one; new
    `MediaAvailability.otherAccount` (no self-retry — it cannot succeed);
    resolution caches dropped on connect/disconnect/uid change.
  - **`FirestoreMediaRegistry.put` now files under the signed-in uid or throws**
    (it routed writes by a caller-supplied owner while every read used the
    current uid), and the Moments capture screen no longer substitutes a
    `'local'` placeholder owner when signed out.
  - **Migration is additive and lazy.** An absent key means *unknown*; unknown is
    never treated as equal to the connected account, but gets the benefit of the
    doubt once and is stamped by the first transfer that actually works. No batch
    job and **no rules change** — the media rule pins only `relativePath` +
    `schemaVersion`.
  - **A file deleted inside Drive now recovers instead of pulsing forever**
    (follow-up, same day). `download` returns a `RemoteFetch` (`bytes` / `gone` /
    `unavailable`) instead of nullable bytes, so a definite **404/410** is told
    apart from a dropped connection. On `gone` the dead reference is cleared
    (`clearRemote`) and the record drops to `BackupState.failed`, which puts it
    back on the work list — so any device still holding the local bytes
    re-uploads it on the next backup. **403 is deliberately not treated as
    gone** (it covers rate limits, and mass-dropping references under load
    would be far worse than a slow retry), and a timeout never is. **Only the
    account that holds an id may declare it dead:** a 404 against a record with
    no recorded account is ambiguous — deleted, or filed in the Drive the user
    just left — so it keeps its reference (reconnecting the old account still
    recovers the photo) and only drops to `failed`.
  - **A deleted photo no longer strands its cloud copy.** `deleteMedia` used to
    look up the remote id only when a session was live — precisely the case
    where it did NOT need preserving — so deleting a Moment while the holding
    account was disconnected dropped the row and left the file in the user's
    Drive with nothing able to name it again. Now the coordinates survive as a
    **`MediaTombstone`** (new owner-only `users/{uid}/mediaTombstones`
    collection + rule + rules tests), and `sweepPendingRemoteDeletions()`
    finishes the job from `connectBackup` and at the head of `backupNow`.
    Tombstones for other accounts are left untouched for whenever those
    reconnect.
  - **Storage & Sync names the photos an account switch left behind** — a count
    plus both routes out (Back up now for the ones still on this device,
    reconnect for the rest). The status banner no longer counts a copy in an
    unreachable account as "backed up", because to this account it isn't.
  - **Local bytes are scoped to the account that captured them.** The store
    wrote every file to a flat `media/{kind}/{id}.{ext}`, shared by every ZIVO
    account used on the device — the id was the only thing preventing a
    collision, and an account's media could not be identified on disk. New
    imports go to `media/{owner}/{kind}/{id}.{ext}` (the owner sanitised to one
    safe path segment). **Nothing is migrated:** a ref is opaque and
    self-describing, so unscoped paths already in `Moment.imagePath` /
    `UserProfile.photoPath` resolve exactly as before. Rewriting them would mean
    touching every Firestore doc holding one, and a single miss recreates the
    unresolvable-photo bug this whole arc exists to remove.
  - New [`test/core/media/drive_account_switch_test.dart`](../test/core/media/drive_account_switch_test.dart)
    drives a fake where **files belong to one account**, so a cross-account read
    404s naturally instead of by scripting; reverting the fix puts four of its
    scenarios red, and [`media_availability_ui_test.dart`](../test/core/media/media_availability_ui_test.dart)
    pins the read-side states. **1176 dart + 137 rules tests green.**

- **The diet feature is localized** (2026-09-04, on `core-edits`). Fifth and
  largest piece of the l10n push — the feature had **264** hardcoded literals,
  more than every other remaining feature put together. **188 new keys**
  (605 → **793**), `l10n-untranslated.txt` still `{}`, all 14 presentation
  files.
  - **The densest version of the structural problem.** Eight enum→word maps
    lived in the Flutter-free `domain/` layer, where they could only ever
    return English, and were rendered straight onto the Targets page, the plan
    verdict and the plan cards. New
    [`diet/presentation/diet_labels.dart`](../lib/features/diet/presentation/diet_labels.dart)
    is the diet feature's `progress_status_style.dart`: `dietGoalText` ·
    `dietGoalDetailText` · `activityText` · `activityDetailText` ·
    `targetSourceText` · `calibrationGapText` · `missingBodyDataText` ·
    `macroText` · `nutritionSourceText` · `dietSourceText` ·
    `targetBasisText`.
  - **Which domain functions died and which stayed is the interesting part.**
    `dietGoalDescription`, `targetSourceLabel`, `calibrationGapLabel`,
    `missingBodyDataLabel`, `nutritionSourceLabel`, `activityDescription` and
    `targetBasisSummary` were **presentation-only** and are gone — two ways to
    name a thing is how the two drift apart. `dietGoalLabel`, `activityLabel`
    and `dietSourceLabel` **stay**: the coaching engine splices them into
    generated English prose (`coaching/rules.dart`, `coaching/evidence.dart`)
    which cannot be half-translated, and two tests assert on the third. Those
    three now carry a doc comment on both sides saying the split is deliberate.
  - **A third stored-value-as-copy bug, found and closed.**
    `MacroProgress.label` was English copy that the plan-details page **switched
    on** to pick each bar's colour (`switch (label) { 'Protein' => green, … }`).
    Translating the label would have sent every macro bar to the fallback colour
    — silently. `MacroProgress` now carries a `MacroKind` enum: the kind is the
    identity to switch on, the label stays the engine's word, and the screen
    reads `macroText(context, kind)`. (After `kUntitledConversationTitle` in
    Ask and `'google.com'` in profile, this is the third; the pattern is worth
    watching for.) Cuisine chips got the same treatment — the value is sent to
    the plan generator, so it stays an English id and only the chip's word is
    translated, matching the allergen chips already in that file.
  - **New `test/diet/diet_l10n_test.dart`** walks **every value of every one of
    those enums** under `Locale('ar')` — so a new goal, activity level or
    nutrition source that forgets its key fails there rather than shipping
    English. It allows proper names through (ZIVO, USDA FoodData Central) and
    separately asserts the engine's three labels are still English.
  - Gates green: `flutter analyze` clean, **1150** tests passing (+8).
  - **Still open:** ~160 literals across 38 presentation files — expenses,
    auth, capture, home, music, shell. Plus the `domain/` coaching prose
    (diet's `coaching/evidence.dart` + workout's `analytics/`), which is the
    same blocked category and still needs an owner decision.

- **The profile surfaces are localized** (2026-09-04, on `core-edits`). Fourth
  piece of the l10n push. **32 new keys** (573 → **605**),
  `l10n-untranslated.txt` still `{}`. Three files: `profile_page` (1,268 lines,
  previously **zero** `l(context)` calls), `profile_completion_page`, and
  `dob_picker_sheet`.
  - **A fourteenth hardcoded month table turned up** — in the date-of-birth
    wheel, which the earlier `date_format.dart` sweep missed because there the
    months are *options in a picker*, not part of a formatted date, so none of
    the existing formatters fit. New `monthNames(context)` in
    [`core/util/date_format.dart`](../lib/core/util/date_format.dart) resolves
    all twelve through `intl`. `lib/` is hardcoded-month-free again.
  - **Deliberately NOT translated:** `'google.com'`/`'apple.com'` (provider
    IDs — data), `'Google'`/`'Apple'` (brand names, like ZIVO), and the `'\s+'`
    regex. Only `'Email & password'` in `_providerLabel` was copy. The switch
    now says so in a comment, so the next reader does not "finish the job".
  - **Two helpers had to take a context** for one string each: `_cropAvatar`
    drives the *native* iOS/Android cropper chrome ("Move & Scale", "Choose"),
    which is real user-facing copy that had been shipping English to every
    Arabic user; and `_name` fell back to "Signed in". `_cropAvatar` is handed
    the strings rather than reading them, because its call site sits after two
    awaits — same rule as the Ask sheet.
  - **New `test/profile/profile_l10n_test.dart`**: the DOB wheel's months in
    Arabic and English, the sheet's own chrome, and a sweep asserting the page
    strings differ per locale and carry no latin — with the one intended
    exception (the product name in `profileCompleteSubtitle`).
  - Gates green: `flutter analyze` clean, **1142** tests passing (+4).
  - **Still open:** ~198 literals across 49 presentation files — diet,
    expenses, auth, capture, home, music. Plus the `domain/analytics/` engine
    prose (owner decision, below).

- **The Ask (AI coach) surface is localized** (2026-09-04, on `core-edits`).
  Third piece of the l10n push, and the one with the two real design problems.
  **66 new keys** (507 → **573**), `l10n-untranslated.txt` still `{}`.
  - **`'New chat'` was a stored sentinel, not copy** — and translating it
    naively would have been a data bug, not a cosmetic one. `createConversation`
    writes it into Firestore, `_fromDoc` defaults to it, and three call sites
    compare `title == 'New chat'` to decide whether a thread is still untitled.
    Localize it and every one of those comparisons silently breaks the moment
    the user switches language, leaving older threads permanently "titled" in
    whatever language created them — exactly what `kAmrapLabel` exists to warn
    about. It is now
    [`kUntitledConversationTitle`](../lib/features/ai/domain/ai_conversation.dart)
    (a named, deliberately untranslated constant), and
    `displayConversationTitle(context, title)` in `sessions_sheet.dart` is the
    **one** render-boundary that maps it to the localized `askNewChat`. Pinned
    by tests on both halves: the stored value stays English, the displayed one
    is Arabic.
  - **`AskController` now takes the copy as a value.** ADR-008 forbids a
    controller holding a `BuildContext` — it says nothing about a value object,
    and `AppLocalizations` is one. The controller took `required
    AppLocalizations strings`, plus `updateStrings()`, which `AskPage` calls
    from `didChangeDependencies`, so **switching language mid-chat re-renders
    the thinking rail** rather than stranding it in the old locale. That closes
    the debt the controller's own doc comment had already flagged ("a future
    move to l10n is one file"). The 13 phase/step rail labels and 8 voice/error
    messages all moved.
  - Also localized: the empty state (its four suggestion chips are both label
    AND the text that gets sent, so an Arabic reader now asks ZIVO in Arabic),
    the proposal card (status, kind, confirm verbs), the sessions sheet, the
    thinking rail, the chat header, the voice composer and the quick-log sheet.
    Widget-test `Key('…')` strings were deliberately left alone — they are
    identifiers, not copy.
  - `ThinkingRail.label` became nullable and resolves in `build`; a `const`
    constructor cannot reach `Localizations`. Two `quick_log_sheet` handlers now
    read `l(context)` once **before** their awaits — a `BuildContext` across an
    async gap is a lint and a bug; a captured `AppLocalizations` is neither.
  - **New `test/ai/ask_l10n_test.dart`** — Arabic render, English unchanged, and
    three assertions on the sentinel (stored value stays English; a sentinel
    title displays Arabic; a user-named thread is untouched in either language).
  - Gates green: `flutter analyze` clean, **1138** tests passing (+5).
  - **Still open:** ~222 literals across 52 presentation files (`profile_page`
    17, diet, expenses, auth). Plus the `domain/analytics/` engine prose, which
    still needs the owner decision described below.

- **The workout progress/analysis stack is localized** (2026-09-04, on
  `core-edits`). The second landed piece of the l10n push, and the debt
  STATE.md had been carrying since the drill-down shipped ("Analysis strings
  stay hardcoded English"). This was the app's newest and most
  product-differentiating surface, and an Arabic reader got an entirely
  English screen on it.
  - **143 new keys** in both `app_en.arb` and `app_ar.arb` (368 → **507**),
    `l10n-untranslated.txt` still `{}`. Eight files: `workout_progress_page` ·
    `workout_analysis_page` · `exercise_analysis_page` · `workout_history_page` ·
    `bodyweight_history_page` · `workout_stats_pages` ·
    `progress_status_style` · `verdict_style`.
  - **The shared progression vocabulary went first**, because everything else
    reads through it. `progressStatusStyle` / `trendToneStyle` /
    `verdictStyle` now take a `BuildContext`, and `verdictStyle` reuses the
    *same three keys* as the other two — so a set-level badge and an
    exercise-level badge can no longer disagree about what "Down" is called.
  - **Plurals are real ICU plurals**, not `count == 1 ? '' : 's'`. Arabic gets
    its own `zero`/`one`/`two`/`few`/`many`/`other` forms where the count is
    visible copy (exercises, sessions, PRs, streak days).
  - **One more duplicated formatter died.** `formatDurationShort` lived on
    `workout_dashboard_page.dart` (three pages imported a *page* to borrow it)
    and was **also** copied verbatim into `workout_stats_pages.dart` as a
    private `_durationLabel`. Both are gone; it now lives in
    `workout/presentation/workout_format.dart` beside `trimWeight`, and its
    `h`/`m` abbreviations come from the `.arb` too.
  - Also localized `ErrorStateView`'s default in `core/widgets/` — it hardcoded
    the same "Couldn't load this." those pages did; the new `errorCouldntLoad`
    key now serves both.
  - **New `test/workout/progress_stack_l10n_test.dart`** pumps each surface
    under `Locale('ar')` and asserts **no** English survives, plus an
    exhaustive sweep over every `ProgressStatus`/`ExerciseTrendTone` (a new
    enum value that forgets its key fails here rather than silently shipping
    English). `wrapWithScope` gained an optional `locale:` that installs the
    real delegates — null by default, so the ~120 existing widget tests are
    untouched.
  - Gates green: `flutter analyze` clean, **1133** tests passing (+6).
  - **Still open:** ~268 user-facing literals across 59 presentation files
    (Ask widgets ~42, `profile_page` 17, diet, expenses, auth). And the
    `domain/analytics/` engines still generate English coaching prose — see the
    entry below for why that one needs an owner decision, not a `.arb` key.

- **One locale-aware date formatter — Arabic dates now actually render in
  Arabic** (2026-09-04, on `core-edits`). The first landed piece of the l10n
  push. Thirteen files had grown their own private copy of the same tables:
  **eight** a `const _monthNames = ['Jan', …]`, **five** a `['Mon', …]`, and
  **four** their own `isPm ? 'PM' : 'AM'`. Beyond the duplication, every one was
  **hardcoded English** — so an Arabic user reading an Arabic app got "MAR 1" on
  session history and "6:30 AM" on their moments. **A `.arb` key can never fix
  this**: a month name spliced out of a Dart list was never a string the
  translator could see.
  - **New [`core/util/date_format.dart`](../lib/core/util/date_format.dart)** —
    `formatMonthDay` · `formatMonthDayCaps` · `formatWeekdayShort` ·
    `formatWeekdayFull` · `formatWeekdayDate` · `formatWeekdayDateTime` ·
    `formatClockTime` · `formatClockTimeWithSeconds` · `formatDayPeriod` ·
    `formatMinutesSinceMidnight` · `formatWeekdayShortForIndex` ·
    `formatDayMonthYear` · `formatFullDateLong`. Each takes a `BuildContext` and
    resolves through `intl`'s `DateFormat` for the locale `Localizations` is
    rendering in, falling back to English with no `Localizations` (the same
    fallback, for the same reason, as `l(context)`).
  - **Nine competing formatters collapsed into one set.** There were **four**
    clock formatters (`formatClockTime(double)` on the dashboard,
    `formatClockTimeLabel`/`formatClockTimeDouble` on the stats pages —
    the latter carrying a comment admitting it was "duplicated here to keep
    pages dependency-light" — and `formatExactTime` in moments) and **five**
    date formatters. Two page files imported `workout_dashboard_page.dart`
    purely to borrow a formatter off it; both now import `core/util` instead.
  - **Migrated (12 files):** workout — stats · dashboard · history ·
    session-details · exercise-analysis · bodyweight-history; moments —
    metadata · photo-viewer; expenses — list · capture; profile — page ·
    completion; diet — plan-edit; home — today. **Zero** hardcoded date tables
    remain in `lib/`.
  - **Deliberate visible changes:** where a call site hand-rolled an order
    (`"20 Aug"`, `"Mon 5 Mar"`), it now uses an `intl` *skeleton* and the locale
    picks the order (`"Aug 20"`, `"Mon, Mar 5"`) — letting the locale decide is
    the whole point. The one exception is the photo detail panel, which keeps an
    explicit day-first pattern because reading like an EXIF record is part of its
    design; only the names localize there. CLDR's U+202F before AM/PM is
    normalised to a plain space, matching what the replaced formatters emitted.
  - Gates green: `flutter analyze` clean, **1127** tests passing (+8). New
    `test/core/date_format_test.dart` asserts the Arabic month, weekday and day
    period explicitly — the thing the old tables could never do.
    `test/moments/moment_metadata_test.dart` became widget tests, since
    `buildMomentMetadata` now takes a context.
  - **Still open (the rest of the l10n debt):** ~305 user-facing string literals
    across 63 presentation files are still hardcoded English — worst are
    `profile_page` (17), the Ask widgets (~42), and the workout progress/analysis
    stack (~49). Separately, the **`domain/analytics/` engines generate English
    coaching prose** (~79 literals across `workout_analytics.dart`,
    `exercise_analysis.dart`, `plan_adherence.dart`) and `domain/` is
    deliberately Flutter-free, so `l(context)` cannot reach it — localizing that
    needs the engines to return structured tokens the presentation layer renders,
    which is an ADR-sized decision touching the Node parity. Owner call.

- **One uid-scoped Firestore mirror, and the stale-cache bug closed everywhere**
  (2026-09-04, on `core-edits`). Ten Firestore repositories each carried the
  same ~60 lines of uid-scoping machinery — `StreamController` + `_uidSub` +
  `_querySub`, `_start`/`_stop`, `_uidWithInitial`, `_emit`, `_requireUid` —
  and seven carried the same six-line explanatory comment **verbatim**. The
  only parts that differed were the collection path, the `orderBy` and the
  doc→domain mapper.
  - **New [`core/firebase/uid_scoped_mirror.dart`](../lib/core/firebase/uid_scoped_mirror.dart)**
    (`UidScopedMirror<T>`) owns uid re-scoping, the cached synchronous
    `current`, the late-subscriber replay, and the always-on listener. It is a
    **held object, not a superclass**, because a repository can own several
    mirrors (diet mirrors plans, targets and body profile independently) —
    inheritance could not express that. `T` covers both shapes: `List<X>` for a
    collection (`signedOutValue: const []`) and `X?` for a single document
    (`signedOutValue: null`). `UidSource.requireUid(this)` replaces the ten
    identical private `_requireUid()`s, reporting the same message.
  - **This is a correctness fix, not a tidy-up.** The always-on listener was
    the hand-rolled fix for the Home/Workout-tab training-card drift — a write
    landing while nothing was subscribed left the cache stale for the next
    subscriber to replay. It had been applied to the **plan, session and
    body-weight** repos only; **moments, expenses, categories, wallet and the
    workout log still had the bug**. Routing all of them through the mirror
    fixes it by construction, pinned per-repository by new
    `test/core/firestore_repos_stay_hot_test.dart` (verified failing against
    the pre-change code).
  - **Migrated (7 mirrors):** moment, expense, category, wallet (doc shape),
    workout, workout-session, body-weight. **Deliberately not migrated:**
    `FirestoreWorkoutPlanRepository` (two coupled streams with a cross-stream
    emission gate), `FirestoreDietRepository` (three mirrors + `onListen`
    coupling), `FirebaseAiRepository` (per-conversation ephemeral streams, not
    a singleton mirror at all). Those are follow-ups, not blockers — see the
    owner action below.
  - Net **−330 lines** across the seven repos. Gates green: `flutter analyze`
    clean, full suite **1119** passing (+15: 8 new mirror-contract tests, 7 new
    per-repo regression tests). One existing wallet test was updated — it read
    `watch().first` immediately after a write and had been relying on the old
    lazy listener opening a fresh query; no production code reads these streams
    via `.first`. No Firestore/rules/backend changes.
  - **Owner follow-up (optional):** diet and workout-plan can move onto the
    mirror by composition (they would hold 3 and 2 mirrors respectively); that
    is a bigger, separately-testable change and was left out on purpose.

- **Hub redesigned as a photographic module dashboard** (2026-09-04, on
  `core-edits`). The Hub grid was four identical near-white neutral-mark icon
  tiles; it's now a 2×2 grid of **photographic module cards** (Workout · Diet ·
  Expenses · Moments) — each a hero photograph (`assets/hub/*.jpg`) melting into
  the card body via a bottom fade, with a **hue-tinted icon chip** (green /
  green / amber / ember — the area's owned hue, inside the four-hue system), the
  localized label, and the same live stat as before. The source images'
  baked-in titles are **cropped off in-source** (via `ffmpeg`, ~2.3 MB PNG →
  ~90 KB JPG each) so the card overlays the app's own l10n label over clean
  photography rather than a fixed-English, screen-reader-invisible title.
  - **Spotify icon fix (owner report):** the Connected band's Spotify row led
    with a generic music glyph that dimmed to near-invisible when disconnected.
    It now uses Spotify's **real brand mark on a neutral plate, always at full
    colour** (the same treatment the Drive row has), with the connection state
    carried entirely by the trailing value — a not-connected Spotify still shows
    its mark and the affordance to connect it.
  - **"Recent" removed** entirely (owner request) — the cross-module activity
    merge (`_RecentSection`/`_mergeRecent`) and its `hubRecent` l10n key are
    gone; the grid → Connected spacing was reflowed so there's no dead gap.
  - This is a deliberate, owner-signed evolution of the Hub's visual direction:
    it leans on **image + colour** for module identity where the grid previously
    differentiated **by icon only** (ADR-006's "grids differentiate by icon, not
    colour"). Everything still dresses from `TrainColors`/`TrainType`; the hue
    chips stay inside the four owned hues. See [hub/FEATURE.md](../lib/features/hub/FEATURE.md).
  - Gates green: `flutter analyze` clean, full suite **1104** passing
    (`test/hub/hub_page_test.dart` updated — Recent group removed, stat/label/
    Connected assertions unchanged). No backend/Firestore/rules changes.

- **The AI coach now sees the per-exercise drill-down + plan adherence**
  (2026-09-03, on `core-edits`). Closes the loop the previous entry left open:
  the deterministic exercise analysis and adherence engines are wired into the
  "Ask" coach through the existing tool pipeline — **the coach explains the same
  numbers the Analysis UI shows, and never recomputes or overturns them.**
  - **Node parity, not a second pipeline.** New
    [`functions/ai/exercise_analytics.js`](../functions/ai/exercise_analytics.js)
    mirrors the two Dart engines (`analyzeExercise` + `analyzePlanAdherence`),
    reusing `workout_analytics.js`'s primitives. Pinned to Dart by NEW shared
    golden vectors (`exerciseAnalysis` + `planAdherence` in
    `test/fixtures/workout_analytics_vectors.json`) that BOTH suites run — the
    numeric facts, the verdict/tone, the change tags, and the adherence reasons
    are guaranteed identical across engines (the human-readable insight prose is
    generated per side and intentionally not pinned, same as the hub's findings).
  - **Tools (the bounded context strategy).** New **`get_exercise_analysis`**
    (`tools.js`) resolves a lift by name and returns ITS full session-by-session
    history + deltas + verdict + insight + PRs — the "how is my bench / why did
    incline improve / did I progress with fewer reps" tool. **`get_training_analysis`**
    now also carries **`planAdherence`** (skipped / never-trained / stale planned
    movements). Whole-training questions get the summary; a specific lift pulls
    its own detail — context stays bounded, asserted by a test. Server plan read:
    new `store.getActiveWorkoutPlan` mirrors the client's active-split resolution
    (pointer → active-status → oldest).
  - **Prompt (`gateway.js`) TRAINING section** now points at the new tool, tells
    the coach the deterministic verdict/tone LEADS (a heavier-fewer-reps session
    can be a gain — don't call it a regression because reps fell), and treats a
    repeatedly-missing planned lift as an adherence issue, not a decline.
  - Gates green: `functions` **420 node tests + ESLint clean**; Dart golden-vector
    parity groups added to `exercise_analysis_test.dart` / `plan_adherence_test.dart`
    (Dart == Node on the shared vectors). New `exercise_analytics.test.js` +
    tool tests in `tools.test.js` (verdict/deltas reach the coach unchanged;
    the 35×10→40×7 case stays "improved"; adherence surfaces; context bounded).
    **Owner action: `firebase deploy --only functions`** to ship it (any prompt/
    tool change needs a deploy; owner credentials).

- **Analysis rebuilt as a coaching drill-down** (2026-09-03, on `core-edits`). The
  progress surface was a flat, read-only scroll with no way into a single lift. It's
  now a real coaching dashboard with a per-exercise detail page underneath it. **All
  deterministic — the pinned `analyzeTraining`/`estimatedOneRepMax` numbers are
  untouched; the new engine is purely additive and reuses the hub's primitives, so
  hub and detail can't disagree.**
  - **New per-exercise engine** —
    [`workout/domain/analytics/exercise_analysis.dart`](../lib/features/workout/domain/analytics/exercise_analysis.dart)
    (`analyzeExercise`): full session-by-session history (per session: sets, reps,
    load, volume, e1RM, avg load, rep range), **session-to-session comparisons** with
    typed deltas (`SessionChange`: load/reps/volume/strength up-down, new PB, no
    change), an **intensity-first verdict** (`ExerciseTrendTone`) — e1RM decides,
    volume is secondary, so 40×7 can beat 35×10 — PR-along-the-timeline flags,
    frequency/days-since-last, and a `CoachingInsight` (what happened → why → do)
    templated FROM the numbers so the AI can re-voice without inventing facts.
  - **New plan-adherence engine** —
    [`workout/domain/analytics/plan_adherence.dart`](../lib/features/workout/domain/analytics/plan_adherence.dart)
    (`analyzePlanAdherence`): joins the active plan against history to surface what's
    **skipped** (planned-but-never-trained) or **stale** (>14d) — the "what's being
    skipped?" the hub couldn't answer.
  - **UI:** new [`exercise_analysis_page.dart`](../lib/features/workout/presentation/pages/exercise_analysis_page.dart)
    (status + insight → strength/volume trend → at-a-glance metrics → PRs → session
    timeline with per-session deltas). `workout_analysis_page.dart` re-composed into
    coaching sections (overall · recent PRs · what's going well · what's getting worse ·
    stalled · what's being skipped · focus next · volume · **all exercises**), every
    exercise/PR/skip row **tappable into the detail page**. Shared
    `progress_status_style.dart` keeps the five directions' word/colour/icon in one place.
  - Gates green: `flutter analyze` clean, full `test/workout/` suite (427) passes,
    including new `exercise_analysis_test.dart`, `plan_adherence_test.dart`,
    `exercise_analysis_page_test.dart`. **Now wired to the AI coach** — see the entry
    above (Node mirror + `get_exercise_analysis` + adherence). Analysis strings stay
    hardcoded English, matching the existing progress surfaces (l10n debt, pre-existing).

- **Workout analytics engine + the AI training pipeline fixed** (2026-09-02, on
  `core-edits`). A focused, correct progress layer — not a deep analytics platform.
  - **One centralized engine** —
    [`workout/domain/analytics/workout_analytics.dart`](../lib/features/workout/domain/analytics/workout_analytics.dart),
    consumed by BOTH the UI and the AI, mirrored server-side by
    [`functions/ai/workout_analytics.js`](../functions/ai/workout_analytics.js) and
    pinned by shared golden vectors (`test/fixtures/workout_analytics_vectors.json`,
    run by both suites). Estimated 1RM (Epley, ≤12 reps), PRs **derived from
    history** (no stored ledger; `detectNewPrs` diffs prior-vs-with-session),
    per-exercise status with a **min-3-appearance gate + a meaningful-change
    threshold + best-of-window smoothing** (kills the old n=2 verdict's daily-noise
    false alarms), a per-muscle rollup, working-volume trend, an overall summary,
    typed `fact`/`interpretation` findings, and a `computeGoal`-based next step.
    **Warm-ups excluded everywhere.**
  - **The AI no longer sees the lossy flat log.** `store.listWorkoutSessions` reads
    the real per-set `workoutSessions`; `get_workouts` now returns real per-set
    actuals (warm-ups flagged, skipped/pending dropped); new **`get_training_analysis`**
    hands the model the deterministic analysis + findings; the system prompt gained a
    workout numbers/findings/confidence block. (Audit fix: the coach used to be fed a
    fabricated single rep/weight per exercise.)
  - **UI:** `workout_analysis_page.dart` rebuilt as a 6-section engine-driven view
    (overall · recent PRs · exercise progress · working volume · needs-attention ·
    next step); the Progress landing's summary card shares the same engine; a
    post-workout **PR celebration** on the completed phase (`detectNewPrs`).
  - Gates green: `flutter analyze` clean, 1085 Flutter tests + 409 functions tests +
    functions lint all pass. **Owner action: `firebase deploy --only functions`** to
    ship the AI-pipeline changes (backend deploys need owner credentials).

- **Local-first saves, one-shot commit buttons, and Spotify that stays connected**
  (2026-09-02, on `core-edits`). Four owner-reported problems, one pass.
  - **Saving no longer waits for the database.** Every repository is Firestore-backed,
    and a Firestore write resolves on the **server's** acknowledgement — not on the
    local cache the UI already reflects — so `await repo.add(x)` before `pop()` froze
    Save for a round trip, and indefinitely offline (expenses worst of all: the wallet
    adjustment is a `runTransaction`, which bypasses the offline cache entirely). New
    [`core/util/deferred_write.dart`](../lib/core/util/deferred_write.dart): the screen
    commits to the local truth and pops, the durable write finishes on its own, and a
    write that genuinely fails surfaces as a toast over whatever screen the user is on
    by then (`DeferredWriteReporter`, mounted in `app.dart`'s `MaterialApp.builder`).
    Applied to moments, expenses, workout capture, the food log, and moment deletion.
    `MediaService.capture` is local-first the same way: it returns at the durable
    on-device copy and does the registry write, the Photos copy and the Drive push on a
    background tail (per-id serialized; `settleCaptures()` for tests).
  - **A commit button can't fire twice.** New
    [`core/widgets/async_action.dart`](../lib/core/widgets/async_action.dart) — the
    `bool _busy` five screens had each grown, written once, plus `once: true` for
    commit-and-leave actions. That flag matters *because* saves are now local-first: the
    flight is over within a frame, so "in flight" alone stopped being a guard and the
    only thing standing between a double-tap and a duplicate row was pop-animation
    timing. `PillButton` gained a `busy` spinner. Guards added where there were none:
    workout capture, both plan editors, the photo viewer's delete, and Start on the
    Up-Next card (which was pushing two live sessions).
  - **Spotify reconnects itself.** `MusicController` gained `linked` / `isLinked` /
    `reconnectIfLinked`: connecting once **links the device** (persisted per-device in
    `SpotifyLinkStore`), and from then on the app reattaches at launch, on every app
    resume (`ZivoApp` is now a `WidgetsBindingObserver`), and on a dropped connection
    via a bounded backoff — never on `authFailed`/`noSpotifyApp`, which can raise an
    auth sheet or can't succeed. `disconnect()` now means *unlink*, and Settings'
    Music card carries it.
  - **The bottom bar is the music surface.** `NowPlayingLozenge` renders every
    connection state instead of only a live track, so a linked device keeps the strip —
    with Reconnect *on* it — through the drops that are normal for App Remote; the
    Connect affordance is no longer buried. With a track it carries the full transport
    (**previous · play/pause · next**) and a hairline playhead in place of the
    unreadable 9pt timecode. The live session's docked bar does the same.
  - **Live Session legibility.** The session clock 13→18pt, the segment captions
    9→10.5pt (both read from arm's length mid-set), the exercise name capped at two
    lines so a long movement can't push the goal card under the fold, and a real gap
    above the music dock, which was welded to the button over it.

- **Auth security pass + the auth module became a reference implementation**
  (2026-09-02, on `core-edits`). Two parts: close the real holes, then draw the
  boundary that keeps them closed. Full architecture writeup: [`AUTH.md`](AUTH.md).
  - **Security (server-side, needs a deploy — see owner actions).**
    (1) `deleteAccount` now verifies reauthentication **server-side** via the ID
    token's `auth_time` (`requireRecentAuth`, 5-minute window). It was gated only by
    the client prompt, so any valid token could reach the app's one irreversible
    operation. (2) The four model-backed callables that had **no call ceiling at all**
    — `aiImportWorkoutPlan`, `aiImportDietPlan`, `aiGenerateDietPlan`, `aiTranscribe` —
    are now bounded by a per-user daily quota (`functions/shared/quota.js`, pure +
    8 unit tests, counters at `users/{uid}/quotas/{bucket}`, Admin-only). Only a size
    cap existed before, so one account could loop 14 MB PDF extractions against the
    Anthropic bill. (3) `resetPasswordWithOtp` now calls `revokeRefreshTokens` — the
    Admin SDK path does not revoke sessions on its own, so an attacker's session
    survived the very reset made to evict it. (4) Client-supplied ids are validated as
    single path segments before reaching `.doc()` (`functions/shared/ids.js`) — Firestore
    reads a slash-bearing id as a *path*, which let a client steer Admin-SDK writes
    (and `aiDeleteConversation`'s `recursiveDelete`) inside its own subtree.
  - **Rules.** Ownership collapsed onto three helpers (`isOwner` / `emailTrusted` /
    `canWrite`) instead of the same predicate repeated 56×. Email verification is now a
    **boundary, not just a screen**: `canWrite` refuses writes from an unverified
    address, while reads stay on plain ownership (a stranded account must still be able
    to read and export). `users/{uid}` — the only PII document, previously a bare
    `allow read, write` — is pinned with `hasOnly` + bounds and denies client deletes.
    `authEvents` and the auth summary are `hasOnly`-pinned, and the summary's
    server-authored `emailVerifiedAt`/`emailLastSentAt` are now immutable to clients.
    Rules suite **111 → 129 green**.
  - **Architecture — identity is not the user.** `features/profile/` split out of
    `features/auth/`: `UserProfile`, its repository, the profile pages, and the new
    `SessionState`. `AuthState` is now free of every ZIVO concept (it used to carry
    `ProfileCompletionRequired`, which made the portable module import ZIVO's
    date-of-birth field), and the app-specific "is this session ready?" question is
    composed on top in `profile/domain/session_state.dart`. Dependency runs
    profile → auth, never back.
  - **Structure.** `FirebaseAuthRepository` 696 → 387 lines, now a composition root over
    `sources/` (email-password · federated · callables) and `mappers/` (user · OTP
    errors), plus `AuthActivityRecorder` whose signatures enforce "bookkeeping can never
    fail a sign-in". `AuthRepository` split into four named facets
    (`SessionAuthentication` · `EmailVerification` · `PasswordManagement` ·
    `AccountLifecycle`) unioned into one injectable object. Barrels at
    `features/auth/auth.dart` and `features/profile/profile.dart`.
  - **Tests:** Flutter 1055 green (+ new `auth_state_test.dart` — the verification
    policy was untested — and a rewritten `session_state_test.dart`), functions 394,
    rules 129. `flutter analyze` clean.

- **Bring-your-own-plan reaches parity: workout import now takes text and voice,
  not just a document — and the two importers stopped being copy-paste twins**
  (2026-09-02, on `claude/refactor-and-feature-review-e5b2ed`). Two parts, done in
  sequence.
  - **Refactor — one import flow, shared by workout and diet.** `workout_pdf_import_page.dart`
    (965 lines) and `diet_import_page.dart` (698) were near-identical: same file
    picker, same `_maxFileBytes`/`_allowedExtensions`, same `_importErrorMessage`
    (the diet file's own comment said it "mirrors `workout_pdf_import_page.dart`
    exactly"), same five phase widgets — and they had already drifted (workout on
    raw `TrainType.ui(...)` literals, diet on the named `AppText` ladder). Now one
    module under [`capture/presentation/import/`](../lib/features/capture/presentation/import):
    `plan_import_file.dart` (`pickImportFile`, `kMaxImportFileBytes`,
    `kImportAllowedExtensions`, `importErrorMessage` with the one differing clause as
    a param) and `import_flow_states.dart` (`ImportSelectingState`/`ImportAnalyzingState`/
    `ImportRejectedState`/`ImportErrorState` + `importProgressLine`). The workout
    preview/done screens stay in the page (only it reviews in place). **Deliberate
    visual settle** (like the sheet-radius/field-decoration passes before it): the
    workout import's select/analyze/reject/error screens now render on the named
    ladder, matching diet — copy is byte-identical, so tests were untouched. The
    describe (dictate/type) screen was extracted the same way to
    `plan_describe_page.dart` (diet's `DietDictatePage` is now a thin wrapper;
    `keyPrefix` keeps its `dictate-*` test keys), and the add-plan sheet's route row
    became the shared `AddPlanRouteTile`.
  - **Feature — every capture route for a split.** Image import already worked (the
    "PDF" name was stale); the missing routes were **type it out** and **say it out
    loud**, both of which diet already had. `importWorkoutPlan` now takes a sealed
    `WorkoutImportInput` (`Document | Description`) mirroring `DietImportInput`;
    `WorkoutPlanSource` gained `photo`/`dictated`/`typed`, threaded through
    `workoutPlanFromImport` for honest provenance. New `showAddWorkoutSheet` (document
    · say it · type it · build by hand) replaces the four bare pushes of the old
    `WorkoutPdfImportPage` **and** the split editor's two-option Cupertino chooser
    (which hard-coded an English "Cancel" — one of the debts STATE flagged).
    `WorkoutPdfImportPage` → `WorkoutImportPage`, file renamed. Voice reuses the
    app-wide recorder + `aiTranscribe`, so it was nearly free.
  - **Backend (owner deploy — see action items).** `functions/ai/workout_import.js`
    gained the `text` branch `diet_import.js` already had (fenced description prompt,
    `MAX_TEXT_CHARS`, exactly-one-kind validation), and `index.js`'s
    `aiImportWorkoutPlan` passes `data.text` through. **Until deployed, the typed/
    dictated workout routes hit the old file-only extractor and fail with
    invalid-argument** — the document/photo route is unaffected.
  - Cover: Flutter **1050 → 1053** (new `workout_capture_routes_test.dart` for the
    type/dictate→`WorkoutImportDescription` paths; import + split-management +
    diet-capture tests migrated to the shared flow, all green). Backend
    `workout_import.test.js` **24 → 31** (mirrors diet's description block); full
    functions suite **386** green. `flutter analyze` clean. Functions **lint not run
    locally** — `eslint` isn't installed in this worktree; the JS mirrors
    `diet_import.js`'s style exactly.

- **The Today dashboard reads one injected clock, and its tests no longer break at night**
  (2026-09-01). Two momentum tests failed on any run after **23:20 local**: `_done(at, id)`
  completes its session at `at + 40 min`, the tests seeded off the real clock, and
  `weekActivity`/`trainingStreakDays` bucket by **calendar day** — so past 23:20 the
  completion landed in tomorrow's bucket and the streak collapsed. Commit `2e24991` had
  pinned the insights strip's clock but never covered momentum, which read `DateTime.now()`
  directly in four places.
  - **Production:** `TodayPulseSection` and `MomentumSection` now take `DateTime Function()?
    now` (defaulting to the real clock, so nothing changes at runtime), threaded from
    `TodayPage.now` down through `_TrainedRing`, `_VolumeRing`, `_StreakRow` and
    `WeekActivityBars` — the same seam `InsightsSection` already had. The whole dashboard
    answers "today"/"this week" from **one** clock.
  - **Tests:** every seeded test pins to `_middayToday()` and passes that same instant to
    the page, so nothing derives from the hour the suite runs at. Midday is deliberate: far
    enough from both midnight boundaries that a +40min completion stays on its day.
  - A **fixture-invariant test** locks it — it asserts a seeded session and its completion
    share a calendar day, and fails the moment the pinned hour moves back into the danger
    zone. Verified by simulation: pinning to 23:30 reproduces exactly the two original
    failures plus the guard; midday passes.

- **The app now streams what it is actually doing — Ask and PDF import** (2026-09-01, on
  `core-edits`). **Deployed to `zivo-63f15` 2026-09-01** — `aiChat` rev `aichat-00023-jiw`,
  `aiImportWorkoutPlan` rev `aiimportworkoutplan-00018-jag`, `aiImportDietPlan` rev
  `aiimportdietplan-00012-xoc`, all ACTIVE. Verified on device: a live turn's rail rendered
  the streamed `working` phase (the buffered path can only ever show "Thinking…"), and two
  multi-tool questions answered from real account data.
  - **Ask.** The rail sat on one `working` label for the whole tool loop. `gateway.js` now
    emits `{type:'step', tool, status}` as each **read** tool starts/finishes, and
    `AskController` maps the name to copy ("Reading today's diet…", "Looking that food
    up…"). Tool name only on the wire — no inputs, no results. Unknown tool → "Working…",
    so a newer server can't leak `get_body_composition` onto an older client. Mutating
    tools emit nothing (they propose, they don't execute). Ephemeral by choice: **no
    Firestore schema change, no rules change, no extra writes per turn.**
  - **PDF/photo import.** Was a plain `.call()` with three hardcoded lines cycling on a
    **1.6s timer that had no connection to the backend**. Both import callables now stream:
    an import emits no assistant text, so `ai/import_progress.js` scans the model's
    partially-written tool input for *complete* `"key": "value"` pairs and reports real
    days/meals and item counts ("Pull · 7 exercises"). Progress only grows; a half-written
    label is never shown; **a stalled import now visibly stalls** instead of animating
    reassuringly. Deliberately never claims a total — the model doesn't know how many days
    a document holds until it reads them, so "Day 2 of 5" would be a number nobody has.
  - **`aiGenerateDietPlan` was NOT converted** and still cycles written lines. Deliberate,
    documented in `diet_import_page.dart` and `ai/FEATURE.md` — not an oversight to
    "finish" without deciding it's worth it.
  - Both paths are **opt-in** (`acceptsStreaming` / `onProgress`); omit them and the call
    is buffered and byte-identical to before.
  - **l10n debt:** the rail's step labels are English-only, like the phase labels they join.
    `AskController` has no `BuildContext` by design (ADR-008) so it can't reach
    `AppLocalizations`. Pre-existing; this widens it. Mapping is client-side in one file, so
    copy changes need no deploy and a future move to l10n is one edit.
  - Cover: 244 backend (`node --test`, incl. a scanner test asserting progress never goes
    backwards across *every prefix* of the JSON) + Dart domain/controller/widget tests.
    Backend lint clean.

- **Capture save is re-entrancy-guarded — a double-tap used to write twice** (owner report,
  2026-09-01, on `core-edits`). `_save` is async and the button stayed live across the
  await, so a second tap ran the whole handler again before the first one's write and pop
  landed. A new expense/moment mints its id from `microsecondsSinceEpoch` **per call**, so
  the second tap wrote a *second* row rather than overwriting the first, and the second
  `pop` popped the route underneath. Same hole in three flows — `expense_capture_page`
  (`_save` **and** `_delete`), `moment_capture_page` (also ran a second media capture racing
  the first on one store path), and `wallet_balance_sheet`, the silent one: `topUpWallet` is
  **additive**, so there was no duplicate row to notice, the balance was just credited
  twice. `add_category_sheet` already had the guard. All three now use the `_busy` pattern
  from `LiveSessionController` (`:164`), guarding the write *and* the pop with the button
  disabled in flight, while `_canSave` still drives the label so it doesn't flip back to a
  bare "Save" the instant it's tapped. Covered by `test/expenses/capture_double_tap_test.dart`
  — which blocks the repository write on a `Completer` **on purpose**: with the plain
  in-memory repos the first tap resolves and pops before a second can land, so a test
  written the obvious way passes against the unguarded code.
  - The two `today_dashboard_widget_test.dart` momentum failures noted here are **fixed**
    (see the entry below). The suite is green: **1050 passing.**

- **Live session — the logging screen, on the owner's own report from a real session.**
  Five complaints, five causes, all in `widgets/live_session/`:
  - **"I don't want to log the weight every time."** The weight field now **carries the
    last load forward** (`LiveSessionController.carriedWeightFor`): this session's earlier
    sets → the index-aligned set from last time → any set of that history that carried a
    load → the plan's target, all scoped to the same exercise. `computeGoal` only ever
    priced a set from an *index-aligned* history set or a plan `targetWeightKg`, so on a
    split written without loads the field was blank on every set forever — which is both
    pure re-typing and why sets were getting logged with no weight at all. The quick-load
    chips ("Same 100 · +2.5 · −2.5") read the same fallback, so they stop vanishing exactly
    when they're most useful. It stays a **suggestion, not a draft** — nothing is persisted
    until the set is committed.
  - **"The reps and weight are jammed at the bottom."** `RunningScaffold` had **one**
    flexible gap, above the hero, so all the spare height piled up between the set chips
    and the goal card and the steppers welded to the commit row — even though the class
    doc had described two gaps for months. Now two equal gaps. The commit row also shrank
    to `kCommitRowHeight` (52, from 60) and its reserved space to 80 (from 100); it is
    pinned *over* the content, so its height is height the steppers don't get. On a 402×874
    screen the goal card moved up ~57pt and the steppers gained ~121pt of clearance.
  - **"It's different when there's no music."** Same single-gap cause: the companion dock
    takes a bar's height out of the phase, and every point of it came off that one gap.
    Split across two, a track starting shifts things half as far — and the dock is now
    wrapped in an `AnimatedSize` (outside the phase, so the `IntrinsicHeight` gotcha
    doesn't apply), so it slides in instead of re-flowing the screen in one frame.
  - **"The keyboard is hard to close."** It genuinely was: the fields open a **decimal
    pad, which ships no Return key on iOS**, so the only exits were committing the set or
    leaving the screen. Three ways out now — a tap anywhere outside the input cluster
    (`kSetInputGroup`, a shared `TapRegion` so the ± steppers and quick-load chips *don't*
    count as outside), a downward drag (`keyboardDismissBehavior: onDrag`), and a **Done
    pill** over the commit row while a field has focus. Focus is detected with an inert
    `Focus` node, **not** `MediaQuery.viewInsets` — a resizing `Scaffold` strips that from
    its own body. The same decimal-pad trap had a twin on **Profile → About**, where the
    multi-line field's Return key makes a newline: it now dismisses on tap-outside and on
    drag, and `Scrollable.ensureVisible(alignment: 1)` lifts the whole card — Cancel/Save
    included — clear of the keyboard instead of just the caret.
  - **"Sometimes the screen is buggy and doesn't scroll."** `PhaseScroll`'s doc claimed
    always-scrollable physics ("a surface that ignores a drag reads as broken scrolling")
    and never set any. It does now.
  - **+9 tests**, in three files: the carry-forward rule
    (`live_session_controller_test.dart`), keyboard dismissal
    (`live_session_keyboard_overflow_test.dart`) and the geometry that was complained
    about — commit-row height, air above it, and the gap absorbing the music dock — in a
    new `live_session_layout_test.dart`.

- **Today's insights strip stopped depending on what time you run the tests.**
  `test/home/today_dashboard_widget_test.dart` was failing on `version-1` — and it was a
  *test* defect, not a Today bug. Two of `buildInsights`'s rules are hour-of-day rules (the
  steps nudge speaks from 16:00, the diet nudge from 19:00) and `InsightsSection` read the
  real wall clock, so the file was only green between 16:00 and 19:00. One test had already
  grown an `if (DateTime.now().hour >= 16)` branch to survive, which meant that for most of
  the day it asserted the nudge was *absent* and never once checked the thing it is named
  after.
  - `InsightsSection` (and `TodayPage`) now take an injectable `now`, the same
    `DateTime Function()?` pattern `LiveSessionPage` already uses. **Deliberately scoped to
    that one section:** it is the only part of Today whose output changes with the hour.
  - The "nothing bluffs" test also needed a genuinely empty account. `InMemoryDietRepository`
    seeds a demo plan, so "3 meals left today" was a true statement about the *fixture* and
    the evening nudge duly fired on a user who had entered nothing — new
    `InMemoryDietRepository.empty()` for tests whose subject is a new account.
  - The hour-gated branch is gone, split into a pair that pins 18:00 (nudge shows) and
    09:00 (nudge stays quiet). Verified green at six times of day from 00:54 to 19:54.
  - **Suite is fully green: 1,037 passing, no known failures.**

- **Structural refactor — a controller layer, and one way to do the common things.**
  Nothing about what the app *does* changed: the 992 pre-existing tests all pass
  untouched, which is the evidence. What changed is where the code lives.
  - **Presentation controllers** ([ADR-008](DECISIONS/ADR-008-presentation-controllers.md)).
    The two screens that had outgrown `setState` now hold their logic in a plain
    `ChangeNotifier` beside the page:
    [`LiveSessionController`](../lib/features/workout/presentation/controllers/live_session_controller.dart)
    (three clocks, the kill-proof rest countdown, draft autosave, set resolution,
    the exits) and
    [`AskController`](../lib/features/ai/presentation/controllers/ask_controller.dart)
    (optimistic/durable reconciliation, idempotent retries, the streamed-reply
    pacer, the voice path), and
    [`PlanEditController`](../lib/features/workout/presentation/controllers/plan_edit_controller.dart)
    (the split editor's day/exercise mutation and — the reason it exists — the
    **rotation-cursor rule**: `cycleCursor` is stored as an index but days can
    be dragged, so the cursor is tracked by day *identity* and resolved back to
    an index on save; getting it wrong silently changes which workout Home
    offers next). **No new dependency** — the ADR explains why this is not
    riverpod/bloc.

    | Page | Before | After |
    |---|---|---|
    | `live_session_page.dart` | 4,236 | **519** |
    | `workout_plan_edit_page.dart` | 1,813 | **416** |
    | `ask_page.dart` | 3,061 | **781** |

  - **33 new unit tests** assert session, turn and plan-edit rules directly,
    with no widget tree, in under a second
    (`test/workout/live_session_controller_test.dart`,
    `test/workout/plan_edit_controller_test.dart`,
    `test/ai/ask_controller_test.dart`). Suite 992 → 1,025 green.
  - **~65 private widget classes became real files** under
    `workout/presentation/widgets/live_session/` (9 + a `phases/` folder),
    `workout/presentation/widgets/plan_edit/` (5) and
    `ai/presentation/widgets/ask/` (7). One test that had to find a widget by
    matching `runtimeType.toString() == '_RiseOnce'` now names the type.
  - **Warm-up and rest are one widget now.** The code already said they were
    "the SAME screen, element for element" and kept two ~90-line copies to
    prove it; `CountdownPhase` makes that structural — a phase only chooses its
    hue, its words and what its buttons do.
  - **`trimWeight` existed twice** (live-session format + a private copy in the
    plan editor) with identical bodies. Now one
    [`workout_format.dart`](../lib/features/workout/presentation/workout_format.dart).
  - **One way to open a sheet.** All 28 hand-rolled `showModalBottomSheet` call
    sites go through [`showZivoSheet`](../lib/core/widgets/zivo_sheet.dart); the
    grab handle that was copy-pasted into 14 files is `ZivoSheetHandle`. This
    also settled a drift nobody chose: the sheet top radius was 24 in six places,
    26 in eighteen and 28 in one — now `AppRadius.sheet`.
  - **One filled-field decoration.** 11 hand-written `InputDecoration` blocks
    across diet/workout/auth/ai became
    [`zivoFieldDecoration`](../lib/core/widgets/zivo_field.dart), which takes the
    feature's hue as an argument (ADR-006 hue ownership, so **not** one universal
    field). Only four of the eleven drew a focus ring before; all do now.
  - **One destructive confirmation, and a real i18n bug fixed.** Seven screens
    each hand-wrote the "are you sure?" dialog (delete a moment · session ·
    split · workout plan · diet plan, discard a live session), and **six of
    them hard-coded the English `'Cancel'`/`'Delete'`** — while `actionCancel`
    ("إلغاء") and `actionDelete` ("حذف") had been sitting translated in both
    `.arb` files, unused. An Arabic user deleting anything saw English buttons.
    All seven now go through
    [`confirmDestructive`](../lib/core/widgets/zivo_confirm.dart), which reads
    its labels from `l(context)` by default; 10 new title/body keys were added
    to both `.arb` files. Copy is byte-identical to before, so the whole
    migration landed with **zero test changes**. It also settles the look: the
    background was `TrainColors.raised` in some and a near-invisible
    `Color(0x08FFFFFF)` in others, across four title styles.
    **Owner check wanted:** the 10 new Arabic strings are mine, not a native
    speaker's.
  - **Still unlocalized (not in this pass):** four hard-coded `'Cancel'`s in
    `CupertinoActionSheet`s (`moment_capture_page.dart`, `profile_page.dart`).
  - **Number parsing moved to [`core/util/parse.dart`](../lib/core/util/parse.dart)**
    from the bottom of a *diet widget* file, which is why 13 call sites had
    hand-written `double.tryParse(x.trim().replaceAll(',', '.'))` instead of
    importing it. **This fixed a real bug:** the bodyweight weigh-in sheet used a
    bare `double.tryParse`, so it silently rejected "72,5" — every value typed on
    a keyboard whose decimal mark is a comma.

- **Simplification pass — the diet a 15-year-old can read (in flight).** The owner's
  verdict on the diet epic was that it worked but read like the engine: too many numbers,
  too much text, arithmetic stacked above the meals. Three parts have landed.
  - **Arabic + English, app-wide (foundation done, copy pass in flight).** `flutter_localizations`
    + `intl` + `l10n.yaml`, ARB files at [`lib/l10n/`](../lib/l10n), and a `LocaleController`
    (device-local, `shared_preferences`) on `AppScope`, driving `MaterialApp.locale` through a
    `ValueListenableBuilder` in `app.dart` — so a language change re-renders the app **and**
    flips it RTL, because direction follows the locale and nothing else. Strings are read
    through **`l(context)`** ([`lib/l10n/l10n.dart`](../lib/l10n/l10n.dart)), never
    `AppLocalizations.of` — `l` falls back to English when no delegate is installed, which is
    what lets 120-odd widget tests keep pumping a bare page. Picker: Settings → Language
    ([`core/l10n/language_sheet.dart`](../lib/core/l10n/language_sheet.dart)), options written
    in their own language. `test/core/l10n_test.dart` fails the build on an en/ar key gap.
    **Only the diet + shell + settings strings are keyed so far** — the rest of the app is
    still hardcoded English; that is the remaining work.
  - **Groceries deleted.** `grocery_list_page.dart`, `domain/grocery_list.dart`, the Diet
    header's basket action and both tests are gone, at the owner's instruction. The
    *Expenses* category named "Groceries" is untouched — that is money, not diet.
  - **The Diet screen: seven blocks to two.** `diet_plan_page.dart` now shows **one number**
    (kcal left), the meals as **Meal 1 … Meal N** (the plan's own name for each demoted
    beside it), supplements, and **Eaten today**. The plan-vs-target caption, the macro bars,
    the plan verdict, the target row and Today's read all moved down a level to the new
    [`diet_plan_details_page.dart`](../lib/features/diet/presentation/pages/diet_plan_details_page.dart),
    reached by one quiet row at the foot of the screen. **The `ConsumedBasis` rule moved with
    them, it did not lapse:** the hero dropped its "1400 EATEN" figure, so it no longer makes
    the claim the basis qualifies — and Plan details, which does print an eaten figure,
    prints the basis with it (`Key('consumed-basis')`). Tests moved rather than weakened:
    `diet_plan_details_page_test.dart` + the retargeted `plan_verdict_card_test.dart`.
  - **Body data is asked once.** The target calculator's sheet no longer renders weight,
    height, age, sex and activity as editable fields — it **reads** them through
    `resolveBodyMeasures` (body profile + weigh-in log + the account's date of birth),
    states what it will use, and routes to `body_profile_page.dart` when something is
    missing or needs changing. The old sheet let a user type a weight that never reached
    the weigh-in log, so ZIVO could hold two. `body_profile_page.dart` itself dropped its
    four-sentence preamble for plain questions ("What do you weigh?"), and the optional
    known-maintenance field moved behind "I already know my daily calories" — the one
    engine-facing input on the screen, kept off it until asked for.
  - **Preferences are tapped, not typed.** `diet_preferences_page.dart`'s four free-text
    boxes are now chips (`presentation/widgets/food_chip_picker.dart` over
    `domain/common_foods.dart`), with an **Other…** chip for anything a fixed list can't
    cover — non-negotiable for allergies. Chip ids are **English and stay English** on the
    wire: `functions/ai/diet_generate.js` resolves against an English USDA catalog, so only
    the label is localized. "Anything else" stays a text field, deliberately.
  - **The Arabic copy pass — about 40% through.** **344 keys** in both languages. Done:
    **diet, home/Today, shell, hub, capture, expenses**, and the workout surfaces a user
    touches daily (hub, plan, up-next card, start/change sheets, and the whole **live
    session** screen). Remaining, on the same metric that started at ~330 literals and now
    reads **197**: workout drill-downs ~75 (analysis, stats, history, splits, PDF import,
    plan editor, session details), auth ~45, ai ~28, moments ~13, music ~12, core ~9,
    expenses ~8.
  - **Three rules the pass established, worth keeping:**
    - **Calendar names come from `intl`, never from ARB.** `formatTodayShort` and the
      dashboard's `_shortDate` take a locale and use `DateFormat`; both fall back to the
      default locale, because `intl` only ships `en_US` eagerly and a widget test with no
      delegates would otherwise throw on a date caption.
    - **`l(context)` is illegal in `initState`.** It reads an inherited widget. This bit
      once already: a `goal.repsLabel == 'AMRAP'` comparison was localized, which both
      crashed the live session in tests and would have silently stopped matching in Arabic.
      The sentinel is now `kAmrapLabel` in `workout/domain/progression.dart` — a **value**,
      not copy. Same shape as `common_foods.dart`'s English chip ids and
      `expense_category.dart`'s ids: ids travel, labels translate.
    - **Whole sentences are keys, not templates.** Arabic attaches a name with **يا** and
      has no separate afternoon greeting, so `greetingFor` branches to six keys rather than
      filling "{greeting}, {name}"; the same reasoning split the meals-left nudge into four
      phrasings and the weight-trend nudge into up/down pairs.
  - **Owner action:** the AI coach answering in Arabic is a `functions/ai/gateway.js` change
    and therefore an **owner deploy**.

- **Diet onboarding — Phase E: the coach knows what you burn.** ZIVO now **measures**
  maintenance from the user's own weigh-ins and food log instead of only estimating it from
  an equation (`domain/analysis/maintenance_calibration.dart`), refusing unless there are ≥2
  weigh-ins ≥14 days apart and ≥10 logged days covering ≥⅔ of the window — and naming what's
  missing when it refuses. Precedence is **stated > measured > estimated**: a measurement
  replaces the equation but never overrides a figure the user gave, which is surfaced as a
  disagreement instead. That figure rides in `DietState.energy` (an input on both sides, so
  the screen and the coach cannot diverge), mirrored in `functions/diet/energy.js` and pinned
  by `test/fixtures/energy_vectors.json` across both suites. New coaching rule
  `target_does_not_serve_goal` catches the one failure daily logging can never reveal: a
  target that quietly fights the goal. **Needs a functions deploy.**
- **Diet onboarding — Phase D: ZIVO builds the plan.** A preferences screen (meals/day,
  likes, won't-eats, allergies, cuisine) feeds `aiGenerateDietPlan`, where **the model picks
  foods and amounts but never calories** — every item is priced through the same USDA +
  custom-food resolver the coach and food log use, ambiguous foods go back to the model in a
  second call to pick a row, and anything still unresolved keeps a marked estimate. The day
  is then fitted to the user's target by deterministic arithmetic, and an allergen in the
  result **refuses the whole plan** rather than being left to prompt compliance
  (`functions/ai/plan_fitting.js`). Generated plans land in the same review editor as
  imports and carry `DietSource.generated`. **Needs a functions deploy.**
- **Diet onboarding — Phase C: capture from anywhere.** One **"Add a diet"** sheet with four
  routes — PDF/photo, **say it out loud**, type it out, build by hand — all landing in the
  same extractor and the same review editor. Dictation records through the Ask feature's
  recorder, transcribes via the existing `aiTranscribe`, and shows the transcript in an
  **editable field before extraction** (STT mis-hears foods and amounts; fixing it later
  means fixing a calorie figure). `importDietPlan` now takes a sealed `DietImportInput`, and
  `functions/ai/diet_import.js` accepts `text` alongside a file — **needs a functions
  deploy** before dictation/typing work against the real backend. `DietSource` gained
  `photo`/`dictated` so a plan says how it arrived.
- **Diet onboarding — Phase B: a library of plans.** The user can keep several plans (a
  cut, a bulk, the one their coach wrote) with exactly one being followed — a new
  `diet_plans_page.dart` lists them with their verdicts, and follow/stop-following/delete.
  The invariant lives in the repository's batched write, not in rules or callers. The Diet
  screen now tells "no plans" apart from "not following any", and the **"No daily target
  set" card offers the plan's own daily figure** as a target (`planDerived`) behind a sheet
  that asks what the plan is *for*. `planDailyEnergy` is the single basis for every "N kcal
  a day" figure; `BodyMeasuresBuilder` is the single place body data is assembled.
- **Diet onboarding — Phase A: body data + the plan verdict.** Diet can now answer *"what is
  this plan doing to me"*: `analysePlan` (pure, on-device — `domain/analysis/plan_verdict.dart`)
  measures the plan's average day against maintenance and reports a direction, a kcal/day
  delta and a projected kg/week, with a ±100 kcal deadband and the plan's `estimated` flag
  carried through. Body data is a stored entity now (`BodyProfile` at `bodyProfile/current`
  — height/sex/activity/optional known maintenance; **weight stays in the workout weigh-in
  log**, age still comes from the profile's DOB), entered on the new `body_profile_page.dart`,
  which also prefills the target calculator so it stops asking twice. The Diet screen shows the
  verdict card, or a prompt naming exactly which body data is missing. **No target is ever
  auto-derived** — that rule is unchanged. Decisions:
  [ADR-007](DECISIONS/ADR-007-diet-onboarding-body-data-and-generation.md); the remaining
  phases (plan library · dictate/photo capture · AI generation · coach wiring) are planned in
  [DIET_ONBOARDING_PLAN.md](DIET_ONBOARDING_PLAN.md).
- **Keyboard fix (shell):** `HomeShell` no longer resizes for the keyboard
  (`resizeToAvoidBottomInset: false`). A resizing scaffold also strips `viewInsets` from its
  body's `MediaQuery`, which left Ask's composer floating a nav-island's height above the
  keyboard; each tab owns the inset now. Regression test:
  `test/shell/home_shell_keyboard_test.dart`.

- **Workout-tracking design handoff — the remaining screens.** The handoff in
  `assets/design_handoff_workout_tracking 2/` (`IDENTITY.md` is the binding spec) had
  Today, Active set and Rest already built. This pass added the rest of the eleven:
  **Workout hub** (`workout_dashboard_page`), **You** (`profile_page`), **Settings**,
  **Diet** (`diet_plan_page`), **Expenses** (`expenses_list_page`), **Moments**
  (`moments_timeline_page`) and **Ask** (`ask_page` + `chat_header`) — plus the **Hub
  tab**, which isn't a handoff screen but is the doorway into four of them.
  - New shared primitives in [`core/widgets/train_surfaces.dart`](../lib/core/widgets/train_surfaces.dart):
    `TrainScreen` (the tinted page ground), `TrainPageHeader`, `TrainSectionLabel`,
    `TrainIconTile`/`TrainListRow`/`TrainListCard`, `TrainStatTile`, `TrainStatStrip`,
    `TrainSparkline`/`TrainAreaChart`/`TrainBarCluster`, `TrainBar`/`TrainBarRow`,
    `TrainFab`, `TrainFilterPill`, `TrainDashedCard`.
  - [`train_tokens.dart`](../lib/core/theme/train_tokens.dart) gained the remaining
    screen tints, `amber` (money only), and `TrainType.serif` — **Instrument Serif
    italic, the assistant's voice and nothing else in the app**.
  - `SettingsRow`/`SettingsSectionCard` were re-dressed in place (shared by You,
    Settings, Storage & sync), which retired the saturated gradient icon chips the
    identity doc rules out.
  - Domain additions: `weeklySessionCounts` / `dailySessionCounts` /
    `recentSessionDurationMinutes` (tile sparklines) and `lifetimeVolumeKg` (You's
    lifetime tonnage).
- **Plan editing + import flows too** (beyond the handoff's stated scope, at the owner's
  request): the workout plan editor, PDF import wizard and workout capture. Done through
  the shared `capture_widgets.dart` chrome (`CaptureTopBar`/`CaptureIconButton`/
  `PillButton`/`SelectChip`), so the diet and expense/moment capture flows come along
  with them. Commit actions moved from green to **ember** across these screens — green is
  state, ember is the one committing action (identity §3) — and secondary "Add day"/"Add
  exercise" buttons went quiet so they stop competing with Save.
- **Workout drill-downs on the handoff too.** Every page reached from the Workout hub —
  Progress, the four stat pages, Bodyweight history, Day details, Session details,
  History, Analysis, Splits — was still on v2 material. All are across now, via two
  shared seams so they can't drift again: `WorkoutSectionLabel` is a wrapper over
  `TrainSectionLabel`, and `StatDrillDownScaffold` is the one shell behind all four
  stat pages. `verdictStyle` moved onto the handoff's four hues (green progressing,
  ember down, neutral matched — no fifth red). Decorative colored glows stripped
  app-wide on these surfaces per identity §5.

- **Auth hardening + account lifecycle** — completed the auth system on the
  `claude/auth-system-review-1c7a20` branch: **forgot-password** (branded OTP → new
  password, signed-out, `forgot_password_page.dart`), **change password** (reauth →
  `change_password_page.dart`), **account deletion** (reauth → server-side data + identity
  wipe, `delete_account_sheet.dart` + the `deleteAccount` callable), plus the OTP
  **rate-limit-bypass fix** (throttle accounting now survives a code being consumed/expired/
  locked out — shared `functions/auth/otp.js`, unit-tested), the **already-verified** send
  path, and smaller fixes (deadline→network copy, Apple null-token guard). New locked
  collection `passwordResetOtps/{uid}` (rule + test). See
  [auth/FEATURE.md](../lib/features/auth/FEATURE.md).
- **Music restored** as a workout-anchored now-playing companion + immersive **Now Playing**
  screen with an **album-artwork color-adaptive background** and a subtle mini-bar tint
  (`palette_generator`). Controller seam: `FakeMusicController` (default/offline) vs
  `SpotifyMusicController` (real App Remote). See [music/FEATURE.md](../lib/features/music/FEATURE.md).
- **Diet epic** — premium Diet Today UI, **Diet PDF import** (`diet_pdf_import_page` +
  `functions/ai/diet_import.js`), grocery list, and the **AI coach persona** system-prompt
  rewrite (`functions/ai/gateway.js` — verified: no longer references removed features/tools).
  `functions/ai/coach_report.js` (weekly coach report) is present.
- **Device / pedometer** — `StepCounterService` drives Today's Move ring (hidden on hosts
  with no step sensor).
- **Shell + profile redesign** — floating island bottom bar with a spring-gliding ember
  capsule; "You" surface redesign.
- **Media pipeline** — local-first store + registry + Google Drive backup target in
  [`core/media/`](../lib/core/media); Moments and profile avatars run on it.

> Don't re-derive or "fix" the above as if missing — it's built and committed. Verify
> against the code before assuming otherwise.

## Owner action items (blockers only the owner can clear — not code bugs)

- **Rules deploy for single-device sessions (2026-09-10):**
  `firebase deploy --only firestore:rules` (owner creds). Until it ships, the
  catch-all denies the new `users/{uid}/session/current` doc, so a device cannot
  write its claim — the client-side realtime enforcement then silently no-ops
  (the guard swallows the rejected write) and two devices can still both be
  active. No functions change is required. Purely additive; safe to deploy with
  or ahead of the client build.

- **Rules deploy for the streak/session-duration work (2026-09-08):**
  `firebase deploy --only firestore:rules` (owner creds). Until it ships, the
  catch-all denies the new `users/{uid}/trainingDayMarks` collection, so a
  streak restore or a missed-day reason will fail to save on device (it surfaces
  as a deferred-write toast, nothing is lost locally). The same deploy adds
  `voided` to the allowed `workoutSessions` statuses and the bounds on
  `correctedDurationMinutes` — **voiding a session and correcting a duration
  will be rejected until then.** No functions change is required for this, but
  `functions/ai/tools.js` + `store.js` also changed (the coach now honours a
  corrected duration and withholds an implausible one), so a
  `firebase deploy --only functions` is worth pairing with it.

- **Live Session screen-wake — a dependency decision, not a bug.** The phone still
  sleeps mid-set during a guided session: the app never asks the OS to keep the screen
  on, and there is no way to do that from Flutter without a plugin (`wakelock_plus` is
  the maintained one). "Every dependency pays rent" makes that the owner's call, so it
  was **not** added as a side effect of the Live Session polish pass. If yes: one dep,
  enable on entering `LiveSessionPage` and release in its `dispose` (and on Finish /
  Leave / Discard, which all pop through it).

- **Spotify on Android:** real playback fails with `authFailed` until the owner registers,
  in the Spotify Developer Dashboard, the Android package `com.ziadelsewedy.zivo` + the
  signing **SHA-1** (release currently signs with the *debug* keystore) **and** adds the
  account under User Management. The app code + manifest are already correct. iOS works.
  App Remote can't run in a simulator — real playback is device-only. Get the debug SHA-1:
  ```
  keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android | grep SHA1
  ```
- **Google Drive backup:** enable the Drive API, add the `drive.file` scope to the OAuth
  consent screen, and add the test user in project `zivo-63f15`; then do the on-device
  OAuth verify of `GoogleDriveBackupClient` (the one path unit tests can't exercise).
- **Backend deploys:** any change under `functions/` (gateway/diet_import/coach_report/
  workout_import) needs `firebase deploy --only functions` with the owner's creds —
  **confirm the exact command with the owner; never run it yourself.**
  - **Pending now (workout multi-format import):** `ai/workout_import.js` + `index.js`
    now accept a dictated/typed **description** (the `text` branch, mirroring
    `diet_import.js`). Until deployed, the workout **"Say it out loud" / "Type it out"**
    routes reach the old file-only extractor and fail with invalid-argument; the
    PDF/photo route is unaffected. Command: `firebase deploy --only functions`.
  - **Pending now:** the **Diet Coach Phases 0–7** work (`gateway.js`, `tools.js`,
    `dates.js`, `mutations.js`, `store.js`, `validator.js`, `index.js`, `functions/diet/*`,
    `functions/nutrition/*` **+ `firestore.rules`**) — see
    [DIET_COACH_AUDIT.md](DIET_COACH_AUDIT.md). Until deployed the live coach keeps the old
    prompt (which licensed invented calories), has no idea what day it is, can write an
    unverified meal id, can't see the user's targets, findings, or nutrition catalog, can't
    resolve/log food from chat, and its replies are never validated against the state. **Deploy
    functions and rules together with the client build** — the tightened `dietEntries` rule
    rejects writes from older app builds, and the `dietTargets`/`foodLogs`/`customFoods` rules
    are what let a target, a food log, or a custom food be saved at all. Phase 8.1 adds the
    `dietPlans` document bounds to the same rules file. **Phase A of the diet-onboarding
    epic adds the `bodyProfile` collection rule** (rules-tested) to the same file — body
    data cannot be saved against the real backend until it is deployed. **Phase C changes
    `ai/diet_import.js` + `index.js`** to accept a dictated/typed description; until that
    deploys, the "say it out loud" and "type it out" routes reach an extractor that only
    understands files and fail with an invalid-argument. **Phase D adds the whole
    `aiGenerateDietPlan` callable** (`ai/diet_generate.js`, `ai/plan_fitting.js`,
    `index.js`); until it deploys, "Build one for me" fails with not-found. **Phase E adds
    `diet/energy.js` and body-data reads to `ai/store.js` + `ai/tools.js`**; until it
    deploys the coach keeps estimating maintenance from nothing and can't see the
    target-vs-goal problem the app now shows. Command:
    `firebase deploy --only functions,firestore:rules` — worth running with `--dry-run`
    first, since nothing here can validate rules syntax locally.
  - **Pending now (1):** the Ask **edit/delete-expense** tools (ADR-005 — `mutations.js`, `store.js`,
    `gateway.js`, `tools.js`) are code-complete + tested but **not deployed**. Until deployed the
    live AI keeps the old create-only backend (the app's redesigned cards already render
    edit/delete proposals once the backend proposes them). Command: `firebase deploy --only functions`.
- **Firestore rules deploy — REQUIRED before creating a category works against the real
  backend.** Two schema changes land in one deploy: categories now write `iconId` instead
  of `emoji` (audit H3), and no longer write `hue` at all (the colour picker was removed —
  see below). `firestore.rules` matches; the **live** rule still demands `emoji` *and*
  `hue`, so until it is deployed every "Add category" write is rejected with
  permission-denied. Reads and existing categories are unaffected — rules validate writes
  only, legacy `emoji` docs still resolve their icon, and a leftover `hue` field on an old
  document is simply ignored. Command (owner creds):
  `firebase deploy --only firestore:rules`.
- **Manual E2E:** real-PDF-in-app import → review → confirm for both workout and diet.
- **Auth callables deploy:** the new `sendPasswordResetOtp` / `resetPasswordWithOtp` /
  `deleteAccount` callables need `firebase deploy --only functions` (owner creds) before the
  new flows work against the real backend. The forgot-password email reuses the existing
  `RESEND_API_KEY` + `OTP_PEPPER` secrets — no new secrets required.
- **Firebase App Check (still recommended, deferred by request):** the callables + Auth
  endpoints remain reachable by anything with the app config. Adding `firebase_app_check`
  + `enforceAppCheck: true` is the outstanding hardening layer that caps scripted abuse of
  the (now unauthenticated) reset endpoint and account creation. **Needs a real release
  keystore first** — Android release still signs with the debug key
  (`android/app/build.gradle.kts`), which also blocks Play Integrity.
- **Auth security pass deploy (2026-09-02):** `firebase deploy --only functions,firestore:rules`
  (owner creds). Both halves must ship together — the rules now require a verified email
  for writes, and the functions carry the reauth check, the daily quotas, and the token
  revocation. No new secrets.
- **⚠️ Migration caveat for the verified-email rule:** any EXISTING account with
  `emailVerified == false` loses **write** access the moment the rules deploy (reads are
  unaffected, by design). Password accounts recover by completing the OTP screen they are
  already routed to; social accounts arrive verified so are unaffected. Worth a glance at
  the Firebase Auth console for unverified accounts before deploying.
- **Firebase Auth password policy:** sign-up strength is still client-side only
  (`signUpWithEmail` goes straight to Firebase, whose floor is 6 characters); the *reset*
  path is validated server-side. Enable the server-side policy in the Auth console — zero
  code.

## How work happens here (workflow)

- `version-1` is the working trunk; `main` lags behind it. Parallel agents run in git
  worktrees under [`.claude/worktrees/`](../.claude/worktrees) (each its own branch/checkout).
- **Shared working tree caution:** stage files by name (`git add <path>`), **never
  `git add -A`/`.`**, and avoid `git checkout`/branch switches while another session has
  uncommitted changes.
- Ziad orchestrates + reviews and commits himself; implementation is often delegated to a
  peer terminal agent. Keep the suite **green** (`make gates`) before handing work back.

## Verification bar

`flutter analyze` clean · `flutter test` green · `functions` `npm test` green · rules
suite green. **Always re-run `make gates` rather than trusting a remembered test count.**

**The Flutter suite is fully green (749) as of 2026-08-28** — the long-standing ~32 red
tests are fixed, so a new failure now means *you broke something*, not "that one was
already red." Keep it that way.

**Driving widget tests:** prefer `find.byKey` over `find.text` for anything a test *taps*.
The 32 stale failures were almost entirely copy coupling — a redesign renamed `Done` to
`Log set`, uppercased `Back`, swapped `-` for `−`, and turned "Set 1 of 2" into a chip row,
and the suite went red without a single behaviour changing. Tap targets on the live-session
screen now carry stable keys (`log-set`, `skip-set`, `back-chip`, `pause-toggle`,
`set-chip-<n>-<state>`, `rest-±15`, `warmup-±15`, `goal-reps`, `goal-weight`). Also note
`tester.tap` does **not** fail when the target is below the fold — it warns and hits
nothing, and the test then fails somewhere unrelated; `live_session_page_test`'s `_tap`
helper scrolls first, and replaced 31 hand-patched `tester.drag(...)` workarounds.

---

### Update log (newest first — one line per session)
- 2026-09-11 — **Motivational workout reminders** (on `feature/reminders-sync`; Dart + l10n,
  no repo/rules change). A synced workout reminder can now be flipped to **motivational**: a
  nested "Motivational message" toggle on the edit sheet (shown only once "Sync with my plan"
  is on). In that mode the notification **names today's workout but swaps the exercise list for
  one line of encouragement** ("Arm Day · Don't skip leg day.") instead of the lift details.
  New local, offline copy in `reminders/domain/workout_motivations.dart` (EN + AR, index-aligned)
  + pure deterministic `pickWorkoutMotivation(seed, languageCode)`; the app root picks **one line
  per calendar day** (seeded so the choice is stable across a reschedule, keeping the dedupe that
  protects the platform channel) and hands it in via the new `ReminderContext.workoutMotivation`.
  `WorkoutSync` gains a persisted `motivational` flag (absent = off, unchanged behaviour). New
  `remindersMotivational`/`remindersMotivationalHint` l10n keys (en + ar). Tests: motivational
  occurrence cases, `WorkoutSync` motivational round-trip, and a `workout_motivations` suite —
  `flutter test test/reminders` green (37 → +6).
- 2026-09-11 — **Workout Analysis redesign + Progress retired** (on
  `feature/workout-analysis-redesign`, cut from `feature/ask-elicitation`; Dart/UI only, no
  engine/repo/functions change). The Analysis hub (`workout_analysis_page.dart`) is reorganised
  from verdict-grouped lists (going-well / getting-worse / stalled / all-exercises, where a lift
  appeared twice) into a slim summary (verdict · volume · PRs · focus-next) over a **searchable,
  muscle-category-grouped exercise browser** (`_ExerciseBrowser`, grouping on the engine's existing
  `ExercisePerformance.muscleGroup` — no engine change) → the unchanged per-exercise drill-down.
  The dashboard's bare top-right icon is now a labelled **"Analysis"** pill
  (new `TrainHeaderTextAction`) that opens the Analysis hub **directly**. The separate
  **`workout_progress_page.dart` landing was deleted** — its Plan/History/Splits links moved to
  an always-present "Go deeper" card on Analysis, and its overview stats already live on the
  dashboard tiles (so nothing was orphaned; the plan viewer `WorkoutPlanPage`, which only Progress
  reached, is now reached from that card). Colour carries **status only** on these screens:
  decorative green icon tiles are neutral ink, "focus next" is ember (the Now/Next colour). New
  `AppIcons.search`, `muscleGroupLabel` in `workout_labels.dart`, muscle/search l10n keys in both
  ARBs. Tests updated (Progress-nav tests repointed to Analysis, Progress-only tests removed) +
  search/grouping coverage added; **full suite green (1537)**. Deferred: a global light-base
  softening (whole-app palette, ADR-011) if light mode still reads harsh after the de-green.
- 2026-09-10 — **Ask elicitation — audit fixes F1 + F2** (on `feature/ask-elicitation`;
  Dart-only, no functions redeploy). F1: `AskController.submitInput` now fires body-data
  persistence with `unawaited(...)`, so an un-acked Firestore write can't block the coach's
  reply offline (matching the app's fire-and-forget capture convention). F2: new
  `DietRepository.fetchBodyProfile()` (one-shot read, impl in both repos + the test stub);
  `repository_body_data_writer` reads through it instead of the sync `currentBodyProfile`
  cache, so height is remembered even when Ask is reached without a Diet screen warming the
  cache. Both locked with regression tests. F3 (duplicate card on retry) left documented.
- 2026-09-10 — **Ask elicitation Phase 3 — the coach remembers what it asks for** (on
  `feature/ask-elicitation`; **not yet deployed**). A `request_input` field keyed `heightCm`
  or `weightKg` is now persisted to the user's own body data on submit, so the coach asks
  once and never again: `AskController._persistBodyData` → `BodyDataWriter`
  (`ai/data/repository_body_data_writer.dart`) writes height into the diet `BodyProfile`
  (merging, when one exists) and weight as a workout `BodyWeightEntry` weigh-in — the same
  user-owned writes the manual capture screens use, with range/typo guards. **Targets/goal
  are never written** (`body_profile.dart`'s rule stands). Direct write on submit, not
  propose→confirm — the user is entering their own data, so ADR-003's model-write gate
  doesn't apply. Best-effort: a failed save never blocks the reply. 461 node + 131 Ask
  flutter tests green.
- 2026-09-10 — **Ask elicitation Phase 2 — the coach can ask for missing data with a form**
  (on `feature/ask-elicitation`; **not yet deployed**). New `request_input` elicitation tool
  (`functions/ai/elicitations.js`) pauses the turn and appends an `input_request` card the
  client renders as a 1–4 field form (`input_request_card.dart`: number/text/choice fields
  with units); on submit a readable summary ("Height: 180 cm · Weight: 74 kg") is sent back
  as an ordinary next turn via `AskController.submitInput`. The turn loop needed no change —
  `persistElicitation` is generic over `tool.messageKind`. **Values are NOT persisted to the
  profile yet — that's Phase 3.** 461 node + 122 Ask flutter tests green.
- 2026-09-10 — **Ask elicitation Phase 1 — the coach can ask option-chip questions instead
  of guessing** (on `feature/ask-elicitation`, cut from `feature/theme-modes`; **not yet
  deployed** — prompt/tool changes need a functions deploy). New non-executing `ask_choice`
  tool (`functions/ai/elicitations.js`, `elicits: true`) pauses the turn and appends a
  `choice_request` card the client renders as tappable chips (`choice_chips.dart`); the
  pick returns as an ordinary next turn via `AskController.answerChoice` — no confirm/
  execute half and no pending-action doc (a question resolves by being answered). Turn-ender
  wiring + `awaiting_input` phase in `turn.js`, `persistElicitation` in `actions.js`,
  read-before-you-ask prompt rules in `prompt/sections/elicitation.js`. 453 node + 120
  Ask flutter tests green. Phases 2–3 (`request_input` form + profile persistence) still to
  come. See `lib/features/ai/FEATURE.md`.
- 2026-09-06 — **Media bytes are scoped by owner on disk.** `LocalMediaStore` wrote to a
  flat `media/{kind}/{id}.{ext}` shared across every account on the device. New imports
  use `media/{owner}/{kind}/{id}.{ext}`, with the owner sanitised to one safe path
  segment (a hostile value cannot escape the store, an empty one gets `_shared`). Reads
  are layout-agnostic, so the unscoped refs already sitting in Firestore keep resolving —
  no file is moved and no stored ref is rewritten, deliberately. 1176 dart tests green.
- 2026-09-06 — **Deleted photos no longer strand a Drive copy; Storage & Sync explains an
  account switch.** `deleteMedia` read the remote id only when a session was live, so
  deleting while the holding account was disconnected discarded the only pointer and left
  the file in the user's Drive forever (a privacy issue, since they deleted it). Added
  `MediaTombstone` + `users/{uid}/mediaTombstones` (rule + rules tests) and
  `sweepPendingRemoteDeletions()`, run on connect and at the head of `backupNow`. The
  Storage & Sync card now counts photos reachable only from another Google account and
  names both routes out. 1172 dart + 137 rules tests green.
- 2026-09-06 — **Only the owning account may declare a file id dead.** Follow-up to the
  deletion fix: it discarded a reference on ANY 404, which for a record with no recorded
  account (i.e. every record predating `driveAccountKey` — all existing data) destroyed
  the only pointer to a copy still sitting in the account the user had switched away
  from. Now a 404 is conclusive only when the id is attributed to the account that
  answered; otherwise the record keeps its id, drops to `failed` so local bytes
  re-upload, and reads `otherAccount`. 1166 dart tests green.
- 2026-09-06 — **A photo deleted from Drive no longer pulses forever.** `download`
  collapsed a hard 404 and a network blip into one null, so a deleted file read as
  `cloudOnly` ("on its way") indefinitely while its record still claimed `done`, which
  `pendingBackups` skipped — nothing could ever restore it. `download` now returns
  `RemoteFetch` (bytes/gone/unavailable); a confirmed 404/410 clears the reference and
  marks the record `failed` so a device holding the bytes re-uploads it. Transport
  errors and 403s are never treated as deletions. 1164 dart tests green.
- 2026-09-06 — **Drive account switch no longer strands photos.** `remoteId` had no
  companion account key, so after disconnecting Drive #1 and connecting Drive #2 every
  old file id was reissued against the wrong account (blank image, `cloudOnly` forever)
  and `pendingBackups` skipped them as `done` (Drive #2 never got the back catalogue —
  real loss on reinstall). Added `MediaObject.remoteAccountKey` + `driveAccountKey`
  (schema 2), moved the account check onto the `MediaBackupProvider` seam, made
  `pendingBackups` destination-relative, added the `files.create` fallback and the
  `otherAccount` read state. Additive lazy migration, no rules change. 1160 dart tests
  green.
- 2026-09-03 — **Fixed bogus per-exercise strength % (e.g. "+2750%").** Root cause:
  `classify` fell back to a rep-count "score" when a lift's early sessions had no
  logged weight, then divided a later estimated-1RM (kg) by it — mixing scales. Fix
  (Dart `workout_analytics.dart` + Node mirror): compare on ONE metric (e1RM for a
  loaded lift, reps for bodyweight); a loaded lift whose baseline window has no
  weight reads "building", not a ratio; and a change beyond ±`kMaxReliableStrengthChangePct`
  (100%) keeps its direction but withholds the number (null → status word only).
  New shared `strengthChange` golden vectors both suites run (incl. the exact bug
  case). 421 node + 1108 dart tests green. **Owner: deploy functions** (engine changed).
- 2026-09-03 — **AI coach wired to the drill-down + adherence.** Node mirror
  `functions/ai/exercise_analytics.js` (`analyzeExercise` + `analyzePlanAdherence`),
  pinned to Dart by new shared golden vectors both suites run. New
  `get_exercise_analysis` tool (one lift's full history/deltas/verdict/insight);
  `get_training_analysis` now carries `planAdherence`; `store.getActiveWorkoutPlan`
  mirrors the client's active-split resolution; TRAINING prompt says the deterministic
  verdict leads (don't recompute/overturn). 420 node tests + ESLint green; Dart parity
  groups green. **Owner: deploy functions.**
- 2026-09-03 — **Analysis → coaching drill-down.** New per-exercise engine
  `workout/domain/analytics/exercise_analysis.dart` (`analyzeExercise`: session history,
  session-to-session typed deltas, intensity-first verdict so 40×7 can beat 35×10, PR
  timeline, what-happened/why/do insight) + `plan_adherence.dart` (`analyzePlanAdherence`:
  skipped/stale planned movements) — both pure, additive, reusing the pinned hub
  primitives (its numbers untouched). New `exercise_analysis_page.dart` drill-down;
  `workout_analysis_page.dart` re-composed into tappable coaching sections; shared
  `progress_status_style.dart`. `test/workout/` green (427). Not yet fed to the AI coach
  (Dart-only for now) — clean follow-up.
- 2026-09-02 — **Workout analytics engine + AI training pipeline.** New centralized
  `workout/domain/analytics/workout_analytics.dart` (e1RM, history-derived PRs,
  thresholded per-exercise status, muscle rollup, working-volume trend, typed findings,
  `computeGoal` next step; warm-ups excluded) with a Node mirror (`functions/ai/workout_analytics.js`)
  pinned by shared golden vectors. AI now reads real per-set sessions (`store.listWorkoutSessions`,
  real `get_workouts`, new `get_training_analysis`) + a workout system-prompt block instead of the
  lossy flat log. `workout_analysis_page.dart` rebuilt as a 6-section engine view; Progress landing
  card + post-workout PR celebration share the engine. All gates green; **owner: deploy functions.**
- 2026-09-02 — **Save flow, button guards, Spotify auto-connect, Live Session polish.**
  Local-first persistence (`deferWrite` + `DeferredWriteReporter`) so Save never waits on
  a Firestore round trip; a shared `AsyncAction` guard with a `once` mode for
  commit-and-leave buttons; `MusicController.linked`/`reconnectIfLinked` with per-device
  consent so Spotify reattaches at launch, on resume and after a drop; the nav-island
  strip now shows every connection state and carries prev/play-pause/next; live-session
  header and captions sized for arm's length. Owner action: consider a screen-wake
  package for the live session (see Owner action items).
- 2026-08-30 — **Diet Coach Phase 8.1: the nutrition cross-check, and T12 closed by
  re-audit.** The audit's last open finding (T14) is done and the table is now clean:
  T1–T15 all closed. `domain/nutrition/plausibility.dart` reads a plan item against
  **itself** — does the stated calorie figure agree with the macros beside it, on the 4/4/9
  Atwater factors? No catalog, no network; it catches a model contradicting its own numbers
  ("600 kcal" beside macros worth 107). Absent macros are absent, not zero, so the check is
  asymmetric: with a macro missing the implied figure is a **floor**, so a too-low figure is
  still reported and a too-high one never is (the missing macro is exactly what explains
  it). Tolerance is the greater of 30 kcal and 20% — alcohol isn't Atwater, fibre doesn't
  burn at 4, and whole-gram rounding costs a few kcal — and half the tests assert the
  silence, because a flag the user learns to ignore is worse than no flag. Surfaced in the
  **plan editor**, which is the review gate a PDF import lands in, stating both figures
  rather than a verdict; it never blocks Save. Nothing is stored — the verdict is derivable,
  so there's no field to migrate or go stale. `firestore.rules` for `dietPlans` now bounds
  the document (name non-empty/≤500, `status` in the enum, `days` ≤31, `schemaVersion` ≥1)
  and says in a comment why per-item nutrition can't be checked there (rules can't walk a
  nested list) and where it lives instead. **T12 needed no fix**: the flag survives the
  import mapper, the Firestore round-trip and the editor's drafts, and the item sheet is
  add-only — a freshly typed item is genuinely user-stated. `flutter analyze` clean ·
  Flutter **896** · functions **325 pass** · functions lint clean. **The rules change rides
  the already-pending rules deploy** — worth a `--dry-run` first; this repo has no rules
  test harness.
- 2026-08-30 — **Diet Coach Phase 8: the trust stack reaches the screen.** The coaching
  engine is now rendered on the Diet screen, not just handed to the chat coach:
  `TodaysReadCard` shows the exact findings `coachingFindings` produces (same engine, same
  state, at most three), so the screen and the coach can't recommend different things from
  identical data — and the coaching works with no model call at all. Each finding carries a
  **Why** that resolves its `evidence` paths against the same state
  (`domain/coaching/evidence.dart`): *"Protein left — 100 g"*, *"Daily target — 2200 kcal"*.
  It only reads; an unknown path is dropped, never blank, and a test asserts every finding
  the engine can emit resolves at least one row. The hero's consumed figure now states its
  `ConsumedBasis` (`FROM TICKED MEALS, NOT WEIGHED`) — the coach was already forbidden to
  say "you ate" about ticked meals, and the screen was still printing the bare number. A
  calculated target explains itself (*82 kg · moderate · 2790 kcal maintenance*). The page
  builds **one** `DietState` per frame and shares it with the hero (which used to build its
  own partial one, null whenever targets were unset). And a reply the Phase 7 validator
  threw away now leaves the screen the moment the `done` event's `replaced` arrives, rather
  than sitting there until Firestore catches up. And a day with **no plan day** no longer
  collapses to the bare "No plan for today." line: the hero, the target row and the read
  measure the day, not the plan, so they survive a missing plan day (only Meals/Supplements
  end with it) — with neither a plan day nor a target there is no yardstick and the screen
  still says so. Held back on purpose: no read card when no
  target is set — the empty-state card already says it, with somewhere to tap.
  `flutter analyze` clean · Flutter **884** · functions **325 pass** · functions lint clean.
  **No deploy** — client-only. Detail: [DIET_COACH_AUDIT.md](DIET_COACH_AUDIT.md), which is
  now complete: Phases 0–8 landed, and what's left is food-catalog coverage, not
  architecture.
- 2026-08-30 — **Diet Coach Phase 7: the advice validator + safety intercept.** The last
  layer of the trust stack. After the model produces its reply, the gateway now runs
  `functions/ai/validator.js` against the diet state+findings it was handed (from
  `get_today`/`get_diet`). **Safety (T15):** a reply that *recommends* eating below the
  1,200 kcal floor is replaced with a message pointing at a doctor/dietitian — carefully
  distinguished from *warning* about a low number or pushing intake up. **Contradiction
  (T8):** every calorie figure the reply states about the user's day must trace to the
  state (consumed/remaining/target/a plan meal/a logged food) within tolerance; one that
  matches nothing, or a claim of eating when nothing's logged, or an "over/under" on an
  untracked macro, is rejected and the reply falls back to the findings' deterministic
  text — which is why rejecting is safe: there's always a correct answer to land on.
  Precision-first: hypotheticals and general-knowledge facts are excluded. Server-only (no
  Dart mirror — replies are only generated server-side). The outcome is logged to usage and
  the status becomes `validated-fallback`/`safety-intercept` on a substitution; streamed
  turns carry `replaced` on the done event (the persisted reply is the validated one).
  `flutter analyze` clean · Flutter **863** (unchanged — server-only) · functions **325
  pass** · functions lint clean. Detail: [DIET_COACH_AUDIT.md](DIET_COACH_AUDIT.md).
- 2026-08-30 — **Diet Coach Phase 6: the AI acts on food.** The coach gained three
  tools and can now log what the user ate. Reads: `resolve_food` (a food → its `foodId`,
  per-100g nutrition and measures, or `ambiguous`/`notFound`) and
  `calculate_meal_nutrition` (items → computed kcal/macros + a total, withheld until every
  item resolves). Write: `log_food`, a propose→confirm mutation whose nutrition is computed
  **server-side** in `verify` — the model names foods and amounts, never a calorie, and an
  item that's ambiguous, not found, or given an unconvertible unit is refused back to the
  model with the reason rather than guessed. All three share one path,
  `functions/nutrition/resolve.js` (the server mirror of `CompositeFoodResolver`: custom
  foods over USDA), so they can't disagree with each other or with the screen. A confirmed
  `log_food` writes the same `foodLogs` rows the log sheet writes (`origin: logged`,
  `estimated: false`, real `source`/`sourceRef`), snapshotted at log time; ids derive from
  the actionId so a double-confirm overwrites and a multi-item meal is one batch. The Ask
  card renders a green "Log food" receipt with the computed amounts. The prompt flips from
  "you can't look food up" to "you look it up with these tools, never from your own
  knowledge", keeping `log_food` distinct from `mark_meal_eaten`. Deliberately did NOT add
  `get_diet_state`/`get_diet_targets`/`get_diet_history` — `get_diet`/`get_today` already
  are the state, carry targets, and include a week of history.
  `flutter analyze` clean · Flutter **863 pass** · functions **305 pass** · functions lint
  clean · rules unchanged (no `firestore.rules` change). Detail:
  [DIET_COACH_AUDIT.md](DIET_COACH_AUDIT.md).
- 2026-08-30 — **Diet Coach Phase 5: the coaching rules engine.** What the coach *decides*
  to say now lives in code, not in the prompt. `CoachingFinding` types the six registers
  (observation · analysis · recommendation · warning · encouragement · clarification), each
  with a severity, a deterministic sentence that is correct on its own, and the `DietState`
  fields it rests on — so "why is this being said?" is answerable, and Phase 7's validator
  has something correct to fall back to. `coachingFindings` is pure and capped at **three**
  (a coach who lists six has said nothing). The rules only fire when they have something
  real to say, and the tests assert the silences: a met protein target yields encouragement
  and no shortfall; a protein gap at 09:00 stays quiet; the same gap at 19:00 with the
  budget spent becomes the brief's worked example. `localHour` is a rules input, not a state
  field — unknown hour means time-sensitive rules don't fire. Mirrored in
  `functions/diet/rules.js` and pinned by `test/fixtures/coaching_vectors.json` (11 cases,
  both suites). The diet tool payload now carries `findings`, and the prompt says: lead with
  them, never contradict one, never invent a recommendation they don't contain, don't soften
  a warning. One ranking fix along the way — provenance clarifications were being crowded
  out of the cap by plain readouts and are now `notable`.
  `flutter analyze` clean · Flutter **860 pass** · functions **275 pass** · functions lint
  clean · rules 99 pass. Detail: [DIET_COACH_AUDIT.md](DIET_COACH_AUDIT.md).
- 2026-08-30 — **Diet Coach Phase 4: one `DietState`, provably identical on both sides.**
  The Diet screen, Today's glance and the coach were each deriving "how am I doing" from
  raw plan/log reads. Now there is one object — goal · targets · consumed (with its
  `ConsumedBasis`) · remaining · meals · a week of history · and a `DietQuality` block
  naming what the app does **not** know — built by one pure function, `buildDietState`,
  which is where the ordering rules now live (supplements never count; the log beats the
  plan; a missing target is null, not zero; an empty log is "nothing recorded", not a
  measured zero). `functions/diet/state.js` mirrors it, and
  `test/fixtures/diet_state_vectors.json` (10 state cases + **28 day resolutions** across
  all seven weekdays) is run by **both** suites — so `dayForDate` and `resolveDietDay` are
  now provably the same rule, closing the half of T13 that Phase 2 left open. The diet tool
  payload **is** the state, and the prompt reads its `quality` flags. Phase 1's
  `TargetProgress` was the stopgap this replaces and is **deleted** — keeping both would
  have been the two-implementations problem in miniature. `get_today` also gained a week of
  history in a single range query (no composite index, no seven round-trips).
  `flutter analyze` clean · Flutter **846 pass** · functions **259 pass** · functions lint
  clean · rules **99 pass**. Detail: [DIET_COACH_AUDIT.md](DIET_COACH_AUDIT.md).
- 2026-08-30 — **Diet Coach Phase 3: a real food log.** Consumption was a per-meal
  checkbox: ticking a meal credited its *planned* macros whether you ate half of it or
  swapped the rice, so "consumed" was an assumption wearing a number's clothes. Now
  `FoodLogEntry` (at `foodLogs/`, with its own rule) records what was actually eaten —
  food reference, quantity, resolved mass, and the nutrition computed at log time and
  **stored**, so rebuilding the catalog can't silently rewrite a past day. `origin`
  separates *logged by the user* from *materialised from a ticked plan meal*, and that
  distinction now travels all the way to the prompt: the coach must read `consumed.basis`
  before saying "you ate" — and an empty log means nothing was **recorded**, not that
  nothing was eaten. Ticking a meal is unchanged for the user but writes both
  `dietEntries` (still the tick state) and one log entry per item; un-ticking removes
  exactly those. `CustomFood` + `CompositeFoodResolver` close the USDA coverage gap: the
  logging sheet's not-found state offers to define the food instead of approximating it.
  The sheet only offers measures the source recorded for that exact food and refuses the
  rest with a reason. Also added `test/support/diet_repository_stub.dart` so the next
  repository addition doesn't break every hand-written fake.
  `flutter analyze` clean · Flutter **840 pass** · functions **251 pass** · functions lint
  clean · rules **99 pass**. Detail: [DIET_COACH_AUDIT.md](DIET_COACH_AUDIT.md).
- 2026-08-30 — **Diet Coach Phase 2: the nutrition catalog (the missing dependency).**
  ZIVO had no way to know what any food was worth except asking a model. It now ships
  **7,308 foods (1.0 MB)** in `assets/nutrition/foods.json`, built by
  `scripts/nutrition/build_food_db.js` from USDA FoodData Central's Foundation Foods +
  SR Legacy exports (public domain). Every row carries its real `fdcId`; nothing in the
  catalog is hand-written or model-generated — that was the whole point, and a
  hand-authored catalog would have reproduced the original bug one layer down.
  New domain: `FoodReference`/`FoodPreparation`/`NutritionSource`, the sealed
  `FoodMatch` (**resolved / ambiguous / not-found**, so uncertainty can't be skipped),
  `FoodResolver`, and `nutritionFor` — the only path from a food + an amount to
  calories. Raw vs cooked is first-class (raw rice 365 kcal/100g vs cooked 130), and a
  query matching both becomes a **question**; volumes are refused unless the source
  recorded that measure for that food (no assumed densities). Mirrored server-side in
  `functions/nutrition/food_db.js`, with the catalog written to both trees and
  `test/fixtures/nutrition_vectors.json` run by **both** suites plus a checksum — so the
  app and the coach cannot drift into different numbers. Wired as `AppScope.foods`
  (lazily parsed); the screens that use it are Phase 3.
  `flutter analyze` clean · Flutter **816 pass** · functions **245 pass** ·
  functions lint clean · rules 89 pass. Full detail:
  [DIET_COACH_AUDIT.md](DIET_COACH_AUDIT.md).
- 2026-08-30 — **Diet Coach Phase 1: goal + targets, the missing spine.** The coach could
  describe a plan but had no idea what it was *for*, which made every recommendation generic
  by construction. Now: `DietGoal` + `NutritionTargets` (kcal + optional macros, with a
  `TargetSource` recording whether a person typed it, a formula proposed it, or it was adopted
  from the plan), stored at `dietTargets/current` with its own rule; a target-setting screen
  with a pure on-device Mifflin-St Jeor calculator that **fills the fields as a proposal and
  shows its working** rather than saving anything; and a deterministic 1200 kcal safety floor
  that warns instead of clamping. **Unset stays a real state** — no default, nothing
  auto-derived: the Diet hero then counts down the plan under the label `KCAL LEFT OF PLAN`,
  Today's glance says "of plan", and the coach is told `targets: null`. With a target set the
  hero counts down *that* (`KCAL OVER` when past it — never clamped), macro bars use the
  user's own macro targets, and the header labels both figures
  (`TARGET 2200 KCAL · PLANNED ~1270 KCAL`). Server-side, `get_diet`/`get_today` now carry
  `targets` and a computed `remaining` (null per macro where no target was set), and the prompt
  separates the user's objective from a plan day's sum and states that `remaining` comes from
  **ticked meals, not a food log**. Fixed in passing: `_PlanBody` was re-creating the
  consumption stream on every rebuild.
  `flutter analyze` clean · Flutter **796 pass** · functions **238 pass** · rules **89 pass**.
  **Still needs the same deploy** — see the owner action items above.
- 2026-08-30 — **Diet Coach trust audit + Phase 0.** Audited the whole diet/AI path against
  one question: *where does each number come from?* Answer: every calorie in ZIVO is
  model-generated (`diet_import.js` makes calories/macros **required** schema fields so the
  model fills them), there is no nutrition database, no goal, no target, no real food log,
  and nothing validated the coach's output. Full findings + the phased plan:
  [DIET_COACH_AUDIT.md](DIET_COACH_AUDIT.md) — findings are id'd `T1`…`T15` and referenced
  from the phases, so keep the ids stable.
  **Phase 0 landed** (labelling + dates + verified ids; no new deps, no migration): the turn
  now carries a `CONTEXT` block with the user's local date (the model previously had **no
  way to know what day it was**); `dates.js` resolves every day key/range in the user's
  timezone from a `utcOffsetMinutes` the client sends, fixing the UTC-vs-device split that
  fed the coach yesterday's diet entries for the first hours of every local day; the prompt's
  estimation licence is replaced by a `NUMBERS` rule (no figure that didn't come from a tool
  result, and it says outright there is no food database); mutating tools gained an async
  `verify` hook and `mark_meal_eaten` now proves its meal id against the real plan at propose
  **and** confirm time (a hallucinated id used to write an orphan `dietEntries` doc); the
  four tools for deleted features are gone; `get_today` puts diet before workouts so
  truncation can't eat it; and `estimated` became load-bearing — carried into the AI payloads
  and aggregated into a "~" on the Diet hero (`EST. KCAL LEFT`), macro bars, meal rows,
  Today's glance and the Hub tile. `dietEntries` rules tightened.
  `flutter analyze` clean · Flutter **765 pass** · functions **231 pass** · rules **81 pass**.
  **Needs a deploy** — see the owner action items above.
- 2026-08-29 — **App-wide scrolling pass + the Spotify mark (owner report).** The scroll
  complaint ("gets stuck, feels restricted, indicator in the wrong place") was three
  separate causes, all now fixed at a seam rather than per page.
  **(1) The bottom of a pushed page had no owner.** Every screen guessed its own scroll
  clearance — 6, 8, 20, 28, 40, 44, 48, 100, 110, 120 — and none of them included
  `viewPadding.bottom`, so the small guesses put the last row under the home indicator and
  the large ones (on screens with no FAB to clear) left a dead band of empty scroll extent
  below the content, which is what read as the scroll position being wrong. New
  **`TrainBottomInset`** in `train_surfaces.dart` — the pushed-page twin of
  `BottomChrome` — is provided by `TrainScreen`, derived from the device inset plus
  whether the screen has a FAB, and now consumed by all 14 scrolling pages
  (`TrainBottomInset.forScaffold` covers the three still on a plain `Scaffold`). A page
  that docks its own action bar (plan/capture editors) correctly keeps its tight padding.
  **(2) Today's viewport was short by the status-bar inset** — it sat in a `SizedBox`
  *outside* the `Expanded`, as a fixed dead band. Moved into the list's own top padding,
  so the viewport is full height and the inset scrolls away.
  **(3) Ask's auto-follow fought itself.** The per-token pin used the 220ms eased
  `animateTo`, restarted every frame; each restart began a *driven* scroll, which reports
  a non-drag scroll start, cleared `_userDragging`, and let the metrics-notification
  `jumpTo` cut the tween off mid-flight — the two then fought for the position every
  frame while ZIVO replied. Streaming now pins instantly, the eased scroll is kept for
  the settled case, and both paths refuse to pin unless the list is at rest
  (`_restingAtPinnableOffset`), which also stops a `jumpTo` cancelling a rubber-band
  settle. Ask's empty state also stretched to `size.height * 0.6` — a fraction of the
  *screen*, ignoring header, composer and keyboard — now `LayoutBuilder`-derived from the
  real viewport.
  **Consistency:** four scroll views restated `physics:` and disagreed (a bare
  `BouncingScrollPhysics()` silently drops the `AlwaysScrollable` parent, so those screens
  stopped bouncing whenever content fit). Removed; everything inherits
  `ZivoScrollBehavior`, which now documents the rule. The music player keeps its explicit
  physics **on purpose** — its pull-down-to-dismiss is built on overscroll and must not
  depend on the ambient host (its widget test proves it).
  **Spotify:** the Settings connection card led with a generic `EqualizerGlyph`; it now
  carries the real `assets/spotify/spotify-icon.png`, the same mark the now-playing strip
  and player screen already use.
  `flutter analyze` clean. Suite **752 passed / 3 failed — byte-identical to the
  `version-1` baseline**, i.e. no regressions; those 3 (`today_dashboard_widget_test`)
  were already red at HEAD and are still owner-eye items below.
- 2026-08-29 — **Live-session + music-strip pass (owner list).** Fixed the real bug in it:
  the rest phase's eyebrow pill wore a **pause glyph and did nothing** — it sat inside the
  phase's `IgnorePointer`'d region, so the only working pause was the header toggle, which
  doesn't read as a button. Both countdown phases now pause from the pill, the ring, or the
  header, and while paused the dimmed phase itself resumes (`paused-resume-overlay`).
  **Warm-up was rebuilt on the rest layout** (eyebrow → ring → what's-coming card → music →
  ±15s → skip; ember instead of green) — it was the only screen still speaking a different
  dialect. The **rest numeral is genuinely centred** now on both axes: it was right-aligned
  in a slot reserved for "9:59" (so every sub-minute rest drew a character-width right of
  centre) and shared a Column with the caption (which pushed it above centre); a mirrored
  invisible spacer and a fractionally-offset caption fix each, with a geometry test.
  **`SpotifyStrip` gained the album-art tile + Spotify mark** — reversing the handoff's
  no-artwork rule at the owner's request — plus a track-change transition (artwork/text
  spring-swap + a bloom of the incoming track's colour) and an `accent` its host feeds it,
  so the transport controls follow the song. `SessionAmbience` now publishes a second,
  **foreground-normalised** accent (`vividOf`) for marks drawn ON the ground, and the rest/
  warm-up ring takes the song's colour outright — blending it with the phase hue walked
  through grey and rendered tan. Goal card reads as **one expression, `9 REPS × 30 KG`,
  with the volume under it** instead of two numbers at opposite ends. Back chip moved
  top-**left**; a hard 18px gap keeps the up-next card off the music strip when the
  balancing Spacer collapses. Then a second owner round on the logging screen: the goal
  card's numerals **roll** to their new value instead of snapping (`_RollingNumber`), and
  the card now holds **one height for a given set whatever you type** — both the
  comparison chip and the volume line used to appear only once you'd moved the weight, so
  a +2.5 grew the card and shunted everything under it (the chip says "matching your
  previous set" rather than vanishing; the volume line is a reserved 14px). The commit row
  **floats over** the scroll instead of splitting the space with it, so "Log set" is never
  below the fold and content dissolves into it (`_FadeOutBottom`) rather than being sliced
  at a hard seam; all three phases share one scroll shell (`PhaseScroll`) with
  always-scrollable physics and the header's own 22pt inset. Note `AnimatedSize` is
  **unusable** in these phases — it reports one intrinsic height and lays out another,
  which pins the `IntrinsicHeight` column short and overflows it. The rest numeral was
  also still crossing the ring's stroke; 74/26 → 64/17 with the hundredths overhanging at
  zero layout width clears the inner edge at the widest value it can show. Verified on an
  iPhone 17 simulator against a temporary harness that served real artwork bytes.
  753 tests + 4 new ones green, analyze clean.

  > **Known-failing, not from this work:** `today_dashboard_widget_test.dart`'s "a
  > brand-new user sees neither momentum nor insights" fails whenever the suite runs after
  > 19:00 — `today_pulse.dart:207` fires its evening diet nudge off the real clock and the
  > test doesn't inject one (line 246 has the same shape at `hour >= 16`). Reproduces on a
  > clean tree.
- 2026-08-29 — **Owner UI feedback round.** Fixed a **regression I shipped in the polish
  pass**: Momentum's low-data row overflowed by 20px on a real phone (the left caption I
  added pushed the pair past the edge — both captions are `Flexible` now, copy shortened to
  "NO STREAK YET", covered by a narrow-viewport regression test). Storage & Sync's toggle
  rows truncated ("Upload to Dr…") because they rendered an On/Off label *and* a switch —
  the switch is the value, so the label went; convention documented on `SettingsRow.value`.
  Auth fields 64→54pt with a smaller icon, and the password checklist lost its card chrome
  (a bordered box between two bordered inputs read as a third field). Hub module tiles got
  a bigger glyph on a lighter plate (`TrainIconTile` now exposes `fillAlpha`/`borderAlpha`
  — the defaults are tuned for a saturated accent and a near-white neutral needs different
  weighting); the tiles stay neutral, so ADR-006's hue rule is untouched. New **Connected**
  band on the Hub fills the dead mid-band with Spotify + Google Drive live state and their
  brand marks, each a shortcut into the screen that owns the setting.
- 2026-08-29 — **Removed the category colour picker, and the v2 palette is now fully
  deleted.** Categories are a label + a stroked icon; `CategoryHue`, the sheet's COLOR
  section, the `hue` Firestore field + rules clause, and `category_hue_colors.dart` are
  gone. Rationale: H3 gave every category a distinct glyph and C2 made every money surface
  amber, so the chosen swatch had nowhere to render — a picker that sets an invisible
  value is worse than no picker. Folded into the already-pending rules deploy rather than
  needing a second one. Old documents keep a harmless `hue` field; nothing reads it.
  With that file gone, `app_colors.dart` had no importers either — **`AppColors` and
  `AppShadows` are both deleted; `TrainColors` is the only palette in the app.** Also
  deleted the dead `ZCard`. Rules suite 76 green against the emulator.
- 2026-08-29 — **Redressed the remaining v2 flows — the app is on one palette now.** ~44
  files / ~430 references: the whole auth flow (which also closes the audit's warm→cool
  jump on sign-in), the diet plan editor + PDF import + meal detail + grocery list,
  storage & sync, moment capture + photo viewer, quick capture, the workout sheets, the
  Today glances, and the shared `core/widgets` chrome. Highest leverage were
  `app_typography.dart` and `app_theme.dart`: the default ink and scaffold background were
  warm, so every screen inherited a warm cast unless it overrode them. `AppShadows` is
  deleted outright (orphaned). `ZHue.flare` removed — on `TrainColors` it resolved to the
  same ember as `ZHue.ember`, and two names for one colour is what C2 rules out.
  **Correction:** C2's Expenses *chip* change never actually applied (a `dart format`
  line-wrap defeated the string match and the edit was reported as done); the chips are
  amber now for real. Bars and spines were correct.
- 2026-08-29 — **Design audit C4 + C3 — the last two findings.** C4: music's own accent no
  longer contradicts itself — the player's play/pause disc and the scrubber's fallback
  accent are green like the rest of the feature (equalizer, strips, Spotify wordmark, and
  the now-playing lozenge's own transport), with a dark glyph on the filled green the way
  the other green primaries do it. The orb's ember progress ring, C4's other half, went
  with the orb in H1. C3: the banned `AppShadows.card` is gone from every surface the audit
  named — Today's cards and Ask's proposal card went in C1, and expense capture (page +
  keypad) is redressed here, which also clears the mixed palette H3 left on that screen.
  **Deliberately not touched:** `storage_sync_page` and `meal_detail_page` still carry it,
  but they are pure-v2 pages where shadows *are* the elevation model — stripping the shadow
  without redressing the palette would make them less coherent, not more. They belong to
  the un-redressed-flows list above, not to C3.
- 2026-08-29 — **Design audit polish pass (P1–P7), all seven.** P1 capture FAB now wears the
  chrome's raised material + top-lit ramp (deliberately *not* ember — Today's ember is
  Start Workout's, and C2 makes ember the single committing action). P2 one date-caption
  formatter: `formatTodayDate` retired, Hub joined Today on `formatTodayShort` (note:
  Moments never had a date caption, so the audit's "Hub and Moments" was half right).
  P3 the skip control is now the secondary in *all three* live-session phases, with the
  phase hue owning the ring only — it was an ember primary on warm-up and a green primary
  on rest. P4 no-artwork draws a bare stroked glyph over the player's colour wash instead
  of a full opaque plate. P5 designed low-data states: Momentum's left slot always renders
  ("STREAK STARTS AT 2 DAYS" dimmed), the diet ring's track reads at 0%, and a sparse
  Moments grid fills its first row with dashed add-tiles. P6 Volume ring green (progress,
  not a committing action). P7 the day's **planned** kcal is always shown and labelled —
  the mismatch the audit saw was the plan's own *name* ("Balanced — 2200 kcal") versus a
  day summing to 1270, and the old code hid the real figure whenever the name had one.
- 2026-08-29 — **Design audit C2 — held the hue rule strictly.** 30-odd decorative accents
  moved onto the hue that actually owns their meaning (see the standing decision above).
  Added `TrainColors.neutralMark` for tiles that differentiate by icon.
  **Consequence, now resolved (2026-08-28):** the colour picker is gone. With Expenses
  all-amber a category's `CategoryHue` rendered nowhere, so the picker was setting a value
  the app never showed. `CategoryHue`, the picker's COLOR section, the `hue` Firestore
  field and its rules clause, and `category_hue_colors.dart` are all deleted.
- 2026-08-29 — **Design audit C1 — one dark system for the chrome.** The nav island, the
  Ask composer/header/quick-log sheet, the whole Ask page, Today's empty + insight cards,
  and the mixed-palette handoff screens (live session, workout hub, You, Diet, music
  scrubber, plan page, Settings) are off the warm v2 palette and on `TrainColors`. The two
  violets are one: `AppColors.iris #6E5BFF` is gone from every chrome surface, leaving the
  `violet`/`violetGlyph` pair. `TrainColors` gained the tokens the handoff palette lacked
  for floating chrome — `raised`, `raisedStrong`, `hairlineStrong`, `tabInactive`, and
  `ember/violet/green/amberWash`. `flare` (the v2 red) maps to **ember** throughout: the
  handoff has four hues and deliberately no fifth red, and ember already owns "live/now +
  the committing action + worth noticing". Today's empty cards also lost their banned
  drop-shadow and their glowing gradient icon-chips (now `TrainIconTile`), which finishes
  C3 for Today and Ask.
- 2026-08-29 — **Fixed the 32 long-standing red tests; suite is green (749) and
  `flutter analyze` is clean.** They were stale finders, not regressions: every control
  STATE.md worried had been "renamed *or dropped*" still exists, verified against the
  source. Root causes were six renames (`Done`→`Log set`, `Back`→`BACK`, `-15s`→`−15s`,
  "Set 1 of 2"→a chip row, Pause/Resume→one keyed toggle, the goal hero split into
  `goal-reps`/`goal-weight`), plus a silent-tap trap: 31 `tester.drag(...)` workarounds
  were papering over `tester.tap` missing below-the-fold targets. Fixed by adding stable
  keys to the live-session controls and a `_tap` helper that scrolls first. Two real
  design changes the tests had to be rewritten for, not worked around: the pulse card's
  third ring is Volume (diet moved to its own glance row), and the goal caption now leads
  with the **load** delta ("↑ 5 KG VS LAST") instead of a "Progressing +17%" badge.
  Verified the repaired suite still has teeth by mutation-testing it (`_onBack` no-op → 4
  failures incl. Ziad's-incident test; corrupted goal hero → happy path fails).
- 2026-08-28 — **Design audit H3.** Retired emoji from expense categories (identity §4/§8).
  `ExpenseCategory.emoji` became `icon: CategoryIcon` — a semantic enum persisted as
  `iconId`, resolved to a stroked Lucide glyph by the new
  `expenses/presentation/widgets/category_icons.dart` via `AppIcons` (nothing but
  `AppIcons` imports the icon package). Chips are now hue-tinted stroked icons, the
  24-emoji picker became a 24-icon picker, and the Add chip's stray Material
  `Icons.add_rounded` went to Lucide. Pre-migration documents are still read correctly via
  `categoryIconFromLegacyEmoji`. `firestore.rules` now validates `iconId` — **needs a
  rules deploy** (owner action above). Added the `expenseCategories` rules coverage that
  was missing entirely (rules suite 71 → 76 green) plus domain tests for both fallbacks.
  Verified end-to-end on iPhone 17: created a category and saw it render with its glyph.
- 2026-08-28 — **Design audit H1 + H2.** Rebuilt the bottom as ONE height-aware object:
  music is now a slim strip fused inside the nav island (`NowPlayingLozenge` in the new
  `ZivoBottomBar.fused` slot), and the new `BottomChrome` inherited widget publishes the
  island+strip height so Today/Hub/You/Ask all derive their clearance from one value.
  Retired `now_playing_bar.dart` and `now_playing_orb.dart` — the orb only existed to
  shrink a too-tall bar and it docked on top of the Ask composer. Ask drops from three
  bottom bars to two; the Hub's last row and You's sign-in card now clear the strip (the
  Hub reserved nothing for music before). Also guarded the splash screen's post-frame
  callback with `mounted` (it threw on every cold start). Verified on iPhone 17 with the
  seeded harness. Suite unchanged: same 32 pre-existing failures, name-for-name.
- 2026-08-28 — Redressed the plan editor, PDF import and workout capture via the shared
  capture chrome; commit actions are ember now, not green. Still 32 failing (unchanged).
- 2026-08-28 — Carried the handoff into the workout drill-downs (Progress, the four stat
  pages, bodyweight/day/session details, history, analysis, splits) behind two shared
  seams. No new test failures — still the same 33 that fail on `version-1` untouched.
- 2026-08-28 — Built the seven remaining design-handoff screens (Workout hub, You,
  Settings, Diet, Expenses, Moments, Ask) plus the Hub tab, on a new shared
  `train_surfaces.dart` primitive set. Fixed a real overflow on the Rest ring's timer
  (now scales down instead of overflowing, which also covers Dynamic Type) and three
  pre-existing test failures (`auth_gate` × 2, `profile_page` bio). **Still red:** ~40
  tests in `live_session_page_test`, `today_page_test`, `today_dashboard_widget_test`,
  `live_session_keyboard_overflow_test`, `workout_plan_page_test` — all stale finders
  left behind by the EARLIER Today/live-session redesign (commit `c191e33`), not by
  this pass. Several look for controls that may have been renamed *or dropped*
  ('Done', 'Back', 'Pause', 'Set 1 of 2'), so they need the owner's eye before the
  assertions are rewritten.
- 2026-08-27 — Hardened + completed the auth system (branch `claude/auth-system-review-1c7a20`):
  forgot-password (OTP), change password, account deletion; fixed the OTP hourly-cap bypass by
  moving throttle accounting into a shared, unit-tested `functions/auth/otp.js`; handled the
  already-verified send path; added `passwordResetOtps` lockdown (rule + test) and Flutter
  widget tests for the new flows. `flutter analyze` clean; Flutter suite green (2 pre-existing
  failures unrelated to auth: `profile_page` bio + `today_dashboard` brand-new-user); functions
  `node --test` 208 green; rules suite 71 green. App Check intentionally left out for now.
- 2026-08-27 — Ask polish + AI edit/delete: fixed the Momentum week-bars 4px bottom overflow
  (`today_pulse_card.dart`); reworked the Ask composer into a floating frosted island that the
  chat scrolls under, bumped ZIVO's reply font, and redesigned the confirmation card + made its
  resolved state a keep-the-details history receipt (`ask_page.dart`, `voice_composer.dart`);
  added confirm-gated **edit_expense/delete_expense** AI tools + `get_expenses` id exposure
  (ADR-005 — `functions/ai/*`, tests green). **Backend not yet deployed** (owner action above).
- 2026-08-27 — Added the agent-neutral context system (AGENTS.md router + CLAUDE.md adapter,
  PRODUCT.md positioning, this file, per-feature FEATURE.md maps, ADR-004); repositioned as an
  AI gym tracker; de-stated the reference docs; added the STATE.md freshness pre-commit hook
  (`make hooks`); cleaned up debug-log / Firebase-cache noise.
