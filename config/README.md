# `config/` — per-configuration dart-defines

These JSON files hold **non-secret** environment values, passed at build time via
`--dart-define-from-file=config/<env>.json` and read through
[`AppEnvironment`](../lib/core/env/app_environment.dart).

| File | Used by | Committed? |
|------|---------|------------|
| `development.json` | Development (debug) run | yes |
| `profile.json`     | Profile run — **the M7 profiling config** | yes |
| `release.json`     | Release build | yes |
| `local.json`       | Per-developer overrides (App Check debug token) — loaded by the Development launch config **after** `development.json` | **no — git-ignored** |
| `local.example.json` | Template to copy to `local.json` | yes |

## Keys

| Key | Type | Meaning |
|-----|------|---------|
| `USE_FIRESTORE` | bool | Persist to Firestore (`false` = in-memory/offline dev). |
| `FORCE_APP_CHECK_DEBUG` | bool | **Diagnostic only** — force App Check debug providers even in Profile. Leave `false` for real M7 runs so attestation stays production-like. |
| `APP_CHECK_DEBUG_TOKEN` | string | **`local.json` only.** A fixed App Check *debug* token so debug builds attest with a stable token across reinstalls (no per-install churn). Register the same value in Firebase Console → App Check → Manage debug tokens, for **both** the Android and iOS apps. Empty/unset → the SDK generates and logs a per-install token instead. Read by `AppEnvironment.appCheckDebugToken`. |

## Fixed App Check debug token (reliable dev)

1. Copy the template: `cp config/local.example.json config/local.json`.
2. Put a stable UUID in `local.json`'s `APP_CHECK_DEBUG_TOKEN` (any v4 UUID).
3. Register that **exact** value in Firebase Console → App Check → Apps →
   (Android app) → ⋮ → **Manage debug tokens** → Add, and again for the iOS app.
4. Run the **Development (debug)** launch config (which loads `local.json`), or
   pass `--dart-define=APP_CHECK_DEBUG_TOKEN=<uuid>` manually.

Because the token is compile-time, it survives uninstalls/reinstalls — register
once and it keeps working. `local.json` is git-ignored so the token never lands
in source.

## No secrets in the committed files

`development.json` / `profile.json` / `release.json` / `local.example.json` are
committed and must never contain secrets (API keys, tokens, private keys) — they
hold feature flags and public identifiers only. The App Check debug token lives
**only** in the git-ignored `local.json`. Real Firebase credentials live in the
platform config files (`android/app/google-services.json`,
`ios/Runner/GoogleService-Info.plist`), which are Firebase **client** config —
public by design, not secret.
