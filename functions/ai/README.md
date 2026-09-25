# `functions/ai/` — the backend AI

This is the whole AI brain: the Ask chat coach, the plan importers, the diet
generator, the weekly report, voice transcription, and the deterministic engines
they all lean on. The Flutter side (`lib/features/ai/`) is just the UI + the
repository seam that calls into here.

Open a folder by what you're looking for:

| You want… | Look in |
|---|---|
| **The entry points** (what `index.js` calls) | [`gateway.js`](gateway.js) + [`services/`](services) + [`speech/gateway.js`](speech/gateway.js) |
| **Core / orchestration** — how one chat turn runs | [`chat/`](chat/README.md) |
| **The prompts** | [`chat/prompt/`](chat/prompt) |
| **What the model can call** (tools) | [`tools/`](tools) |
| **The model vendors** (Anthropic, Gemini) + routing | [`providers/`](providers) + [`routing/`](routing) |
| **The AI use-cases** (import, generate, report…) | [`services/`](services) |
| **Deterministic engines** (the math the model must *not* do) | [`analytics/`](analytics) |
| **Voice** (speech-to-text) | [`speech/`](speech) |
| **Plumbing** (Firestore, dates, abort, import runtime) | [`shared/`](shared) |

## The map

```
ai/
├─ gateway.js        the aiChat entry facade — re-exports chat/ (runAiTurn, confirm/cancel)
│
├─ chat/             CORE / ORCHESTRATION: turn loop, actions, context, usage, messages,
│  │                 errors, the reply validator — see chat/README.md
│  └─ prompt/        the system prompt, composed from sections/
│
├─ tools/            everything the model can call
│  ├─ read.js                 read-only tools (get_today, get_workouts, resolve_food,
│  │                          search_food_alternatives, …)
│  ├─ mutations.js            confirm-gated writes (create_expense, log_food,
│  │                          create_custom_food, replace_meal_item, … — ADR-003)
│  ├─ elicitations.js         turn-enders that ask the user (ask_choice, request_input)
│  └─ food_search_product.js  search_food_product — a branded product resolve_food can't
│                              find, via a dedicated Gemini Google Search grounding call
│                              (see docs/DIET_AI_FOOD_ASSISTANT_ARCHITECTURE.md)
│
├─ providers/        model adapters behind one NormalizedRequest/Response seam
│  ├─ anthropic_provider.js   (primary)
│  ├─ gemini_provider.js      (when Gemini is the active model; also the only adapter that
│  │                          understands `grounding: {googleSearch}`)
│  └─ provider.js · registry.js · classify.js · legacy_client.js
├─ routing/          models.js — the model catalog: ids + per-model prices (the ONE
│                    place pricing lives). router.js — ONE model per request: the
│                    user's active model, else Claude Sonnet; no fallback. A provider
│                    that can't answer (incl. out-of-credit, which Anthropic sends as a
│                    400) → AiUnavailableError naming provider + reason. `food_search`
│                    is Gemini-only (search grounding has no Anthropic equivalent)
│
├─ services/         the AI USE-CASES (one per callable capability)
│  ├─ workout_import.js · diet_import.js   PDF/text → structured plan
│  ├─ diet_generate.js                     preferences → plan (ADR-007)
│  ├─ coach_report.js                      the weekly proactive digest
│  └─ sleep_insights.js                    sleep interpretation (staged — tested, not yet wired)
│
├─ analytics/        deterministic engines, mirrors of lib/…/domain, pinned to Dart by
│  │                 shared golden vectors in <repo>/test/fixtures/. The model reads
│  │                 their output; it never recomputes it.
│  ├─ workout_analytics.js · exercise_analytics.js
│  ├─ readiness.js · plan_fitting.js
│  └─ training_calendar.js   calendar adherence (trained / inactive days) from sessions
│
├─ speech/           the voice subsystem, self-contained (gateway + providers + routing)
│
└─ shared/           cross-cutting plumbing
   ├─ store.js         the single Firestore seam (the read/persistence boundary)
   ├─ dates.js         timezone-aware day/week resolution (the user's "today")
   ├─ abort.js         "was this a user cancellation?" predicate
   ├─ usage_log.js     UsageMeter + the aiUsage v4 record every non-chat AI request writes
   └─ import_runtime.js per-instance import execution registry (server half of executionId)
```

## How a chat turn connects

```
index.js  →  gateway.js  →  chat/turn.js
                              ├─ providers/ (+ routing/)   the model call
                              ├─ tools/read.js             read the user's data (via shared/store.js)
                              ├─ tools/mutations.js        propose a write (confirm-gated)
                              ├─ tools/elicitations.js     or pause to ask the user
                              ├─ analytics/*               deterministic facts handed to the model
                              └─ chat/validator.js         guard the final reply before it persists
```

**Dependency direction:** `services/` and `tools/` depend on `analytics/` and
`shared/`; nothing in `analytics/` or `shared/` depends back up. `chat/` owns the
turn and its validator. `providers/`/`routing/` know nothing about ZIVO — swapping
or adding a vendor is one adapter file + one route entry.

## Conventions

- **Tests are co-located** (`x.js` + `x.test.js`), offline (`node --test`, no live
  API). Run `npm test` from `functions/`. The analytics + diet-state tests load
  shared golden vectors from the **repo root** `test/fixtures/` (the same files the
  Dart suite runs) — that's why those tests walk up to the repo root, not `functions/`.
- **Schemas live with their owner.** A tool's `input_schema` sits in the tool file;
  an importer's extraction schema sits in the importer. There is no separate
  `schemas/` folder on purpose — splitting a tool across two files hurts more than
  it helps.
- **Any prompt or tool change needs a `functions` deploy** (owner's credentials —
  see `docs/STATE.md`). Offline tests prove the wiring, not the model's behaviour.
