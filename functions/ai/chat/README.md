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
| **Context retrieval rules** (which tools, how far back) | [`prompt/sections/focus.js`](prompt/sections/focus.js) (policy) + [`../tools.js`](../tools.js) (the tools) |
| **Write use-cases** (propose → confirm → execute) | [`actions.js`](actions.js) |
| **Token / context management** (ceilings, history, cost) | [`config.js`](config.js) + [`usage.js`](usage.js) + [`messages.js`](messages.js) |
| **What decides how much a turn may do** | [`config.js`](config.js) (`DEFAULT_CONFIG`) enforced in [`turn.js`](turn.js) |
| **The user-facing "can't answer" copy** | [`config.js`](config.js) |

## The files

- **`turn.js`** — `runAiTurn`: the model↔tool round-trip loop for one user turn.
  Enforces the ceilings, emits live phase/step events, runs read tools, turns a
  mutating tool call into a proposal, validates the diet reply, logs usage. This
  is the orchestrator; it stays thin by delegating to the modules below.
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
  cost with the cache-price multipliers) and `isOverDailyCap`.
- **`messages.js`** — history normalization, assistant-text extraction, empty
  thinking-block stripping, and tool-result capping. Pure string/array helpers.
- **`errors.js`** — `GatewayError` (gRPC-style `code`) and the document-id guard.

## The prompt (`prompt/`)

`system_prompt.js` composes `SYSTEM_PROMPT` from the sections in `sections/`,
joined by blank lines. Order is for readability; the gateway tests assert
substrings, not order. Sections:

| Section | What it governs | Load-bearing? |
|---|---|---|
| `persona.js` | Who ZIVO is + how it talks (voice) | no — free to tune |
| `focus.js` | Answer the exact question; pull only relevant context | tested (focus) |
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
