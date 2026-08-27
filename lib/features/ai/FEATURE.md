# ai — feature map ("Ask")

> Tool-mediated Claude assistant over the user's own data: streaming answers, read tools,
> and confirm-gated writes, plus voice input. ADRs:
> [ADR-001](../../../docs/DECISIONS/ADR-001-ai-assistant.md) (V1 read-only),
> [ADR-003](../../../docs/DECISIONS/ADR-003-ai-mutations-v2.md) (V2 propose→confirm→execute).
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
| `gateway.js` | Ask entrypoint: streaming, prompt-cache prefix, history trim, tool loop, **system prompt (coach persona)** |
| `tools.js` | uid-scoped **read** tools |
| `mutations.js` | confirm-gated **write** tools (propose → confirm → execute) |
| `workout_import.js`, `diet_import.js` | PDF → structured plan extractors |
| `coach_report.js` | weekly AI coach report |
| `store.js`, `dates.js` | Firestore access + date helpers |

Each has a `*.test.js` (`node --test`, offline — canned fake model, no live API).

## Gotchas

- **Offline tests can't catch model-wire bugs.** Streaming vs buffered paths differ (e.g.
  the empty-`thinking`-block signature issue fixed in `gateway.js`'s `stripEmptyThinking`);
  validate real changes against the emulator + real API, not just `node --test`.
- **Any prompt/tool change needs a `functions` deploy** (owner's creds — see `docs/STATE.md`).
- Writes are **always** confirmation-gated (ADR-003) — never make the AI execute a mutation
  without the propose→confirm step.
