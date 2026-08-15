# ZIVO — Changelog

Chronological log of meaningful milestones, architectural decisions, completed
features, and verification results. Intentionally concise — not a commit-by-commit
history. Newest last within each phase; see `docs/PROJECT_CONTEXT.md` for the current
state.

> **Status of the whole project so far:** a UX-first prototype. Every feature is a full
> `domain → data → presentation` vertical slice backed by **in-memory** repositories.
> **No backend or persistence exists yet** — data resets on restart.

---

## Design foundation

- Adopted the **light & warm direction (Brand System v2)**: warm off-white surfaces,
  meaning-carrying hues (ember/pulse/solar/iris/flare), two Google fonts (Bricolage
  Grotesque + Hanken Grotesk).
- Implemented the **design system** (`core/theme/`: colors, typography, spacing, shadows,
  motion) and the **Today** command surface.
- Produced high-fidelity Today mockups (morning + states) under `docs/mockups/`.
- **Decision:** UX-first, in-memory-first — build polished feature verticals before
  introducing Firebase/persistence.

## Core architecture conventions locked

- Established the **repository seam**: `abstract interface class` + in-memory impl
  (`current` / `watchAll()` / `add()`, broadcast stream, seeded demo data), provided via
  the **`AppScope` `InheritedWidget`** (lightweight DI).
- Reactive UI via `StreamBuilder`; **pure, testable builders** take `now` as a parameter.
- Shared capture UX (`CaptureTopBar` / `PillButton` / `SelectChip`); one Quick Capture
  sheet as the single capture verb.

## Features — first wave

- **Expenses:** end-to-end capture (custom amount keypad + category chips); Today
  "Spending" glance reads live from the expense repository.
- **Tasks:** end-to-end quick-create + complete-toggle; Today "Focus/Today" list reads
  live from the task repository (merged with a demo university deadline via `buildFocus`).

## Features — second wave (Schedule, Notes, Moments)

- **Schedule / Event:** event capture; Today **"Now · Next"** now reads live from the
  schedule repository (pure `event_time` formatter + `now_next_builder`); empty-state
  handling on the Now/Next card.
- **Notes:** entity + repository + capture + list, reached through the new **Hub** launcher;
  `time_ago` relative-time helper.
- **Moments:** entity + repository + capture (optional photo via **`image_picker`**) +
  timeline, via Hub.
- Added the **Hub** module launcher and wired all five Quick Capture choices.
- Added the iOS **`NSPhotoLibraryUsageDescription`** for `image_picker`.
- **Verification:** `flutter analyze` clean; test suite green.

## Workout (2026-08-15)

- **Workout feature, end-to-end:**
  - Domain: `Exercise`, `Workout` (`exerciseCount` / `summary`), pure `workout_format`
    (`setRepLabel`, `workoutMeta`), `WorkoutRepository`.
  - Data: `InMemoryWorkoutRepository` (seeded "Push" session, newest-first).
  - Presentation: `WorkoutCapturePage` (Pulse-themed; name + add-exercise sheet) and
    `WorkoutHistoryPage` (reactive history, Pulse FAB).
  - Wiring: added to `AppScope` + `app.dart`; Hub "Workout" tile made live; sixth Quick
    Capture choice ("Workout logged" toast).
- **Decision:** kept Today's "Training" card as demo — it models a *planned* session and
  is deliberately distinct from logged Workout *history* (no plan/template source yet).
- **Verification:** `flutter analyze` → no issues; `flutter test` → 12 tests pass
  (added `workout_domain_test`, `workout_repository_test`, `workout_history_page_test`).

## Project context system (2026-08-15)

- Added `docs/PROJECT_CONTEXT.md` (canonical, self-contained project snapshot) and this
  `docs/CHANGELOG.md`.
- Documentation only — no product features added, no application behavior changed.
- Verified the context against the codebase: state as above; `flutter analyze` clean and
  all 12 tests passing at time of writing.

## Firebase Core connected (2026-08-15)

- **First step of the foundation/persistence milestone — Firebase Core only.** The app
  now connects to the **`zivo-63f15`** Firebase project.
  - Added `firebase_core` (only) to `pubspec.yaml` (resolves to 4.13.0).
  - `main.dart`: `WidgetsFlutterBinding.ensureInitialized()` +
    `await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` before
    `runApp`.
  - Added `lib/firebase_options.dart`, **authored by hand** from the verified
    `ios/Runner/GoogleService-Info.plist` because the FlutterFire CLI cannot currently
    discover the project (the underlying Firebase CLI can). Regenerate with
    `flutterfire configure` once the CLI can see it.
  - iOS: registered `GoogleService-Info.plist` in the **Runner target** (Resources build
    phase) and raised the **iOS deployment target to 15.0** (Podfile + Xcode project), as
    required by `firebase_core`. `pod install` pulls Firebase Apple SDK 12.17.0.
- **Explicitly NOT done (still planned):** Firestore, Auth, Storage, Cloud Functions, any
  persistence, and any migration of the in-memory repositories to a real backend. **No
  repository, feature, or UI code changed** — data still resets on restart.
- **Verification:** `flutter analyze` → no issues; `flutter test` → 12 tests pass; iOS
  simulator build succeeds with the plist bundled into `Runner.app`; the app launches and
  renders Today, confirming Firebase Core initializes before `runApp`.
