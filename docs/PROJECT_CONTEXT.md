# ZIVO — Project Context

> **Purpose of this file.** A single, canonical, self-contained snapshot so a new
> Claude session (or developer) can understand ZIVO without replaying its history.
> **The codebase is the source of truth.** Where this file and `docs/PLAN.md`
> disagree, the code wins — `PLAN.md` is the *aspirational* architecture; this file
> describes what is *actually built today*.
>
> **Last verified against the codebase:** 2026-08-19 (active development moved to the Workout/Diet
> overhaul on `feature/workout-diet-v2` — the AI streaming work described later in this handoff
> (Phase 3.5, `feature/ai-streaming-ux`) is **paused, not abandoned**; M9 AI V2 remains the last
> milestone once this track wraps. Firestore persistence, Authentication, and University are merged
> into `main`).
> **Last updated:** 2026-08-19 — active branch `claude/media-storage-architecture-95c0a4`: media
> storage rework **Phase 1 (local-first pipeline) + Phase 2 (Google Drive) code done & committed**;
> Phase 2 now pending only the owner's GCP setup + an on-device OAuth check. See the **Active** entry
> in Current Handoff. Prior AI-streaming context below was last verified 2026-08-17.
>
> **Last verified against the codebase:** 2026-08-17 (Phase 3.5 AI streaming **deployed**; the
> `add task` propose→confirm→execute flow **verified on-device**; the empty-collection infinite
> spinner **fixed** (`3635a60`, 256 tests); **M7 Performance signed off** → M9 AI V2 is the last
> milestone; App Check **still not enforced** (M9 Phase 4). On `feature/ai-streaming-ux`; Firestore
> persistence, Authentication, and University are merged into `main`).

---

## Current Handoff

> Cross-account handoff snapshot. A new session MUST read this, then inspect the actual
> git state / diff, recover the exact state, and continue from **Exact next action** —
> without redoing completed work. Active development is on `feature/workout-diet-v2`.

### Workout/Diet overhaul — CURRENT

- **Status (as of 2026-08-20):** `feature/workout-diet-v2`, HEAD `6f78302`, working tree **CLEAN**
  (all committed). Since the last handoff snapshot (`3b39f43`, then an uncommitted Home/Workout
  sync fix), the branch landed — in order — `9dfe432` (progressive-overload analysis page),
  `245a051` (first-class splits data foundation: multi-split repo + migration), `e4c7601` (pinned
  the exercise-identity invariant + `splitId` alias), `9253b2a` (split management: create/switch/
  edit/delete), `dff3c4d` (scoped analysis + history to the active split), `33d0630` (AI PDF
  import — extractor + review UI, **Phase 6**), `a9d3f5b` + `76c9fb0` (two code-review passes over
  Phases 0–6), and `6f78302` (a further Phase 6 hardening pass: a reversed-rep-range crash fix +
  `normalize()` numeric bounds). The Home/Workout sync fix from the prior handoff (deleting
  `TrainingCard`/`training_builder.dart`, `AliveColorDrift` made continuous) is folded into this
  history and done.
- **Phase 6 (AI PDF import) is BUILT + TESTED + DEPLOYED (2026-08-20).** `aiImportWorkoutPlan` is
  live (v2 callable, us-central1) in `zivo-63f15`, deployed via
  `firebase deploy --only functions:aiImportWorkoutPlan` after a full green verification pass
  (551 Flutter / 52 Node tests, analyze + eslint clean); it reuses the existing `ANTHROPIC_API_KEY`
  secret already bound to `aiChat`. **Phase 7 (verify + handoff) is done.** The ONLY step still
  open is the real-PDF-in-app end-to-end (import → review → confirm → see the new split) — needs
  the running app + a real file, so it's the owner's manual verify.
- **Verification bar:** `flutter analyze` clean; `flutter test` **551 passing**; functions
  `node --test` **52 passing**; eslint clean.
- **Do not redo / do not undo (compressed):**
  - Don't re-derive the progression-analysis page, the first-class splits data foundation +
    migration, the exercise-identity invariant/`splitId` alias, split management (create/switch/
    edit/delete), or active-split scoping for analysis/history — all built, tested, committed.
  - Don't re-derive the Phase 6 AI PDF import pipeline (server `aiImportWorkoutPlan` callable,
    client import→review→save flow) or its hardening pass (the reversed-range fix in
    `workoutPlanFromImport`, `normalize()`'s `MAX_SETS`/non-negative bounds in
    `functions/ai/workout_import.js`).
  - The splits migration's "oldest vs newest active split on a tie" fallback resolves to
    oldest-by-`createdAt` — confirmed intentional, matches `deleteSplit()`'s own re-pointing
    convention, not a bug; don't flip it.
  - `WorkoutImportResult`/`ImportedDay`/`ImportedExercise` live in `lib/features/workout/domain/`
    (moved off `lib/features/ai/domain/`) — don't move them back.
  - Settled, deliberately-not-fixed (don't re-flag as bugs without surfacing first): a collapsed
    day hiding its notes is Phase 1's intentional design, not a regression; the AI Cloud Function
    callables' auth-boilerplate duplication and `analyzeDayProgress()`'s lack of memoization are
    both real but deliberately deferred at this app's personal scale.
  - From the earlier Home-card slice: don't reintroduce `TrainingCard`/`training_builder.dart`/
    `todaysWorkout()` on Home (Home reads the same `watchActivePlan()` → `plan.nextDay` source as
    the Workout page, guaranteed in sync); don't gate `AliveColorDrift` back to active-only — it's
    deliberately continuous.
  - **Shared working directory caution:** avoid `git checkout`/branch switches on this repo while
    another session has uncommitted changes in flight; stage files by name, never
    `git add -A`/`.`.
- **Exact next action:** the milestone is code-complete, verified, and deployed. The ONLY step
  left is the owner's manual **real-PDF-in-app end-to-end verify** (import an actual PDF → review →
  confirm → see the new split) on the running app. Deploy is done (`aiImportWorkoutPlan` live,
  2026-08-20); Phase 7 handoff docs are refreshed.

### AI streaming / launch (Phase 3.5) — paused, preserved for reference

> Predates the workout/diet track above and is **paused, not superseded** — its own git state,
> verification status, and manual next steps are unchanged from when it was last active. Resume
> directly from here if the owner picks this track back up.
> without redoing completed work. Active development is on `claude/media-storage-architecture-95c0a4`
> (media storage rework); the AI-streaming handoff below is the prior, still-valid `main`/
> `feature/ai-streaming-ux` context.

### Active: Media storage architecture (2026-08-19, `claude/media-storage-architecture-95c0a4`)

- **Goal:** make media (Moments photos, profile pictures, future images) storage-agnostic and
  per-account configurable — WhatsApp-style local-first storage with optional cloud backup —
  instead of being tied to Firebase Storage. Key finding: **the app never actually used Firebase
  Storage.** Moments stored the ephemeral `image_picker` cache path directly in Firestore; profile
  avatars copied into `Documents/avatars/{uid}.ext` but stored an absolute path (breaks on iOS
  reinstall). No bytes ever went to a bucket.
- **Owner decisions (2026-08-19):** build local + Google Drive together on one branch; default =
  durable local copy always + auto Drive backup every 3 days + a manual "Back up now"; **`drive.file`**
  scope (app-created files only — no Google restricted-scope review); Save-to-Photos is opt-in.
- **Status: Phase 1 (local-first pipeline) DONE & committed (`cce035a`).** New `lib/core/media/`
  module: `MediaStore`/`LocalMediaStore` (durable copies under `Documents/media/{kind}/{id}.ext`,
  addressed by **relative** refs so files survive iOS container-path changes), `MediaObject` +
  `MediaRegistry` (Firestore/in-memory metadata + per-target backup state at `users/{uid}/media`;
  bytes never touch Firestore), `MediaStoragePreferences` + repos (per-account at
  `users/{uid}/settings/media`), `MediaBackupTarget` interface + `DeviceGalleryTarget` (via `gal`),
  `MediaService` orchestrator (capture fan-out, `backupNow()`, 3-day `runAutoBackupIfDue()` — all
  unit-tested against a fake Drive target), and a `MediaImage` display widget. Moments + profile
  avatars migrated onto it; a "Media & Backup" Settings section added (Save to Photos works; Drive
  row is a labelled placeholder). DI wired in `AppScope`/`app.dart`; Firestore rules added for
  `media` + `settings`; iOS `NSPhotoLibraryAddUsageDescription` + Android legacy storage permission
  added. Added `gal` + `path` deps. **`flutter analyze` clean; all 461 tests pass (19 new).**
- **Phase 2 (Google Drive) — CODE DONE & committed; blocked only on the owner's GCP setup + an
  on-device OAuth check.** Built: `DriveBackupClient` interface + `GoogleDriveBackupClient`
  (google_sign_in v7 incremental authorization — `authorizationClient.authorizeScopes([DriveApi.driveFileScope])`
  — plus googleapis Drive v3, with the OAuth bearer token injected into a custom `http.Client`, so no
  google_sign_in↔googleapis bridge package is needed); `GoogleDriveTarget` keyed `BackupTargetId.drive`;
  `MediaService.connectDrive()/disconnectDrive()/supportsDrive` and an `isUnmetered` seam
  (`connectivity_plus`) that enforces "Wi-Fi only" on the **automatic** path only (manual "Back up now"
  ignores it, by design). The Media & Backup Settings section is now a full flow (Connect / Back up now /
  Auto-backup 3-day toggle / Wi-Fi only / Disconnect), and `HomeShell.initState` fires
  `runAutoBackupIfDue()` on app open. Deps added: `googleapis`, `http`, `connectivity_plus`.
  **`flutter analyze` clean; 471 tests pass (+10 Drive tests using a fake `DriveBackupClient`).**
- **Still needed from the owner** (project `zivo-63f15`): (1) enable the Google Drive API, (2) add scope
  `https://www.googleapis.com/auth/drive.file` to the OAuth consent screen, (3) add
  `ziadelsewedy1@gmail.com` as a test user. iOS URL scheme + Android SHA-1 already exist from Firebase auth.
- **Exact next action:** after the 3 GCP steps, do the **on-device verification** of
  `GoogleDriveBackupClient` (the only file unit tests couldn't exercise): connect prompt, `drive.file`
  scope grant, app folder create, upload, and re-backup via `replaceFileId`. Fix any google_sign_in v7 /
  googleapis signature mismatches surfaced there. Then decide on merging the branch. iOS can't guarantee
  true timed background — the 3-day cadence realistically fires on the next app open after 3 days.
- **Manual owner action:** the 3 Google Cloud steps above; decide when to merge this branch.
- **Do not redo:** don't re-derive the `lib/core/media/` module, the Moments/Profile migration, or the
  Drive client/target/connect flow — Phases 1 and 2 are built, committed, and green. Don't reintroduce
  raw picker paths or absolute stored paths; media flows through `MediaService`. Don't add a
  google_sign_in↔googleapis bridge package — the custom bearer `http.Client` is deliberate.

### Prior handoff: AI streaming UX (2026-08-17, `feature/ai-streaming-ux`)

- **Status (as of 2026-08-17):** **Phase 3.5 (AI streaming UX + caching cost win) is deployed to
  `zivo-63f15`.** `aiChat`, `aiConfirmAction`, `aiCancelAction` were redeployed 2026-08-17
  (Node 24, 2nd Gen, `us-central1`). Phase 3.5 shipped three slices: **Slice C** — real streaming
  (`aiChat` streams over Firebase callable streaming, `response.sendChunk` ↔ `httpsCallable.stream()`;
  server-authoritative phase events drive the iris activity rail); **Slice A** — prompt caching + history
  trimming (a cached static system+tools prefix reads back at 0.1×; `aiUsage` docs gain
  `cacheReadTokens`/`cacheWriteTokens` and `schemaVersion: 2`); **Slice B** — a client typewriter
  fallback for the buffered `.call()` path. Runbook: `docs/PHASE_3_5_DEPLOY.md`.
- **Bug found & fixed during the Phase 3.5 deploy validation (committed, `9c6d153`):**
  the emulator dry-run (driving the emulated `aiChat` over the real callable streaming wire against
  the **real Anthropic API**) exposed a prod-breaking defect the offline suite could not catch.
  `claude-sonnet-5` returns a **signed placeholder `thinking` block** by default; the buffered path
  (`messages.create`) preserves its signature so the follow-up model call is accepted, but the
  streaming path (`@anthropic-ai/sdk@0.32.0` `stream.finalMessage()`) reconstructs it with an
  **empty signature**. Re-sending that block on the second model call of any `tool_use` turn fails
  the API's `each thinking block must contain thinking` check → **400 on every streamed multi-tool
  (read) turn**. The offline tests stayed green because their canned fake model emits no thinking
  blocks. **Fix** (`functions/ai/gateway.js`, `stripEmptyThinking`): strip empty-content thinking
  blocks from the assistant message before echoing it back into history — transport-agnostic,
  genuinely-signed blocks preserved. A gateway **regression test** covers both (empty stripped,
  signed kept). Note added to revisit if extended thinking is ever enabled.
- **Validation done (server/wire, without a device):** post-fix, verified live against the
  emulator — read turn streams `understanding → working → text deltas → done → ok` result;
  proposal turn streams `understanding → deltas → preparing_change → done → proposed` (+`actionId`).
  **Slice A caching confirmed with real numbers** from the emulator's `aiUsage` docs:
  `schemaVersion: 2` on every doc and `cacheReadTokens > 0` every turn (~4712 on 2-call read turns,
  2356 on the single-call proposal) — the static prefix reads back cached, saving ≈ $0.013/read turn
  vs. full price. The runbook's failure condition (reads stuck at 0) is not hit.
- **On-device client check — DONE (2026-08-17, owner verified):** ran the Ask mutation flow on a
  signed-in simulator. `can you add a random task today` → model **proposed** (title/due/priority)
  → owner **confirmed** → **`Confirmed`** card → **`Added to Tasks · Random task`**. The streamed
  response settled cleanly into one durable message — **no double-bubble** (the specific runbook
  Step 2 concern). This closes the last device-only validation for Phase 3.5's `add task` path.
  Two behavior notes to review (not bugs): (1) the model **asked clarifying questions first**
  ("set a due time? high or normal?") instead of proposing one action immediately per ADR-003's
  "propose-one" intent — candidate system-prompt tightening; (2) the proposal arrived as **prose**
  ("just confirm and I'll add it") rather than the structured iris confirmation *card*, yet the
  Confirmed/Added cards still rendered after — confirm whether that's the intended path.
- **Separate infinite-spinner bug — root-caused & FIXED (committed, `3635a60`; earlier partial
  `eaebc17`):** opening any **empty** Hub detail page (Schedule, Diet, …) spun forever — no data,
  no error. The handoff's backend theory (App Check / indexes / Firestore connection) was a **red
  herring**: reproduced live, the Today screen renders real Firestore data, so the backend works.
  Real cause: Firestore repos returned a **raw broadcast stream** from `watchAll()`, and a Dart
  broadcast stream **never replays its latest value to a late subscriber**. The Today dashboard
  (kept alive in the `IndexedStack`) is the *first* subscriber to every `watchAll()`; a Hub detail
  page's `StreamBuilder` is a *second, late* subscriber → gets no replay → sits at `waiting` with
  empty `initialData` → infinite spinner, but **only for empty collections** (non-empty ones render
  from non-empty `current`). The in-memory repos never had this because they `yield current` first;
  the Firestore repos silently broke that contract — which is why 255 tests and the console stayed
  clean. **Fix:** all 8 Firestore repos (`schedule`/`tasks`/`expenses`/`notes`/`moments`/`workout`/
  `university` list repos + `diet`'s `watchActivePlan()`) now track a `_hasSnapshot` flag and
  `yield current` on subscribe before the broadcast stream — restoring the in-memory contract.
  A schedule **regression test** was *proven* to catch it (times out on old code, passes on new).
  `flutter analyze` clean; `flutter test` **256 pass**.
- **Spinner fix — live re-verify CONFIRMED (2026-08-17):** fresh full rebuild on the iPhone 17
  sim; both empty Hub pages Today pre-subscribes to now render their empty state instead of
  spinning (Workout → "No workouts yet.", Diet → "No diet plan yet." + Create plan). Console clean
  (zero `cloud_firestore` errors), 256 tests green. (Note: `3635a60` was auto-committed by a
  concurrent session — byte-for-byte identical to the fix author's working tree, nothing added.)
- **Confirmation-card state bug — FIXED & committed (`1a85c77`, 2026-08-17):** *"fix(ai): make
  confirmation cards reflect true server state and stop duplicate writes."* Fixed five things:
  (1) **duplicate-write guard** — gateway refuses a second proposal while an unexpired pending
  action exists (`store.getActivePendingAction`), so re-proposing (e.g. typing "confirm") can't mint
  a second card/task; (2) **card reflects true server state + survives reopen** — action_proposal
  messages now persist `status` (+ `expiresAt`); confirm/cancel/expire flip it (`store.markProposalMessage`);
  the client reads the stored status instead of hardcoding `pending`; (3) **typed "confirm" = nudge**
  (owner decision) — hits the guard, replies "tap Confirm or Cancel on the card above"; tap-to-confirm
  stays the only write path (ADR-003), no free-text auto-execute; (4) **expiry edge** — a still-pending
  card renders as **Expired** on read once its TTL passes; (5) **prompt tightening** — don't re-propose
  while one is pending, don't treat typed "confirm"/"yes" as permission, propose via the tool not prose.
  Root cause had been: the applied-state override `_resolved[actionId]` was only set on button tap
  (`ask_page.dart`), and the proposal message's server status was never flipped for a text-turn confirm.
  Gates: functions node --test **42/42**, `flutter test` **258/258**, analyze + eslint clean.
  6 files (`functions/ai/{gateway,store}.js` + 2 gateway tests, `firebase_ai_repository.dart` + its
  test). **NOT pushed, NOT deployed.** ⚠️ **Deploy client + server together** — the client reads the
  `status`/`expiresAt` fields the new gateway writes, so `firebase deploy --only functions` and a
  fresh app build must ship in the same go, or deployed cards won't reflect server state.
- **App Check — still NOT enforced** (unchanged pre-launch item): `aiChat`/`aiConfirmAction`/
  `aiCancelAction` have no `enforceAppCheck: true`. Fine for private validation on the owner's
  account; add + verify providers in the Console before any public launch.
- **M7 Performance — DONE (2026-08-17):** owner ran the on-device profiling passes and signed off
  — performance is good, **no measured fixes needed**. The profiling harness stays in the repo
  (`docs/performance/`, `scripts/perf/`). This leaves **M9 (AI V2) as the only remaining milestone.**
- **Branch:** `feature/ai-streaming-ux`, checked out and active. Latest commits: `3635a60`
  (broadcast-replay fix) on top of `9c6d153` (empty-thinking-block fix). Working tree: this handoff
  doc update only.
- **App Check — still NOT enforced** (unchanged pre-launch item): `aiChat`/`aiConfirmAction`/
  `aiCancelAction` have no `enforceAppCheck: true`. Fine for private validation; this is **M9 Phase
  4** — enforce it (server flag + Console providers) before any public launch.
- **Exact next action:** (1) confirm the live-simulator re-verify of the spinner fix completed
  (open an empty Hub detail page → empty state, not a spinner); (2) **decide on merging
  `feature/ai-streaming-ux` into `main`** — Phase 3.5 is deployed & on-device-verified, the spinner
  fix is landed & 256 tests green; (3) then finish **M9 Phase 4** (enforce App Check + final deploy),
  the last step to launch-readiness. Optionally review the two AI-behavior notes above (propose-one;
  card vs. prose) as a system-prompt polish.
- **What the read-only V1 slice (still current architecture) adds:**
  - **Gateway** (`functions/ai/gateway.js`): `runAiTurn({store, callModel, uid, conversationId,
    message, now, config})` — a pure-ish orchestration function kept free of
    `@anthropic-ai/sdk`/`firebase-admin` so it runs offline. Persists the user message, checks the
    per-day cap (`store.getTodayUsageTotals`), loops up to `maxIterations` (5) model↔tool
    round-trips with `stop_reason` handling for `tool_use` / `end_turn` / `refusal`, aborts cleanly
    on the per-turn token ceiling (50000) or the iteration cap, persists the assistant's final
    reply, and logs usage (`tokensIn`/`tokensOut`/`costUsd`/`tools`/`iterations`/`latencyMs`,
    Sonnet 5 pricing $3/$15 per 1M in/out tokens). The `SYSTEM_PROMPT` constant states ZIVO +
    read-only scope and explicitly fences tool output as **untrusted data, not instructions**
    (prompt-injection defense). Each tool call's `tool_use.id` is threaded through as `toolCallId`
    in the usage log (idempotency groundwork for a future V2 mutation phase).
  - **Tools** (`functions/ai/tools.js`): 9 uid-scoped read-only tools — `get_today`, `get_tasks`,
    `get_schedule`, `get_expenses`, `get_university`, `get_workouts`, `get_diet`, `search_notes`,
    `summarize_week` — each `{name, description, inputSchema, execute(store, uid, input, now)}`.
    Money stays integer minor units; totals-by-category are computed server-side, not left to the
    model. `search_notes` is a naive case-insensitive substring match (not full-text), matching
    ADR-001's stated scope.
  - **Store seam** (`functions/ai/store.js`): `FirestoreStore` — the only file besides `index.js`
    that touches Firestore (Admin SDK, always explicitly `uid`-scoped). Implements 8 uid-scoped
    reads (`listTasks`, `listSchedule`, `listExpenses`, `listUniversity`, `listWorkouts`,
    `searchNotes`, `getActiveDietPlan`, `listDietEntries`) plus persistence
    (`appendMessage`/`touchConversation`/`logUsage`) and `getRecentMessages`/
    `getTodayUsageTotals`. Field names mirror the client `FirestoreXRepository` classes exactly.
    `functions/ai/dates.js` holds pure date-range helpers (today/week/month bounds, `dayKeyFor`,
    the diet day-resolution mirror of the client's `dayForDate`) shared by both.
  - **`functions/index.js`**: added `exports.aiChat = onCall({secrets: [ANTHROPIC_API_KEY],
    region: "us-central1"}, ...)` — a thin wrapper (auth guard, input coercion, constructs the real
    `Anthropic` client + `FirestoreStore`, calls `runAiTurn`, maps `GatewayError` → `HttpsError`).
    All real logic stays in `gateway.js`/`tools.js` for testability. `functions/package.json`
    gained the `@anthropic-ai/sdk` dependency and a `"test": "node --test"` script.
  - **Tests** (`functions/ai/gateway.test.js`, `functions/ai/tools.test.js`, offline `node --test`,
    no SDK/emulator): input validation, uid-scoped tool execution, the iteration cap (asserts exact
    model-call count), the per-turn token ceiling, the per-day cap (asserts zero model calls),
    refusal handling, a tool-executor error recovering via an `is_error` tool_result, the
    prompt-injection fence, and usage logging — plus direct `tools.js` tests (`get_expenses`
    category totals, `search_notes` matching). **17/17 pass.**
  - **`lib/features/ai/data/firebase_ai_repository.dart`**: the real `AiRepository`.
    `ensureConversation()` reuses the most-recently-updated `aiConversations` doc or creates one;
    `watchMessages()` streams `.../messages` ordered by `createdAt`, re-scoping on uid change
    (mirrors `FirestoreUniversityRepository`'s `UidSource` pattern); `send()` never writes
    Firestore directly (rules forbid it) — it calls an injectable `invokeChat` seam defaulting to
    `FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('aiChat')`. `app.dart`'s
    `_defaultAi()` now returns `FirebaseAiRepository` when `USE_FIRESTORE=true` (the default),
    `FakeAiRepository` otherwise — same pattern as the other 8 repositories.
  - **`test/ai/firebase_ai_repository_test.dart`** (`fake_cloud_firestore`, mirrors the University
    repo test): conversation create-then-reuse (including reuse of a doc already in Firestore, not
    just the in-memory cache), message ordering/role-mapping, `send()` invoking the injected fake
    `invokeChat` with the trimmed text, and no-op on empty/whitespace input. The real callable
    invocation is on-device-only and explicitly not exercised here.
  *(V1 read-only architecture above is still current; V2 mutations (ADR-003) and Phase 3.5
  streaming/caching build on top of it.)*
- **Last completed action:** ran the Phase 3.5 deploy & validation runbook — emulator dry-run,
  discovered and fixed the streamed empty-thinking-block 400 (`9c6d153`, with a regression test),
  redeployed the three AI callables, and validated the streaming transport + Slice A caching against
  the emulator with the real Anthropic API (see Status bullets above).
- **Verification status:** functions lint clean; `functions` offline suite **40/40 pass** (was 39,
  +1 `stripEmptyThinking` regression test); `flutter test` **251 pass** (unchanged — server-only
  fix). Live emulator validation: streaming read + proposal turns both stream phases→deltas→result;
  `aiUsage` docs show `schemaVersion: 2` with `cacheReadTokens > 0` every turn. **Not run:** the
  on-device signed-in client rendering (runbook Step 2) — needs the owner's device.
- **Manual user action:** (1) run runbook Step 2 on a signed-in device (`what's due this week?`,
  `add task Submit the report`) to confirm the client rendering — rail phases, no double-bubble,
  durable message persists across reopen; (2) enforce App Check (server `enforceAppCheck: true` +
  Console providers) before any public launch; (3) decide on merging `feature/ai-streaming-ux`.
- **Do not redo:** don't re-derive the gateway/tools/store or the streaming/caching slices — Phase
  3.5 is built and deployed. The empty-thinking-block fix is committed; don't reintroduce echoing
  raw `resp.content` back into history without stripping empty thinking blocks. Don't set secrets or
  flip App Check enforcement — owner-only.

---

## 1. Product vision and purpose

ZIVO is a **Personal OS** — a single, cohesive mobile surface that centralizes one
person's life areas (schedule, tasks, expenses, workouts, notes, moments, university,
and eventually an AI assistant) instead of scattering them across separate apps.

Guiding principles (from `docs/PLAN.md §0`, still in force):

- **One person, one system.** No multi-tenancy, sharing, teams, or roles. Take every
  simplification single-user allows.
- **One connected system, not ten CRUD apps.** Schedule feeds Today; Today aggregates
  everything; AI (later) reads across all of it. Design for the graph, not silos.
- **Every abstraction pays rent.** No pattern for its own sake — but keep the seams
  that let us swap the in-memory backend for a real one later.
- **Premium is a feature.** Motion, spacing, typography, and perceived speed are
  first-class requirements, not polish added at the end.

**The connective tissue:** Schedule/Tasks/Workout/etc. feed the **Today** command
surface ("what matters right now"); capture is a single verb (one Quick Capture sheet),
not five destinations.

---

## 2. Current tech stack

| Concern | Actual (built) |
|---|---|
| Framework | Flutter (Material 3), Dart SDK `^3.12.2` |
| App name / version | `zivo` / `1.0.0+1` |
| State management | **Plain `StatefulWidget` + `StreamBuilder`** over repository streams. No bloc/cubit/riverpod/provider. |
| Dependency injection | **`AppScope` `InheritedWidget`** holding repositories. No `get_it`. |
| Navigation | **`IndexedStack`** in `HomeShell` + `Navigator.push` `MaterialPageRoute` for captures/detail. No `go_router`. |
| Auth | **Real Firebase Authentication** (Apple, Google, Email/Password) behind an `AuthRepository` seam. `AuthGate` gates the app on `watchAuthState()`. Signed-in `uid` is the app's canonical user identity. See §7. |
| Persistence | **All six feature repositories now persist to Firestore** under `users/{uid}/<collection>` (Tasks, Expenses, Schedule, Notes, Workout, Moments), scoped by the signed-in `uid`, behind their unchanged interfaces. The auth **session** persists via Firebase Auth and the **user profile** via Firestore `users/{uid}`. The `InMemory*` repos are retained as a `--dart-define USE_FIRESTORE=false` fallback and for tests. No local DB. Moments photos are **not** persisted yet (Storage is deferred — see §7). |
| Firebase | **`firebase_core` + `firebase_auth` + `cloud_functions` + `cloud_firestore`.** Initialized in `main.dart` via `DefaultFirebaseOptions` (`lib/firebase_options.dart`, full FlutterFire output). iOS + Android apps registered in `zivo-63f15` for bundle **`com.ziadelsewedy.zivo`**. Cloud Functions back the email-OTP flow; **Firestore now backs the OTP records (Functions-only), user profiles (`users/{uid}`), and all six feature collections (`users/{uid}/{tasks,expenses,schedule,notes,workouts,moments}`)** — owner-only rules for all deployed. No Storage yet. |
| Fonts | `google_fonts`: **Bricolage Grotesque** (display) + **Hanken Grotesk** (text). |
| Other deps | `image_picker ^1.2.3` (Moments photos), `firebase_core ^4.1.1`, `firebase_auth ^6.5.7`, `cloud_functions ^6.0.3`, `cloud_firestore ^6.0.0`, `google_sign_in ^7.2.0`, `sign_in_with_apple ^8.1.0`, `crypto ^3.0.7`, `cupertino_icons`. |
| Lints | `flutter_lints ^6.0.0` via `analysis_options.yaml` (default rule set). |

> Firebase **Core + Auth** are now wired (see §7). Anything involving **Firestore,
> Storage, Cloud Functions**, `get_it`, `go_router`, Cubits, AI, PDF import, backend
> repository migration, or CI in `docs/PLAN.md` is still **planned, not implemented.**

---

## 3. Architecture and major conventions

**Layered per feature:** `domain → data → presentation`.

```
lib/
  main.dart                     # Firebase.initializeApp() then runApp(ZivoApp)
  firebase_options.dart         # DefaultFirebaseOptions (iOS) — firebase_core only
  app/app.dart                  # ZivoApp: owns the in-memory repos, provides AppScope, MaterialApp
  core/
    scope/app_scope.dart        # InheritedWidget DI seam (the 6 repositories)
    theme/                      # app_colors, app_typography, app_spacing, app_shadows, app_theme
    util/                       # money.dart, time_ago.dart
    widgets/rise_in.dart        # shared entrance animation
  features/<feature>/
    domain/                     # entities (immutable) + `abstract interface class` repository (+ pure helpers)
    data/                       # in_memory_<x>_repository.dart
    presentation/pages|widgets/ # UI
```

**Repository seam (the key convention — this is the swap point for a real backend):**

Every repository is an `abstract interface class` with an in-memory implementation that:
- holds a `List<T> _items` and a broadcast `StreamController<List<T>>`,
- exposes `List<T> get current` (returns `List.unmodifiable`),
- exposes `Stream<List<T>> watchAll()` that `yield`s `current` then the controller stream,
- exposes `Future<void> add(T)` (and feature-specific mutators, e.g. tasks' `setDone`),
- seeds demo data in its constructor,
- has a `dispose()` that closes the controller (see Known Issues — not currently called).

**Reactive UI convention:** presentation reads live data via
`StreamBuilder(stream: repo.watchAll(), initialData: repo.current, …)`.

**Pure, testable builders/formatters** live in `domain` or `home/presentation` and take
`DateTime now` as a parameter (never call `DateTime.now()` internally) so they are unit
testable. Examples: `schedule/domain/event_time.dart`, `workout/domain/workout_format.dart`,
`home/presentation/focus_builder.dart`, `home/presentation/now_next_builder.dart`.

**Capture convention:** all capture screens reuse shared widgets from
`features/capture/presentation/widgets/capture_widgets.dart` (`CaptureTopBar`,
`PillButton`, `SelectChip`) and follow the same lifecycle (controller in a
`StatefulWidget`, `add`-listener toggling a `_canSave/_canAdd` flag, read
`AppScope.of(context)` **before** any `await`, guard `Navigator` with `if (mounted)`).

---

## 4. Design system / UX conventions

**Brand System v2 — light & warm.** Defined in `docs/ZIVO-brand-system.md`; implemented
in `core/theme/`.

- **Surfaces:** `ground` warm off-white background, `card` white; text hierarchy
  `ink` → `ink2` → `ink3`; `hairline`/`hairline2` borders.
- **Hues — one per life area, meaning not decoration.** Each has a vivid dot/fill tone,
  a darker legible text tone, and (some) a soft wash:
  - `ember` — **Now / Next + the primary action** (reserved; appears once on Today)
  - `pulse` — training / health / **Workout**
  - `solar` — money / **Expenses**
  - `iris` — university / study / focus
  - `flare` — overdue / alert
- **Tokens:** `AppSpacing` (4pt base; `screen=22`, `section=34`), `AppRadius`
  (`chip=8`, `card=20`, `pill=999`), `AppShadows`, `AppMotion` (`ease`, `tap`, `enter`).
- **Typography:** `AppText` styles (greeting, cardTitle, rowTitle, body, meta, aside,
  sectionLabel, hueLabel, dateLabel…).
- **UX rules:** Today reads "like a sentence about the day"; Ember is singular on Today;
  capture is one sheet → one pick; empty states are intentional; entrance motion via
  `RiseIn`. A themed capture screen adopts its area's hue (Expense = Solar screen,
  Workout = Pulse screen).

Full intent lives in `docs/UX_BLUEPRINT.md` and `docs/mockups/`.

---

## 5. Implemented features and their current status

Legend: ✅ built & wired · 🟡 partial/demo · ⛔ placeholder only.

| Feature | Status | Notes |
|---|---|---|
| **Home / Today** | 🟡 | Live sections + some demo. See breakdown below. |
| **Expenses** | ✅ | Capture (custom keypad + category chips); feeds Today "Spending". **Firestore** (`users/{uid}/expenses`). |
| **Tasks** | ✅ | Quick-create; toggle done; feeds Today "Today/Focus" list. **Firestore** (`users/{uid}/tasks`). |
| **Schedule / Event** | ✅ | Event capture; feeds Today "Now · Next" reactively. **Firestore** (`users/{uid}/schedule`). |
| **Notes** | ✅ | Capture + list; reachable via Hub. **Firestore** (`users/{uid}/notes`). |
| **Moments** | ✅ | Capture (optional photo via `image_picker`) + timeline; via Hub. **Firestore** (`users/{uid}/moments`) — caption/time/location only; photo path is device-local (Storage deferred). |
| **Workout** | ✅ | Capture (name + add-exercise sheet) + history; via Hub. **Firestore** (`users/{uid}/workouts`, exercises embedded). |
| **Diet** | ✅ | Structured plan (days → meals → items, Pulse-themed, shares Workout's hue); today's meals with an eaten checkbox + "meals eaten · kcal left" summary, a read-only full-week browse section, and a bottom-sheet plan editor; via Hub. **Firestore** (`users/{uid}/dietPlans` embedded days/meals/items + `users/{uid}/dietEntries` consumption log). Manual-entry only — PDF import is designed in `docs/DECISIONS/ADR-002-document-pdf-pipeline.md` but not built; Today integration is deferred. |
| **Hub (launcher)** | ✅ | Grid of modules. Live tiles: Notes, Moments, Workout, Diet, University. "Soon" tiles: Schedule, Tasks, Expenses. |
| **Quick Capture** | ✅ | Bottom sheet → 6 choices: Expense, Task, Event, Note, Moment, Workout. |
| **University** | ✅ | Assignments/exams grouped by course; via Hub; merged live into Today's focus. **Firestore** (`users/{uid}/universityItems`). |
| **Ask (AI assistant)** | 🟡 | `AskPage` chat UI (iris-themed) wired to the real, read-only `aiChat` Cloud Function gateway (Claude Sonnet 5, 9 uid-scoped Firestore read tools, enforced iteration/token/day ceilings, `aiUsage` logging, prompt-injection fencing — `functions/ai/{gateway,tools,store}.js`) via `FirebaseAiRepository` (Firestore message stream + the callable) — see `docs/DECISIONS/ADR-001-ai-assistant.md`. Fully unit-tested offline (gateway/tools via `node --test`; the repo via `fake_cloud_firestore`) but **not yet deployed** — `USE_FIRESTORE=false` still serves the honest in-memory `FakeAiRepository`. Owner-only remaining: `firebase deploy` (functions + rules), App Check, on-device end-to-end verification. |
| **You (Profile)** | 🟡 | `ProfilePage` (shows the signed-in `AuthUser`, sign-out). Settings not built. Separate from the post-auth **profile completion** step (name + DOB) below. |
| **Authentication** | ✅ | Real Firebase Auth — Apple (iOS only), Google, Email/Password (strong-password sign-up + 6-digit email OTP) — behind `AuthGate`. Clean state machine: unauth → email-verification → **profile-completion (name + DOB, Firestore `users/{uid}`)** → ready. Session persists; sign-out works. Provider end-to-end sign-in pending Console/Apple-Developer enablement (see §7). |

**Today breakdown (`features/home/`):**
- **Now · Next** — ✅ live from `ScheduleRepository`.
- **Today / Focus** — ✅ live from `TaskRepository` (merged with one demo university
  deadline via `buildFocus`).
- **Spending** — ✅ live from `ExpenseRepository`.
- **Training card** — 🟡 **static demo** (`today_demo_data.dart`); it represents a
  *planned* session with a "Start" button and is **not** wired to the Workout
  repository/history (see Known Issues #3).
- **Header** (date/greeting/aside) — 🟡 hardcoded demo values in `today_demo_data.dart`.

---

## 6. Current repository / data architecture

Six repositories, provided through `AppScope`. Each has **two** implementations behind one
`abstract interface class`: a `Firestore*` impl (the runtime default) and an `InMemory*` impl
(the `--dart-define USE_FIRESTORE=false` fallback and the test double). `app.dart` selects
between them; nothing above the `data/` layer knows which is live.

| Repository | Interface | Firestore impl (default) | In-memory impl (fallback/tests) | Extra mutators |
|---|---|---|---|---|
| `ExpenseRepository` | expenses/domain | `FirestoreExpenseRepository` | `InMemoryExpenseRepository` | — |
| `TaskRepository` | tasks/domain | `FirestoreTaskRepository` | `InMemoryTaskRepository` | `setDone(id, done)` |
| `ScheduleRepository` | schedule/domain | `FirestoreScheduleRepository` | `InMemoryScheduleRepository` | + free fn `nextRelevant()` |
| `NoteRepository` | notes/domain | `FirestoreNoteRepository` | `InMemoryNoteRepository` | — |
| `MomentRepository` | moments/domain | `FirestoreMomentRepository` | `InMemoryMomentRepository` | — |
| `WorkoutRepository` | workout/domain | `FirestoreWorkoutRepository` | `InMemoryWorkoutRepository` | — |

The Firestore impls store under `users/{uid}/<collection>` (ordered newest-first, except
schedule which orders by `start` ascending), resolve the `uid` via the shared `UidSource`
seam (`lib/core/firebase/uid_source.dart`), and re-scope `watchAll()` on auth change. The
`InMemory*` impls seed demo content. Both share the `current` / `watchAll()` / `add()` shape.

---

## 7. Backend / persistence status

**Firebase Core + Auth + Firestore are wired, and all six feature repositories now
persist to Firestore.** On launch the app calls `Firebase.initializeApp()` (with
`DefaultFirebaseOptions.currentPlatform`) and connects to the **`zivo-63f15`** project, then
`AuthGate` gates the UI on `AuthRepository.watchAuthState()`. Firebase Auth persists the
**session**, and Firestore persists the **user profile** (`users/{uid}`) and **all feature
data** (`users/{uid}/{tasks,expenses,schedule,notes,workouts,moments}`), scoped by the
signed-in `uid`.

**Authentication (implemented):** three providers behind the `AuthRepository` seam —
**Sign in with Apple** (native, SHA-256 nonce), **Sign in with Google**
(`google_sign_in` 7.x), and **Email/Password** (normal Firebase email/password; Gmail
addresses are ordinary email/password accounts, *not* a separate provider). The signed-in
`uid` is the app's canonical user identity — the key the Firestore layer scopes data by. See
`lib/features/auth/`.

**Firestore persistence (implemented — the completed milestone):** each feature repository
has a `Firestore*` implementation behind its unchanged interface, storing under
`users/{uid}/<collection>`. Every doc carries `schemaVersion: 1` + `createdAt`/`updatedAt`;
timestamps are UTC, money is integer minor units, writes are idempotent (doc id = entity id).
The Firestore SDK is confined to `data/` — no `cloud_firestore` import appears in any
`domain/` or `presentation/` file. Repos resolve the `uid` from the shared `UidSource` seam
(`lib/core/firebase/uid_source.dart`) and re-scope on auth change. **Owner-only security
rules with field validation for all six subcollections are deployed to `zivo-63f15`**
(`firestore.rules`; rules do not cascade from `/users/{uid}`, so each is explicit, plus a
deny-by-default catch-all). The `InMemory*` impls are retained as a `--dart-define
USE_FIRESTORE=false` fallback and the test doubles. See `lib/features/*/data/firestore_*_repository.dart`.

**Still NOT implemented:** Firebase **Storage** and any photo/file upload — Moments'
`imagePath` is persisted only as a device-local path string, so photos do not survive across
devices/reinstalls yet (deliberately deferred to the V1.5 Storage milestone per PLAN §26).
No rollup/aggregation Cloud Functions, no AI, no University feature. The DI/nav/state
foundation is unchanged (still `AppScope` + `StreamBuilder`; no `get_it`/`go_router`/Cubit).

**Provider setup that is code-complete but not yet verified end-to-end (manual,
non-headless steps):** enabling **Email/Password**, **Google**, and **Apple** providers in
the Firebase Console (Authentication → Sign-in method); configuring Apple (Service ID +
Sign in with Apple key) in the Apple Developer portal; and, for Android Google id-tokens,
passing the web `serverClientId` via `--dart-define=GOOGLE_SERVER_CLIENT_ID`. Until those
are done and tested on a device/simulator, **no provider is claimed to sign in end-to-end**
— only the build/launch/render path is verified (see §14).

**Native integration (bundle `com.ziadelsewedy.zivo`):**
- iOS + Android Firebase apps registered in `zivo-63f15` (iOS
  `…ios:fb766e1151cf147755f7a8`, Android `…android:e4fd2ec7f3ae385855f7a8`).
  `lib/firebase_options.dart`, `firebase.json`, and the macOS config are the FlutterFire
  CLI output; `ios/Runner/GoogleService-Info.plist` and `android/app/google-services.json`
  are the downloaded per-app configs.
- iOS: `Runner.entitlements` (Apple Sign-In) + `CODE_SIGN_ENTITLEMENTS` in all Runner
  configs, `DEVELOPMENT_TEAM = 7Q3PY75VGH`, deployment target 15.0, and the Google
  `REVERSED_CLIENT_ID` URL scheme in `Info.plist`.
- Android: `namespace`/`applicationId = com.ziadelsewedy.zivo`, `minSdk ≥ 23`,
  `com.google.gms.google-services` plugin, `MainActivity` in the new package.

> **CLI note:** `flutterfire configure` initially failed with "Firebase project id
> `zivo-63f15` could not be found on this Firebase account" (the project doesn't surface in
> `firebase projects:list` for this account) even though `firebase apps:*  --project
> zivo-63f15` works directly. The apps were therefore created with `firebase apps:create`;
> `flutterfire configure` later succeeded and regenerated `firebase_options.dart`.

---

## 8. Important architectural decisions

1. **UX-first, in-memory-first.** Build every feature as a full vertical slice
   (domain/data/presentation/tests) against in-memory repos to lock the design and the
   layering template *before* introducing Firebase/persistence.
2. **Repository interface as the backend seam.** Presentation depends only on the
   `abstract interface class`, never on the implementation → swapping to Firestore is a
   data-layer change only.
3. **Lightweight DI/state now, heavier later.** `InheritedWidget` (`AppScope`) +
   `StreamBuilder` are deliberately minimal stand-ins for the planned `get_it` + Cubits;
   chosen because "every abstraction pays rent" and the app is small today.
4. **Pure builders take `now` as a parameter** so time-dependent logic is deterministic
   and unit-testable.
5. **Hue ownership.** Each life area owns exactly one hue; Ember is reserved for Now/Next
   and the single primary action so Today stays legible.
6. **Planned vs. logged separation.** Today's "Training" card models a *plan* (with
   Start); the Workout feature currently only logs *history*. These are deliberately
   distinct concepts (a plan/template source does not yet exist).

---

## 9. Known issues and technical debt

1. **~~No persistence~~ — RESOLVED.** All six feature repositories now persist to Firestore
   (see §7). Remaining persistence gap: **Moments photos** (only the device-local path is
   stored; real photo storage awaits the deferred V1.5 Firebase Storage milestone).
2. **`dispose()` on the repos is never called.** `ZivoApp` (a `StatefulWidget`)
   holds the repos for the whole app lifetime but never disposes their
   `StreamController`s. Benign today (app-lifetime singletons) but real debt once repos
   gain resources.
3. **Today's Training card is demo-only** and not connected to `WorkoutRepository`, so
   logged workouts do not appear on Today. Wiring this requires deciding the
   planned-vs-logged model (see §8.6).
4. **Today header/greeting/date and the university deadline are hardcoded demo data**
   (`today_demo_data.dart`), pending a real `GetToday` composition and a University feature.
5. **Relative time labels don't tick.** Now/Next and "time ago" recompute only when the
   stream emits (they read `DateTime.now()` in `build`), so "in 2h" can go stale until
   the next data change. Acceptable for now.
6. **Number inputs in Workout capture are permissive** — sets/reps fields accept decimal
   characters; invalid values fall back safely (`int.tryParse ?? 1`, clamped ≥1). No crash
   path, but not strictly validated.
7. **`README.md` and `pubspec.yaml description` are still the default Flutter template**
   ("A new Flutter project.") — cosmetic documentation debt, not touched here.

---

## 10. Current roadmap

The proven pattern was: **finish the feature verticals in-memory, then introduce the real
backend** — both now done (auth + Firestore persistence). Remaining, roughly in order:

1. ✅ **~~Foundation / persistence (data)~~ — DONE.** All six feature repos migrated to
   Firestore behind their existing interfaces, scoped by `uid`, rules deployed. (The *rest*
   of the "foundation" — migrating DI → `get_it`, nav → `go_router`, state → Cubits — remains
   a separate, deliberate, not-yet-started decision, NOT triggered by this milestone.)
2. **University** — the last unbuilt life-area module (currently a "soon" Hub tile and one
   hardcoded Today deadline). Build it as a vertical slice like the others (now directly
   against Firestore, following the migrated repos as the template).
3. **AI assistant ("Ask")** and **Profile ("You")** — currently placeholder tabs.
4. **Firebase Storage (V1.5)** — real Moments photos (upload + `storageRef`), which the
   current metadata-only Moments persistence deliberately deferred.
5. Later (V1.5+ in `docs/PLAN.md`): PDF → workout import, richer AI actions, polish.

---

## 11. Current milestone

**Firestore persistence** — COMPLETE on `feature/firestore-persistence` (6 commits, not yet
merged into `main`). All six feature repositories (Tasks, Expenses, Schedule, Notes, Workout,
Moments) migrated from in-memory to Firestore behind their unchanged interfaces, scoped by the
auth `uid`; owner-only per-collection rules deployed to `zivo-63f15`. Deliberately scoped:
**no** Firebase Storage/photo upload, no rollup Functions, no AI, no University, and **no**
change to the DI/nav/state foundation (still `AppScope` + `StreamBuilder`). Each feature was
landed as its own reviewed commit; verification each step: `flutter analyze` clean +
`flutter test` green (63 → 93). See §12.

The prior milestone — **Authentication + clean user-identity foundation** (real Firebase Auth:
Apple iOS-only, Google, Email/Password + email OTP + profile completion behind `AuthGate`; the
signed-in `uid` is the canonical identity) — is done and **merged into `main`**, alongside the
**App-identity** milestone (ZIVO "Dark" launcher icon). Real provider sign-in still awaits the
manual Console/Apple-Developer enablement (§7, §13). **University** remains the one unbuilt
core life-area module.

---

## 12. Last completed work

**Firestore persistence milestone (2026-08-15, branch `feature/firestore-persistence`, off
`main`).** Six commits, one per feature, each reviewed and verified before the next:
- `0a8381f` Tasks (proof-of-slice) · `83ccc3b` Expenses · `8b36b57` Schedule · `b665109`
  Notes · `240d1f7` Workout · `0202c1f` Moments.
- Each adds a `Firestore<Feature>Repository` at `users/{uid}/<collection>` behind the
  unchanged interface (Firestore SDK confined to `data/`), wires it as the `app.dart` default
  behind the `--dart-define USE_FIRESTORE` flag (keeping the `InMemory*` fallback), adds an
  explicit owner-only security rule with field validation, and a
  `firestore_*_repository_test.dart` using `fake_cloud_firestore`.
- Introduced the `UidSource` seam (`lib/core/firebase/uid_source.dart`) so repos built at app
  root resolve the `uid` from an injected source and re-scope `watchAll()` on auth change,
  testable without a FirebaseAuth mock. Added `fake_cloud_firestore` (dev dep) and a
  `build/**` exclude in `analysis_options.yaml`.
- Per-feature specifics: Expenses enum `category` ↔ `.name` (+ `other` fallback); Notes
  `updatedAt` / Moments `takenAt` are domain fields (mapped, not server-stamped); Workout
  embeds its `List<Exercise>` as an array (documented deviation from PLAN §7's sets
  subcollection); Moments `imagePath` is a device-local string only (no Storage).
- **Verification:** `flutter analyze` clean; `flutter test` → **93 pass** (was 63); the six
  security rules **deployed** to `zivo-63f15` via `firebase deploy --only firestore:rules`.
  Live on-device Firestore read/write not yet exercised (needs a signed-in `uid` → the same
  manual Auth-provider enablement, §7/§13). Interfaces + domain entities unchanged; no
  Storage/Functions/AI/foundation changes.

**App-identity milestone (2026-08-15, branch `feature/app-identity`, off `planning-setup`).**
- Added the ZIVO brand asset set under `assets/` (`app-icon/` full-bleed 1024 squares in
  dark/light/ember, `rounded/` pre-rounded tiles, `transparent/` marks, `svg/` originals,
  `README.txt`).
- Added `flutter_launcher_icons` (dev dep) + config in `pubspec.yaml`; chose the **Dark**
  finish (paper Z on `#101317`). `dart run flutter_launcher_icons` regenerated the iOS
  `AppIcon.appiconset` and Android mipmaps + an **adaptive icon** (`#101317` background +
  the dark square as the inset foreground; `colors.xml` added). Also set the real app
  `description` in `pubspec.yaml` (was the Flutter template default).
- **Verification:** `flutter analyze` clean; base `flutter test` (12) pass; iOS simulator
  build + install → the Dark icon renders on the home screen; Android debug APK builds
  (adaptive icon resources compile).
- Scope note: this branch is off `planning-setup`, so its app bundle is still the base
  `com.example.zivo` and it has **no** auth code — icons are independent of auth.

**Authentication milestone (2026-08-15, branch `feature/authentication`).**
- Added `firebase_auth`, `google_sign_in`, `sign_in_with_apple`, `crypto`.
- `lib/features/auth/`: domain (`AuthUser`, `AuthState`, `AuthResult`, `AuthFailure`,
  `AuthRepository`, pure `mapAuthErrorCode`); data (`FirebaseAuthRepository` —
  email/Google/Apple with nonce + cancellation handling; `FakeAuthRepository`;
  `AuthConfig`); presentation (`AuthGate`, `SplashScreen`, `AuthPage`, `ProfilePage`,
  auth buttons/form). `ProfilePage` (sign-out) replaced the "You" placeholder.
- Wiring: `auth` in `AppScope`; `ZivoApp` uses the real `FirebaseAuthRepository` +
  `home: AuthGate`. In-memory feature repos untouched.
- Platform: bundle `com.example.zivo` → **`com.ziadelsewedy.zivo`** (iOS + Android);
  registered iOS + Android Firebase apps in `zivo-63f15`; iOS entitlements/Apple-Sign-In +
  Google URL scheme; Android namespace/applicationId/minSdk/google-services plugin +
  MainActivity package move. (`flutterfire configure` regenerated `firebase_options.dart`
  et al. after the apps were created via `firebase apps:create` — see §7 CLI note.)
- **Verification:** `flutter analyze` clean; `flutter test` → **24 pass**; **Android**
  `build apk --debug` and **iOS** `build ios --debug --simulator` both succeed; runtime
  smoke test (iPhone 17 Pro) launches on the new bundle, initializes Firebase, and renders
  the real sign-in screen. Real provider sign-in not yet verified end-to-end (§7, §14).

**Prior: Firebase Core connected (2026-08-15).** Added `firebase_core`; `main.dart`
`ensureInitialized()` + `await Firebase.initializeApp(...)`; iOS deployment target 15.0.
No Auth/Firestore/persistence at that point.

**Prior: Workout feature, end-to-end (2026-08-15).**
- Domain: `Exercise`, `Workout` (with `exerciseCount`/`summary`), pure
  `workout_format.dart` (`setRepLabel`, `workoutMeta`), `WorkoutRepository`.
- Data: `InMemoryWorkoutRepository` (seeded "Push" session, newest-first).
- Presentation: `WorkoutCapturePage` (Pulse-themed; name + add-exercise bottom sheet) and
  `WorkoutHistoryPage` (reactive history list, Pulse FAB).
- Wiring: added to `AppScope` + `app.dart`; Hub "Workout" tile made live; Quick Capture
  gained a **Workout** option (+ `home_shell` case → "Workout logged" toast).
- Tests: `workout_domain_test.dart`, `workout_repository_test.dart`,
  `workout_history_page_test.dart`.
- Today's Training demo card was intentionally left untouched.

(Immediately prior: Schedule/Event, Notes, and Moments features + Hub + shared capture
widgets + iOS photo-library permission.)

---

## 13. Exact recommended next step

**Review and merge `feature/firestore-persistence` into `main`** (the branch must be merged
separately, by decision — not automatically). The Firestore persistence milestone is complete
and verified (analyze clean, 93 tests, rules deployed); the branch is 6 commits ahead of
`main` and has not been pushed.

**Then verify live, on a device** (this is the one thing automated tests can't cover, and it
shares the auth milestone's still-open manual setup):
1. In the **Firebase Console** (project `zivo-63f15`, Authentication → Sign-in method) enable
   **Email/Password**, **Google**, and **Apple**; configure Apple in the Apple Developer
   portal; for Android Google id-tokens pass `--dart-define=GOOGLE_SERVER_CLIENT_ID=<web>`.
2. Sign in on a device/simulator, then exercise each feature (add a task/expense/event/note/
   workout/moment), restart the app, and confirm the data **survives** (reads back from
   Firestore) — and that it is correctly isolated per `uid`.

**After the merge, pick the next milestone** (a decision for the user): **University** (the
last unbuilt life-area module — build it directly against Firestore, using the migrated repos
as the template), the **AI assistant ("Ask")**, or the **Firebase Storage** surface (V1.5),
which also unlocks real Moments photos.

**Do not** re-migrate any repository, change the repository interfaces/entities, re-deploy the
same rules, or build Firebase Storage/photo upload on this branch — the persistence milestone
is done and deliberately scoped.

---

## 14. Test / analyze status

As of 2026-08-15 (after the Firestore persistence milestone — all six feature repos migrated):

- `flutter analyze` → **No issues found.** (`analysis_options.yaml` now excludes `build/**` so
  vendored Firebase iOS/macOS SPM sources don't pollute analysis.)
- `flutter test` → **all tests pass (93)** (was 63 before this milestone). New coverage: one
  `firestore_*_repository_test.dart` per feature — `tasks/`, `expenses/`, `schedule/`, `notes/`,
  `workout/`, `moments/` — each exercising add/field-mapping, ordering, the per-feature wrinkle
  (enum round-trip, embedded exercises, domain-timestamp round-trip, nullable fields), and the
  signed-out empty/guard path, all via `fake_cloud_firestore` + a plain injected `UidSource`
  (no FirebaseAuth mock). The boot `widget_test.dart` now injects in-memory repos for all six
  features so it stays Firebase-free.
- **Firestore security rules deployed** to `zivo-63f15` (`firebase deploy --only
  firestore:rules`): owner-only rules with field validation for all six subcollections.
- **Since then (later branches, not yet merged into `main`):**
  - `feature/university` — the **University** feature shipped (7th collection
    `universityItems`); `flutter test` is now **110** and `flutter analyze` stays clean.
  - `feature/security-rules-tests` — **emulator-based Firestore security-rules tests** added
    under `firestore-tests/` (Node + `@firebase/rules-unit-testing`, **37 tests, all pass**):
    deny-by-default, per-user ownership isolation, per-collection field validation for all
    seven collections, and the `emailOtps` client lockout. Run from the repo root with
    `firebase emulators:exec --only firestore --project demo-zivo "npm --prefix firestore-tests
    test"`. This is the plan's "rules are tested code" privacy guarantee (§20/§28); it is NOT
    part of the Flutter `flutter test` run.
- **Not covered by automated tests / not verified:** live on-device Firestore read/write
  (needs a signed-in `uid` → the same manual Auth-provider enablement, §7/§13). Platform builds
  (Android APK / iOS simulator) were last verified during the auth milestone and are unaffected
  by this data-layer-only change.

Test files (`test/`):
- `widget_test.dart` — app boot (via `test/support/test_app.dart`, authenticated fake).
- `auth/auth_gate_test.dart` — Splash → Auth → Home as `AuthState` changes.
- `auth/auth_page_test.dart` — create-account toggle, email-failure error, provider
  cancellation shows no error, `AuthActionButton` spinner blocks taps while loading.
- `auth/auth_failure_test.dart` — pure `mapAuthErrorCode` mapping.
- `support/fake_auth_repository.dart`, `support/test_app.dart` — test scaffolding.
- `workout_domain_test.dart`, `workout_repository_test.dart`,
  `workout_history_page_test.dart` — Workout coverage (unchanged).

> Coverage is strongest on Workout and the Today boot path. Expenses/Tasks/Schedule/
> Notes/Moments rely on the app-boot widget test and their in-memory repos; dedicated
> tests for those are **not yet** written (a reasonable place to backfill).

---

## 15. Important files and entry points

| Path | Role |
|---|---|
| `lib/main.dart` | Entry point → `ensureInitialized()` + `await Firebase.initializeApp()` → `runApp(ZivoApp())`. |
| `lib/firebase_options.dart` | Hand-authored `DefaultFirebaseOptions` (iOS) from the verified `GoogleService-Info.plist`. Regenerate via `flutterfire configure` when the CLI can discover the project. |
| `ios/Runner/GoogleService-Info.plist` | Firebase config for the registered iOS app; bundled into the Runner target. |
| `lib/app/app.dart` | Root: instantiates the 6 in-memory repos, provides `AppScope`, `MaterialApp` (`AppTheme.light`, `home: HomeShell`). |
| `lib/core/scope/app_scope.dart` | DI seam (`AppScope.of(context)`). **Add new repos here.** |
| `lib/features/shell/presentation/home_shell.dart` | 4-tab `IndexedStack` (Today, Hub, Ask, You) + Quick Capture routing. |
| `lib/features/capture/presentation/quick_capture_sheet.dart` | `CaptureChoice` enum + the capture sheet. |
| `lib/features/capture/presentation/widgets/capture_widgets.dart` | Shared `CaptureTopBar` / `PillButton` / `SelectChip`. |
| `lib/features/home/presentation/pages/today_page.dart` | Today surface + its reactive sections. |
| `lib/features/home/data/today_demo_data.dart` | Remaining hardcoded Today demo data. |
| `lib/features/hub/presentation/hub_page.dart` | Module launcher; where tiles go live. |
| `lib/core/theme/*` | Design system tokens. |
| `docs/PLAN.md` | Long-term aspirational architecture (Firebase/AI/etc.). |
| `docs/UX_BLUEPRINT.md`, `docs/ZIVO-brand-system.md`, `docs/mockups/` | Design intent. |
| `docs/CHANGELOG.md` | Chronological milestone log. |

Any feature under `lib/features/<x>/` is the reference template — Workout, Notes, and
Moments are the cleanest current examples.

---

## 16. Explicit constraints — things that must NOT be changed (without a deliberate decision)

- **Do not break the repository seam.** Keep every repo an `abstract interface class`
  with an in-memory impl provided via `AppScope`, exposing `current` / `watchAll()` /
  `add()`. This is the backend swap point.
- **Do not silently swap the foundation.** No introducing `get_it`, `go_router`, Cubit/
  bloc/riverpod/provider, or Firebase as a side effect of feature work. Those are a
  distinct, explicitly-approved milestone.
- **Do not add dependencies casually.** "Every abstraction pays rent." The only non-trivial
  runtime deps today are `google_fonts` and `image_picker`.
- **Do not violate the design system.** Respect hue ownership (Ember = Now/Next + the one
  primary action), the spacing/radius/typography tokens, and the shared capture widgets.
- **Do not present in-memory/demo data as persistent.** Keep documenting clearly what is
  live vs. seeded/demo.
- **Do not change Today's "Training" card semantics** (planned vs. logged) without deciding
  the model first (§8.6, §9.3).
- **Do not treat `docs/PLAN.md` as the current state** — it is the plan, not the build.
- **This task adds no product features and no behavior changes** — documentation only.
