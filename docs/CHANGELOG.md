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

## Authentication milestone — real sign-in foundation (2026-08-15)

> Isolated on branch **`feature/authentication`** (not merged). Scope: **real
> authentication + a clean user-identity foundation only.** No Firestore,
> persistence migration, Storage, Functions, AI, or University work — the six
> in-memory repositories are deliberately untouched.

**Providers:** Sign in with Apple, Sign in with Google, and Email/Password
(normal Firebase email/password; Gmail addresses are ordinary email/password
accounts, *not* a separate provider).

**Dependencies added:** `firebase_auth`, `google_sign_in`, `sign_in_with_apple`,
`crypto`.

**Dart layer (`lib/features/auth/`):**
- Domain: `AuthUser`, `AuthState` (`AuthUnknown`/`Unauthenticated`/`Authenticated`),
  `AuthResult` (`AuthSuccess`/`AuthCancelled`/`AuthFailed`), `AuthFailure` +
  `AuthRepository` interface + pure `mapAuthErrorCode` error mapping.
- Data: `FirebaseAuthRepository` (email sign-in/up, Google via `google_sign_in`
  7.x, Apple with SHA-256 nonce, Firebase-user→`AuthUser` mapping, provider
  cancellation handling) and `FakeAuthRepository` for tests. `AuthConfig` reads an
  optional Google **web** `serverClientId` from `--dart-define=GOOGLE_SERVER_CLIENT_ID`.
- Presentation: `AuthGate` (Splash → AuthPage → app shell driven by `watchAuthState`),
  `SplashScreen`, `AuthPage` (Apple/Google buttons + email/password + create-account
  toggle, loading/error states), `ProfilePage` with sign-out (replaces the old "You"
  placeholder).
- Wiring: `auth` added to `AppScope`; `ZivoApp` uses the real `FirebaseAuthRepository`
  and `home: AuthGate`.

**Platform / native configuration:**
- Bundle id changed `com.example.zivo` → **`com.ziadelsewedy.zivo`** (iOS + Android).
- Registered **new** Firebase apps in project `zivo-63f15` for the new bundle:
  iOS `1:317167114617:ios:fb766e1151cf147755f7a8`, Android
  `1:317167114617:android:e4fd2ec7f3ae385855f7a8` (via `firebase apps:create`;
  `flutterfire configure` then regenerated `lib/firebase_options.dart`, `firebase.json`,
  and the macOS config). Downloaded fresh `ios/Runner/GoogleService-Info.plist` and
  `android/app/google-services.json` for the new bundle.
- iOS: `Runner.entitlements` (Apple Sign-In capability) + `CODE_SIGN_ENTITLEMENTS`
  wired into all Runner build configs; `DEVELOPMENT_TEAM = 7Q3PY75VGH`; added the
  Google `REVERSED_CLIENT_ID` URL scheme to `Info.plist` (for the Google redirect).
- Android: `namespace`/`applicationId = com.ziadelsewedy.zivo`, `minSdk ≥ 23`,
  `com.google.gms.google-services` plugin applied, Kotlin `MainActivity` moved to the
  new package.

**Verification (this session):**
- `flutter analyze` → **no issues**.
- `flutter test` → **24 tests pass** (auth gate/page/failure + support fakes added to
  the prior suite).
- **Android** `flutter build apk --debug` → **succeeds** (previously impossible: the
  google-services plugin had no `google-services.json`).
- **iOS** `flutter build ios --debug --simulator` → **succeeds** (`pod install` pulls
  firebase_auth/google_sign_in/sign_in_with_apple pods).
- **Runtime smoke test** (iPhone 17 Pro simulator): app launches on
  `com.ziadelsewedy.zivo`, Firebase Core initializes, `AuthGate` resolves to
  `Unauthenticated`, and the real `AuthPage` renders all three sign-in options.

**NOT verified end-to-end (requires manual, non-headless steps):** actually completing
Apple / Google / email sign-in. Remaining manual setup: enable **Email/Password**,
**Google**, and **Apple** providers in the Firebase Console (Authentication → Sign-in
method); configure Apple (Service ID + Sign in with Apple key) in the Apple Developer
portal; for Android Google id-tokens, pass the web `serverClientId` via
`--dart-define=GOOGLE_SERVER_CLIENT_ID`. No provider is claimed to work end-to-end until
tested on a real device/simulator with those enabled.

## App-identity milestone — launcher icon (2026-08-15)

> Isolated on branch **`feature/app-identity`** (cut from `planning-setup`, **not merged**).
> Independent of the auth branch; contains no auth code and keeps the base `com.example.zivo`
> bundle. Scope: **app launcher icon / brand identity only.**

- Added the ZIVO brand asset set under `assets/` (`app-icon/`, `rounded/`, `transparent/`,
  `svg/`, `README.txt`) — colours: Paper `#F4F2ED` · Ink `#0B0C0D` · Dark `#101317` ·
  Ember `#FF5A1F`.
- Chose the **Dark** finish (paper Z on `#101317`) as the app identity. Added
  `flutter_launcher_icons` (dev dep) + config in `pubspec.yaml`; `dart run
  flutter_launcher_icons` regenerated the iOS `AppIcon.appiconset` and Android mipmaps +
  an **adaptive icon** (`#101317` background + dark square inset foreground; `colors.xml`
  added). Set the real app `description` in `pubspec.yaml`.
- **Verification:** `flutter analyze` clean; base `flutter test` (12) pass; iOS simulator
  build + install → the Dark icon renders on the home screen; Android debug APK builds.
- **Handoff:** see the **Current Handoff** section at the top of `docs/PROJECT_CONTEXT.md`
  — two milestones (`feature/authentication`, `feature/app-identity`) are complete and
  await the user's separate review/merge.
