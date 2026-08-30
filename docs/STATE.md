# STATE — where ZIVO is right now

> **The single source of truth for "current state."** Small on purpose. Read it every
> session; update it when you finish a task. For *what ZIVO is + what makes it different*
> see [`PRODUCT.md`](PRODUCT.md); for *how the code is organized* see
> [`/AGENTS.md`](../AGENTS.md) and each feature's `FEATURE.md`; for *why* decisions were
> made, see [`DECISIONS/`](DECISIONS). The **code is the ultimate source of truth** — if
> this file disagrees with the code, fix this file.

**Last updated:** 2026-08-30 · **Active branch:** `version-1`
(`version-1` is 51 commits ahead of `main` — worth a merge).

---

## Positioning (current)

**AI-powered gym / training tracker** — built around an AI coach that knows your numbers,
not a log with a chatbot bolted on. Full positioning + differentiation: [`PRODUCT.md`](PRODUCT.md).

## The app in one paragraph (current)

Firebase-backed Flutter app (`USE_FIRESTORE` defaults **true**; in-memory repos are the
offline/test fallback). **Dark theme only** (`AppTheme.dark`). Shell is a 4-tab
`IndexedStack`: **Today · Hub · Ask · You** with a floating "island" bottom bar and a
center capture FAB. Sign-in gate is [`AuthGate`](../lib/features/auth/presentation/auth_gate.dart).
Live feature set: **workout, diet, expenses, moments, ai (Ask), music (Spotify companion),
auth/profile, home/Today, hub, capture, device (steps)**.

## Scope (standing decisions)

- **In scope:** fitness-first personal OS — workout · diet · expenses · moments · Ask AI ·
  music companion. See [ADR-004](DECISIONS/ADR-004-scope-specialization.md).
- **Removed for good (do not resurrect without the owner asking):** Schedule, Tasks,
  University, Notes (removed 2026-08-24).
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
    `dietPlans` document bounds to the same rules file. Command:
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
  the (now unauthenticated) reset endpoint and account creation.

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
  at a hard seam; all three phases share one scroll shell (`_phaseScroll`) with
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
