# AGENTS.md — ZIVO agent guide

> **The shared, agent-neutral entry point for any AI coding agent** (Claude, Codex,
> Cursor, or others) working on ZIVO. Project knowledge lives here and in [`docs/`](docs) —
> it is not tied to any one agent. Agent-specific launcher files (e.g. `CLAUDE.md`) are
> thin **adapters** that just point here; don't duplicate knowledge into them.
> Keep this file **short and evergreen** — volatile "where we are now" lives in
> [`docs/STATE.md`](docs/STATE.md).

**ZIVO is an AI-powered gym / training tracker** (Flutter + Firebase, iOS/Android). The
bet is that a training app built *around* an AI coach that actually knows your numbers —
your splits, your logged sets, your body-weight trend, your diet — feels categorically
different from a log with a chatbot bolted on. What the product is and **what makes it
different** is [`docs/PRODUCT.md`](docs/PRODUCT.md) — read it to work in the product's
spirit. Owner: Ziad.

---

## Boot sequence — read in this order, stop when you know enough

1. **This file** — the map + the rules.
2. **[`docs/PRODUCT.md`](docs/PRODUCT.md)** — what ZIVO is and what makes it different
   (the positioning to protect and push on).
3. **[`docs/STATE.md`](docs/STATE.md)** — current branch, what's live, what's in flight,
   owner action items. *Always read this; it's small and it's the truth of "now".*
4. **The feature's `FEATURE.md`** — every `lib/features/<x>/` folder has one (see the map
   below): entry file, domain entities, repos, and gotchas for that feature. Read the one
   you need — not the whole codebase.
5. **A deep doc or ADR** only if the task needs it (see the map's right column).
6. **The code** — now you know the 2–3 files to open. Open those, not the repo.

> **Do not** grep-scan the whole repo to "understand the project" before starting. The map
> below plus the feature's `FEATURE.md` is designed to get you to the right 2–3 files
> directly. If you can't find something here, that's a gap worth fixing in these docs —
> tell the user.

---

## Golden rules (constraints — don't break without an explicit decision)

- **Protect the differentiation.** The AI coach, guided live sessions, and
  progression intelligence are the product's reason to exist (see `docs/PRODUCT.md`).
  Prefer changes that deepen them over generic tracker features.
- **Keep the repository seam.** Every feature has an `abstract interface class
  <X>Repository` in `domain/`, a `Firestore<X>Repository` and an `InMemory<X>Repository`
  in `data/`, wired in [`lib/app/app.dart`](lib/app/app.dart) and exposed via
  [`AppScope`](lib/core/scope/app_scope.dart). This is the backend swap point and the
  reason tests run without Firebase. Presentation depends on `domain/` interfaces only.
- **No new foundational framework** as a side effect of feature work. The app
  deliberately uses **plain `setState` + streams + the `AppScope` `InheritedWidget`**
  (and, for a screen whose rules outgrew `setState`, a plain `ChangeNotifier`
  controller in `presentation/controllers/` — [ADR-008](docs/DECISIONS/ADR-008-presentation-controllers.md)),
  `IndexedStack` + `Navigator` for routing. Do **not** introduce `go_router`,
  `riverpod`/`bloc`/`provider`/`get_it`, etc. without an ADR. *(Firebase is the adopted
  backend — that ship has sailed; everything else above has not.)*
- **Every dependency pays rent.** Adding a package is a deliberate decision, not a
  convenience. Each dep in [`pubspec.yaml`](pubspec.yaml) carries a one-line justification;
  match that bar.
- **Respect the design system.** Hue ownership (each area owns one color; Ember = Now/Next
  + the single primary action), the spacing/radius/typography/motion tokens in
  [`lib/core/theme/`](lib/core/theme) and [`lib/core/motion/springs.dart`](lib/core/motion/springs.dart),
  and the shared capture widgets. **One palette only — `TrainColors`; `AppColors`/`AppShadows`
  are deleted and must not come back** ([ADR-006](docs/DECISIONS/ADR-006-one-design-system.md)).
  See also [`docs/ZIVO-brand-system.md`](docs/ZIVO-brand-system.md) for intent (superseded for
  colour values by ADR-006).
- **Security is deny-by-default, owner-scoped.** All persistence goes through Firestore
  with per-collection field validation in [`firestore.rules`](firestore.rules), covered by
  the emulator suite in [`firestore-tests/`](firestore-tests). A new collection needs a
  rule **and** a rule test.
- **Don't present demo/in-memory data as persistent.** In-memory repos are the offline/test
  fallback; the real app runs on Firestore (`USE_FIRESTORE` defaults true).
- **Reference docs are not current state.** `docs/PLAN.md` is aspirational; the big docs are
  design intent. When a doc and the code disagree, **the code wins**; "current status"
  lives in `docs/STATE.md`.

---

## The map — where everything lives

**Architecture:** clean layering per feature — `presentation/` (pages · widgets) →
`domain/` (entities · repository interfaces) → `data/` (Firestore + in-memory impls).
Entry: [`lib/main.dart`](lib/main.dart) → [`lib/app/app.dart`](lib/app/app.dart) (wires all
repos, provides `AppScope`, dark `MaterialApp`, `home: AuthGate`).

| Feature | What it is | Folder + map | Deep doc / ADR |
|---|---|---|---|
| **workout** | Splits, live guided sessions, progression analysis, body-weight, PDF import — **the core** | [`lib/features/workout/`](lib/features/workout/FEATURE.md) | [WORKOUT_SYSTEM.md](docs/WORKOUT_SYSTEM.md) |
| **ai** | "Ask": streaming chat + tool-mediated read/confirm-write over your data + voice — **the coach** | [`lib/features/ai/`](lib/features/ai/FEATURE.md) | [ADR-001](docs/DECISIONS/ADR-001-ai-assistant.md), [ADR-003](docs/DECISIONS/ADR-003-ai-mutations-v2.md) |
| **diet** | Meal plans, daily ledger, PDF import, AI kcal — training fuel | [`lib/features/diet/`](lib/features/diet/FEATURE.md) | — |
| **music** | Training-anchored Spotify now-playing + color-adaptive Now Playing screen | [`lib/features/music/`](lib/features/music/FEATURE.md) | — |
| **auth** | Email-OTP + Apple/Google/password, verify, profile, settings, privacy | [`lib/features/auth/`](lib/features/auth/FEATURE.md) | — |
| **expenses** | Append-only spend log, wallet balance, categories | [`lib/features/expenses/`](lib/features/expenses/FEATURE.md) | — |
| **moments** | Local-first photo memories, timeline, viewer | [`lib/features/moments/`](lib/features/moments/FEATURE.md) | — |
| **home** | Today surface (reactive glances: training, diet, spend, move ring) | [`lib/features/home/`](lib/features/home/FEATURE.md) | [UX_BLUEPRINT.md](docs/UX_BLUEPRINT.md) |
| **hub** | Module launcher tab | [`lib/features/hub/`](lib/features/hub/FEATURE.md) | — |
| **shell** | 4-tab scaffold (Today · Hub · Ask · You) + floating bottom bar + capture FAB | [`lib/features/shell/`](lib/features/shell/FEATURE.md) | — |
| **capture** | Quick-capture sheet + shared capture widgets | [`lib/features/capture/`](lib/features/capture/FEATURE.md) | — |
| **device** | Pedometer step counter (Today's Move ring) | [`lib/features/device/`](lib/features/device/FEATURE.md) | — |

**Shared / cross-cutting (`lib/core/`):**

| Path | Role |
|---|---|
| [`core/scope/app_scope.dart`](lib/core/scope/app_scope.dart) | DI seam — `AppScope.of(context)`. **Add new repos here + in `app.dart`.** |
| [`core/theme/`](lib/core/theme) | Design tokens: colors, typography, spacing, shadows, icons (Lucide), theme |
| [`l10n/`](lib/l10n) + [`core/l10n/`](lib/core/l10n) | Arabic + English. Read strings via **`l(context)`**; add keys to `app_en.arb` (with a `@description`) *and* `app_ar.arb` |
| [`core/motion/springs.dart`](lib/core/motion/springs.dart) | Apple-style springs (damping + response) — the one motion material |
| [`core/media/`](lib/core/media) | Storage-agnostic media pipeline: local-first store + registry + Google Drive backup |
| [`core/env/app_environment.dart`](lib/core/env/app_environment.dart) | `USE_FIRESTORE` and other dart-define flags |
| [`core/firebase/uid_source.dart`](lib/core/firebase/uid_source.dart) | Current-uid source injected into every Firestore repo |
| [`core/widgets/`](lib/core/widgets) | Shared widgets (RiseIn, reactive state views, toasts, loading bar, marks). **`zivo_sheet.dart` is the one way to open a bottom sheet** (`showZivoSheet`, + `ZivoSheetSurface`/`ZivoSheetHandle` for the chrome); **`zivo_field.dart` is the one filled-input decoration** (`zivoFieldDecoration`, which takes the feature's hue); **`zivo_confirm.dart` is the one destructive confirmation** (`confirmDestructive`, whose labels default to the localized `actionDelete`/`actionCancel`) |
| [`core/util/`](lib/core/util) | Small shared functions — `parse.dart` (every number a user types), `money.dart`, `time_ago.dart` |

**Backend ([`functions/`](functions), Node — Cloud Functions):** `functions/ai/` —
`gateway.js` (Ask streaming + tool loop + coach persona), `tools.js` (read tools),
`mutations.js` (confirm-gated writes), `workout_import.js`, `diet_import.js`,
`coach_report.js`, `store.js`, `dates.js`. `functions/auth/activity.js` (auth event log +
OTP mail). Each has a `*.test.js` (`node --test`, offline).

---

## Commands

```bash
make dev            # run Development (debug) on default device
make gates          # local quality gates: flutter analyze && flutter test
make build-apk      # release Android APK    |  make build-ipa  — release iOS archive
make hooks          # install the shared git hooks (STATE.md freshness check) — once per clone
```

```bash
cd functions && npm test                       # Cloud Functions unit tests (offline)
firebase emulators:exec --only firestore \
  --project demo-zivo "cd firestore-tests && npm test"   # security-rules suite
```

Full run/build config + dart-defines: [`docs/build_configurations.md`](docs/build_configurations.md).
**Backend deploys and Firebase console changes need the owner's credentials — never run
`firebase deploy` yourself; surface it as an owner action.**

---

## Keeping this system current (do this — it's how we avoid doc-rot)

- **When you finish a task, update [`docs/STATE.md`](docs/STATE.md)** (what changed, what's
  now in flight, any new owner action item) and, for a milestone, append to
  [`docs/CHANGELOG.md`](docs/CHANGELOG.md). STATE.md is intentionally small so this is a
  30-second habit. A **pre-commit hook** ([`scripts/hooks/pre-commit`](scripts/hooks/pre-commit),
  installed via `make hooks`) nudges you when a commit changes `lib/`/`functions/` code
  without touching `docs/STATE.md` — it only warns (bypass: `git commit --no-verify`; enforce:
  `ZIVO_STRICT_STATE_CHECK=1`).
- **Changed a feature's structure** (new entity, repo, or entry page)? Update that feature's
  `FEATURE.md` in the same change.
- **Made a real architectural/product decision?** Add an ADR under
  [`docs/DECISIONS/`](docs/DECISIONS) (decision + trade-offs only — no handoff logs).
- **Don't** put current status into the reference docs — it rots there. Status → STATE.md.

## Agent adapters

Knowledge is agent-neutral and lives in this file + `docs/`. Some agents auto-load a native
launcher file; those are kept to a one-line pointer here so there is a single source of truth:

- **Claude Code** → [`CLAUDE.md`](CLAUDE.md) (adapter → this file).
- **Codex / Cursor / others** → read this `AGENTS.md` natively.
- Adding another agent? Create its native file as a one-line pointer to `AGENTS.md` — never
  copy the knowledge.

## Full docs index

| Doc | Contents | Kind |
|---|---|---|
| [`docs/PRODUCT.md`](docs/PRODUCT.md) | **What ZIVO is + what makes it different** | positioning |
| [`docs/STATE.md`](docs/STATE.md) | **Current state — read every session** | live |
| [`docs/PROJECT_CONTEXT.md`](docs/PROJECT_CONTEXT.md) | Deep architecture/conventions reference | reference |
| [`docs/WORKOUT_SYSTEM.md`](docs/WORKOUT_SYSTEM.md) | Splits · sessions · progression engine | reference |
| [`docs/UX_BLUEPRINT.md`](docs/UX_BLUEPRINT.md) | Interaction/screen blueprints | design intent |
| [`docs/ZIVO-brand-system.md`](docs/ZIVO-brand-system.md) | Type · motion · tone identity (colour superseded by ADR-006) | reference |
| [`docs/PLAN.md`](docs/PLAN.md) | Long-term milestone plan | aspirational |
| [`docs/DECISIONS/`](docs/DECISIONS) | Architecture decision records (ADRs) | reference |
| [`docs/DECISIONS/ADR-008-presentation-controllers.md`](docs/DECISIONS/ADR-008-presentation-controllers.md) | **When a page gets a controller, and the rules that keep the seam honest** | reference |
| [`docs/build_configurations.md`](docs/build_configurations.md) | Build configs + dart-defines | reference |
