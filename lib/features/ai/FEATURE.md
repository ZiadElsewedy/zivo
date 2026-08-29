# ai — feature map ("Ask")

> Tool-mediated Claude assistant over the user's own data: streaming answers, read tools,
> and confirm-gated writes, plus voice input. ADRs:
> [ADR-001](../../../docs/DECISIONS/ADR-001-ai-assistant.md) (V1 read-only),
> [ADR-003](../../../docs/DECISIONS/ADR-003-ai-mutations-v2.md) (V2 propose→confirm→execute),
> [ADR-005](../../../docs/DECISIONS/ADR-005-ai-edit-delete-expenses.md) (edit/delete expenses).
> **The model + tools live in the backend** — see `functions/ai/` (below), not just here.

## Start here

- `presentation/pages/ask_page.dart` — the Ask tab (chat, streaming, empty-state
  suggestions). Reached as tab index 2 in the shell; other surfaces switch to it via
  `HomeShell`'s `onOpenAsk`.
- Widgets: `chat_header.dart`, `voice_composer.dart` (mic → transcript), `quick_log_sheet.dart`.

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
| `gateway.js` | Ask entrypoint: streaming, prompt-cache prefix, history trim, tool loop, **system prompt (coach persona)**, confirm/execute dispatch (`applyProposedAction`) |
| `tools.js` | uid-scoped **read** tools — `get_today`, `get_diet`, `get_workouts`, `get_expenses`, `summarize_week`. Every payload states the **date** it resolved, and diet figures carry their `estimated` provenance. `get_expenses` surfaces each expense's `id` so edit/delete can target it |
| `dates.js` | timezone-aware day/week/month resolution — takes the client's `offsetMinutes` so "today" is the **user's** today, not the server's UTC one |
| `mutations.js` | confirm-gated **write** tools (propose → confirm → execute): `create_expense`, `edit_expense`, `delete_expense`, `mark_meal_eaten` |
| `workout_import.js`, `diet_import.js` | PDF → structured plan extractors |
| `coach_report.js` | weekly AI coach report |
| `store.js`, `dates.js` | Firestore access + date helpers |

Each has a `*.test.js` (`node --test`, offline — canned fake model, no live API).

## Gotchas

- **Offline tests can't catch model-wire bugs.** Streaming vs buffered paths differ (e.g.
  the empty-`thinking`-block signature issue fixed in `gateway.js`'s `stripEmptyThinking`);
  validate real changes against the emulator + real API, not just `node --test`.
- **Any prompt/tool change needs a `functions` deploy** (owner's creds — see `docs/STATE.md`).
- **The model may not invent numbers.** The system prompt's NUMBERS section forbids
  stating any figure about the user's data that didn't come from a tool result in that
  turn, and says outright that there is **no food database** behind it — so "I ate two
  eggs and rice" must be answered with what the app knows, not a guess. `gateway.test.js`
  asserts the prompt still says this; don't soften it without reading
  [the Diet Coach audit](../../../docs/DIET_COACH_AUDIT.md).
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
