# ADR-003: Ask V2 — mutations with confirmation (propose → confirm → execute)

**Status:** Accepted (2026-08-16) — Phase -1 UX approved and open decisions resolved (see below).
Implementation may proceed on `feature/performance`'s successor work. Supersedes the "read-only"
clause of ADR-001 for a bounded, confirmation-gated set of writes.
**Date:** 2026-08-16
**Deciders:** Ziad (owner) · implementer
**Supersedes / relates to:** `docs/DECISIONS/ADR-001-ai-assistant.md` (V1, read-only — this is
the "V2 (ADR-later)" it deferred); `docs/PLAN.md` §11 (AI architecture), §12 (tools).

---

> **Implementation status is not tracked in this ADR.** The propose→confirm→execute
> flow is built and live; see [`../STATE.md`](../STATE.md) for current AI state and
> [`../../lib/features/ai/FEATURE.md`](../../lib/features/ai/FEATURE.md) for where the code
> lives. (A stale 2026-08-16 "where Ask is today" handoff block was removed here 2026-08-27 —
> ADRs record the decision, not the handoff.)

## Context

V1 answers questions over the user's own data but cannot change anything; the system prompt
hard-codes *"strictly READ-ONLY … never claim to have done so."* The natural next capability is
letting Ask **act** — "add a task to submit the report Friday", "log a 12 EGP coffee", "put gym at
6pm tomorrow on my schedule" — without leaving the chat.

The hard constraint (ADR-001, non-negotiable): **no silent writes.** Every mutation must be
explicitly confirmed by the user before it touches Firestore, and the assistant must never claim
to have done something it hasn't. This ADR defines how confirmation fits the existing
gateway architecture with **no re-architecture** — mutations slot into the same tool→gateway loop.

---

## Decision (summary)

Adopt a **two-phase, server-authoritative propose → confirm → execute** flow:

1. **Propose.** Mutating tools (`create_task`, `create_expense`, …) are declared to the model but
   are **non-executing**. When the model calls one, the gateway does **not** write. It validates
   the proposed input server-side, persists a **pending action** record, appends an
   `action_proposal` message describing the change in human terms, and **ends the turn** — no
   `tool_result` is fed back, so the loop stops cleanly awaiting the user.
2. **Confirm.** The client renders a **confirmation card** (the proposed change + Confirm / Cancel).
   Nothing has been written yet.
3. **Execute.** On Confirm, the client calls a new callable `aiConfirmAction({conversationId,
   actionId})`. The gateway re-validates the still-pending action, performs the write through the
   `store` seam (idempotent, keyed by `actionId`), marks the action `applied`, and appends an
   `assistant` result message ("Added 'Submit report' due Fri"). On Cancel, `aiCancelAction` marks
   it `cancelled` and appends a brief note. The model is not re-invoked on confirm in the first
   slice (deterministic, cheap); a follow-up model turn for a natural closing line is a later polish.

Why server-authoritative and not "let the client apply the write": the client is untrusted, and V1
already made messages/writes server-only. Keeping the write inside the Cloud Function (Admin SDK)
means one audited entry point, server-side field validation mirroring the Firestore rules, and no
new client write-paths or rule loosening.

---

## Phase -1 — UX first (approve before any code)

Per the project's UX-first rule, the confirmation experience is designed and approved before
implementation. Proposed experience:

- **Confirmation card in the chat stream.** When Ask proposes a change, the assistant "bubble" is
  replaced/accompanied by a card: an icon + one-line summary ("**New task** · Submit report · due
  Fri 22 Aug · High"), the key fields, and two buttons — **Confirm** (iris, filled) and **Cancel**
  (text). Matches the existing iris theme, `AppSpacing`, `AppColors`, `AppText`.
- **States:** pending (buttons active) → on Confirm: card collapses to a compact "✓ Added" result
  line; on Cancel: "Cancelled" line. Disabled/expired pending actions (see expiry) render as
  "This suggestion expired — ask again."
- **One pending action at a time** in the first slice (the model is instructed to propose a single
  change per turn). Multiple/batched proposals are a later iteration.
- **No destructive actions in V2.** Create-only to start (see scope). No `delete_*` or `edit_*`
  until create is proven and the confirmation UX is trusted.
- **Honesty:** until the user taps Confirm, the assistant text must be phrased as a proposal
  ("I can add…", "Want me to log…"), never as done. Enforced by the system prompt.

*Deliverable for Phase -1: a short mock/description of the card in each state, owner-approved.*

---

## Architecture

### Server (`functions/ai/`)

- **`tools.js`:** add mutating tools with an explicit `mutating: true` flag and a `validate(input)`
  that returns a normalized, fully-validated write payload or throws. First slice:
  - `create_task({title, due?, priority?})`
  - `create_expense({amountMinor, currency, category, note?, spentAt?})`
  - (stretch) `create_event({title, start, durationMinutes?})`
  Validation mirrors the existing Firestore rules' field constraints (types, required fields,
  enums, money as integer minor units, UTC timestamps) — the same invariants the manual capture
  pages enforce.
- **`gateway.js`:** in the tool loop, branch on `tool.mutating`. For a mutating call: validate,
  `store.createPendingAction(uid, conversationId, {actionId, tool, input, createdAt, status:
  "pending", expiresAt})`, append an `action_proposal` message (structured: `{kind, summary,
  fields, actionId}`), set a `proposedAction` result, and **break** the loop (do not append a
  `tool_result`). Read tools keep auto-executing exactly as today. The `SYSTEM_PROMPT` read-only
  clause is rewritten: the model may *propose* changes via mutating tools; it must propose exactly
  one change per turn, phrase replies as proposals, and never claim completion.
- **New store methods (`store.js`):** `createPendingAction`, `getPendingAction`,
  `markPendingAction(status)`, and the actual entity writes `createTask`, `createExpense`
  (`createEvent`) — Admin SDK writes to `users/{uid}/{tasks,expenses,schedule}` with the same doc
  shape the client repositories use (doc id = entity id, idempotent).
- **New callables (`index.js`):** `aiConfirmAction` and `aiCancelAction` — both `onCall`, both
  `enforceAppCheck: true`, both requiring `request.auth`. Confirm: load pending action (404 if
  missing/expired/not-pending), execute the write keyed by `actionId` (idempotent — re-confirm is a
  no-op), mark `applied`, append the `assistant` result message. Errors map through the existing
  `GatewayError` → `HttpsError` path.

### Client (`lib/features/ai/`)

- **Domain:** extend `AiMessage` with an optional `pendingAction` (or add an `AiMessageKind`), and
  add `AiPendingAction {actionId, kind, summary, fields, status}`. `AiRole` already reserves `tool`;
  add nothing there unless needed.
- **`AiRepository`:** add `Future<void> confirmAction({conversationId, actionId})` and
  `cancelAction({...})`. Implement in both `FakeAiRepository` (in-memory, so the UI is buildable and
  widget-testable offline — the proven "vertical slice against a fake first" pattern) and
  `FirebaseAiRepository` (calls the new callables).
- **`AskPage`:** render an `action_proposal` message as the confirmation card; wire Confirm/Cancel
  to the repo. Fold in the deferred graceful error handling here (catch send/confirm failures → an
  in-chat error line, not a thrown exception).

### Firestore schema & rules

- `users/{uid}/aiConversations/{cid}/pendingActions/{actionId}` — server-write-only (same posture
  as `messages`), owner-read. Rules + rules tests added (mirror the existing AI rules).
- Entity writes land in the existing `users/{uid}/{tasks,expenses,schedule}` collections, which
  **already have owner-only rules with field validation**. Because the Cloud Function uses the
  Admin SDK (bypasses rules), the gateway's server-side `validate()` is what enforces the invariants
  — it must be kept in lockstep with those rules. No rule loosening required.

### Security & cost

- **App Check enforced first** (see Handoff) — a writing callable must reject non-app clients.
- **Idempotency:** writes keyed by `actionId`; double-confirm/retry never double-writes.
- **Expiry:** pending actions expire (e.g. 1h) so a stale proposal can't be confirmed much later.
- **Validation parity:** every field validated server-side against the same constraints as the
  feature's Firestore rules and capture forms.
- **Injection fence unchanged:** tool *results* remain data-not-instructions; a note/task title can
  never cause a write — only an explicit user Confirm executes one.
- Confirm/cancel are cheap (no model call in the first slice), so cost is dominated by the propose
  turn, already covered by V1's ceilings.

---

## V2 scope (first slice)

**In:** create-only mutations for **tasks and expenses** (schedule as stretch), single proposal per
turn, confirmation card, idempotent server execution, App Check enforced, graceful client errors.

**Explicitly out (later iterations):** edits and deletes; batched/multi-action proposals; a
follow-up model turn for a natural closing line; mutations for university/workouts/diet/notes;
undo. Non-goals from ADR-001 remain non-goals (embeddings/semantic search, scheduled/unattended
actions).

---

## Phased implementation (each phase its own reviewed commit on `feature/ai-assistant`)

0. **Phase -1 (UX):** confirmation-card mock in each state, owner-approved. *No code.*
1. **Server, offline-testable:** `mutating` tool flag + `create_task`/`create_expense` validate();
   gateway propose branch; `store` pending-action + write methods; `aiConfirmAction`/`aiCancelAction`.
   Unit tests via `node --test` with the in-memory fake store (no network/emulator), mirroring
   `gateway.test.js`/`tools.test.js`. Rules + rules tests for `pendingActions`.
2. **Client seam against the fake:** domain + `AiRepository.confirm/cancel` + `FakeAiRepository`
   proposals; `AskPage` confirmation card + graceful errors; widget tests (Firebase-free).
3. **Wire the real path:** `FirebaseAiRepository.confirm/cancel` → callables; manual on-device
   verification of a real create-task/expense round-trip.
4. **Deploy:** owner deploys functions + rules; enforce App Check; verify end-to-end.

**Gates each phase (same as V1):** `flutter analyze` clean; full `flutter test` green;
`functions` `node --test` green; rules tests green. Orchestrator reviews the diff and commits.

---

## Open decisions — RESOLVED (owner sign-off 2026-08-16)

1. **UX approval (Phase -1):** ✅ Approved as-is (confirmation card, iris theme, pending →
   added/cancelled/expired states). Mock reviewed and accepted.
2. **First-slice scope:** ✅ **tasks + expenses + schedule** — all three create-only tools are in
   the first slice (schedule promoted from stretch to in-scope).
3. **Closing line:** ✅ Deterministic result message (no follow-up model call on confirm).
4. **Pending-action expiry window:** ✅ 1 hour.
5. **App Check enforcement:** ✅ Hard gate before the live writes ship. Build/test phases run
   offline against the fake, so enforcement blocks only the final live deploy (sequenced last;
   needs the owner's Firebase-console step).

---

## Consequences

**Becomes easier:** Ask becomes an actual assistant, not just a reader; the propose→confirm pattern
generalizes to every future write; the gateway stays the single audited entry point.

**New burden:** a second (and third) callable to maintain; server-side validation must stay in
lockstep with Firestore rules; more surface to test. All bounded by the fake-first, phased,
gate-on-green workflow already proven for V1.

**To revisit later:** edits/deletes (need stronger confirmation + undo), batched proposals, and a
model-generated closing line once the deterministic flow is trusted.
