# ai — feature map ("Ask")

> Tool-mediated Claude assistant over the user's own data: streaming answers, read tools,
> and confirm-gated writes, plus voice input. ADRs:
> [ADR-001](../../../docs/DECISIONS/ADR-001-ai-assistant.md) (V1 read-only),
> [ADR-003](../../../docs/DECISIONS/ADR-003-ai-mutations-v2.md) (V2 propose→confirm→execute),
> [ADR-005](../../../docs/DECISIONS/ADR-005-ai-edit-delete-expenses.md) (edit/delete expenses).
> **The model + tools live in the backend** — see `functions/ai/` (below), not just here.
> **For the end-to-end workflow + a table of every tool call across all AI features,
> see [`AGENTS.md` → "AI agent workflow and tool calls"](../../../AGENTS.md#ai-agent-workflow-and-tool-calls).**

## Start here

- `presentation/controllers/ask_controller.dart` — **everything a turn does**
  ([ADR-008](../../../docs/DECISIONS/ADR-008-presentation-controllers.md)): conversation
  resolution and switching, the send path with its idempotency key, optimistic-bubble ↔
  durable-message reconciliation, the streamed-reply pacer, the slow-turn admission and
  landing watchdog, proposal confirm/cancel, and the voice path. A plain `ChangeNotifier`;
  it reaches the screen only through `onError`/`onContentGrew` callbacks, never a
  `BuildContext`. **Start here for behaviour.**
- `presentation/pages/ask_page.dart` — the Ask tab's `build`, plus the state that is
  genuinely about a list of widgets: scroll position and auto-follow, the entrance ledger,
  and which bubble is mid-typewriter. Reached as tab index 2 in the shell; other surfaces
  switch to it via `HomeShell`'s `onOpenAsk`.
- `presentation/ask_constants.dart` — the turn timings and the composer's float clearance,
  shared by the page and its widgets.
- Widgets: `presentation/widgets/ask/` (`message_bubble`, `proposal_card`, `thinking_rail`,
  `sessions_sheet`, `ask_empty_state`, `error_retry`, `ask_effects`), plus the older
  `chat_header.dart`, `voice_composer.dart` (mic → transcript), `quick_log_sheet.dart`.

Turn rules are unit-tested directly in `test/ai/ask_controller_test.dart` — no widget
tree. The `ask_page_*_test.dart` suite still covers what the screen renders.

## Repository (`AppScope.ai`)

- **`AiRepository`** (`domain/ai_repository.dart`) with two impls in `data/`:
  - `firebase_ai_repository.dart` — real: Firestore reads for history + the `aiChat`
    callable (streaming); `aiConfirmAction`/`aiCancelAction` for mutations; `aiTranscribe`
    for voice. **Default when `USE_FIRESTORE` is true.**
  - `fake_ai_repository.dart` — offline/test fallback.
- `data/audio_recorder.dart` — `AudioRecorderService` (owns the mic permission; `record` dep).

## Domain (`domain/`)

`ai_conversation.dart`, `ai_message.dart`, `ai_role.dart`, `ai_turn_event.dart`
(server-authoritative phase events driving the activity rail), `ai_pending_action.dart`
(a proposed write awaiting confirm), `ai_choice_request.dart` (an assistant question with
option chips — Ask elicitation Phase 1; rendered by `widgets/ask/choice_chips.dart`,
answered via `AskController.answerChoice`), `ai_input_request.dart` (an assistant form
asking for typed values — Phase 2; rendered by `widgets/ask/input_request_card.dart`,
answered via `AskController.submitInput`), `body_data_writer.dart` (Phase 3 — the seam the
input form persists height/weight through; impl `data/repository_body_data_writer.dart`
composes the diet `BodyProfile` + workout `BodyWeightRepository`, the same user-owned
writes the manual capture screens use; **never writes targets/goal**),
`ai_response_style.dart`, `ai_model_selection.dart` (the **active model** — a
backend model-catalog key: `'claude-sonnet'` (default) | `'gemini-flash'` — one
model per provider; the retired `'auto'`/`'gemini-pro'`/`'claude-haiku'` and legacy
`'claude'`/`'gemini'` are upgraded on read. Persisted at `users/{uid}/settings/ai`
field `provider`, forwarded on every `send`, and read server-side by the plan
import/generation callables — this model answers first, with the OTHER provider as
an automatic fallback on a transient failure, see below),
`ai_failure.dart` (`AiFailure(kind, provider, issue)` — what every AI repository
method throws in place of a transport error: `unavailable` (the active model's
provider couldn't answer — with WHICH provider and WHY: out of credit · not
configured · busy · overloaded · no response · model retired · down) · `dailyLimit` ·
`timeout` · `network` · `auth` · `notDeployed` · `unknown`. `aiFailureFrom` maps both
the `.call()` `FirebaseFunctionsException` and the **streaming** call's raw
`PlatformException`; `ai_labels.dart`'s `aiFailureTitle`/`aiFailureBody` phrase it, so
no SDK/provider text is ever shown),
`ai_usage_summary.dart` (`AiUsageRecord`, `aiProviderStats`, `aiUsageTotalsBy`), and STT:
`stt_outcome.dart`, `stt_error.dart`.

Plan import (workout + diet) is a single buffered model call — one long,
opaque extraction (~a minute for a real document) with no observable sub-steps,
so the analysing screen sets the wait expectation rather than animating fake
progress. It is cancellable: `import_cancellation.dart` (`ImportCancellation` +
`ImportCancelledException` — pressing X closes the streaming callable, firing
the function's `response.signal` so the backend model call actually aborts, and
the import method throws `ImportCancelledException` instead of resolving). The
import methods carry a `cancellation` handle only; a cancelled import stops the
work (and the billing) instead of running to completion for output nobody reads.

Both the model switch and the reply-style preference live in the **Ask settings
page** (`presentation/pages/ask_settings_page.dart` — a pushed full page, opened
from the single header settings button, which shows a small "pinned" dot when
the model isn't Auto). Each model row carries its provider's brand mark
(`widgets/ask/provider_mark.dart` — code-drawn Gemini spark / Anthropic burst,
no image assets). Selecting a row applies in place via the controller's
`setModelSelection`/`setResponseStyle`; there is no separate Save. The active model
wears an **"Active" badge** as well as the check. The page also shows a
**per-provider usage** section (tokens, requests, est. cost) read via
`AiRepository.usageByProvider()`; tapping a provider opens
**`pages/ai_usage_page.dart`** (also Settings → AI usage) switched to it: a
Claude | Gemini switch, then that provider's estimated cost and cost per completed
request, requests by type (total · chat · generate · import · other · failed), tokens
(used · input · output) and its latest requests, read via
`AiRepository.usageRecords()` from the owner-readable `aiUsage` log — which holds
**every** AI request (chat, imports, plan builder, food search, voice), each priced by
the backend at the rate of the model that answered.

**Retry** (`AskController.retry`) re-sends the failed turn's text from `_turnText`,
not the optimistic bubble: the server saves the user message *before* the model
call, so on a model failure the bubble has already been retired — Retry used to find
nothing to send. It reuses the turn id (no duplicate) and the model active *now*, so
"Claude isn't available → Switch model → Retry" works.

## Backend — the real brain ([`functions/ai/`](../../../functions/ai))

> The backend is now organized by responsibility — `chat/` (orchestration + prompt),
> `tools/`, `providers/` + `routing/`, `services/` (the use-cases), `analytics/`
> (deterministic engines), `speech/`, and `shared/` (plumbing). Its own map is
> [`functions/ai/README.md`](../../../functions/ai/README.md) — read that first.

| File | Role |
|---|---|
| `gateway.js` | Ask entrypoint — now a thin **facade** re-exporting `chat/` (`runAiTurn`, `confirmAction`, `cancelAction`, `GatewayError`, `SYSTEM_PROMPT`, `DEFAULT_CONFIG`). The split is invisible to callers |
| **`chat/`** | The chat subsystem, split by concern (see [`chat/README.md`](../../../functions/ai/chat/README.md)): `turn.js` (the model↔tool loop), `actions.js` (propose→confirm→execute writes), `context.js` (the system blocks handed to the model each turn + prompt-cache discipline), `config.js` (ceilings/pricing/canned messages), `usage.js` (token accounting + cost + daily cap; logs per-turn observability — provider/model, uncached vs cached input, output, approx tool-result tokens, tools, iterations, latency, cost — as `aiUsage` **schema v3**), `messages.js` (history + tool-result shaping), `errors.js` (`GatewayError`) |
| **`chat/prompt/`** | The **system prompt**, composed in `system_prompt.js` from `sections/` — `persona` · **`focus`** (answer the exact question, pull only relevant context) · **`formatting`** (plain-text structure the client renders) · `numbers` · `training` · `coaching` · `mutations` · `safety`. The load-bearing sections are pinned by `gateway.test.js`; `formatting` assumes the client renders **plain text** (no Markdown) |
| `tools/read.js` | uid-scoped **read** tools — `get_today`, `get_diet`, `get_workouts`, **`get_last_workout`**, **`get_training_analysis`**, `get_expenses`, `summarize_week`, **`get_readiness`**, **`get_sleep_summary`**, plus **`resolve_food`** (a food → its `foodId` + per-100g nutrition, or `ambiguous`/`notFound`) and **`calculate_meal_nutrition`** (items → computed kcal/macros + total). Every payload states the **date** it resolved; diet payloads carry the user's `targets`, what's `remaining` of them, and the `estimated` provenance of every figure. `get_expenses` surfaces each expense's `id` so edit/delete can target it. **`get_workouts` returns the REAL per-set actuals** from `workoutSessions` (weight/reps/type/outcome per set — warm-ups flagged, skipped/pending dropped), never the lossy flat log; **`get_last_workout`** returns just the SINGLE most recent completed session (with each exercise's top working set precomputed) so "what did I do last workout" doesn't fetch a whole week; **`get_training_analysis` hands the model ZIVO's deterministic workout analysis + typed `findings`** (see `workout_analytics.js`) so it phrases strength/PRs/trends, never computes them — and now also **`planAdherence`** (planned movements being skipped/gone-stale, from `exercise_analytics.js` + `store.getActiveWorkoutPlan`); **`get_exercise_analysis`** resolves ONE lift by name and returns its full session-by-session history, session-to-session deltas, verdict/tone and deterministic insight (the drill-down the model explains, never recomputes); **`get_sleep_summary`** returns last night vs target + a rolling average for sleep-specific questions (`get_readiness` still owns "how am I today", fusing sleep with load/recovery). **Token discipline:** `dropNull` strips absent fields from the workout/expense/week payloads (re-sent every tool iteration), but **never from the diet tools** — there a `null` is a semantic signal (`targets:null` = no objective) the prompt reasons about |
| `analytics/workout_analytics.js` | the **workout analytics engine** — the Node mirror of `lib/features/workout/domain/analytics/workout_analytics.dart`, pinned to it by shared golden vectors (`test/fixtures/workout_analytics_vectors.json`, run by both suites). Estimated 1RM (Epley), PRs derived from history, per-exercise status (thresholded, min-3-appearance, warm-ups excluded), per-muscle rollup, working-volume trend, and `fact`/`interpretation`-typed findings. `store.listWorkoutSessions` feeds it |
| `analytics/exercise_analytics.js` | the **per-exercise drill-down + plan-adherence engine** — the Node mirror of `exercise_analysis.dart` + `plan_adherence.dart`, reusing `workout_analytics.js`'s primitives. `analyzeExercise` (one lift's session records, session-to-session deltas, **intensity-first** verdict/tone, PRs, frequency, insight) and `analyzePlanAdherence` (skipped/never-trained/stale planned movements). The numeric facts + verdict/tone + change tags + adherence reasons are pinned to Dart by the `exerciseAnalysis`/`planAdherence` golden vectors (both suites); the insight PROSE is generated per side, not pinned |
| `shared/dates.js` | timezone-aware day/week/month resolution — takes the client's `offsetMinutes` so "today" is the **user's** today, not the server's UTC one |
| `tools/mutations.js` | confirm-gated **write** tools (propose → confirm → execute): `create_expense`, `edit_expense`, `delete_expense`, `mark_meal_eaten`, **`log_food`** (logs what the user ate; nutrition computed server-side in `verify`, never supplied by the model) |
| `tools/elicitations.js` | **elicitation** tools (non-executing turn-enders, `elicits: true`) that PAUSE the turn to ask the user instead of guessing: **`ask_choice`** (Phase 1 — option chips) and **`request_input`** (Phase 2 — a 1–4 field form for a value no tool has). `runAiTurn` persists either as a `choice_request` / `input_request` assistant message (via `chat/actions.js` `persistElicitation`, generic over `tool.messageKind`/`fields`); status is `awaiting-input`. Unlike a write proposal there's **no pending-action doc and no confirm/execute half** — the user's answer returns as an ordinary next `aiChat` turn (client `AskController.answerChoice` / `submitInput`), which is how the coach continues. **Phase 3:** a `request_input` field keyed `heightCm`/`weightKg` is persisted client-side to the user's own body data on submit (via `AskController._persistBodyData` → `BodyDataWriter`), so the coach asks once — height merges into the diet `BodyProfile`, weight becomes a weigh-in; **targets/goal are never written** (the form-submit itself is the user's confirmation, so no ADR-003 propose→confirm — the user is entering their own data, not the model). Prompt rules live in `chat/prompt/sections/elicitation.js` (**read before you ask** — `get_today` already carries profile/weight/age; one question per turn) |
| `../nutrition/resolve.js` | the ONE server path from a food reference (query or `foodId`) + an amount to calories — mirrors the Dart `CompositeFoodResolver` (custom foods layered over USDA). Shared by `resolve_food`, `calculate_meal_nutrition` and `log_food` so they can't disagree |
| `chat/validator.js` | **advice validator + safety intercept** (Phase 7): checks the model's reply against the diet state it read and, on a violation, replaces it with the findings' deterministic text (or a safety message). Server-only — replies are generated only here |
| `services/workout_import.js`, `services/diet_import.js` | PDF → structured plan extractors |
| `services/coach_report.js` | weekly AI coach report |
| `shared/store.js`, `shared/dates.js` | Firestore access + date helpers |

**Providers & routing (`functions/ai/providers/` + `routing/router.js`).** The
model call is behind a `NormalizedRequest`/`NormalizedResponse` seam so a turn's
orchestration never names a vendor. `anthropic_provider.js` and
`gemini_provider.js` are the two real adapters; `routing/models.js` is the model
catalog (Claude Sonnet 5 · Gemini Flash — one model per provider, ids and
per-model prices, the one place pricing lives). `router.js` resolves each request
to the user's active model, else Claude Sonnet. A TRANSIENT failure (overload,
rate limit, server error, timeout, network — `isTransientFailure` in
`providers/classify.js`) is retried once on the same provider after a short
backoff, then automatically re-run on the OTHER provider if still failing — the
response then carries `requestedProvider`/`requestedModel`/`fallbackOccurred`/
`fallbackReason`. A PERMANENT failure (billing — Anthropic's out-of-credit is a
*400* — auth, retired model, or a malformed request) is never retried or fallen
back for → `AiUnavailableError` → `unavailable` with `details:
{reason:'ai_unavailable', provider, model, kind}`; a malformed request is
rethrown as-is. `food_search` always runs on Gemini and never falls back (search
grounding is Gemini-only).
Adding OpenAI/DeepSeek later is one adapter file + catalog entries. See
`gateway.js`/`chat/turn.js` (both take an injected `provider`).

Each has a `*.test.js` (`node --test`, offline — canned fake model, no live API).

## Live progress (what the rail and the import screens show)

Both surfaces report **real backend state**, never a timer.

- **Ask.** `gateway.js` emits `{type:'phase'}` for the loop's coarse boundaries and
  `{type:'step', tool, status}` as each **read** tool starts and finishes. Only the tool
  *name* crosses the wire — never its input or result — and `AskController._stepLabel`
  maps it to human copy ("Reading today's diet…"). A running step outranks the phase; an
  unknown tool falls back to "Working…" so a newer server can't leak a raw identifier onto
  an older client. **Activity timeline:** the controller also keeps every step in order
  (`AskController.activity`, `AiActivityStep`), drawn by `widgets/ask/activity_timeline.dart`
  as chips — "✓ Grab · Diet details", "◌ Search · Food alternatives" (`aiActivityLabel` in
  `ai_labels.dart`; unknown tools are omitted) — above the rail, which says "Thinking…"
  on the `thinking` phase the gateway emits between tool rounds. The reply message carries
  the same list (`AiMessage.activity`, from the doc's `activity`), so `MessageBubble` draws
  the timeline above the reply live and on reload. Never the model's reasoning, never a
  tool's input/result. The loop behind it is bounded — see `functions/ai/chat/README.md`. Mutating tools emit no step: they propose rather than execute, which
  `preparing_change` and the confirmation card already describe.
- **PDF/photo import.** `aiImportWorkoutPlan` / `aiImportDietPlan` are single buffered
  extractions — one opaque model call (`toolChoice: "any"` forces a tool call, so the turn
  emits **no assistant text** to stream either way). There is no live sub-progress to
  report: the analysing screen shows a fixed wait line ("This can take up to a minute")
  rather than fake motion, so **a stalled import visibly stalls.** The one thing the screen
  streams is *cancellation* — the callable stays open so pressing X can close it and abort
  the model call (see `import_cancellation.dart`).
- **Chat is opt-in streaming**: without `acceptsStreaming` the `send` call is buffered and
  byte-identical to before. Import has no streaming toggle — it is always the buffered call
  above, carrying only a `cancellation` handle.
- **`aiGenerateDietPlan`** cycles written lines on the analysing screen, and
  `diet_import_page` says so in a comment — it designs a plan rather than extracting one,
  so there is no document to read against.

## Gotchas

- **Offline tests can't catch model-wire bugs.** Streaming vs buffered paths differ (e.g.
  the empty-`thinking`-block signature issue fixed in `gateway.js`'s `stripEmptyThinking`);
  validate real changes against the emulator + real API, not just `node --test`.
- **Any prompt/tool change needs a `functions` deploy** (owner's creds — see `docs/STATE.md`).
- **The model may not invent numbers — it looks them up.** The NUMBERS section forbids
  stating any figure about the user's data that didn't come from a tool result in that
  turn. Since Phase 6 the coach *does* have tools onto the catalog (`resolve_food`,
  `calculate_meal_nutrition`) and can log food (`log_food`) — but the number always comes
  from the tool, computed server-side, never from the model's own nutritional knowledge.
  So "I ate two eggs and 100g of rice" is resolved-and-computed, not guessed; and a food
  the catalog lacks (`notFound`) or a raw/cooked fork (`ambiguous`) is surfaced, not
  papered over. `gateway.test.js` asserts the prompt still says this; don't soften it
  without reading [the Diet Coach audit](../../../docs/DIET_COACH_AUDIT.md).
- **`log_food` never trusts a model-supplied calorie.** The model names foods and amounts;
  `log_food.verify` resolves each against the real catalog (+ the user's custom foods) and
  computes the nutrition, refusing — back to the model, with the reason — anything it can't
  resolve. The figures are snapshotted into the log entry at propose time, so they're
  frozen and can't drift if the catalog is rebuilt. To tick a *planned* meal off, that's
  still `mark_meal_eaten`, not `log_food`.
- **The reply is validated before it's persisted (Phase 7).** When a turn read diet data,
  `validator.js` checks the model's final text against that state: a calorie figure that
  traces to nothing in the state, a claim of eating when nothing's logged, an "over/under"
  on an untracked macro, or a *recommendation* to eat below the safety floor is rejected and
  the reply falls back to the findings' deterministic sentences (or, for safety, a
  professional-referral message). It biases hard to precision — hypotheticals and
  general-knowledge facts are excluded — because a false rejection replaces a good reply.
  The outcome is logged to usage and shows in the turn status (`validated-fallback` /
  `safety-intercept`). On a streamed turn the draft has already reached the client, so the
  `done` event carries **`replaced`** — `AiPhaseEvent.replaced`, which `ask_page` acts on by
  retiring the live bubble the moment the verdict lands and letting the validated message
  type itself in. Don't drop that flag when touching the stream plumbing: without it the
  user goes on reading figures the server has already ruled invented until Firestore
  catches up. (Buffering diet turns server-side until after validation is the fuller fix,
  and is not done.)
- **The coach is handed decisions, not just data.** The diet payload carries `findings`
  from the deterministic rules engine (`functions/diet/rules.js`) — ranked, capped at three,
  each typed and evidenced. The prompt tells the model to lead with them, never to
  contradict one, and never to invent a recommendation they don't contain. New coaching
  behaviour goes in the engine; the prompt is delivery, not policy.
- **The diet tool payload IS a `DietState`** — the same object, built by the same rules,
  that the Diet screen renders (`functions/diet/state.js` mirrors
  `lib/features/diet/domain/diet_state_builder.dart`; `test/fixtures/diet_state_vectors.json`
  is run by both suites so they cannot drift). It carries a `quality` block naming what the
  app does *not* know. Don't add a second way to derive "how is the user doing".
- **Read `consumed.basis` before characterising a number.** Three kinds of day, three
  different claims: `logged by the user` (safe to say "you ate"), `materialised from
  ticked plan meals, not weighed` (say "your plan values what you've ticked at N"), and
  `nothing logged` (an empty log means nothing was recorded, NOT that they haven't
  eaten). `logEntries` lists the individual foods.
- **Two things are called "target" and they are not the same.** `targets` is the user's own
  objective (goal + daily numbers they set); `nutrition.target` is what a plan day happens to
  add up to. The prompt coaches against the first and describes the second. When `targets` is
  null the user has set no objective and the coach must say so rather than treating the plan's
  sum as a goal. `remaining` is computed server-side from **ticked meals**, not a food log —
  it means "the plan values what you ticked at N", and the prompt says so.
- **The turn carries the date.** Nothing else does — the prompt is static and cached, the
  history is undated. `runAiTurn` appends an uncached `CONTEXT` system block with the
  user's local date/weekday/time, built from the `utcOffsetMinutes` the client sends.
- **Mutating tools may declare `verify`** (see `mark_meal_eaten`): an async check of the
  proposed input against the user's real stored data, run *before* a card is shown, whose
  return value patches the payload. `validate` proves shape; `verify` proves the thing
  actually exists.
- Writes are **always** confirmation-gated (ADR-003) — never make the AI execute a mutation
  without the propose→confirm step. This holds for edits/deletes too (ADR-005): the model must
  identify the exact record by its real `id` (from a read tool) and still wait on Confirm.
