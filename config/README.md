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
| `FORCE_APP_CHECK_DEBUG` | bool | **Diagnostic only** — force App Check debug providers even in Profile. Leave `false` for real M7 runs so attestation stays production-like. |

## No secrets here

These files are committed and must never contain secrets (API keys, tokens,
private keys). They hold feature flags and public identifiers only. Real
Firebase credentials live in the platform config files
(`android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`),
which are Firebase **client** config — public by design, not secret.
