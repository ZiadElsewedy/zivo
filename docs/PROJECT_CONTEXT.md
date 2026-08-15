# ZIVO — Project Context

> **Purpose of this file.** A single, canonical, self-contained snapshot so a new
> Claude session (or developer) can understand ZIVO without replaying its history.
> **The codebase is the source of truth.** Where this file and `docs/PLAN.md`
> disagree, the code wins — `PLAN.md` is the *aspirational* architecture; this file
> describes what is *actually built today*.
>
> **Last verified against the codebase:** 2026-08-15 (after building the **Ask (AI assistant)
> client seam** — part 1 of Phase 9 — on `feature/ai-assistant`; see Current Handoff below.
> Firestore persistence, Authentication, and University are merged into `main`).

---

## Current Handoff

> Cross-account handoff snapshot. A new session MUST read this, then inspect the actual
> git state / diff, recover the exact state, and continue from **Exact next action** —
> without redoing completed work. Active development is on `feature/ai-assistant`.

- **Status (as of 2026-08-15):** Phase 9 part 1 — the **"Ask" AI assistant client seam** — is
  built on `feature/ai-assistant`, following `docs/DECISIONS/ADR-001-ai-assistant.md`'s
  "client seam (buildable now, no key/deploy)" section exactly: `features/ai/` domain +
  a pure in-memory `FakeAiRepository` + an `AskPage` chat UI, replacing the `ComingSoon('Ask')`
  placeholder tab. **No Cloud Function, no Anthropic SDK, no API key, no deploy, no network** —
  this part is offline-only; the server half (the `aiChat` gateway + `FirebaseAiRepository`) is
  explicitly deferred to part 2. **Not yet committed** — all changes are unstaged in the working
  tree, pending review. (The Diet Plan feature, built earlier on this same branch, remains
  unchanged and already merged into this history — see §5/§12 below.)
- **Branch:** `feature/ai-assistant`, checked out and active.
- **What the Ask client seam adds:**
  - **Domain** (`lib/features/ai/domain/`): `AiRole` (`user`/`assistant`/`tool`, safe
    `aiRoleFromName` fallback to `assistant`), `AiMessage` (id/role/content/createdAt),
    `AiConversation` (id/title/createdAt/updatedAt), and `AiRepository` — storage-agnostic
    (`ensureConversation()`, `watchMessages(conversationId)`, `send({conversationId, text})`) so
    the future `FirebaseAiRepository` (Firestore reads + the `aiChat` callable) can implement the
    exact same interface.
  - **Data** (`lib/features/ai/data/fake_ai_repository.dart`): `FakeAiRepository` — pure
    in-memory, broadcast-stream, no Firestore/network. `send()` appends the user's message then
    an **honest** canned assistant reply (`kFakeAiReply`: "The assistant isn't connected yet —
    this is a placeholder reply…"), never masquerading as real AI. Empty/whitespace `send()` is
    a no-op; a monotonic sequence counter guarantees strictly increasing ids/timestamps even for
    the two messages appended in the same call.
  - **Presentation** (`lib/features/ai/presentation/pages/ask_page.dart`): `AskPage` — a
    `StatefulWidget` with a const constructor (so `home_shell`'s `const _tabs` list still
    compiles), its own header (no `AppBar`, matching Today/Hub), an iris-themed message list
    (user bubbles right-aligned/iris-filled, assistant bubbles left-aligned/card-surfaced), an
    empty state ("Ask about your day."), and a pinned composer respecting
    `MediaQuery.viewInsets.bottom`. Calls `ensureConversation()` once (held as a `late final
    Future<String>`, resolved via `AppScope.of(context)` — same lazy-field pattern as
    `app.dart`'s `_ai`), then drives the body off `StreamBuilder<List<AiMessage>>`.
  - **Wiring**: `ai` added to `AppScope` (required field) and `ZivoApp` (optional named param,
    `main.dart`'s `const ZivoApp()` unaffected); `app.dart`'s `_defaultAi()` returns
    `FakeAiRepository()` unconditionally (with a `// TODO(phase9)` marking the future
    `USE_FIRESTORE`-gated swap to `FirebaseAiRepository`); `home_shell.dart`'s `_tabs` now holds
    `AskPage()` instead of `ComingSoon('Ask')` (the now-unused `coming_soon.dart` import was
    dropped from `home_shell.dart`, but the widget file itself is kept in place per the task
    scope); every `AppScope(...)`/`ZivoApp(...)` construction site across `test/` was updated to
    pass `ai: FakeAiRepository()` (verified via `grep -rn "AppScope("/"ZivoApp(" lib test`).
  - **Storage contract (rules only — the fake ignores all of this)**: per ADR-001,
    `users/{uid}/aiConversations/{conversationId}` is **client-writable** (owner
    create/rename, `title`/`schemaVersion` validated); `.../messages/{messageId}` and
    `users/{uid}/aiUsage/{usageId}` are **server-written only** (the future `aiChat` Cloud
    Function via the Admin SDK bypasses rules) — a client may never forge an assistant/tool
    message or its own usage log. Added to `firestore.rules` (three new `match` blocks, deny-by
    -default catch-all comment updated) and to `firestore-tests/rules.test.mjs`: `aiConversations`
    joined the generic ownership+validation loop (valid/invalid maps), and two new dedicated
    `describe` blocks (modelled on the existing `emailOtps` lockout test) assert the owner can
    read a seeded `messages`/`aiUsage` doc but cannot write one, and a different signed-in user
    can't read it either. README updated to describe all ten persisted collections plus the two
    server-only AI collections.
  - **Deliberately deferred** (scope boundary, not an oversight — see ADR-001's action items 3–6):
    the `aiChat` Cloud Function itself (no `functions/` changes), the Anthropic SDK/API key, any
    deploy, `FirebaseAiRepository`, any read-tool implementation (`get_today`, `get_tasks`, …),
    cost/rate limiting, `aiUsage` writes, and App Check. The assistant does **not** work
    end-to-end yet — every reply is the honest canned placeholder.
- **In progress:** nothing.
- **Last completed action:** wrote the Ask client-seam vertical slice (domain/data/presentation +
  `test/ai/*` + the eight DI wiring edits + `firestore.rules` + rules-tests + README) and ran
  `flutter analyze` (clean).
- **Exact next action:** decide on merging `feature/ai-assistant` into `main`. After that, Phase 9
  part 2 — the `aiChat` Cloud Function (JS, v2 `onCall`, `defineSecret`), the read tools, cost/
  iteration ceilings, and `FirebaseAiRepository` — needs the owner's sign-off on ADR-001's four
  open decisions (provider/model, API key, deploy authorization, App Check timing) before it can
  start.
- **Files currently being modified:** none (this slice is complete, pending review/commit).
- **Verification status:** all three gates GREEN (run by the orchestrator on the final diff):
  `flutter analyze` → clean (**No issues found!**); `flutter test` → **141 pass** (was 133 — +8 new
  AI cases across `ai_domain_test.dart`, `fake_ai_repository_test.dart`, `ask_page_test.dart`);
  Firestore emulator rules-tests → **53 pass, 0 fail** (was 45 — +8: the `aiConversations`
  ownership/validation cases from the generic loop plus the dedicated `messages`/`aiUsage` lockout
  cases). The Ask surface is a real, tested chat UI, but every reply is the honest canned placeholder
  — the assistant does not answer over real data until part 2's gateway is built and deployed.
- **Blockers:** none code-side. (Unchanged from before: the OTP sender is still
  `onboarding@resend.dev` in `functions/index.js`.) The *server* half of Phase 9 is blocked on the
  owner per ADR-001 (API key + deploy authorization).
- **Manual user action:** (1) decide on merging `feature/ai-assistant` into `main`; (2) deploy the
  `dietPlans`/`dietEntries` rules from the prior Diet slice and the three new AI rules blocks together
  when ready (`firebase deploy --only firestore:rules --project zivo-63f15`) — none of this branch's
  rules are deployed yet; (3) authorize deploying the (forthcoming) `aiChat` function. The owner has
  already answered ADR-001's provider/model (**Claude Sonnet 5**), set `ANTHROPIC_API_KEY` in Secret
  Manager, and rotated the previously-exposed key — so part 2 (gateway + tools + `FirebaseAiRepository`)
  is unblocked to build; only the deploy authorization + App Check timing remain the owner's call.
- **Do not redo:** don't re-derive the `features/ai/` domain/data/presentation layers or the
  Diet/University patterns they mirror; don't build the `aiChat` Cloud Function,
  `FirebaseAiRepository`, any read tool, or App Check in this slice — all explicitly deferred to
  Phase 9 part 2, which needs the owner's ADR-001 sign-off first.

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
| **Ask (AI assistant)** | 🟡 | Live chat surface (`AskPage`, iris-themed) replacing the `ComingSoon('Ask')` placeholder, backed by an honest in-memory `FakeAiRepository` (canned "not connected yet" replies) — see `docs/DECISIONS/ADR-001-ai-assistant.md`. No Firestore I/O, no gateway; the real `aiChat` Cloud Function + `FirebaseAiRepository` are the next milestone (Phase 9 part 2). |
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
