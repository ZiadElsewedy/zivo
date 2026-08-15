# ADR-001: AI assistant ("Ask") — read-only, gateway-mediated

**Status:** Proposed — awaiting owner approval before any code
**Date:** 2026-08-15
**Deciders:** Ziad (owner) · implementer
**Supersedes / relates to:** `docs/PLAN.md` §10 (security), §11 (AI architecture), §12 (tools)

---

## Context

ZIVO now persists all seven life-area collections to Firestore behind their repository
interfaces (auth → persistence → University, all merged to `main`). The "Ask" tab is still a
`ComingSoon('Ask')` placeholder. Phase 9 of the plan is a **read-only AI assistant**: natural
language over the user's own data — "what's due this week?", "how much did I spend on coffee
this month?", "summarise my week" — that can *answer* by reading across features, but cannot yet
*mutate* anything.

**Forces at play:**

- **Privacy is the whole point.** The primary asset is one person's private life data. The AI
  provider key must never touch the client; retrieved personal data must be treated carefully
  (PLAN §10). "Private by construction."
- **Cost is real money.** An LLM behind a chat box with unbounded history and chatty tool loops
  is a cost/abuse surface. This must be bounded server-side (PLAN §11).
- **The repository seam is the app's core discipline.** Everything is built as a vertical slice
  against a fake/in-memory impl behind an `abstract interface class`, then the real backend slots
  in. AI should follow the same pattern.
- **Existing infra is JavaScript.** `functions/index.js` already runs Cloud Functions (Node 24,
  `firebase-functions` v2 `onCall`, `defineSecret` for secrets, `firebase-admin`) for the email
  OTP flow. The client already depends on `cloud_functions` (callable functions). PLAN §5 sketched
  a *TypeScript* `functions/` tree, but the codebase — the source of truth — is JS.
- **Two things are gated on the owner:** an AI provider **API key** (a secret + spend decision)
  and **authorization to deploy** a Cloud Function. Nothing that needs either can proceed without
  Ziad. Everything that does *not* need them (the client seam) can.

**Constraints:**

- Single-user app. No multi-tenancy, no sharing. `request.auth.uid` is the only identity.
- V1 is **read-only** — no AI writes. Mutations (with confirmation) are an explicit V2 (ADR-later).
- No new heavyweight client dependencies; the DI/nav/state foundation stays as-is (`AppScope` +
  `StreamBuilder`).

---

## Decision

Build the assistant as a **single server-side gateway** — an `aiChat` **callable Cloud
Function** — that holds the provider key, enforces auth + cost/rate limits, and answers via
**tool-based retrieval** over the user's Firestore data. The Flutter client talks *only* to this
function, behind an `AiRepository` seam. V1 ships **read-only** tools; mutations are deferred.

Concretely, four sub-decisions:

1. **Gateway, not client-direct.** The client calls `aiChat({conversationId, message})`; the
   function calls the model. The key lives in Secret Manager via `defineSecret`, exactly like
   `RESEND_API_KEY`/`OTP_PEPPER` today. (Decision 1 below.)
2. **Tool-based retrieval, executed server-side.** The model is given read tools; when it calls
   one, the function executes it against Firestore with the Admin SDK (scoped to `context.auth.uid`)
   and feeds the result back. No vector DB, no "stuff everything into the prompt." (Decision 2.)
3. **Provider = Claude (Anthropic API).** This is a Claude-built app; default to a Claude model.
   *Which* model and the key are the owner's call. (Decision 3 — needs approval.)
4. **Extend the existing JS `functions/` codebase.** Add `aiChat` alongside the OTP functions in
   the same `default` codebase, same v2 `onCall`/`defineSecret` patterns — not a parallel TS tree.
   (Decision 4.)

And a build-order decision: **client seam first, against a fake.** Build the `AiRepository` +
`FakeAiRepository` + the Ask chat UI now (no key, no deploy, fully tested); wire the real
`FirebaseAiRepository` → `aiChat` once the key + deploy are authorized.

---

## Options Considered

### Decision 1 — Where does the model call happen?

#### Option 1A: `aiChat` callable Cloud Function gateway (recommended)
| Dimension | Assessment |
|-----------|------------|
| Complexity | Med — one function, mirrors the OTP functions |
| Cost control | Strong — limits enforced server-side |
| Key safety | Strong — key in Secret Manager, never shipped |
| Team familiarity | High — same pattern already in `functions/index.js` |

**Pros:** key never on device; auth context automatic with callables; cost/rate/token caps
enforceable in one place; one audit/log point; leaves the door open to V2 server-side mutations.
**Cons:** requires a deploy; a cold-start latency tax on the first call.

#### Option 1B: Client calls the Anthropic API directly
**Pros:** no function to deploy; lowest latency.
**Cons:** **the key would ship in the app** — disqualifying (PLAN §10 non-negotiable). No
server-side cost ceiling. Rejected outright.

#### Option 1C: A dedicated backend service (NestJS/Cloud Run)
**Pros:** room for long-running/streaming jobs.
**Cons:** massive over-build for a single user; ops burden the plan explicitly rejects for V1
(PLAN §3). Revisit only if AI analytics outgrow Functions. Rejected for V1.

### Decision 2 — How does the model get the user's data?

#### Option 2A: Tool-based retrieval, server-executed (recommended)
The model is given read tools (`get_today`, `get_tasks`, …); it decides what to fetch; the
function runs each against Firestore (Admin SDK, `uid`-scoped) and returns results.
**Pros:** only the data needed for the turn leaves Firestore; auditable; cheap; matches how the
repositories already expose data; naturally extends to V2 mutations (same tool→use-case pattern).
**Cons:** multi-round-trip per turn (bounded — see cost controls); tools must be written + tested.

#### Option 2B: Stuff all context into the system prompt every turn
**Pros:** no tool loop; simplest to write.
**Cons:** sends *all* personal data to the model on every turn (privacy + token cost); doesn't
scale past a small dataset; no selectivity. Rejected.

#### Option 2C: Vector DB / embeddings RAG
**Pros:** semantic search over notes.
**Cons:** whole new subsystem for a personal-scale dataset; PLAN defers this to V2 and only "if
naive search proves inadequate." Deferred, not rejected.

### Decision 3 — Provider & model (**needs owner input**)
Default: **Claude via the Anthropic API.** Candidate: a mid-tier Claude model for the assistant
(good reasoning at sane cost), optionally a cheaper/faster tier for trivial turns later. The
**owner supplies the API key** (Secret Manager) and picks the model. No other provider is proposed.

### Decision 4 — Functions language/codebase
**Extend the existing JS `functions/`** (Node 24, v2 `onCall`, `defineSecret`) — recommended:
zero new toolchain, identical patterns to the OTP function, one deploy. *Alternative:* adopt
TypeScript per PLAN §5 — rejected for now (adds a build step + migration for one function; the
code, not the plan, is authoritative and the code is JS).

---

## Trade-off analysis

The central trade-off is **latency/deploy overhead (gateway) vs. key exposure (client-direct)** —
and key exposure is non-negotiable for a private data app, so the gateway wins decisively. The
secondary trade-off is **tool round-trips (selective, private, cheap) vs. one big prompt (simple
but leaks everything)** — privacy + cost make tool-based retrieval the clear choice, and it also
sets up V2 mutations for free. Everything else (JS vs TS, which Claude model) is low-stakes and
reversible.

The one genuinely irreversible-ish commitment is **conversation storage shape** (below); we pin
it now with `schemaVersion` so it can migrate, consistent with every other collection.

---

## V1 scope (what "read-only assistant" means concretely)

**Read tools (auto-execute, no confirmation), each a `uid`-scoped Firestore read:**
`get_today`, `get_tasks(filter)`, `get_schedule(range)`, `get_expenses(range, category?)`,
`get_university(filter)`, `search_notes(query)` (substring/prefix, *not* full-text — PLAN §7),
`get_workouts(range)`, and `summarize_week()` (a composed read across features).

**Conversation storage:** `users/{uid}/aiConversations/{conversationId}` +
`.../messages/{messageId}` (role: user|assistant|tool, content, createdAt, `schemaVersion:1`).
Owner-only rules (same pattern as the 7 existing collections) + rules tests. A bounded history
window is sent to the model.

**Cost & safety controls (all server-side, enforced — PLAN §11):**
- Max **N=5** model↔tool round-trips per turn, then abort cleanly.
- Per-turn **token/cost ceiling**; separate per-day cap.
- Per-turn usage logged to `users/{uid}/aiUsage` (tokens in/out, cost, tools, latency).
- **Firebase App Check** so only real app instances can call the function (also a general
  hardening the plan flags as non-negotiable, §10) — *note: enabling App Check is its own
  deploy/config step and may be split into a follow-up.*
- Retrieved Firestore content is fenced as **data, not instructions** (prompt-injection guard),
  even though V1 is read-only so nothing can be silently acted on.

**Explicitly deferred to V2 (not in this ADR):** any mutating tool (`create_task`,
`create_expense`, …) and its confirmation UI; embeddings/semantic search; multi-conversation
management polish; scheduled/unattended actions.

---

## The client seam (buildable now, no key/deploy)

Mirrors every other feature:
- `features/ai/domain/`: `AiMessage` (role, content, createdAt), `AiConversation`, `AiRepository`
  (`Stream<List<AiMessage>> watchMessages(conversationId)`, `Future<void> send(...)`, ...).
- `features/ai/data/`: `FakeAiRepository` — **honest** canned responses ("The assistant isn't
  connected yet — this is a placeholder reply."), never masquerading as real AI; and (later)
  `FirebaseAiRepository` calling `FirebaseFunctions.instance.httpsCallable('aiChat')`.
- `features/ai/presentation/`: `AskPage` chat UI (message list + composer) replacing
  `ComingSoon('Ask')` in `home_shell`; wired via `AppScope`.
- Tests: domain + fake repo + a widget test, all Firebase-free.

This lets us ship a real Ask surface immediately and swap the fake for the real gateway the
moment it's deployed — the proven "vertical slice against a fake first" pattern.

---

## Consequences

**Becomes easier:**
- A real, extensible AI surface with one audited entry point and bounded cost.
- V2 mutations slot into the same tool→use-case gateway (no re-architecture).
- The chat UI can ship and be iterated on now, decoupled from the backend.

**Becomes harder / new burden:**
- A deploy + a monthly AI bill to watch (mitigated by caps + `aiUsage` logging).
- A new secret to manage (the AI key) and App Check to configure.
- Cloud Functions cold-start latency on the first call of a session.

**To revisit:**
- Whether App Check lands with V1 or as an immediate follow-up.
- Model tiering (cheap model for simple turns) once real usage/cost is observed.
- Full-text/semantic note search if substring `search_notes` proves too weak (V2).

---

## Open decisions requiring the owner's sign-off (blocking the *server* half only)

1. **Provider/model:** confirm Claude, and pick the model tier.
2. **API key:** provide it (goes to Secret Manager via `firebase functions:secrets:set`); the
   implementer never sees the value.
3. **Deploy authorization:** approve deploying `aiChat` (and its rules) to `zivo-63f15`.
4. **App Check:** land it with V1, or as a fast follow-up?

The **client seam** (chat UI + fake) needs none of the above and can start immediately on approval
of this ADR's direction.

---

## Action items

1. [ ] Owner reviews/approves this ADR (status → Accepted), and answers the four open decisions.
2. [ ] (No key/deploy) Build the client seam: `features/ai/` domain + `FakeAiRepository` +
       `AskPage` chat UI replacing `ComingSoon('Ask')`; wire via `AppScope`; tests. Commit.
3. [ ] (Needs key + deploy) Add `aiChat` to `functions/` (JS, v2 `onCall`, `defineSecret` for the
       AI key), with the read tools, history windowing, and cost/iteration ceilings.
4. [ ] Add `aiConversations`/`messages` (+ `aiUsage`) owner-only rules + emulator rules tests.
5. [ ] `FirebaseAiRepository` → callable; swap it in behind `AppScope`; end-to-end verify on device.
6. [ ] (Decision) App Check enablement.
7. [ ] Update `docs/PROJECT_CONTEXT.md` (§5/§7/§10/§11) when the milestone lands.
