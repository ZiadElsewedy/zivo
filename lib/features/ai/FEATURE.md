# ai — feature map ("Ask")

> Tool-mediated Claude assistant over the user's own data: streaming answers, read tools,
> and confirm-gated writes, plus voice input. ADRs:
> [ADR-001](../../../docs/DECISIONS/ADR-001-ai-assistant.md) (V1 read-only),
> [ADR-003](../../../docs/DECISIONS/ADR-003-ai-mutations-v2.md) (V2 propose→confirm→execute),
> [ADR-005](../../../docs/DECISIONS/ADR-005-ai-edit-delete-expenses.md) (edit/delete expenses).
> **The model + tools live in the backend** — see `functions/ai/` (below), not just here.

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
(a proposed write awaiting confirm), `ai_response_style.dart`, and STT: `stt_outcome.dart`,
`stt_error.dart`.

## Backend — the real brain ([`functions/ai/`](../../../functions/ai))

| File | Role |
|---|---|
| `gateway.js` | Ask entrypoint — now a thin **facade** re-exporting `chat/` (`runAiTurn`, `confirmAction`, `cancelAction`, `GatewayError`, `SYSTEM_PROMPT`, `DEFAULT_CONFIG`). The split is invisible to callers |
| **`chat/`** | The chat subsystem, split by concern (see [`chat/README.md`](../../../functions/ai/chat/README.md)): `turn.js` (the model↔tool loop), `actions.js` (propose→confirm→execute writes), `context.js` (the system blocks handed to the model each turn + prompt-cache discipline), `config.js` (ceilings/pricing/canned messages), `usage.js` (token accounting + cost + daily cap), `messages.js` (history + tool-result shaping), `errors.js` (`GatewayError`) |
| **`chat/prompt/`** | The **system prompt**, composed in `system_prompt.js` from `sections/` — `persona` · **`focus`** (answer the exact question, pull only relevant context) · **`formatting`** (plain-text structure the client renders) · `numbers` · `training` · `coaching` · `mutations` · `safety`. The load-bearing sections are pinned by `gateway.test.js`; `formatting` assumes the client renders **plain text** (no Markdown) |
| `tools.js` | uid-scoped **read** tools — `get_today`, `get_diet`, `get_workouts`, **`get_training_analysis`**, `get_expenses`, `summarize_week`, plus **`resolve_food`** (a food → its `foodId` + per-100g nutrition, or `ambiguous`/`notFound`) and **`calculate_meal_nutrition`** (items → computed kcal/macros + total). Every payload states the **date** it resolved; diet payloads carry the user's `targets`, what's `remaining` of them, and the `estimated` provenance of every figure. `get_expenses` surfaces each expense's `id` so edit/delete can target it. **`get_workouts` returns the REAL per-set actuals** from `workoutSessions` (weight/reps/type/outcome per set — warm-ups flagged, skipped/pending dropped), never the lossy flat log; **`get_training_analysis` hands the model ZIVO's deterministic workout analysis + typed `findings`** (see `workout_analytics.js`) so it phrases strength/PRs/trends, never computes them — and now also **`planAdherence`** (planned movements being skipped/gone-stale, from `exercise_analytics.js` + `store.getActiveWorkoutPlan`); **`get_exercise_analysis`** resolves ONE lift by name and returns its full session-by-session history, session-to-session deltas, verdict/tone and deterministic insight (the drill-down the model explains, never recomputes) |
| `workout_analytics.js` | the **workout analytics engine** — the Node mirror of `lib/features/workout/domain/analytics/workout_analytics.dart`, pinned to it by shared golden vectors (`test/fixtures/workout_analytics_vectors.json`, run by both suites). Estimated 1RM (Epley), PRs derived from history, per-exercise status (thresholded, min-3-appearance, warm-ups excluded), per-muscle rollup, working-volume trend, and `fact`/`interpretation`-typed findings. `store.listWorkoutSessions` feeds it |
| `exercise_analytics.js` | the **per-exercise drill-down + plan-adherence engine** — the Node mirror of `exercise_analysis.dart` + `plan_adherence.dart`, reusing `workout_analytics.js`'s primitives. `analyzeExercise` (one lift's session records, session-to-session deltas, **intensity-first** verdict/tone, PRs, frequency, insight) and `analyzePlanAdherence` (skipped/never-trained/stale planned movements). The numeric facts + verdict/tone + change tags + adherence reasons are pinned to Dart by the `exerciseAnalysis`/`planAdherence` golden vectors (both suites); the insight PROSE is generated per side, not pinned |
| `dates.js` | timezone-aware day/week/month resolution — takes the client's `offsetMinutes` so "today" is the **user's** today, not the server's UTC one |
| `mutations.js` | confirm-gated **write** tools (propose → confirm → execute): `create_expense`, `edit_expense`, `delete_expense`, `mark_meal_eaten`, **`log_food`** (logs what the user ate; nutrition computed server-side in `verify`, never supplied by the model) |
| `../nutrition/resolve.js` | the ONE server path from a food reference (query or `foodId`) + an amount to calories — mirrors the Dart `CompositeFoodResolver` (custom foods layered over USDA). Shared by `resolve_food`, `calculate_meal_nutrition` and `log_food` so they can't disagree |
| `validator.js` | **advice validator + safety intercept** (Phase 7): checks the model's reply against the diet state it read and, on a violation, replaces it with the findings' deterministic text (or a safety message). Server-only — replies are generated only here |
| `workout_import.js`, `diet_import.js` | PDF → structured plan extractors |
| `coach_report.js` | weekly AI coach report |
| `store.js`, `dates.js` | Firestore access + date helpers |

Each has a `*.test.js` (`node --test`, offline — canned fake model, no live API).

## Live progress (what the rail and the import screens show)

Both surfaces report **real backend state**, never a timer.

- **Ask.** `gateway.js` emits `{type:'phase'}` for the loop's coarse boundaries and
  `{type:'step', tool, status}` as each **read** tool starts and finishes. Only the tool
  *name* crosses the wire — never its input or result — and `AskController._stepLabel`
  maps it to human copy ("Reading today's diet…"). A running step outranks the phase; an
  unknown tool falls back to "Working…" so a newer server can't leak a raw identifier onto
  an older client. Mutating tools emit no step: they propose rather than execute, which
  `preparing_change` and the confirmation card already describe.
- **PDF/photo import.** `aiImportWorkoutPlan` / `aiImportDietPlan` stream. These turns emit
  **no assistant text** (`toolChoice: "any"` forces a tool call), so the only thing moving
  is the structured output being written — `ai/import_progress.js` scans that partially
  streamed tool input for *complete* `"key": "value"` pairs and reports days/meals and item
  counts as they land. Progress only ever grows, and a half-written label is never shown.
  The screens previously cycled three hardcoded lines on a 1.6s timer, which moved whether
  or not the backend did; **a stalled import now visibly stalls.**
- Both are **opt-in**: without `acceptsStreaming` (chat) or `onProgress` (import) the call
  is buffered and byte-identical to before.
- **`aiGenerateDietPlan` was NOT converted** — it still cycles written lines, and
  `diet_import_page` says so in a comment. That asymmetry is deliberate, not an oversight.

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
