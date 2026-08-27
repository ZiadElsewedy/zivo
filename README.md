<div align="center">

<img src="assets/transparent/zivo-mark-paper-256.png" width="88" alt="ZIVO mark" />

# ZIVO

### The gym tracker with a coach that knows your numbers.

An AI-powered training tracker — guided sessions, progressive-overload analysis, and an<br/>
assistant that reads your own splits, sets, and body-weight — with diet, a workout music
companion, and moments along for the ride.

[![Platform](https://img.shields.io/badge/platform-iOS%20%C2%B7%20Android-15110D?style=flat-square&labelColor=15110D&color=F6F1E9)](#getting-started)
[![Built with](https://img.shields.io/badge/built%20with-Flutter-15110D?style=flat-square&logo=flutter&logoColor=F6F1E9&labelColor=15110D&color=FF5A1F)](https://flutter.dev)
[![Backend](https://img.shields.io/badge/backend-Firebase-15110D?style=flat-square&logo=firebase&logoColor=15110D&labelColor=15110D&color=F6B300)](https://firebase.google.com)
[![AI](https://img.shields.io/badge/AI-Claude%20%C2%B7%20Gemini-15110D?style=flat-square&labelColor=15110D&color=6E5BFF)](docs/DECISIONS/ADR-001-ai-assistant.md)
[![Quality gates](https://img.shields.io/badge/quality%20gates-analyze%20%C2%B7%20test%20%C2%B7%20rules-15110D?style=flat-square&labelColor=15110D&color=12C48A)](#quality-gates)

</div>

---

## Why ZIVO

Most training apps are a log with a chatbot bolted on. ZIVO is built the other way around:
an AI coach that actually knows your numbers — your splits, your logged sets, your
body-weight trend, your diet — wrapped in guided live sessions and progression analysis,
in one warm, dark, calm design so checking in takes seconds, not willpower. It is built
**private-first**: your content lives in your account, the AI only ever acts on *your own*
data, backups go to *your own* Google Drive, and nothing is sold or used to train
third-party models.

## The Six Areas

ZIVO's design system assigns one color to each area of life — the same dots you'll see in the app:

| | Area | What it does |
|---|---|---|
| <img src="https://img.shields.io/badge/-%20-FF5A1F?style=flat-square" height="10"/> | **Today & Hub** | A single home for what's next — training, meals, spending, and moments at a glance. |
| <img src="https://img.shields.io/badge/-%20-12C48A?style=flat-square" height="10"/> | **Workout** | First-class splits, guided live sessions, body-weight tracking, progressive-overload analysis, and PDF plan import. |
| <img src="https://img.shields.io/badge/-%20-12C48A?style=flat-square" height="10"/> | **Diet** | Meal plans you can edit, and a daily "did I eat this" ledger. |
| <img src="https://img.shields.io/badge/-%20-F6B300?style=flat-square" height="10"/> | **Expenses** | An append-only spending log with a running wallet balance and custom categories. |
| <img src="https://img.shields.io/badge/-%20-6E5BFF?style=flat-square" height="10"/> | **Ask AI** | A tool-mediated Claude assistant over *your own* data — streaming answers, propose-and-confirm writes. |
| <img src="https://img.shields.io/badge/-%20-F6F1E9?style=flat-square" height="10"/> | **Moments** | Photos and small memories, local-first, backed up to your Drive. |

Cross-cutting: email-code verification, Sign in with Apple / Google / password,
Spotify playback integration, offline-first persistence, and full media backup.

## Architecture

Clean architecture end-to-end — presentation depends on domain interfaces only;
Firestore/Firebase are data-layer details behind repositories.

```
┌──────────────────────────────────────────────────────────┐
│  presentation   pages · widgets · motion (RiseIn, springs) │
├──────────────────────────────────────────────────────────┤
│  domain         entities · repository interfaces · policy  │
├──────────────────────────────────────────────────────────┤
│  data           Firestore / Firebase Auth implementations  │
│                 (swap-in fakes power every widget test)    │
└──────────────────────────────────────────────────────────┘
          │
          ▼
Cloud Functions (Node) ── OTP email codes · Ask gateway ·
PDF plan import · speech-to-text · auth-event bookkeeping
```

- **Dependency injection** through a tiny `AppScope` seam; every repository is injectable, so tests run without Firebase.
- **Security** is enforced by Firestore rules with per-collection field validation — covered by emulator rule tests (`firestore-tests/`).
- **Motion** follows one physical material: Apple-style springs specified as damping + response (`core/motion/springs.dart`).

### Project structure

```
lib/
├── app/               # root widget + repository wiring
├── core/              # theme · motion · media pipeline · scope · widgets
└── features/
    ├── auth/          # gate · login/signup · verify · settings · privacy
    ├── workout/       # plans · sessions · analysis · body weight
    ├── diet/          # plans + daily entries
    ├── expenses/      # log · wallet · categories
    ├── moments/       # photo memories
    ├── ai/            # Ask: chat, streaming, recorder
    ├── music/         # Spotify playback
    ├── home/ hub/ shell/
functions/             # Cloud Functions (Node): ai/ · auth/ · otp mail
firestore.rules        # deny-by-default, owner-scoped, field-validated
firestore-tests/       # security-rules suite (runs against the emulator)
docs/                  # project context · plan · ADRs · brand system
config/                # per-environment dart-define files
Makefile               # run/build configurations + quality gates
```

## Getting Started

**Prerequisites:** Flutter (SDK `^3.12.2`) · Node 20+ (for Functions) · Firebase CLI (for emulators/deploys)

```bash
git clone https://github.com/<owner>/zivo.git && cd zivo
flutter pub get

# Run against a real device/emulator in the Development environment:
make dev

# Other configurations (each maps to config/*.json dart-defines):
make profile     # Profile mode, physical device
make release     # Release mode
```

Build artifacts:

```bash
make build-apk   # Release APK
make build-ipa   # Release iOS archive
```

Firebase setup (project selection, secrets, rules deploy) is documented in
[`docs/build_configurations.md`](docs/build_configurations.md).

## Quality Gates

```bash
make gates                       # flutter analyze && flutter test
cd functions && npm test         # Cloud Functions unit tests (offline)
firebase emulators:exec --only firestore \
  --project demo-zivo "cd firestore-tests && npm test"   # security-rules suite
```

Every collection in Firestore is covered by ownership-isolation and
field-validation tests; auth event logs are additionally verified append-only.

## Documentation

> **Working on ZIVO with an AI agent?** Start at [`AGENTS.md`](AGENTS.md) — the
> agent-neutral guide (map, read-order, constraints). `CLAUDE.md` is a thin adapter to it.

| Document | Contents |
|---|---|
| [`AGENTS.md`](AGENTS.md) | **Agent entry point** — codebase map, read-order, constraints (any AI agent) |
| [`docs/PRODUCT.md`](docs/PRODUCT.md) | What ZIVO is + what makes it different (positioning) |
| [`docs/STATE.md`](docs/STATE.md) | **Current state** — branch, what's live, what's in flight |
| [`docs/PROJECT_CONTEXT.md`](docs/PROJECT_CONTEXT.md) | Deep architecture/conventions reference |
| [`docs/PLAN.md`](docs/PLAN.md) | Milestones and phased architecture plan (aspirational) |
| [`docs/WORKOUT_SYSTEM.md`](docs/WORKOUT_SYSTEM.md) | Splits, sessions, progression engine |
| [`docs/UX_BLUEPRINT.md`](docs/UX_BLUEPRINT.md) | Interaction and screen blueprints |
| [`docs/ZIVO-brand-system.md`](docs/ZIVO-brand-system.md) | Color hues, type, motion identity |
| [`docs/build_configurations.md`](docs/build_configurations.md) | The three build configs + dart-defines |
| [`docs/DECISIONS/`](docs/DECISIONS/) | Architecture decision records (ADRs) |

## Security & Privacy

Privacy isn't a page here — it's the threat model. Owner-only Firestore rules,
hashed verification codes, server-authoritative audit events, and integrations
that always act on *your own* accounts (Drive `drive.file` scope, official
Spotify SDK). The full policy lives at [zzivo.com/privacy](https://zzivo.com/privacy),
and natively in-app under **Settings → About → Privacy policy**.

Questions about data or security: <ziadelsewedy1@gmail.com>

---

<div align="center">

<img src="assets/transparent/zivo-mark-paper-256.png" width="28" alt="" />

**ZIVO** · © 2026 · built with restraint

</div>
