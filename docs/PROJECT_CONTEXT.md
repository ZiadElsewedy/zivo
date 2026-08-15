# ZIVO — Project Context

> **Purpose of this file.** A single, canonical, self-contained snapshot so a new
> Claude session (or developer) can understand ZIVO without replaying its history.
> **The codebase is the source of truth.** Where this file and `docs/PLAN.md`
> disagree, the code wins — `PLAN.md` is the *aspirational* architecture; this file
> describes what is *actually built today*.
>
> **Last verified against the codebase:** 2026-08-15 (after the **Authentication
> milestone** — real Apple/Google/Email sign-in — on branch `feature/authentication`).

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
| Persistence | **None — all *feature* data is in-memory and resets on restart.** No local DB, no Firestore. Auth **session** is persisted by Firebase (survives restart), but no feature/domain data is. The six feature repositories are still fully in-memory. |
| Firebase | **`firebase_core` + `firebase_auth`.** Initialized in `main.dart` via `DefaultFirebaseOptions` (`lib/firebase_options.dart`, now full FlutterFire output: web/android/ios/macos/windows). iOS + Android apps registered in `zivo-63f15` for bundle **`com.ziadelsewedy.zivo`**. **No Firestore/Storage/Functions yet.** |
| Fonts | `google_fonts`: **Bricolage Grotesque** (display) + **Hanken Grotesk** (text). |
| Other deps | `image_picker ^1.2.3` (Moments photos), `firebase_core ^4.1.1`, `firebase_auth ^6.5.7`, `google_sign_in ^7.2.0`, `sign_in_with_apple ^8.1.0`, `crypto ^3.0.7`, `cupertino_icons`. |
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
| **Expenses** | ✅ | Capture (custom keypad + category chips); feeds Today "Spending". In-memory. |
| **Tasks** | ✅ | Quick-create; toggle done; feeds Today "Today/Focus" list. In-memory. |
| **Schedule / Event** | ✅ | Event capture; feeds Today "Now · Next" reactively. In-memory. |
| **Notes** | ✅ | Capture + list; reachable via Hub. In-memory. |
| **Moments** | ✅ | Capture (optional photo via `image_picker`) + timeline; via Hub. In-memory. |
| **Workout** | ✅ | Capture (name + add-exercise sheet) + history; via Hub. In-memory. **Most recent feature.** |
| **Hub (launcher)** | ✅ | Grid of modules. Live tiles: Notes, Moments, Workout. "Soon" tiles: Schedule, Tasks, Expenses, University. |
| **Quick Capture** | ✅ | Bottom sheet → 6 choices: Expense, Task, Event, Note, Moment, Workout. |
| **University** | ⛔ | Not built. "Soon" tile only; one demo deadline hardcoded into Today's focus. |
| **Ask (AI assistant)** | ⛔ | `ComingSoon('Ask')` tab placeholder. |
| **You (Profile)** | 🟡 | Now `ProfilePage` (shows the signed-in `AuthUser`, sign-out). Replaced the old `ComingSoon('You')`. Settings not built. |
| **Authentication** | ✅ | Real Firebase Auth — Apple, Google, Email/Password — behind `AuthGate`. Session persists across restart; sign-out works. Provider end-to-end sign-in pending Console/Apple-Developer enablement (see §7). |

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

Six repositories, **all in-memory**, provided through `AppScope`:

| Repository | Interface | In-memory impl | Extra mutators |
|---|---|---|---|
| `ExpenseRepository` | expenses/domain | `InMemoryExpenseRepository` | — |
| `TaskRepository` | tasks/domain | `InMemoryTaskRepository` | `setDone(id, done)` |
| `ScheduleRepository` | schedule/domain | `InMemoryScheduleRepository` | + free fn `nextRelevant()` |
| `NoteRepository` | notes/domain | `InMemoryNoteRepository` | — |
| `MomentRepository` | moments/domain | `InMemoryMomentRepository` | — |
| `WorkoutRepository` | workout/domain | `InMemoryWorkoutRepository` | — |

Each is seeded with demo content and stores newest-first (schedule sorts by start time
via `nextRelevant`). All share the `current` / `watchAll()` / `add()` shape.

---

## 7. Backend / persistence status

**Firebase Core + Auth are wired; there is still no *data* persistence.** On launch the
app calls `Firebase.initializeApp()` (with `DefaultFirebaseOptions.currentPlatform`) and
connects to the **`zivo-63f15`** project, then `AuthGate` gates the UI on
`AuthRepository.watchAuthState()`. **Firebase Auth is the entire cloud *usage* so far** —
it persists the auth **session** (a signed-in user survives an app restart) but stores no
feature/domain data.

**Authentication (implemented):** three providers behind the `AuthRepository` seam —
**Sign in with Apple** (native, SHA-256 nonce), **Sign in with Google**
(`google_sign_in` 7.x), and **Email/Password** (normal Firebase email/password; Gmail
addresses are ordinary email/password accounts, *not* a separate provider). The signed-in
`uid` is the app's canonical user identity — the key the future Firestore layer will scope
data by. See `lib/features/auth/`.

**Still NOT implemented:** Firestore, Storage, Cloud Functions, and any migration of the
six feature repositories to a real backend. **All feature data still lives in memory and
is lost on app restart** — seed data reappears each launch. No feature repository has
changed; the in-memory implementations remain the only ones.

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

1. **No persistence** (see §7) — the single biggest gap; everything resets on restart.
2. **`dispose()` on in-memory repos is never called.** `ZivoApp` (a `StatefulWidget`)
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

The proven pattern is: **finish the feature verticals in-memory, then introduce the real
backend.** Remaining, roughly in order:

1. **University** — the last unbuilt life-area module (currently a "soon" Hub tile and one
   hardcoded Today deadline). Build it as a vertical slice like the others.
2. **Foundation / persistence** — replace in-memory repos with a real backend behind the
   existing interfaces (Firebase/Firestore per `docs/PLAN.md`), add auth, and (per plan)
   migrate DI → `get_it`, navigation → `go_router`, state → Cubits **as a deliberate
   decision**, not incidentally.
3. **AI assistant ("Ask")** and **Profile ("You")** — currently placeholder tabs.
4. Later (V1.5+ in `docs/PLAN.md`): PDF → workout import, richer AI actions, polish.

> `docs/PLAN.md` is the detailed long-term plan; note it *defers* Moments to V1.5, but
> Moments is already built — another reason the codebase, not the plan, is authoritative.

---

## 11. Current milestone

**Authentication + clean user-identity foundation** (branch `feature/authentication`,
not yet merged). Real Firebase Auth with Apple, Google, and Email/Password behind an
`AuthRepository` seam, gated by `AuthGate`; the signed-in `uid` is the app's canonical
identity. Deliberately scoped: **no** Firestore/persistence migration, Storage, Functions,
AI, or University in this milestone — the six feature repositories stay in-memory. The
Dart layer, both platform builds, and the launch→sign-in-screen render path are verified;
real provider sign-in awaits Console/Apple-Developer enablement (§7, §14).

The prior milestone — **feature-completeness of the core life-area modules, in-memory**
(Expenses, Tasks, Schedule, Notes, Moments, Workout + Today, Hub, Quick Capture) — remains
done; **University** is still the one unbuilt core life-area module.

---

## 12. Last completed work

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

**Finish verifying the Authentication milestone, then review/merge
`feature/authentication`** (the branch must be merged separately, by decision — not
automatically):

1. In the **Firebase Console** (project `zivo-63f15`, Authentication → Sign-in method)
   enable **Email/Password**, **Google**, and **Apple**.
2. In the **Apple Developer** portal configure Sign in with Apple (Service ID + key) and
   add it to the Firebase Apple provider.
3. For Android Google id-tokens, supply the web `serverClientId` via
   `--dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>`.
4. Test each provider end-to-end on a real device/simulator: sign in → app shell,
   restart → session persists, `ProfilePage` → sign-out → back to `AuthPage`.
5. Only then merge `feature/authentication`.

**After auth is merged — Firestore persistence keyed by the auth `uid`** (§10.2): migrate
the six feature repositories from in-memory to Firestore *behind their existing
interfaces*, scoping all data by the signed-in user. This is the natural next milestone and
the whole reason the auth/identity foundation came first.

> University (the last unbuilt life-area module, in-memory) remains a valid alternative if
> the goal is more feature-completeness before persistence — a **decision for the user**.

**Do not begin Firestore, University, or any new feature on this branch** — keep
`feature/authentication` scoped to auth only.

---

## 14. Test / analyze status

As of 2026-08-15 (after the Authentication milestone):

- `flutter analyze` → **No issues found.**
- `flutter test` → **all tests pass (24).**
- **Android** build (`flutter build apk --debug`) → **succeeds** (google-services.json now
  present, so the plugin resolves).
- **iOS** simulator build (`flutter build ios --debug --simulator`) → **succeeds**;
  `pod install` pulls the firebase_auth/google_sign_in/sign_in_with_apple pods.
- **Runtime smoke test** (iPhone 17 Pro simulator): app launches on
  `com.ziadelsewedy.zivo`, Firebase initializes, `AuthGate` → `Unauthenticated` → real
  `AuthPage` renders all three sign-in options. (Tests do not call `main()`, so they do not
  initialize Firebase; the auth tests use `FakeAuthRepository`.)
- **Not covered by automated tests / not verified:** actually completing Apple/Google/email
  sign-in against the live backend (needs Console + Apple-Developer enablement — §7, §13).

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
