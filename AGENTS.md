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
  **One palette, now in two skins** — dark and light are two `ZivoPalette` instances,
  and a new colour goes in **both** ([ADR-011](docs/DECISIONS/ADR-011-light-mode.md)).
  **One type system only — three families, all named in `train_tokens.dart`: Manrope (text),
  Azeret Mono (numbers), Instrument Serif italic (ZIVO speaking). Never call `GoogleFonts`
  anywhere else** ([ADR-009](docs/DECISIONS/ADR-009-one-type-system.md)).
  See also [`docs/ZIVO-brand-system.md`](docs/ZIVO-brand-system.md) for intent (superseded for
  colour values by ADR-006 and for typography by ADR-009).
- **Security is deny-by-default, owner-scoped.** All persistence goes through Firestore
  with per-collection field validation in [`firestore.rules`](firestore.rules), covered by
  the emulator suite in [`firestore-tests/`](firestore-tests). A new collection needs a
  rule **and** a rule test. Several policies are stated on **both** sides of the wire
  (email verification, password strength, reauth-before-delete, paid-endpoint quotas) —
  the client half picks the screen, the server half is the boundary. Change one, change
  the other: the table is in [`docs/AUTH.md`](docs/AUTH.md) §4.
- **Identity is not the user.** `features/auth/` holds credentials and session and stays
  free of every ZIVO concept so it can be lifted into another project; the app's own
  record of a person lives in `features/profile/`, keyed by uid. Never add a product
  field to `AuthUser` or to the Firebase Auth record — see [`docs/AUTH.md`](docs/AUTH.md).
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
repos, provides `AppScope`, a `MaterialApp` on the chosen skin, `home: AuthGate`).

| Feature | What it is | Folder + map | Deep doc / ADR |
|---|---|---|---|
| **workout** | Splits, live guided sessions, progression analysis, body-weight, PDF import — **the core** | [`lib/features/workout/`](lib/features/workout/FEATURE.md) | [WORKOUT_SYSTEM.md](docs/WORKOUT_SYSTEM.md) |
| **ai** | "Ask": streaming chat + tool-mediated read/confirm-write over your data + voice — **the coach** | [`lib/features/ai/`](lib/features/ai/FEATURE.md) | [ADR-001](docs/DECISIONS/ADR-001-ai-assistant.md), [ADR-003](docs/DECISIONS/ADR-003-ai-mutations-v2.md) |
| **diet** | Meal plans, daily ledger, PDF import, AI kcal — training fuel | [`lib/features/diet/`](lib/features/diet/FEATURE.md) | — |
| **music** | Training-anchored Spotify now-playing + color-adaptive Now Playing screen | [`lib/features/music/`](lib/features/music/FEATURE.md) | — |
| **auth** | Email-OTP + Apple/Google/password, verify, session, account lifecycle — **portable module** | [`lib/features/auth/`](lib/features/auth/FEATURE.md) | [AUTH.md](docs/AUTH.md) |
| **profile** | The app's own user record (name · DOB · photo · bio) + `SessionState` — app-specific half of auth | [`lib/features/profile/`](lib/features/profile/FEATURE.md) | [AUTH.md](docs/AUTH.md), [ADR-014](docs/DECISIONS/ADR-014-avatar-firebase-storage.md) |
| **expenses** | Append-only spend log, wallet balance, categories | [`lib/features/expenses/`](lib/features/expenses/FEATURE.md) | — |
| **moments** | Local-first photo memories, timeline, viewer | [`lib/features/moments/`](lib/features/moments/FEATURE.md) | — |
| **home** | Today surface (reactive glances: training, diet, spend, move ring) | [`lib/features/home/`](lib/features/home/FEATURE.md) | [UX_BLUEPRINT.md](docs/UX_BLUEPRINT.md) |
| **hub** | Module launcher tab | [`lib/features/hub/`](lib/features/hub/FEATURE.md) | — |
| **shell** | 4-tab scaffold (Today · Hub · Ask · You) + floating bottom bar + capture FAB | [`lib/features/shell/`](lib/features/shell/FEATURE.md) | — |
| **capture** | Quick-capture sheet + shared capture widgets | [`lib/features/capture/`](lib/features/capture/FEATURE.md) | — |
| **sleep** | Apple Health / Health Connect sleep + manual logging, with provenance on every number — training recovery | [`lib/features/sleep/`](lib/features/sleep/FEATURE.md) | [SLEEP_SYSTEM.md](docs/SLEEP_SYSTEM.md), [ADR-010](docs/DECISIONS/ADR-010-sleep-provenance.md) |
| **device** | Pedometer step counter (Today's Move ring) | [`lib/features/device/`](lib/features/device/FEATURE.md) | — |
| **reminders** | Simple customizable **local** notifications — meal/workout/activity reminders the user schedules | [`lib/features/reminders/`](lib/features/reminders/FEATURE.md) | [ADR-013](docs/DECISIONS/ADR-013-local-notifications.md) |
| **admin** | Admin Console — users, activity, AI usage, suspend/delete; shown instead of the app to an `admin`-claim account. Server-enforced, counts never content | [`lib/features/admin/`](lib/features/admin/FEATURE.md) | [ADR-018](docs/DECISIONS/ADR-018-admin-console.md), [ADMIN.md](docs/ADMIN.md) |
| **readiness** | The Daily Readiness call (train hard / go light / rest), fused from sleep + training load + recovery + weight — **derived, never stored** | [`lib/features/readiness/`](lib/features/readiness/FEATURE.md) | [ADR-015](docs/DECISIONS/ADR-015-readiness.md) |

**Shared / cross-cutting (`lib/core/`):**

| Path | Role |
|---|---|
| [`core/scope/app_scope.dart`](lib/core/scope/app_scope.dart) | DI seam — `AppScope.of(context)`. **Add new repos here + in `app.dart`.** |
| [`core/theme/`](lib/core/theme) | Design tokens: colors, typography, spacing, shadows, icons (Phosphor), theme. **`zivo_palette.dart` holds the two skins** (`ZivoPalette.dark`/`.light`); `TrainColors` is the façade every screen reads, resolving through whichever `ZivoTheme.use()` last set. **Never cache a token in a field, a `static final`, or `initState`** — see [ADR-011](docs/DECISIONS/ADR-011-light-mode.md) |
| [`l10n/`](lib/l10n) + [`core/l10n/`](lib/core/l10n) | Arabic + English. Read strings via **`l(context)`**; add keys to `app_en.arb` (with a `@description`) *and* `app_ar.arb`. **Keying a string is not licence to reword it** — the English must come out byte-identical. A `domain/` enum persisted by `name` is an **id** and never carries copy: its labels go in a `presentation/*_labels.dart` taking a `BuildContext` (`workout_labels.dart`, `diet_labels.dart`, `password_rule_labels.dart`, `capture_source_labels.dart`) |
| [`core/util/bidi.dart`](lib/core/util/bidi.dart) | **Arabic is not just a string swap.** A composed run of digits and neutral punctuation (`3 × 8–10 · rest 1:30`, `12/15`, `+4%`, `~1270`, `UTC+03:00`) is reordered by the bidi algorithm in an RTL paragraph and comes out backwards — `8–10` renders as `10–8`. Pin every such run with **`ltrFor(context, s)`** (a no-op under LTR, so English is untouched), and wrap text ZIVO did not write — a plan name, an exercise name, a location — with **`isolate(s)`** (first-strong, so the run decides its own direction). `stripBidi` + `test/support/bidi_finders.dart` are the test-side counterparts |
| [`core/motion/springs.dart`](lib/core/motion/springs.dart) | Apple-style springs (damping + response) — the one motion material |
| [`core/media/`](lib/core/media) | Storage-agnostic media pipeline: local-first store + registry + Google Drive backup |
| [`core/env/app_environment.dart`](lib/core/env/app_environment.dart) | `USE_FIRESTORE` and other dart-define flags |
| [`core/firebase/`](lib/core/firebase) | `uid_source.dart` — current-uid source injected into every Firestore repo, plus `requireUid(this)`, the signed-in precondition in front of every write. **`uid_scoped_mirror.dart` is the one way a repository mirrors a uid-scoped Firestore read** (`UidScopedMirror<T>`): uid re-scoping, the cached `current`, the late-subscriber replay, and the always-on listener. A new Firestore repo supplies only its query and its doc→domain mapper — never its own `StreamController`/uid plumbing |
| [`core/widgets/`](lib/core/widgets) | Shared widgets (RiseIn, reactive state views, toasts, loading bar, marks). **`async_action.dart` is the one re-entrancy guard for a button that commits** (`AsyncAction` mixin — `runAction(#save, …, once: true)` for anything that saves and pops); `deferred_write_reporter.dart` surfaces a deferred write that failed. **`zivo_sheet.dart` is the one way to open a bottom sheet** (`showZivoSheet`, + `ZivoSheetSurface`/`ZivoSheetHandle` for the chrome); **`zivo_field.dart` is the one filled-input decoration** (`zivoFieldDecoration`, which takes the feature's hue); **`zivo_confirm.dart` is the one destructive confirmation** (`confirmDestructive`, whose labels default to the localized `actionDelete`/`actionCancel`) |
| [`core/util/`](lib/core/util) | Small shared functions — `parse.dart` (every number a user types), `money.dart`, `time_ago.dart`, **`deferred_write.dart`** (local-first saves: hand the durable write to `deferWrite` and pop — never `await` a repository before navigating), **`date_format.dart` is the one way to render a date, weekday or clock time** (`formatMonthDay`, `formatClockTime`, `formatWeekdayDate`, … — all take `BuildContext` and resolve through the reader's locale). Never hand-roll a `['Jan', …]` / `['Mon', …]` table or an `isPm ? 'PM' : 'AM'`: a month name that is not a string the translator can see is a bug no `.arb` key can fix |

**Backend ([`functions/`](functions), Node — Cloud Functions):** `functions/ai/` is
**organized by responsibility — open [`functions/ai/README.md`](functions/ai/README.md)
first** (it's the map): `gateway.js` (Ask facade) → **`chat/`** (turn loop + prompt +
reply validator — see `chat/README.md`), **`tools/`** (read · mutations · elicitations —
what the model can call), **`providers/`** + **`routing/`** (Anthropic/Gemini adapters
behind one seam), **`services/`** (the use-cases: `workout_import`, `diet_import`,
`diet_generate`, `coach_report`, `sleep_insights`), **`analytics/`** (deterministic
engines mirrored from Dart, pinned by shared golden vectors), **`speech/`** (voice), and
**`shared/`** (`store.js` Firestore seam, `dates.js`, etc.). `functions/auth/activity.js`
(auth event log + OTP mail). **`functions/admin/`** — the Admin Console's
admin-only callables and the triggers that derive product events (ADR-018). Each source file has a co-located `*.test.js` (`node --test`,
offline).

---

## AI agent workflow and tool calls

> The AI coach ("Ask") and all other AI features run in the **backend**
> ([`functions/ai/`](functions/ai)); the Flutter client only streams a turn and renders it.
> Client seam: [`lib/features/ai/FEATURE.md`](lib/features/ai/FEATURE.md). Chat internals:
> [`functions/ai/chat/README.md`](functions/ai/chat/README.md). ADRs:
> [ADR-001](docs/DECISIONS/ADR-001-ai-assistant.md) (read-only V1),
> [ADR-003](docs/DECISIONS/ADR-003-ai-mutations-v2.md) (propose→confirm→execute),
> [ADR-005](docs/DECISIONS/ADR-005-ai-edit-delete-expenses.md) (edit/delete).

**One rule above all — the model never invents a number and never writes on its own.**
Every user figure must come from a **tool result in that turn** (the `NUMBERS` prompt
section); every write is **confirm-gated** (ADR-003/005 — a tool only *proposes*); and the
final reply is **validated before it's persisted** ([`validator.js`](functions/ai/validator.js),
Phase 7) — an unsupported figure is replaced with deterministic text.

### Use cases — what a user asks → what runs

The user talks to one coach; the loop below picks the tools. These are illustrative, not
an exhaustive routing table (the model chooses).

| The user says… | Coach does | Tool(s) / feature |
|---|---|---|
| "How am I doing today?" / "Should I train hard today?" | Reads the daily snapshot and the fused readiness call, then explains it. | `get_today`, `get_readiness` |
| "What did I do last workout?" | Fetches the single most recent session with top working sets. | `get_last_workout` |
| "How's my bench progressing?" | Drills into one lift's session-by-session history + verdict. | `get_exercise_analysis` |
| "Am I making progress / plateauing?" | Reads deterministic analysis + findings + plan adherence. | `get_training_analysis` |
| "How did I sleep?" | Last night vs target + rolling average. | `get_sleep_summary` |
| "How many calories do I have left?" / "What's my diet today?" | Reads the day's `DietState` (targets, remaining, provenance). | `get_diet` / `get_today` |
| "I ate two eggs and 100g of rice — log it." | Resolves each food, computes nutrition server-side, **proposes** a food log → user confirms. | `resolve_food` → `calculate_meal_nutrition` → `log_food` (confirm) |
| "How many calories in 200g chicken breast?" | Looks up + computes; surfaces `ambiguous`/`notFound` rather than guessing. | `resolve_food`, `calculate_meal_nutrition` |
| "Mark my lunch as eaten." | Ticks a *planned* meal by id → user confirms. | `mark_meal_eaten` (confirm) |
| "I spent 120 on groceries." / "Change that to 90." / "Delete it." | Proposes a create/edit/delete against the real expense `id` → user confirms. | `create_expense` / `edit_expense` / `delete_expense` (confirm) |
| "How much did I spend this week?" | Reads expenses / weekly rollup. | `get_expenses`, `summarize_week` |
| "I don't want molokhia." / "مش عايز ملوخية في الدايت" | Reads the diet, proposes realistic swaps that ZIVO prices, **shows 2–4 options and waits**; the pick (tap, "option 2") becomes a replace proposal → user confirms. Never swaps on its own. | `get_diet` → `search_food_alternatives` → `ask_choice` ⏸ → next turn `replace_meal_item` (confirm) |
| "I ate BreadWay tortilla." | Catalog first; if that exact product isn't there, searches saved foods → Open Food Facts → the web; found = label figures, not found = asks for the label's numbers. Never estimates. | `resolve_food` → `search_food_product` → `create_custom_food` / `log_food` (confirm) |
| "I want to do Pull today" (Push is scheduled) | Reads the rotation, lays out both ways and asks: **skip** Push (dropped this round) or **swap** Push with Pull (Pull today, Push next). The tap proposes that exact change → user confirms. An explicit "skip Push and do Pull" / "swap them" is proposed directly. | `get_workout_schedule` → `preview_workout_change` → `ask_choice` ⏸ → tap = bound `change_workout_day` (confirm) |
| Coach needs a value it can't read (e.g. height) | Pauses and asks — an option chip or a small form; the answer returns as the next turn (height/weight persist to the user's own body data). | `ask_choice`, `request_input` |
| User dictates instead of typing | Audio → transcript, then a normal chat turn. | `aiTranscribe` |
| "Import this workout/diet PDF." | Extracts a structured plan; the client's review/edit screen is the save gate. | `aiImportWorkoutPlan` / `aiImportDietPlan` |
| "Generate me a diet plan." | Model picks foods, catalog prices them, arithmetic fits the target. | `aiGenerateDietPlan` |
| (Proactive, weekly) | A deterministic recap is pushed into the user's Ask conversation. | `weeklyCoachReport` |

### The chat turn (`aiChat` → [`chat/turn.js`](functions/ai/chat/turn.js) `runAiTurn`)

```
User message
  ▼
runAiTurn: SYSTEM_PROMPT (cached) + uncached CONTEXT block (user's local
  date/weekday/time from utcOffsetMinutes) + history → call provider
  ▼  BOUNDED agent loop: ≤ maxAgentSteps (6) model calls; the last one is forced
  ▼  to answer (toolChoice 'none'); ends in a TerminalState (chat/outcome.js)
  ├─ TEXT only ............ validate → persist → done            ✅
  ├─ READ tool ........... run → feed result back → loop         🔁  (emits {step,tool,status})
  ├─ MUTATING tool ....... propose: persist pending action, end turn, show card  ⏸️
  └─ ELICITATION tool .... pause: persist choice/input request, end turn, ask     ⏸️
```

- **Every turn terminates** in one of `completed · needs_user_input · max_steps_reached ·
  tool_error · provider_error · cancelled` (+ `daily_limit`). A transient tool failure is
  retried once; the same tool failing twice stops the turn. A turn that can't finish says
  what it checked and what failed (`outcome.js`), never a vague "couldn't do that".
  Contract + diagram: [`chat/README.md`](functions/ai/chat/README.md#the-agent-loop-contract-bounded--turnjs--configjs).
- **Reads never end the turn**; **writes and elicitations do** — they hand control to the user,
  whose answer arrives as the *next* `aiChat` turn.
- **Live progress:** only the tool *name* crosses the wire (`{type:'step',tool,status}`), never
  its input/result; the client maps it to a human **thought state** — Reading · Analyzing ·
  Calculating · Searching · Suggesting · Preparing · Thinking (`presentation/ai_thought.dart`)
  — drawn by the thought trail ("Reading your meal plan…" live, "● Read ● Suggested" once
  settled). The reply persists `activity` so the trail survives reload; raw tool ids appear
  only in debug builds.
- **Follow-ups reuse what was already read** (`chat/context_ledger.js`): the latest reply
  carries its turn's read/search results; the next turn gets them as an EARLIER RESULTS
  block (15-min TTL, same day, broken by a confirmed write) and calls a tool only for
  genuinely new information.
- **Everything the model writes is saved** — text before a tool call included — so the
  streamed words and the saved words are identical, and a card keeps its lead-in (`preface`).
- **Providers:** behind a `NormalizedRequest`/`NormalizedResponse` seam
  ([`providers/`](functions/ai/providers) + [`routing/router.js`](functions/ai/routing/router.js),
  models + prices in [`routing/models.js`](functions/ai/routing/models.js): Claude Sonnet 5 ·
  Gemini Flash — one model per provider). **The selected model answers — no cross-provider
  fallback** (owner decision 2026-09-26, replacing the automatic fallback of 2026-09-24): the
  model the user marks active (`settings/ai.provider`, default `claude-sonnet`) answers chat,
  plan import and the plan builder — Gemini selected → Gemini only, Claude → Claude only. A
  TRANSIENT failure (overload, rate limit, server error, network — see `isTransientFailure` in
  `providers/classify.js`) is retried on the SAME provider (twice; a timeout once); anything that
  survives, and any PERMANENT failure (quota, bad key, out of credit — Anthropic sends that as a
  400 —, retired model), fails with THAT provider's `AiUnavailableError` →
  `HttpsError('unavailable', …, {reason:'ai_unavailable', provider, kind})`, and the app names the
  provider and the reason with a "Switch model" action. The router is the only retry layer (SDK
  clients run `maxRetries: 0`). The fallback path is kept but off (`CROSS_PROVIDER_FALLBACK`).
  `food_search`'s grounding call always runs on Gemini (Anthropic has no search grounding).
- **Scoped context:** each turn is routed deterministically (`chat/intent.js`, no model call) to
  GENERAL · TRAINING · DIET · MONEY or AMBIGUOUS, and `chat/scope.js` hands the model only that
  area's prompt modules + tools (AMBIGUOUS = everything, as before; scoped turns can widen with
  `load_tools`). A tool is never exposed without its area's prompt module.
- **Usage** is logged for **every** AI request, not just chat turns (`aiUsage` v7, `feature` field:
  chat · workout_import · diet_import · diet_generate · food_search · transcribe) —
  [`shared/usage_log.js`](functions/ai/shared/usage_log.js) meters the non-chat callables,
  [`chat/usage.js`](functions/ai/chat/usage.js) the turn: provider/model, type (`feature`),
  tokens in/out, cost at the answering model's rate, status/errorKind, `perCall` rows (tokens
  by bucket, stop reason, latency, provider `tries`) and, on a failure, `failedProvider`/
  `failedModel`; chat turns add `intent`, `promptVersion` and a `context` size breakdown
  (sizes only, never text). The chat daily cap counts chat records only.
  The app reads it on the AI usage page (Settings → AI usage): pick Claude or Gemini to see its
  total/chat/generate/import requests, tokens in/out, estimated cost and cost per request.

### The confirm-gated write flow (ADR-003 / ADR-005)

```
Model calls a mutating tool → validate(input) [shape] → verify(input) [exists; patches payload]
  → persist pending action + end turn → client shows proposal card
      ├─ Confirm → aiConfirmAction → execute() writes to Firestore   ✅
      └─ Cancel  → aiCancelAction  → nothing written                 ❌
```
`validate` proves shape; `verify` proves the record exists (runs before the card). Edits/deletes
target the **exact `id`** from a read tool. Food nutrition is **computed server-side in `verify`**,
never model-supplied, and snapshotted at propose time so it can't drift.

### Read tools — [`tools/read.js`](functions/ai/tools/read.js) (uid-scoped, never mutate; every payload states its date)

| Tool | Returns |
|---|---|
| `get_today` | Today's snapshot — diet (targets/remaining/provenance), profile/weight/age, training. Default context tool. |
| `get_diet` | A day's `DietState` (same builder as the Diet screen): `targets`, `remaining`, `consumed.basis`, `logEntries`, `quality`. |
| `get_workouts` | Real per-set actuals from `workoutSessions` (weight/reps/type/outcome; warm-ups flagged, skipped/pending dropped). |
| `get_last_workout` | Just the single most recent completed session; each exercise's top working set precomputed. |
| `get_training_analysis` | Deterministic workout analysis + typed `findings` + `planAdherence`. The model phrases, never computes. |
| `get_exercise_analysis` | One lift by name → full session-by-session history, deltas, verdict/tone, deterministic insight. |
| `get_readiness` | The Daily Readiness call (train hard / go light / rest), fusing sleep + load + recovery + weight. Owns "how am I today". |
| `get_sleep_summary` | Last night vs target + rolling average, for sleep-specific questions. |
| `get_expenses` | Expenses, each with its real `id` (so edit/delete can target it). |
| `summarize_week` | Trailing-week rollup across surfaces. |
| `resolve_food` | A food query → `foodId` + per-100g nutrition, or `ambiguous` / `notFound`. (SEARCH) |
| `search_food_alternatives` | Model-proposed replacement candidates for one plan item → each priced from the catalog with a portion sized to the original's calories, or `found:false`. Changes nothing. (SEARCH) |
| `search_food_product` | A branded product → saved foods, then Open Food Facts label data, then Gemini web search; per-100g figures that were stated (or converted from a stated serving), energy-consistent, brand-matched — or `notFound`. (SEARCH) |
| `calculate_meal_nutrition` | Items (foodId/query + amount) → computed kcal/macros + total. |

**Token discipline:** `dropNull` strips absent fields from workout/expense/week payloads (re-sent
each iteration) but **never from diet tools** — there `null` is a semantic signal (`targets:null` = no objective).

### Write tools (propose→confirm) — [`tools/mutations.js`](functions/ai/tools/mutations.js)

| Tool | Proposes |
|---|---|
| `create_expense` | A new expense (`amountMinor`, category, `spentAt`). |
| `edit_expense` | A change to an existing expense by `expenseId`. |
| `delete_expense` | Removal of an expense by `expenseId`. |
| `mark_meal_eaten` | Tick/untick a *planned* meal by `mealId` (has `verify`). |
| `log_food` | Log ad-hoc eating; nutrition resolved + computed **server-side in `verify`**, never model-supplied. |

> `mark_meal_eaten` ticks a planned meal off; `log_food` records ad-hoc eating. Not interchangeable.

### Elicitation tools (pause & ask) — [`tools/elicitations.js`](functions/ai/tools/elicitations.js)

Non-executing turn-enders (`elicits: true`). No pending-action doc, no confirm half — the user's
answer returns as the next turn.

| Tool | Asks | Rendered by |
|---|---|---|
| `ask_choice` | A question with 2–5 option chips (Phase 1). | `choice_chips.dart` → `answerChoice` |
| `request_input` | A 1–4 field form for a value no tool has (Phase 2). | `input_request_card.dart` → `submitInput` |

**Phase 3:** a `request_input` field keyed `heightCm`/`weightKg` is persisted client-side to the
user's own body data on submit (`AskController._persistBodyData` → `BodyDataWriter`) — height merges
into the diet `BodyProfile`, weight becomes a weigh-in. **Targets/goal are never written**; the
form-submit is the user's own confirmation (no ADR-003 propose→confirm). Rule: **read before you ask**.

### System prompt — [`chat/prompt/`](functions/ai/chat/prompt) (composed in `system_prompt.js`, pinned by `gateway.test.js`)

`persona` · `focus` (answer the exact question) · `formatting` (**plain text**, no Markdown) ·
`numbers` (look figures up, never invent) · `training`/`coaching` (lead with deterministic
`findings`, never contradict/invent one) · `mutations` (propose→confirm; identify by real `id`) ·
`elicitation` (read before you ask; one question per turn) · `safety`. The prompt is static and
cached; only the appended `CONTEXT` block carries the date.

### Other AI features (separate callables — not the chat loop)

| Feature | Callable / entry | Workflow |
|---|---|---|
| **Voice → text** | `aiTranscribe` → [`speech/gateway.js`](functions/ai/speech/gateway.js) | Audio → transcript (Gemini / OpenAI speech providers); the transcript then goes through a normal chat turn. |
| **Workout PDF import** | `aiImportWorkoutPlan` → [`services/workout_import.js`](functions/ai/services/workout_import.js) | One-shot PDF → proposed split JSON (`toolChoice:"any"`). **No server write** — the client's `WorkoutPlanEditPage` is the human gate; saved via `WorkoutPlanRepository.saveSplit`. Streams `import_progress`. |
| **Diet PDF/text import** | `aiImportDietPlan` → [`services/diet_import.js`](functions/ai/services/diet_import.js) | Mirrors workout import; **difference:** kcal/macros never null (schema forces an estimate; each item reports `estimated`). Reviewed in `DietPlanEditPage`, saved via `DietRepository.savePlan`. |
| **Diet plan generation** | `aiGenerateDietPlan` → [`services/diet_generate.js`](functions/ai/services/diet_generate.js) | ADR-007: **model picks foods, catalog prices them, arithmetic fits them.** Two model calls (2nd disambiguates USDA-`ambiguous` items); fitting/allergen refusal is deterministic ([`plan_fitting.js`](functions/ai/plan_fitting.js)). Not streamed. |
| **Weekly coach report** | `weeklyCoachReport` (scheduled) → [`services/coach_report.js`](functions/ai/services/coach_report.js) | **Proactive, deterministic template — no model call.** Pushed into the user's most recent Ask conversation; users with no conversation are skipped. |

### Deterministic engines the model only *explains* (Node mirrors of Dart, pinned by shared golden vectors)

| Engine | Mirrors | Feeds |
|---|---|---|
| [`analytics/workout_analytics.js`](functions/ai/analytics/workout_analytics.js) | `workout_analytics.dart` | `get_training_analysis` (1RM, PRs, status, trends, findings). |
| [`analytics/exercise_analytics.js`](functions/ai/analytics/exercise_analytics.js) | `exercise_analysis.dart` + `plan_adherence.dart` | `get_exercise_analysis` + `planAdherence`. |
| [`analytics/readiness.js`](functions/ai/analytics/readiness.js) | `readiness.dart` | `get_readiness`. |
| [`services/sleep_insights.js`](functions/ai/services/sleep_insights.js) | `sleep_metrics.dart` | Sleep interpretation (`groundedNumerals` filters every numeral). |
| [`../nutrition/resolve.js`](functions/nutrition/resolve.js) | `CompositeFoodResolver` | The ONE food→calories path shared by `resolve_food`, `calculate_meal_nutrition`, `log_food`. |
| [`../diet/rules.js`](functions/diet/rules.js) | diet rules engine | The `findings` the coach leads with. |

**Gotchas:** any prompt/tool change needs a `functions` deploy (owner's creds); offline
`node --test` can't catch model-wire bugs (test against the emulator + real API too); `targets`
(the user's objective) ≠ `nutrition.target` (a plan day's sum); read `consumed.basis` before
characterising a diet number; don't drop the `replaced` flag in stream plumbing or the user keeps
reading figures the server already ruled invented.

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
| [`docs/SLEEP_SYSTEM.md`](docs/SLEEP_SYSTEM.md) | **Sleep: platform capability research + the provenance/accuracy design** | reference |
| [`docs/UX_BLUEPRINT.md`](docs/UX_BLUEPRINT.md) | Interaction/screen blueprints | design intent |
| [`docs/ZIVO-brand-system.md`](docs/ZIVO-brand-system.md) | Motion · tone · meaning identity (colour superseded by ADR-006, type by ADR-009) | reference |
| [`docs/PLAN.md`](docs/PLAN.md) | Long-term milestone plan | aspirational |
| [`docs/DECISIONS/`](docs/DECISIONS) | Architecture decision records (ADRs) | reference |
| [`docs/DECISIONS/ADR-008-presentation-controllers.md`](docs/DECISIONS/ADR-008-presentation-controllers.md) | **When a page gets a controller, and the rules that keep the seam honest** | reference |
| [`docs/DECISIONS/ADR-009-one-type-system.md`](docs/DECISIONS/ADR-009-one-type-system.md) | **Three typefaces, one system — what `AppText` and `TrainType` are each for** | reference |
| [`docs/DECISIONS/ADR-010-sleep-provenance.md`](docs/DECISIONS/ADR-010-sleep-provenance.md) | **Why every sleep number carries how it was produced, and what that forbids** | reference |
| [`docs/DECISIONS/ADR-011-light-mode.md`](docs/DECISIONS/ADR-011-light-mode.md) | **Two skins on one system — how a token resolves, and why you must never cache one** | reference |
| [`docs/DECISIONS/ADR-012-streaks-and-session-duration.md`](docs/DECISIONS/ADR-012-streaks-and-session-duration.md) | **What a streak means, why calendar maths never uses `Duration`, and why a session's duration is measured rather than capped** | reference |
| [`docs/DECISIONS/ADR-013-local-notifications.md`](docs/DECISIONS/ADR-013-local-notifications.md) | **Reminders: local-only notifications, the three deps, and why scheduling is inexact** | reference |
| [`docs/DECISIONS/ADR-014-avatar-firebase-storage.md`](docs/DECISIONS/ADR-014-avatar-firebase-storage.md) | **Why the profile avatar is in Firebase Storage while moments stay on Google Drive** | reference |
| [`docs/DECISIONS/ADR-015-readiness.md`](docs/DECISIONS/ADR-015-readiness.md) | **The Daily Readiness call — derived-not-stored, how the signals fuse, status-colour-not-a-hue, and why the coach half is deploy-staged** | reference |
| [`docs/build_configurations.md`](docs/build_configurations.md) | Build configs + dart-defines | reference |
