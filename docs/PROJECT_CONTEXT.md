# ZIVO — Project Context

> **Purpose of this file.** A single, canonical, self-contained snapshot so a new
> Claude session (or developer) can understand ZIVO without replaying its history.
> **The codebase is the source of truth.** Where this file and `docs/PLAN.md`
> disagree, the code wins — `PLAN.md` is the *aspirational* architecture; this file
> describes what is *actually built today*.
>
> **Last verified against the codebase:** 2026-08-15 (after connecting Firebase Core).

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
| Persistence | **None — all data is in-memory and resets on restart.** No local DB. **Firebase Core is now initialized** (app connects to the `zivo-63f15` project), but **no Firestore/Auth/Storage and no data is persisted** — the repository layer is still fully in-memory. |
| Firebase | **`firebase_core` only.** Initialized in `main.dart` via `DefaultFirebaseOptions` (`lib/firebase_options.dart`). iOS app registered (`GoogleService-Info.plist` bundled in the Runner target). **No Firestore/Auth/Storage/Functions yet.** |
| Fonts | `google_fonts`: **Bricolage Grotesque** (display) + **Hanken Grotesk** (text). |
| Other deps | `image_picker ^1.2.3` (Moments photos), `firebase_core ^4.1.1` (Firebase Core only, resolves to 4.13.0), `cupertino_icons`. |
| Lints | `flutter_lints ^6.0.0` via `analysis_options.yaml` (default rule set). |

> Firebase **Core** is now connected (see §7). Anything involving **Firestore, Auth,
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
| **You (Profile/Settings)** | ⛔ | `ComingSoon('You')` tab placeholder. |

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

**Firebase Core is connected; there is still no persistence.** As of 2026-08-15 the app
initializes **`firebase_core` only** — on launch it calls `Firebase.initializeApp()`
(with `DefaultFirebaseOptions.currentPlatform`) and connects to the **`zivo-63f15`**
Firebase project. That is the *entire* Firebase footprint so far.

**Still NOT implemented:** Firestore, Authentication, Storage, Cloud Functions, any
network/data layer, and any migration of the repositories to a real backend. **All data
still lives in memory and is lost on app restart** — seed data reappears on each launch.
No repository has been changed; the in-memory implementations remain the only ones.

The repository interfaces remain the seam through which a real backend (per
`docs/PLAN.md`: Firebase/Firestore) will later be introduced **without changing
presentation code**. Connecting Firebase Core is the first, deliberately isolated step of
that foundation work — it adds no product behavior and touches no feature/UI code.

**iOS integration:** `ios/Runner/GoogleService-Info.plist` (for the registered iOS app,
bundle `com.example.zivo`) is bundled into the Runner target's Resources. `firebase_core`
required raising the iOS deployment target to **15.0** (Podfile + Xcode project).
`lib/firebase_options.dart` was authored by hand from the verified plist because the
FlutterFire CLI currently cannot discover the project on this machine (the underlying
Firebase CLI can); regenerate it with `flutterfire configure` once the CLI can see the
project.

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

**Feature-completeness of the core life-area modules, in-memory.** With Workout done,
the built set is: Expenses, Tasks, Schedule, Notes, Moments, Workout (+ the Today
aggregation surface, Hub, and Quick Capture). University is the remaining core module
before the persistence milestone.

---

## 12. Last completed work

**Firebase Core connected (2026-08-15).**
- Added `firebase_core` (only) to `pubspec.yaml`.
- Authored `lib/firebase_options.dart` by hand from the verified
  `GoogleService-Info.plist` (FlutterFire CLI cannot currently discover the project).
- `main.dart` now `WidgetsFlutterBinding.ensureInitialized()` +
  `await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` before
  `runApp`.
- Registered `GoogleService-Info.plist` in the iOS Runner target (Resources build phase);
  raised the iOS deployment target to 15.0 (Podfile + Xcode project) as `firebase_core`
  requires.
- **No** Firestore/Auth/Storage/Functions, **no** persistence, **no** repository changes,
  **no** UI/feature changes.
- **Verification:** `flutter analyze` → no issues; `flutter test` → 12 tests pass; iOS
  simulator build succeeds, the plist is bundled into `Runner.app`, and the app launches
  and renders Today (proving `Firebase.initializeApp()` completes before `runApp`).

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

**Build the University feature as an in-memory vertical slice**, mirroring the existing
pattern exactly:

- `features/university/domain/` — a `Course` and/or `Assignment`/`Deadline` entity + an
  `abstract interface class UniversityRepository` (`current` / `watchAll()` / `add()`),
  plus pure helpers if any date logic is needed (take `now` as a parameter).
- `features/university/data/in_memory_university_repository.dart` — seeded, newest/soonest
  first, broadcast controller.
- Presentation: a capture page (Iris-themed — `AppColors.iris`) and a list page.
- Wiring: add `university` to `AppScope` + `app.dart` (+ `updateShouldNotify`); make the
  Hub "University" tile live; optionally add a Quick Capture choice.
- **Integration:** replace the hardcoded university deadline in `today_demo_data.dart` /
  `buildFocus` with live data from the new repository (this removes a piece of Today's
  demo data — a real win for the "one connected system" principle).
- Tests: domain/format + repository + a page render test, matching the Workout test set.

> Alternative strategic pivot (a **decision for the user**, not a default): if the goal is
> to make the app durable rather than more feature-complete, the next milestone could
> instead be **persistence/foundation** (§10.2). Do not start that without an explicit
> decision — it changes DI, navigation, and state-management foundations.

**Do not begin any new feature or the foundation work until the user confirms direction.**

---

## 14. Test / analyze status

As of 2026-08-15 (after connecting Firebase Core):

- `flutter analyze` → **No issues found.**
- `flutter test` → **all tests pass (12).**
- iOS simulator build (`flutter build ios --debug --simulator`) → **succeeds**; the app
  launches and initializes Firebase Core without error. (Tests do not call `main()`, so
  they do not initialize Firebase.)

Test files (`test/`):
- `widget_test.dart` — Today renders greeting + key sections (boots the full `ZivoApp`).
- `workout_domain_test.dart` — `setRepLabel`, `workoutMeta`, `Workout` getters.
- `workout_repository_test.dart` — seed, newest-first insert, unmodifiable `current`,
  stream emission order.
- `workout_history_page_test.dart` — history renders seed + reacts to a new workout.

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
