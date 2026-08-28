# STATE — where ZIVO is right now

> **The single source of truth for "current state."** Small on purpose. Read it every
> session; update it when you finish a task. For *what ZIVO is + what makes it different*
> see [`PRODUCT.md`](PRODUCT.md); for *how the code is organized* see
> [`/AGENTS.md`](../AGENTS.md) and each feature's `FEATURE.md`; for *why* decisions were
> made, see [`DECISIONS/`](DECISIONS). The **code is the ultimate source of truth** — if
> this file disagrees with the code, fix this file.

**Last updated:** 2026-08-28 · **Active branch:** `claude/workout-tracking-design-05babf`
(off `version-1`; `version-1` is 26 commits ahead of `main`).

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
  - **Pending now:** the Ask **edit/delete-expense** tools (ADR-005 — `mutations.js`, `store.js`,
    `gateway.js`, `tools.js`) are code-complete + tested but **not deployed**. Until deployed the
    live AI keeps the old create-only backend (the app's redesigned cards already render
    edit/delete proposals once the backend proposes them). Command: `firebase deploy --only functions`.
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

---

### Update log (newest first — one line per session)
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
