# STATE — where ZIVO is right now

> **The single source of truth for "current state."** Small on purpose. Read it every
> session; update it when you finish a task. For *what ZIVO is + what makes it different*
> see [`PRODUCT.md`](PRODUCT.md); for *how the code is organized* see
> [`/AGENTS.md`](../AGENTS.md) and each feature's `FEATURE.md`; for *why* decisions were
> made, see [`DECISIONS/`](DECISIONS). The **code is the ultimate source of truth** — if
> this file disagrees with the code, fix this file.

**Last updated:** 2026-08-27 · **Active branch:** `version-1` (26 commits ahead of `main`, 0 behind).

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
- **Manual E2E:** real-PDF-in-app import → review → confirm for both workout and diet.

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
- 2026-08-27 — Added the agent-neutral context system (AGENTS.md router + CLAUDE.md adapter,
  PRODUCT.md positioning, this file, per-feature FEATURE.md maps, ADR-004); repositioned as an
  AI gym tracker; de-stated the reference docs; added the STATE.md freshness pre-commit hook
  (`make hooks`); cleaned up debug-log / Firebase-cache noise.
