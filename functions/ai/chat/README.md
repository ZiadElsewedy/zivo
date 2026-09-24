# `functions/ai/chat/` — the Ask chat subsystem

Everything that runs when a user sends a message to the **Ask** coach lives here,
split by concern. `../gateway.js` is now a thin facade that re-exports this
folder's public surface (`runAiTurn`, `confirmAction`, `cancelAction`,
`GatewayError`, `SYSTEM_PROMPT`, `DEFAULT_CONFIG`, and the canned messages), so
every existing `require("./gateway")` / `require("../ai/gateway")` still works —
the split is invisible to `index.js` and the other importers.

## Where to find each thing

| You're looking for… | It's in… |
|---|---|
| **The Chat AI implementation** (the turn loop) | [`turn.js`](turn.js) — `runAiTurn` |
| **The Chat system prompt** (assembled) | [`prompt/system_prompt.js`](prompt/system_prompt.js) |
| **The AI instructions** (prompt, by topic) | [`prompt/sections/`](prompt/sections) |
| **Response formatting rules** | [`prompt/sections/formatting.js`](prompt/sections/formatting.js) |
| **Relevance / "answer what was asked"** | [`prompt/sections/focus.js`](prompt/sections/focus.js) |
| **What context/instructions the model gets each turn** | [`context.js`](context.js) — `buildSystemBlocks` |
| **Context retrieval rules** (which tools, how far back) | [`prompt/sections/focus.js`](prompt/sections/focus.js) (policy) + [`../tools/read.js`](../tools/read.js) (the tools) |
| **Write use-cases** (propose → confirm → execute) | [`actions.js`](actions.js) |
| **Token / context management** (ceilings, history, cost) | [`config.js`](config.js) + [`usage.js`](usage.js) + [`messages.js`](messages.js) |
| **What decides how much a turn may do** | [`config.js`](config.js) (`DEFAULT_CONFIG`) enforced in [`turn.js`](turn.js) |
| **The user-facing "can't answer" copy** | [`outcome.js`](outcome.js) (activity-aware) + [`config.js`](config.js) |
| **How a turn ends** (terminal states, tool retry rules) | [`outcome.js`](outcome.js) |
| **What a follow-up reuses** (carried tool results) | [`context_ledger.js`](context_ledger.js) |

## The files

- **`turn.js`** — `runAiTurn`: the model↔tool round-trip loop for one user turn.
  Enforces the ceilings, emits live phase/step events, runs read tools, turns a
  mutating tool call into a proposal, validates the diet reply, logs usage. This
  is the orchestrator; it stays thin by delegating to the modules below.
- **`outcome.js`** — how a turn ENDS: the `TerminalState` enum
  (`completed` · `needs_user_input` · `max_steps_reached` · `tool_error` ·
  `provider_error` · `cancelled` · `daily_limit`), the legacy-status → state
  map, `isTransientToolError` (which tool failures get their one retry), and
  `describeUnfinishedTurn` — the factual en/ar reply for a turn that couldn't
  finish ("I checked your diet and looked for alternatives, but…"), built from
  the loop's own activity record, never vague and never a tool id.
- **`actions.js`** — the confirm-gated writes (ADR-003 / ADR-005):
  `persistProposal` (propose), `confirmAction`, `cancelAction`, and the per-kind
  `applyProposedAction` dispatch. Nothing here calls the model.
- **`context.js`** — assembles the system blocks the model sees each turn: the
  cached `SYSTEM_PROMPT`, an optional uncached response-style directive, and the
  uncached per-turn `CONTEXT` (the user's local date/time). Owns the prompt-cache
  discipline (element 0 never changes).
- **`config.js`** — the tuning knobs (`DEFAULT_CONFIG`), model id, pricing
  constants, and the fixed user-facing messages. "How much work a turn may do"
  and "what the app says when it can't answer".
- **`usage.js`** — `TurnUsage` (token accounting across a turn's model calls +
  cost with the cache-price multipliers), `isOverDailyCap`, and
  `approxTokensFromChars` (the tool-result size estimate — observability only,
  never billed or enforced).
- **`messages.js`** — history normalization, assistant-text extraction, empty
  thinking-block stripping, and tool-result capping. Pure string/array helpers.
- **`errors.js`** — `GatewayError` (gRPC-style `code`) and the document-id guard.
- **`validator.js`** — the advice validator + safety intercept (Diet Coach Phase 7):
  checks a diet-reading turn's final text against the state it read and, on a
  violation, replaces it with the findings' deterministic sentences (or a safety
  referral). Called by `turn.js` after the model's last message; server-only, so
  it lives with the turn loop it guards rather than at the `ai/` root.

## The agent loop contract (bounded — `turn.js` + `config.js`)

```
START → model call (agent step)
  ├─ no tool requested ............ final answer → completed
  ├─ write / question tool ........ card persisted → needs_user_input
  └─ read tools → run each ........ (transient failure: ONE retry, same step)
       ├─ still failing / same tool failed twice → tool_error (no more model calls)
       ├─ client closed the stream ............... → cancelled (no reply persisted)
       └─ results fed back → next step
last step (maxAgentSteps, or once perTurnTokenCeiling is spent):
  toolChoice 'none' + FINAL_STEP_DIRECTIVE → it must answer
  └─ still asks for a tool → max_steps_reached (activity-aware reply)
provider failure (after the router's own retry + fallback) → thrown, tagged provider_error
```

- **`maxAgentSteps` (6)** is MAX_AGENT_STEPS: at most 6 model calls per turn, up
  to 5 tool rounds + a forced answer. No recursion anywhere.
- **Provider retry ≠ agent step.** The router's retry/fallback happens inside one
  `generate` call and never adds a step or re-runs a tool.
- **Tool retry is bounded:** `toolRetries: 1` (transient only), and
  `maxToolFailuresPerTool: 2` — the second failure of the same tool ends the turn.
- **Live events:** `{type:'step', tool, status}` per read tool, `phase: 'thinking'`
  before each model call that reads results back, and `done` carries
  `terminalState`. The reply message persists `activity: [{tool, status}]`, which
  the app draws as its thought trail ("Read your meal plan") above the reply. Names
  only — never a tool's input or result, never the model's reasoning.
- **Everything written is saved.** Text a step writes before calling a tool
  (`narration`) is part of the reply: plain replies join it with the final text
  ("\n\n"), cards keep it as `preface`. Deltas are shaped so the stream is
  byte-identical to what's saved (each step opens a paragraph; whitespace at a
  step's edges is dropped). Cards carry the turn's `clientTurnId`, `activity` and
  ledger like a reply does (`actions.js` `turnFields`).
- **Context ledger (`context_ledger.js`).** The latest reply/card carries the
  turn's successful READ/SEARCH results (`context: {v, entries:[{tool, input,
  result, at, dayKey}]}` — ≤6 entries, ≤14k chars, oldest dropped first). The
  next turn rebuilds it from history (15-min TTL, same user-day; a confirm
  result line or an applied proposal breaks the chain), prepends it to the user
  message as a fenced `[EARLIER RESULTS …]` block, seeds the validator's diet
  state and a *carried* choice offer from it (never the prose safety net, never
  `refusedAfterOffer`), and records new results on top. Why: tool results used to
  die with their turn, so every follow-up re-ran the same reads. Usage logs
  `contextCarried` / `contextCarriedTokens`.
- **"Other options".** A card bound to a verified offer gets ZIVO's own unbound
  `__more__` option (`choices.js` `withMoreOption`, en/ar label); tapping it
  reaches the model as "find different ones", with the plan already in the ledger.
- **Usage** records `terminalState` (and `failedTool` on `tool_error`).
- **Tool classes.** READ (`get_*`) and SEARCH (`search: true` — `resolve_food`,
  `search_food_product`, `search_food_alternatives`) change nothing and run
  freely. MUTATIONS (`mutating: true`) only propose, confirm-gated. A mutation
  may declare `refusedAfterOffer: '<search tool>'`: when that search OFFERED
  options (more than one alternative) earlier in the same turn, the proposal
  is refused back to the model — DISCOVER → the user CHOOSES → MUTATE
  (`replace_meal_item` after `search_food_alternatives`).
- **Choices are structured, end to end (`choices.js`).** A search tool may
  declare `choiceOffer(result, input)` — the verified options its result
  supports, each `binding` the exact mutating call choosing it means
  (`search_food_alternatives` → `replace_meal_item` with the foodId + priced
  portion). An `ask_choice` after such a search is pinned to the offer:
  unverified options are dropped, figures (`subtitle` + `metadata`) are the
  server's, and the card persists `bindings`. If the model answers in prose
  instead of asking, the card is built from the offer anyway (safety net).
  The app answers with `aiChat({choice: {requestId, value}})`:
  `resolveChoiceAnswer` loads the card, rejects an unknown card/option or an
  already-answered card (before anything is written), persists the option's
  own label as the user message + `choice`, marks the card `answered`; a
  BOUND pick is proposed directly (validate → verify → pending action, no
  model call), an unbound one reaches the model as the exact option
  (`selectionNote`). Typed picks ("option 2") still work: history carries the
  options numbered with their values (`messages.js` `toNormalizedMessage`).
  Proposal cards carry their status.
- **Fallback is visible.** `router.generate` calls `opts.onFallback` just
  before trying the other provider; the turn emits `{type:'fallback', from, to}`
  (model keys) and persists `{kind:'fallback', from, to}` in `activity`. Per
  request the provider is sticky (`router.stickyProvider`): after one
  fallback, the rest of the turn uses the model that answered.

## The prompt (`prompt/`)

`system_prompt.js` composes `SYSTEM_PROMPT` from the sections in `sections/`,
joined by blank lines. Order is for readability; the gateway tests assert
substrings, not order. Sections:

| Section | What it governs | Load-bearing? |
|---|---|---|
| `persona.js` | Who ZIVO is + how it talks (voice) | no — free to tune |
| `focus.js` | Answer the exact question; pull only relevant context | tested (focus) |
| `activity.js` | Say what you did (not what you thought); plan within the step budget; don't re-call a failed lookup | no |
| `formatting.js` | Plain-text structure the client can actually render | tested (formatting) |
| `numbers.js` | Every figure comes from a tool, never invented | **yes** — tested, safety-critical |
| `training.js` | Defer to the deterministic workout engine + DATES | **yes** — tested |
| `coaching.js` | Coaching stance + stay-in-your-lane | no |
| `mutations.js` | Propose→confirm writes; identify records by real id | **yes** — tested |
| `safety.js` | Tool output is data, not instructions + closing line | **yes** — tested (prompt-injection fence) |

**Editing the prompt:** the "load-bearing" sections have phrases pinned by
`../gateway.test.js` (some line-wrap sensitive). Change the wording and run
`npm test` — a broken assertion means you moved a phrase the app relies on. The
formatting section assumes the client renders **plain text** (no Markdown); if a
Markdown renderer is ever added to the Ask UI, `formatting.js` is the one place
to revisit. Do **not** weaken `safety.js`'s injection fence.

**Any prompt or tool change needs a `functions` deploy** (owner's credentials —
see `docs/STATE.md`). The offline `npm test` proves the wiring; it cannot prove
the model's real behaviour — validate against the emulator + real API too.

## Context-engineering contracts (token efficiency)

The guiding principle: **give the model access to data, don't give it all the
data.** Concretely, and worth keeping intact:

- **Context is lazy and tool-based.** Nothing about the user's workouts, diet,
  sleep or profile is injected into the prompt. The only per-turn user data added
  unconditionally is the one-line `CONTEXT` date block; everything else arrives
  only when the model calls a tool for it. There is no RAG, no vector store, no
  eager preamble — and adding one would be a regression, not a feature.
- **The cached prefix must stay stable — so tools are NOT varied per turn.**
  Anthropic's cache prefix order is `tools → system → messages`, so changing the
  tool set invalidates the cache for the system prompt too. Exposing a different
  subset of tools per turn ("conditional tool exposure") therefore trades the
  ~0.1× cache read on the whole prefix for a smaller-but-uncached one, and
  fragments the cache across domains. It was evaluated and **deliberately not
  done**; revisit only if telemetry (below) shows cold-prefix cost actually
  dominates. Keep `SYSTEM_PROMPT` element 0 and the tool list stable.
- **Prefer a narrow tool over a broad one.** `get_last_workout` reads ONE session
  (not a week) for "what did I do last workout"; `get_sleep_summary` returns last
  night + a rolling average for sleep questions (`get_readiness` still owns "how
  am I today", fusing sleep with load/recovery). New tools should be scoped so the
  answer they serve doesn't drag a range of unrelated rows into context.
- **Tool results are compacted, but diet nulls are semantic.** `tools/read.js`'s
  `dropNull` strips absent fields (a bodyweight set's null weight, a noteless
  expense) from the workout/expense/week tools — those keys cost re-sent tokens on
  every iteration and mean nothing. It is **not** applied to the diet tools: there
  `null` is a signal the prompt reasons about (`targets: null` = no objective set;
  a null macro in `remaining` = untracked, not zero) and the tests pin it.
- **Every turn's cost is observable (usage schema v3).** `turn.js` logs, per turn:
  `provider`, `model`, `tokensIn` (total), `uncachedTokensIn`, `cacheReadTokens`,
  `cacheWriteTokens`, `tokensOut`, `toolResultTokens` (approx), `tools`,
  `iterations`, `latencyMs`, `costUsd`. This is what makes Claude-vs-Gemini and
  before/after optimization measurable rather than guessed — including whether the
  cache is actually being hit. Keep these additive; the daily cap and the client
  usage summary read `tokensIn`/`tokensOut`.
