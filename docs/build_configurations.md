# ZIVO build configurations

ZIVO ships **three configurations**, which are Flutter's three **build modes**.
There is deliberately **no flavor axis** — there's a single Firebase backend, so
flavors (a multi-*environment* tool) would be the wrong instrument here. They'd
be worth adding only if/when a separate dev/staging backend is introduced.

| Configuration | Build mode | Purpose | App Check | Env badge | Tooling |
|---------------|-----------|---------|-----------|-----------|---------|
| **Development** | `debug`   | Daily work: hot reload, assertions, DevTools. | Debug providers | `DEV` (amber) | full debug |
| **Profile**     | `profile` | **Performance profiling (M7)** — production-like, tracing on. | Real attestation | `PROFILE` (blue) | tracing only |
| **Release**     | `release` | Production. Fully optimized, no dev behaviour. | Real attestation | none | none |

## Run / build commands

Each config pairs its build mode with its `config/<env>.json` dart-defines.

| Config | `make` | Raw command |
|--------|--------|-------------|
| Development | `make dev` | `flutter run --dart-define-from-file=config/development.json` |
| Profile | `make profile` | `flutter run --profile --dart-define-from-file=config/profile.json` |
| Release (run) | `make release` | `flutter run --release --dart-define-from-file=config/release.json` |
| Release APK | `make build-apk` | `flutter build apk --release --dart-define-from-file=config/release.json` |
| Release IPA | `make build-ipa` | `flutter build ipa --release --dart-define-from-file=config/release.json` |

In **VS Code / Cursor**, the same three are in `.vscode/launch.json` — pick
**ZIVO · Development / Profile / Release** from the Run and Debug menu.

## Environment configuration

All environment-specific values are resolved once in
[`lib/core/env/app_environment.dart`](../lib/core/env/app_environment.dart) —
nothing reads `kDebugMode` or `fromEnvironment` ad-hoc anymore:

- `AppEnvironment.config` — the active `AppConfig` (from the build mode).
- `AppEnvironment.useFirestore` — Firestore vs in-memory (`USE_FIRESTORE`).
- `AppEnvironment.appCheckMode` — debug providers vs real attestation.
- `AppEnvironment.googleServerClientId` — public OAuth client id.
- `AppEnvironment.showBadge` — drives the corner badge (off in Release).

Non-secret overrides live in [`config/`](../config/README.md) and are passed via
`--dart-define-from-file`. **No secrets** are stored in code or those files.

## App Check across modes — and why M7 isn't misled

App Check attests the app to the backend before `runApp` (it's `await`ed in
`main.dart`). The mode is now explicit:

- **Development** → **debug providers** (register the token printed at launch).
- **Profile & Release** → **real attestation** (Play Integrity / App Attest).

This means a **Profile build includes real App Check cost in startup — on
purpose**, so M7 measures production-like behaviour rather than a debug shortcut.
This is behaviourally identical to the previous `kDebugMode`-based selection,
just centralized and explicit.

If we ever suspect App Check attestation itself is skewing a startup number, the
**diagnostic** flag `--dart-define=FORCE_APP_CHECK_DEBUG=true` forces debug
providers even in Profile so we can A/B it. **Never use it for a real M7 run.**

## Android / iOS consistency

Because the three configs are build modes (native to both platforms), behaviour
is identical across Android and iOS with nothing extra to maintain — no
per-platform flavor divergence. (Android release still signs with debug keys;
wiring a real keystore is a separate, clearly-marked TODO in
`android/app/build.gradle.kts`.)

## Which config for M7, and why

**Profile.** It's the only mode that is both **production-like** (real
optimizations, real App Check attestation, tree-shaken, assertions off) **and**
keeps the **tracing hooks** DevTools needs. `debug` is meaninglessly slow;
`release` strips the profiling instrumentation. Run it on a **physical device**:

```bash
make profile            # or: flutter run --profile --dart-define-from-file=config/profile.json
```

See [performance/M7_profiling_playbook.md](performance/M7_profiling_playbook.md)
for the full profiling procedure.
