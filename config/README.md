# `config/` — per-configuration dart-defines

These JSON files hold **non-secret** environment values, passed at build time via
`--dart-define-from-file=config/<env>.json` and read through
[`AppEnvironment`](../lib/core/env/app_environment.dart).

| File | Used by |
|------|---------|
| `development.json` | Development (debug) run |
| `profile.json`     | Profile run — **the M7 profiling config** |
| `release.json`     | Release build |

## Keys

| Key | Type | Meaning |
|-----|------|---------|
| `USE_FIRESTORE` | bool | Persist to Firestore (`false` = in-memory/offline dev). |
| `USE_FIREBASE_EMULATOR` | bool | Route Firebase at the local Emulator Suite instead of the live backend (debug/profile only; ignored in release). Passed by `make dev-emulator`, not baked into these files. |
| `FIREBASE_EMULATOR_HOST` | string | Override the emulator host — needed for a physical device (your machine's LAN IP). Defaults: `10.0.2.2` on Android emulator, `localhost` elsewhere. |

See [`docs/build_configurations.md`](../docs/build_configurations.md#demo--experimentation-environment--the-emulator-suite)
for the demo/experimentation workflow.

## No secrets here

These files are committed and must never contain secrets (API keys, tokens,
private keys). They hold feature flags and public identifiers only. Real
Firebase credentials live in the platform config files
(`android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`),
which are Firebase **client** config — public by design, not secret.
