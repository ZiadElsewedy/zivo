# Personal OS — Architecture & Implementation Plan

> Codename: **zivo** · Owner: Ziad · Phase: Planning & Setup · Status: Living document
>
> A private, single-user, premium "personal operating system" mobile app.
> Flutter + Firebase, Clean(ish) Architecture, AI as an orchestration layer over
> structured application use cases — **never** as the business logic itself.

This document is the source of truth for _why_ things are built the way they are.
No implementation code exists yet by design. Read sections 1–3 for the mental model,
skip to section 31 (Roadmap) to start building, and section 32 (A–G) for the TL;DR.

---

## 0. Guiding principles (the constitution)

These override any individual decision below. When in doubt, re-read these.

1. **One person, one system.** This is not a SaaS product. No multi-tenancy, no
   sharing, no teams, no roles. Every simplification that single-user allows, take it.
2. **The features are one connected system, not ten CRUD apps.** Schedule feeds Today,
   Today aggregates everything, AI reads across all of it. Design for the graph, not the silos.
3. **AI orchestrates; the app executes.** The AI decides _what_ should happen. Use cases
   decide _how_ and _whether_ it's allowed. The AI never touches Firestore directly.
4. **Every abstraction pays rent.** No pattern for its own sake. If a layer has one
   implementation and will only ever have one, question it. But keep the seams that let
   us swap Firebase → custom backend later.
5. **Postpone aggressively.** V1 is small. Most of the interesting AI/document work is
   V1.5+. Ship a beautiful, reliable core first.
6. **Private by construction.** Data is owned by one `uid`. Security rules deny by
   default. Secrets never touch the client.
7. **Premium is a feature, not a coat of paint.** Motion, spacing, typography, and
   perceived speed are first-class requirements, budgeted into every phase.

---

## 1. Product architecture overview

Personal OS centralizes ten life areas into one cohesive surface:

| # | Area | Core job | AI-relevant? |
|---|------|----------|--------------|
| 1 | Home / Today | The command center. Aggregates everything happening _now_. | Read-heavy context source |
| 2 | AI Assistant | Natural-language layer over the whole system. | The subsystem itself |
| 3 | Workout | Plans, sessions, sets/reps/weight, progress, PDF import. | Read + action (start/log) |
| 4 | Expenses | Fast capture, categorization, monthly/weekly rollups. | Read + action (create/query) |
| 5 | University | Courses, assignments, deadlines, exams. | Read + action |
| 6 | Tasks | Lightweight personal todos with due dates/priority. | Read + action |
| 7 | Schedule | Time-based events; the backbone that drives Today. | Read + action |
| 8 | Moments | Photo/memory capture with time + optional location. | Read (V2 action) |
| 9 | Notes | Fast capture, searchable, markdown-ish. | Read + create + search |
| 10 | Profile / Settings | Identity, preferences, theme, AI config, data controls. | Config source |

**The connective tissue** is what makes this a "personal OS" and not a folder of apps:

```
        Schedule (events)         Tasks / University / Workout (obligations)
              \                        /
               \                      /
                v                    v
        ┌───────────────────────────────────┐
        │         HOME / TODAY               │  ← aggregation surface
        │  "what matters right now"          │
        └───────────────────────────────────┘
                        │ reads
                        v
        ┌───────────────────────────────────┐
        │  Activity & History (append-only)  │  ← workout sessions, expenses,
        │                                    │     completed tasks, moments
        └───────────────────────────────────┘
                        │ context
                        v
        ┌───────────────────────────────────┐
        │           AI ASSISTANT             │
        │  reads context → picks a tool →    │
        │  tool calls a use case → executes  │
        └───────────────────────────────────┘
```

Two distinct data shapes fall out of this and should be modeled differently:

- **State entities** (mutable, "what is true now"): tasks, schedule events, workout plans,
  university items, notes, settings. These are edited in place.
- **Log/event entities** (append-only, "what happened"): workout sessions, completed sets,
  expenses, moments, AI conversations. These are rarely edited, heavily aggregated, and
  drive history/progress/analytics.

Recognizing this split early prevents the classic mistake of treating an append-only
expense log the same as a mutable task list.

---

## 2. System architecture diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                        FLUTTER APP (client)                            │
│                                                                        │
│  Presentation ── Cubit/Bloc ── UseCases ── Repositories(interfaces)    │
│        │                                          │                    │
│        │                                          │ impl               │
│        │                                    Data sources               │
│        │                              (Firestore / Storage / AI GW)    │
│        └─────────────── go_router ────────────────┘                    │
└───────────────┬───────────────────────────┬──────────────────────────┘
                │ Firebase SDK               │ HTTPS (callable functions)
                v                            v
┌───────────────────────────┐   ┌───────────────────────────────────────┐
│      FIREBASE (BaaS)        │   │        CLOUD FUNCTIONS (trusted)       │
│  • Auth                     │   │  • aiChat        (holds AI API key)    │
│  • Firestore (rules-gated)  │◄──┤  • processDocument (PDF → structured)  │
│  • Storage (rules-gated)    │   │  • executeToolCall (server-auth tools) │
│                             │   │  • callable = auth context enforced    │
└───────────────────────────┘   └──────────────────┬────────────────────┘
                                                    │ HTTPS (key in Secret Mgr)
                                                    v
                                    ┌───────────────────────────────────┐
                                    │       EXTERNAL AI API              │
                                    │  (Claude / model provider)         │
                                    └───────────────────────────────────┘
```

**Key rule:** the AI API key lives **only** in Cloud Functions (Secret Manager). The
Flutter client calls a callable function (`aiChat`), which carries the user's auth context
automatically. The client never sees the model key and never calls the AI provider directly.

---

## 3. Firebase-only vs. dedicated backend (challenging the assumption)

You lean toward **Firebase + Cloud Functions, no NestJS, for V1**. That is the right call
for V1 — but let's be precise about _why_ and _where it breaks_.

**Firebase-only is correct for V1 because:**
- Single user → no complex authorization, no tenant isolation logic, no admin surface.
- Firestore's offline cache + realtime streams give you "premium, fast, works-on-the-subway"
  almost for free — this is hard to replicate quickly with a custom backend.
- Cloud Functions cover the _only_ things that genuinely need a server: holding the AI key,
  PDF processing, and server-authoritative tool execution.
- Zero ops. You are one person; you should not be running a NestJS service + Postgres.

**Where Firebase becomes insufficient (the honest limits):**
| Pressure point | When it bites | Mitigation now |
|---|---|---|
| Complex cross-collection queries / analytics ("spend by category over 6 months joined with workout frequency") | When AI analytics get ambitious | Keep aggregation in Cloud Functions; pre-compute rollups. Later: export to BigQuery. |
| Cost of many small reads (Today aggregates 5+ collections on every open) | Not soon at single-user scale | Cache aggressively; consider a `today` denormalized doc. |
| Heavy document/AI pipelines (long-running PDF+LLM jobs) | Cloud Functions have timeouts | Use Cloud Functions v2 / Cloud Run for long jobs; make processing async + status-tracked. |
| Vendor lock-in on business logic | If you ever leave Firebase | **This is why we use the repository + use-case seam.** See below. |

**The migration insurance policy (do this now, costs almost nothing):**
- Domain layer depends on **repository interfaces**, not Firestore types. Firestore models
  (`FooDto`) live in the data layer and map to pure domain entities.
- No `cloud_firestore` import ever appears in `domain/` or `presentation/`.
- AI tools call **use cases**, not repositories directly, and use cases are transport-agnostic.

Result: swapping Firestore for a REST/GraphQL backend later means rewriting the `data/`
layer of each feature — a bounded, mechanical job — while `domain/` and `presentation/`
stay untouched. **We do not build the backend now; we keep the door open.**

**Verdict:** Firebase + Functions for V1. Revisit a dedicated backend only when (a) AI
analytics need real joins/aggregation, or (b) PDF/LLM pipelines outgrow function timeouts.
Both are V2 concerns. Don't build NestJS now.

---

## 4. Flutter architecture

**Feature-first + pragmatic Clean Architecture.** Three layers per feature:

```
feature/
  presentation/   → Widgets, Screens, Cubits/Blocs, view state
  domain/         → Entities, Repository interfaces, UseCases (pure Dart, no Flutter/Firebase)
  data/           → DTOs, Repository implementations, DataSources (Firestore/Storage)
```

**Dependency rule (strict, one direction):**

```
presentation ──► domain ◄── data
                   ▲
        (domain depends on NOTHING app-specific;
         presentation & data depend on domain)
```

- `domain/` imports no Flutter, no Firebase, no other feature's data. Pure Dart.
- `presentation/` talks to `domain` use cases (via DI); never imports `data/` directly.
- `data/` implements `domain` interfaces; owns all Firebase code.

**Pragmatism guardrails (avoiding enterprise cosplay):**
- A use case can be a thin call-through in simple features. Keep it if it adds a real seam
  for AI tools or validation; **collapse it** if it's literally `repo.getX()` with nothing else.
  Rule of thumb: a use case earns its place when it (a) is invoked by an AI tool, (b) enforces
  a business rule/validation, or (c) composes multiple repositories.
- Not every feature needs all three layers fully fleshed out. Notes might be almost pure
  CRUD; Workout will be rich. Let feature complexity dictate layer depth.
- No `Either`/`fpdart` functional error plumbing unless it earns its keep. Start with typed
  exceptions + a `Result` sealed class only where call sites genuinely branch on failure. (See §16.)

---

## 5. Complete project folder structure

```
lib/
  main.dart                      # bootstrap only (env → DI → runApp)
  bootstrap.dart                 # error zone, Firebase init, DI wiring

  app/
    app.dart                     # root MaterialApp.router
    router/
      app_router.dart            # go_router config
      routes.dart                # route name/path constants
    di/
      injector.dart              # get_it setup, registerFeatureX()
    observers/
      app_bloc_observer.dart     # global Bloc logging/analytics

  core/
    config/
      env.dart                   # Env abstraction (dev/prod), flavor-aware
      firebase_options.dart      # generated by flutterfire
    theme/
      app_theme.dart             # ThemeData (mono, premium)
      app_colors.dart
      app_typography.dart
      app_spacing.dart           # spacing scale tokens
      app_motion.dart            # durations, curves
    error/
      failure.dart               # Failure sealed types
      exceptions.dart            # data-layer exceptions
      result.dart                # Result<T> helper (optional per-feature)
    logging/
      logger.dart                # thin wrapper (see §20)
    utils/
      date_x.dart, formatters.dart, ...
    widgets/                     # truly shared, dumb widgets (buttons, sheets)
      app_button.dart, app_scaffold.dart, ...

  features/
    auth/            { presentation/ domain/ data/ }
    home/            # aggregates others; read-only over their domains
    schedule/
    tasks/
    workout/
    expenses/
    university/
    notes/
    moments/
    profile/
    ai/              # the AI subsystem (see §10–11)
      presentation/  # chat UI, message bubbles, tool-confirmation sheet
      domain/        # AiMessage, Conversation, ToolCall entities; AiRepository
      data/          # callable-function client, conversation persistence
      tools/         # tool registry, schemas, tool→usecase adapters

  shared/
    domain/          # cross-feature value objects (Money, DateRange, Priority)
    widgets/         # composed shared UI (e.g., ListSection, EmptyState)

functions/                        # Cloud Functions (TypeScript), separate package
  src/
    ai/aiChat.ts
    ai/toolRegistry.ts            # server mirror of tool authorization
    documents/processDocument.ts
    lib/firestore.ts, lib/auth.ts, lib/secrets.ts
  package.json, tsconfig.json

firestore.rules
storage.rules
firestore.indexes.json
firebase.json
docs/
  PLAN.md                         # this file
  DECISIONS/                      # ADRs as we make hard calls
test/
  <mirror of lib/ per feature>
integration_test/
```

**Why this shape:**
- `core/` = infra & cross-cutting with **no business meaning**. `shared/` = business concepts
  used by 2+ features. Keeping them separate stops `core/` from becoming a junk drawer.
- `ai/tools/` sits inside the `ai` feature but its adapters _call into other features' use
  cases_ via DI — this is the one intentional cross-feature coupling, and it's one-directional
  (ai → others, never others → ai).
- `functions/` is its own package with its own lint/test; it is _not_ Dart.

---

## 6. Feature map (dependencies between features)

```
        profile/settings ──────────────┐ (theme, prefs, ai config)
                                        v
  schedule ─┐                    ┌── home (reads: schedule, tasks, workout,
  tasks ────┼──────────────────► │        university, expenses summary)
  workout ──┤   (domain reads)   └── ai (reads all via tools; writes via use cases)
  university┤
  expenses ─┤
  notes ────┤
  moments ──┘
```

- **home** and **ai** are _consumers_; they depend on other features' **domain use cases**,
  never their presentation or data.
- All other features are independent islands that don't import each other.
- Cross-feature access always goes through the DI container + domain use cases, so the graph
  above is enforceable by import lint rules.

---

## 7. Firestore data model

**Root principle:** everything is owned by one user. Root is `users/{uid}`. Almost everything
is a subcollection under it. This makes security rules trivial (`request.auth.uid == uid`) and
keeps all personal data under one ownership boundary.

```
users/{uid}                                  (profile doc: displayName, createdAt, timezone)
  settings/{singleton: "app"}                (theme, ai prefs, units, currency)

  schedule/{eventId}                         STATE: title, start, end, allDay, location, sourceRef?
  tasks/{taskId}                             STATE: title, notes, due, priority, status, completedAt
  university/
    courses/{courseId}                       STATE: name, code, term, color
    items/{itemId}                           STATE: courseId, type(assignment|exam), title, due, status
  notes/{noteId}                             STATE: title, body, tags[], updatedAt
  moments/{momentId}                         LOG:   caption, takenAt, location?, storageRefs[]

  expenses/{expenseId}                       LOG:   amount, currency, category, note, spentAt
  expenseRollups/{yyyy-MM}                   DERIVED: totalsByCategory, total (computed)

  workoutPlans/{planId}                      STATE: name, source(pdf|manual), status(draft|active)
    days/{dayId}                             STATE: label("Chest"), order, exercises[]  (embedded)
  workoutSessions/{sessionId}                LOG:   planId?, dayLabel, startedAt, endedAt, status
    sets/{setId}                             LOG:   exerciseName, order, reps, weight, done, at

  documents/{docId}                          META:  storagePath, kind, status(uploaded|processing
                                                    |extracted|confirmed|failed), extractedRef?

  aiConversations/{conversationId}           title, createdAt, updatedAt
    messages/{messageId}                     role(user|assistant|tool), content, toolCalls[], at
  aiToolCalls/{callId}                       AUDIT: tool, args, result, status, confirmedByUser, at
```

### Decisions & rationale

**What lives under `users/{uid}` (everything, basically).** Single-user app → one ownership
root. No top-level collections for domain data. The only things that could be top-level are
truly global config, and we have none.

**Subcollections vs. embedded documents:**
- **Embed** when the child is bounded, always loaded with the parent, and not queried across
  parents. → `workoutPlans/{planId}.days[].exercises[]` is embedded (a plan's structure is
  read as a unit; a day has a handful of exercises). Keeps plan editing atomic.
- **Subcollection** when the child is unbounded, appended over time, or queried independently.
  → `workoutSessions/*/sets/*` is a subcollection (sets accumulate; you query "all bench-press
  sets over time" for progress). → `expenses` are their own docs (thousands over years, queried
  by date/category).

**Document boundaries (avoid the 1 MiB trap):** never embed an append-only list in a parent
doc. Sessions, sets, expenses, moments, messages = one doc each. A single `today` doc that
inlined everything would be an anti-pattern; Today is _computed_, not stored (with an optional
cache doc — see below).

**Derived/rollup docs:** `expenseRollups/{yyyy-MM}` and (optionally) a `today` cache are
_computed_ by Cloud Functions on write, not authored by the client. They exist purely to make
the two hottest reads (monthly spend, Today) O(1). Treat them as disposable/rebuildable.

**Query patterns → index requirements:**
| Query | Where | Index |
|---|---|---|
| Today's schedule | `schedule` where start in [dayStart,dayEnd) | composite (start asc) — single field, auto |
| Open tasks by due | `tasks` where status==open orderBy due | composite (status, due) |
| Upcoming uni deadlines | `university/items` where status==open orderBy due | composite (status, due) |
| This month's expenses | `expenses` where spentAt in [monthStart,monthEnd) orderBy spentAt | single-field (auto) |
| Expenses by category this month | `expenses` where category==X && spentAt in range | composite (category, spentAt) |
| Progress for an exercise | collectionGroup `sets` where exerciseName==X orderBy at | composite + collectionGroup index |
| Recent conversations | `aiConversations` orderBy updatedAt desc | single-field (auto) |

Declare composites in `firestore.indexes.json` up front for the ones above; let single-field
auto-indexes handle the rest. **Collection-group index on `sets`** is the one non-obvious
requirement (needed for cross-session exercise progress).

**Offline behavior:** Firestore persistence is ON. State entities (tasks, schedule, notes)
edit-in-place and sync — great offline. Log writes (expenses, sets) queue and flush — also
great. **Rollups and AI calls are NOT offline-capable** (they need Functions); the UI must
degrade gracefully (show cached rollup + "updating…", disable AI send when offline).

**Data ownership & future migration:** every doc is under `users/{uid}` → a full export is a
single subtree read; a future backend migration is a tree walk. Store timestamps as Firestore
`Timestamp` but map to UTC `DateTime` in domain; store money as **integer minor units + currency
code** (never floats). These two choices prevent the most common migration pain.

**Privacy:** no field ever contains another person's data. Location on moments is optional and
user-toggled. Nothing is shared or public — rules enforce this (see §9).

---

## 8. Firebase Storage structure

```
users/{uid}/
  documents/{docId}/original.pdf         # raw uploaded workout PDF, etc.
  documents/{docId}/extracted.json       # (optional) function-written extraction artifact
  moments/{momentId}/{n}.jpg             # moment photos (resized client-side before upload)
  profile/avatar.jpg
```

- Path is namespaced by `uid` → rules mirror Firestore (`match /users/{uid}/{allPaths=**}`
  → allow if `request.auth.uid == uid`).
- **Client resizes/compresses images before upload** (moments, avatar) — never upload raw
  camera output. Enforce max dimensions + quality.
- PDFs: validate `contentType == application/pdf` and size cap in both client and Storage rules.
- The `documents/{docId}` folder pairs 1:1 with the Firestore `documents/{docId}` meta doc, so
  status tracking and cleanup are straightforward.

---

## 9. Authentication architecture

- **Firebase Auth.** For a single-user personal app, start with **email/password** or
  **Sign in with Apple** (Apple is the premium, privacy-forward choice on iOS and is required
  by App Store if you offer other social logins — so if it's Apple-only, no conflict).
- **Recommendation:** Sign in with Apple as primary (matches the premium/Apple-like brand),
  email/password as fallback for dev. No anonymous auth (this app is meaningless without _you_).
- **Auth state drives routing** via a repository stream → an `AuthCubit` → `go_router`
  `redirect`. Signed-out → `/auth`; signed-in → `/` (Today).
- **Single-user hardening:** because it's just you, you can optionally pin allowed `uid`(s) in
  Firestore rules or a Function check, so even if someone else signs up, they get an empty,
  isolated space and can never see yours. (Rules already guarantee isolation; the pin just
  prevents unwanted signups from consuming your project.)
- Token/session handling is delegated to the Firebase SDK; Cloud Functions receive verified
  auth context automatically via callable functions.

---

## 10. Security model

**Threat model is unusual: the primary asset is _your private life data_, and the primary
adversaries are (a) anyone who isn't you, (b) prompt-injection via uploaded documents, (c)
accidental key exposure.** Plan accordingly.

**Layered controls:**
1. **Firestore Security Rules — deny by default.**
   ```
   match /users/{uid}/{document=**} {
     allow read, write: if request.auth != null && request.auth.uid == uid;
   }
   ```
   Plus per-collection `allow` refinements with **field validation** (types, required fields,
   enum values, amount ≥ 0, timestamps present) so a compromised client can't write garbage.
2. **Storage Rules** mirror Firestore ownership + enforce contentType/size (§8).
3. **Cloud Functions security:** all functions are **callable** (auth context enforced); reject
   `context.auth == null`. Re-validate every input server-side. Never trust client-provided
   `uid` — use `context.auth.uid`.
4. **AI API key protection:** key in **Secret Manager**, injected into the function env at
   deploy. Never in the client, never in Firestore, never in git. `.env`/keys in `.gitignore`.
5. **Secrets management:** Secret Manager for prod; local `functions/.env.local` (gitignored)
   for dev. flutterfire `firebase_options.dart` is _not_ a secret (it's public config) but
   still gitignore-review it.
6. **Input validation:** two places — client (UX) and server/rules (trust boundary). Client
   validation is convenience; rules + Functions are the real gate.
7. **File upload validation:** type + size + (server-side) content sniffing before processing.
   Treat PDF text as **untrusted** — see prompt-injection note in §11.
8. **Rate limiting:** AI + document functions are the abuse/cost surface. Enforce per-user
   rate + daily token/cost caps in the function (Firestore counter or App Check + quota).
   Enable **Firebase App Check** so only your app instances can call Functions/Firestore.
9. **Data privacy:** no analytics on content, no third-party SDKs that exfiltrate data, AI
   provider chosen for a no-training/retention posture; document what leaves the device (only
   what's needed for the current AI turn).

**Non-negotiables:** App Check on; rules deny-by-default with field validation; AI key server-only.

---

## 11. AI architecture

Treat AI as a **first-class subsystem**, not a text box bolted onto chat.

```
User message
   │
   ▼
[Flutter AI Cubit] ── persists user msg ──► aiConversations/*/messages
   │ callable: aiChat({conversationId, message})
   ▼
[Cloud Function: aiChat]  (holds key, enforces auth + rate/cost)
   │  1. load conversation history (bounded window)
   │  2. build system prompt + retrieve context (see below)
   │  3. call AI provider with tool schemas
   ▼
[AI provider] ── returns text OR tool_call(s)
   │
   ├─ text only ────────────► persist assistant msg ► return to client
   │
   └─ tool_call ──► [Tool Registry / authorization]
                       │  read-only tool?  → execute now (server use-case call)
                       │  mutating tool?   → return "needs confirmation" to client
                       ▼
                    result fed back to model → final assistant msg → persist → return
```

**Components:**
- **AI Gateway** = the `aiChat` Cloud Function. Single entry point. Owns key, rate limits,
  retries, logging, cost accounting. The client only ever speaks to this.
- **System prompt / instructions:** identity ("You are Ziad's Personal OS assistant"), the
  ground rules (use tools for data, never invent facts, confirm before mutations), the current
  date/timezone, and a compact user profile. Versioned in the functions repo.
- **Context retrieval:** V1 = _tool-based retrieval_ (model calls `get_today`, `get_schedule`
  etc. to pull what it needs). No vector DB in V1. This is simpler, cheaper, and auditable.
  V2 (if needed): embed notes for semantic `search_notes`.
- **Tool registry:** declarative schema list (name, description, JSON params, `mutating: bool`).
  The **server** is the authority on what tools exist and whether they mutate.
- **Tool execution:** each tool maps to a **domain use case** (executed server-side in the
  function, or dispatched to the client for confirmation-then-execute). Tools never write
  Firestore ad hoc; they invoke the same validated use cases the UI uses.
- **Authorization:** read tools auto-run; mutating tools require explicit user confirmation in
  the app (a confirmation sheet showing exactly what will happen) before execution. Destructive
  tools (delete) always confirm and are minimized in V1.
- **Conversation storage:** `aiConversations` + `messages` subcollection. Bounded history
  window sent to the model (last N turns + summary for older), to control tokens.
- **Error handling & retries:** transient provider errors → bounded exponential retry in the
  function; tool errors → returned to the model as a tool error result so it can recover or
  explain. Never silently swallow; surface a clean message to the user.
- **Observability:** log per-turn — tokens in/out, cost, tools called, latency, errors — to a
  `aiUsage` collection or logging sink. This is how you keep cost sane.
- **Token/cost management:** history windowing + summary; per-day cost cap; small model for
  routing/simple turns if the provider supports tiers; count tokens before sending.

**Prompt-injection defense (critical, because of PDFs):** extracted document text and any
Firestore content are **untrusted data**, not instructions. In the system prompt, fence
retrieved/document content and instruct the model to treat it as data only. Mutating tool calls
_always_ require user confirmation, so even a successful injection can't silently act.

---

## 12. AI tool / action architecture

Tools = the API surface between the model and your use cases. Proposed V1→V1.5 set:

**Read tools (auto-execute, no confirmation):**
- `get_today()` — aggregated today view
- `get_schedule(range)` — events in a date range
- `get_tasks(filter)` — tasks by status/due
- `get_workout_today()` — today's planned day (e.g., "Chest")
- `get_expenses(range, category?)` — expense query + totals
- `get_university(filter)` — upcoming assignments/exams
- `search_notes(query)` — text search over notes
- `summarize_week()` — composed read across features (a use case, not a raw query)

**Mutating tools (require confirmation before execute):**
- `create_task(title, due?, priority?)`
- `complete_task(taskId)`
- `create_expense(amount, category, note?, spentAt?)`
- `create_schedule_event(title, start, end?)`
- `create_note(title?, body)`
- `start_workout(dayLabel?)` — begins a session
- `log_set(sessionId, exerciseName, reps, weight)`

**Deliberately deferred (V2):** anything deleting data, editing workout plans via AI,
bulk operations, cross-entity mutations. Keep the mutating surface small and safe in V1.

**Contract per tool:**
```
{
  name, description,
  parameters: <JSON schema>,
  mutating: bool,        // drives confirmation
  useCase: () => UseCase // server + client both resolve name → use case
}
```
The registry lives in two mirrored places: the **function** (authority, decides mutating +
executes read tools) and the **client** (`ai/tools/`, executes confirmed mutations by invoking
the local use case). A single shared JSON schema definition should be the source both derive
from to prevent drift (checked in under `functions/` and imported/generated for Dart).

---

## 13. PDF / document processing architecture

```
Flutter: pick PDF ──► validate(type,size) ──► upload to Storage
                                                users/{uid}/documents/{docId}/original.pdf
   │ create Firestore documents/{docId} { status: "uploaded" }
   ▼
Cloud Function (Storage trigger OR callable processDocument):
   status: "processing"
   1. fetch PDF from Storage
   2. extract text (pdf-parse / provider file input)
   3. AI structured extraction → normalized workout JSON (days, exercises, sets, reps)
   4. VALIDATE against a strict schema (reject/repair malformed)
   5. write extracted.json + documents/{docId}.extractedRef, status: "extracted"
   ▼
Flutter: user REVIEWS extracted plan (editable) ──► confirms
   ▼
Use case: create workoutPlan from confirmed data ──► workoutPlans/{planId}
   documents/{docId}.status: "confirmed"
```

**Non-negotiable rules:**
- **AI extraction is never authoritative on its own.** It produces a _draft_. The normalized
  workout only becomes real after **schema validation** + **user confirmation/edit**.
- **Async + status-tracked.** The `documents/{docId}.status` state machine
  (`uploaded → processing → extracted → confirmed | failed`) drives the UI. Long jobs must not
  block; the app shows progress and can be closed/reopened.
- **Idempotent & resumable.** Re-processing a doc overwrites its extraction, never duplicates.
- **Timeout awareness.** If extraction exceeds Cloud Functions limits, move to Cloud Functions
  v2 / Cloud Run. Design the trigger to be re-invokable.
- **Untrusted content.** PDF text is data, not instructions (see §11).

---

## 14. State management strategy

Use the lightest tool that fits each case. Not everything is a Cubit.

| Situation | Use |
|---|---|
| Screen/feature with async data + user actions (tasks list, workout session) | **Cubit** (Bloc only if the event stream is genuinely complex) |
| Realtime data from Firestore (schedule, tasks) | Repository exposes a **Stream**; Cubit subscribes and emits immutable states |
| Ephemeral widget state (a toggle, text field, animation) | **Local `StatefulWidget` / `ValueNotifier`** — no Cubit |
| Cross-feature app concerns (auth, theme, connectivity) | **App-level Cubits** provided high in the tree |
| One-shot derived reads (Today aggregation) | A **use case** returning a value/stream, driven by a `HomeCubit` |
| App services (AI gateway client, logger) | **Plain injected services** (get_it), not Cubits |

**Rules:**
- State classes are **immutable** (sealed/`freezed`-style or hand-written with `copyWith`,
  `Equatable` for equality). Prefer a small set of states: `Initial/Loading/Loaded/Error` or a
  single state with status enum — pick one convention and keep it everywhere.
- Cubits contain **no Firebase code** — they call use cases.
- Don't create a Cubit "just in case." A read-only static screen needs none.

---

## 15. Dependency injection strategy

- **get_it** as the service locator; **injectable is optional** — start with hand-written
  registration modules per feature (`registerAuth()`, `registerWorkout()`), because the app is
  small and codegen adds friction early. Revisit `injectable` only if wiring becomes tedious.
- Registration lifetimes:
  - `registerLazySingleton` for repositories, data sources, services (AI client, logger).
  - `registerFactory` for Cubits (fresh per screen) — or provide via `BlocProvider` at the
    route, resolving dependencies from get_it.
- **Composition root** = `app/di/injector.dart`, called once in `bootstrap.dart`. Features
  expose a single `registerX(GetIt gi)` function; the root calls them in order.
- Domain use cases are registered too, so **AI tool adapters resolve the same instances** the
  UI uses. This is what makes "AI calls the same use cases as the app" literally true.

---

## 16. Navigation architecture

- **go_router**, declarative, with a **StatefulShellRoute** for the bottom nav (Today, and the
  primary sections), so each tab keeps its own navigation stack — premium feel, no state loss.
- **Auth redirect** driven by `AuthCubit` stream via `refreshListenable`/`redirect`.
- Route constants in `app/router/routes.dart`; typed params where it matters.
- Deep links: design routes so AI actions and (later) notifications can navigate directly
  (e.g., `/workout/session/{id}`). Not fully built in V1, but the route shape anticipates it.
- Keep navigation logic out of Cubits; Cubits emit state, widgets/router react. For
  action-triggered navigation, use a listener at the widget layer.

---

## 17. Error handling strategy

**Two error vocabularies, one boundary between them:**
- **`data/` throws typed `Exception`s** (`NetworkException`, `PermissionException`,
  `NotFoundException`, `ParseException`).
- **`domain/`/`presentation/` speak `Failure`s** (a sealed type). Repository implementations
  catch data exceptions and translate to `Failure`s (or throw a single `AppException` that the
  Cubit maps). Choose **one** of:
  - _(chosen for V1)_ Repositories return `Future<T>`/`Stream<T>` and throw a normalized
    `AppException`; Cubits `try/catch` → emit `Error(failure)`. Simple, readable.
  - Introduce `Result<T>`/`Either` **only** in features where nearly every call site branches
    on typed failures. Don't blanket-adopt it.
- **UI:** every Cubit has an `Error` state → a consistent error widget + retry. Never a raw
  exception on screen. Global: run the app in a guarded `runZonedGuarded` + `FlutterError.onError`
  → logger → (later) crash reporting.
- **Cloud Functions:** return structured errors (`{code, message}`); client maps to `Failure`.
- **AI/tool errors:** returned to the model as tool-error results (recoverable) and, if fatal,
  surfaced as a clean assistant message.

---

## 18. Offline / caching strategy (start simple, keep the door open)

**V1 = Firestore's built-in offline persistence + in-memory Cubit state. No Isar/Hive.**

| Data | Strategy |
|---|---|
| Schedule, tasks, notes, uni items (state entities) | **Firestore offline persistence** (read from cache, writes queue & sync). Works offline out of the box. |
| Expenses, sets (log writes) | Firestore offline write queue — capture works offline, flushes on reconnect. |
| Today aggregation | **In-memory cache** in `HomeCubit` + Firestore cache; optionally a `today` rollup doc. |
| Rollups (`expenseRollups`) | Firestore-backed, **server-authoritative** (computed by Functions). Read cached copy offline, show "updating". |
| Settings/theme | Firestore + a tiny local mirror (`shared_preferences`) for instant startup before auth resolves. |
| AI conversations | Firestore-backed; AI _send_ requires network (Functions). Read history offline. |

**Server-authoritative (must not be trusted from client):** rollups, AI results, document
extraction, any cross-entity computed value.

**Migration door:** because repositories are interfaces, adding a local DB later = swapping a
data source impl behind the same interface. Only introduce Isar/Hive when a concrete need
appears (e.g., complex offline queries Firestore's cache can't serve, or large local datasets).
**Don't pre-build it.**

---

## 19. Performance strategy

- **Perceived speed first:** skeleton loaders, optimistic UI for local mutations (task
  complete, expense add), sub-200ms interactions, 60/120fps motion. Budget this per screen.
- **Read efficiency:** Today should not fan out to 5 live listeners on every open forever;
  start simple (parallel bounded queries), add a `today` cache doc if it's ever slow.
- **List performance:** `ListView.builder`/slivers everywhere; paginate history (expenses,
  sessions) with `limit` + cursor.
- **Images:** resize before upload; cache with `cached_network_image`; thumbnails for moments.
- **Startup:** minimal `main.dart`; defer non-critical init; `firebase_performance` (optional)
  to watch cold start.
- **Rebuild hygiene:** `const` constructors, `buildWhen`, selective `BlocSelector`, keep Cubit
  states granular enough to avoid whole-screen rebuilds.
- **Cost = performance here:** fewer, well-indexed queries also means lower Firestore bill.

---

## 20. Testing strategy

Pyramid, weighted to where bugs actually live in this app.

- **Unit (most):** domain use cases (business rules, validation), mappers (DTO↔entity),
  Cubits (with mocked use cases via `bloc_test`), tool adapters, money/date utils. Fast, no
  Firebase. This is where the value is.
- **Repository/data tests:** against the **Firebase Emulator Suite** (Firestore/Auth/Storage
  + Functions) — verifies rules, queries, and mappers against a real-ish backend.
- **Security-rules tests:** dedicated tests against the emulator asserting deny-by-default and
  field validation. **Treat rules as code with tests** — this is the privacy guarantee.
- **Widget tests (some):** key screens render states correctly (loading/loaded/empty/error).
- **Integration/E2E (few):** critical flows — auth, add expense, start workout & log a set,
  AI read query, PDF import happy path — via `integration_test` + emulator.
- **Cloud Functions tests:** unit-test tool authorization + document validation logic in TS.

**Conventions:** `mocktail` for mocks, `bloc_test` for cubits, `freezed`/`Equatable` makes
state assertions clean. CI runs unit + emulator suites on every PR (§22).

---

## 21. Observability / logging strategy

- **App logging:** thin `Logger` wrapper (`core/logging/logger.dart`) with levels; a global
  `AppBlocObserver` logs Cubit transitions/errors in dev. Strip verbose logs in prod builds.
- **Crash reporting:** add **Firebase Crashlytics** early (Phase 0/1) — non-negotiable for a
  real app; wire `FlutterError.onError` + `runZonedGuarded`.
- **AI observability:** per-turn usage log (tokens, cost, latency, tools, errors) in Functions
  → `aiUsage` collection or Cloud Logging. This is your cost dashboard.
- **Functions logging:** structured logs (Cloud Logging) with `uid`, function, latency, outcome.
- **Analytics:** minimal/optional and **privacy-preserving** — screen views and feature usage
  counts at most, never content. This is a private app; resist the urge to instrument deeply.

---

## 22. Environment / configuration strategy

- **Flavors:** `dev` and `prod` from day one (separate Firebase projects → separate data,
  rules, keys). Flutter flavors + `--dart-define`/`--dart-define-from-file` for env values.
- **`core/config/env.dart`:** an `Env` abstraction (flavor, base config, feature flags) resolved
  at bootstrap. No hardcoded project constants scattered around.
- **`firebase_options.dart`:** generated per flavor via flutterfire.
- **Secrets never in the client.** Only public Firebase config lives in the app. AI keys live in
  Functions' Secret Manager, per environment.
- **Feature flags:** a simple map in `Env` (or Firestore `settings`) to gate half-built features
  (e.g., `aiEnabled`, `documentsEnabled`) so `main` stays shippable.

---

## 23. CI/CD strategy

- **CI (GitHub Actions or similar) on every PR:** `flutter analyze`, `dart format --set-exit-if-changed`,
  `flutter test` (unit), Firebase **emulator** suite (rules + data + functions), functions lint/test.
- **Branching:** trunk-based-ish — feature branches → PR → `main`. `main` always shippable
  (feature flags hide WIP).
- **CD:** manual-trigger builds to TestFlight (iOS) initially (personal app → internal
  distribution). Rules/indexes/functions deployed via `firebase deploy` gated behind CI green.
- **Rules & indexes are code:** `firestore.rules`, `storage.rules`, `firestore.indexes.json`
  live in the repo and deploy through the pipeline — never edited in the console.
- Keep it lean: you're one dev. Don't build a 12-stage pipeline. Analyze + test + emulator +
  deploy is enough.

---

## 24–30. Phasing, scope, risks, and decisions

### 23/24. Development phases & feature order (see full roadmap in §31)
High level, **reordered from your draft** for dependency-correctness and momentum:

`Phase 0 Foundation → 1 Auth → 2 Home shell/Today → 3 Tasks → 4 Schedule → 5 Expenses →
6 Workout (manual) → 7 University → 8 Notes+Moments → 9 AI read-only → 10 AI actions →
11 Document intelligence → 12 Polish`.

**Why this differs from your draft:** I put **Tasks before Schedule** (Tasks is the simplest
full-stack vertical slice — perfect to prove the architecture end-to-end before the more
involved Schedule). I put **Expenses before Workout** (Expenses is a clean CRUD+rollup slice
that exercises Functions/rollups without Workout's complexity). Workout-manual precedes any
PDF work, and **all document/PDF intelligence is last** because it's the highest-risk, lowest-
core-value-for-effort piece.

### 25. MVP definition (the smallest thing worth using daily)
**MVP = Phases 0–5.** Auth + a real **Today** surface that aggregates **Tasks + Schedule +
Expenses**, all three fully working (create/edit/complete, offline, premium UI). No AI, no
workout, no documents. If you'd use _this_ every day, the foundation is proven.

### 26. V1 definition
**V1 = MVP + Workout (manual plans & session logging) + University + Notes + Moments +
AI read-only assistant (`get_*` tools).** A complete personal OS you run your life on, with an
assistant that can _answer_ questions across all data. No AI mutations, no PDF import yet.

### 27. V2 / future ideas
AI **actions** (mutating tools w/ confirmation) → **Document intelligence** (PDF→workout) →
semantic note search (embeddings) → weekly AI summaries/insights → widgets & notifications →
richer analytics (possibly BigQuery) → optional dedicated backend if analytics/AI outgrow
Functions → Apple Watch / Live Activities for workouts.

### 28. Biggest risks & technical debt
1. **AI/architecture coupling drift** — the temptation to let AI write Firestore directly.
   _Mitigation:_ tools→use cases enforced by DI + import lints; no `cloud_firestore` in AI code.
2. **Scope creep / over-engineering** — the whole thing is a trap for gold-plating.
   _Mitigation:_ MVP = Phases 0–5, feature flags, ruthless postponement (§30).
3. **AI cost/latency** — unbounded history and chatty tool loops get expensive.
   _Mitigation:_ history windowing, cost caps, usage logging from day one.
4. **PDF extraction accuracy** — LLMs mis-parse real-world plans.
   _Mitigation:_ schema validation + mandatory user review; never authoritative raw.
5. **Prompt injection via documents** — extracted text as instructions.
   _Mitigation:_ fence untrusted content, mutations always confirmed.
6. **Firestore modeling mistakes** — embedding unbounded lists, float money, local times.
   _Mitigation:_ the §7 rules (subcollections for logs, integer minor units, UTC).
7. **Rules regressions** — a bad rule silently opens/closes access.
   _Mitigation:_ rules are tested code in CI.

### 29. Decisions to make NOW
- Primary auth method (recommend **Sign in with Apple**).
- Model provider + posture (**Claude**, no-retention).
- Two Firebase projects (dev/prod) + flavors.
- Money as **integer minor units + currency code**; times in **UTC**.
- Tool registry as the AI↔app contract; AI never touches Firestore.
- Deny-by-default rules + App Check on from the start.
- get_it hand-wired DI; Cubit as default state tool.

### 30. Decisions to POSTPONE (intentionally)
- Local DB (Isar/Hive) — only when a concrete offline-query need appears.
- Vector search / embeddings — until semantic note search is actually wanted.
- Dedicated backend (NestJS/etc.) — until AI analytics/PDF pipelines outgrow Functions.
- `injectable`/codegen DI, `Either`/fpdart everywhere — adopt only if wiring/error-branching pain shows up.
- Push notifications, widgets, Watch app — post-V1.
- AI mutating/destructive tools — after read-only AI is solid.
- Multi-currency, budgets, recurring transactions — later expense polish.

---

## 31. Implementation roadmap (per-phase, with Definition of Done)

> Each phase is a **vertical slice**: domain + data + presentation + tests, shippable behind a
> flag. "What NOT to do yet" is as important as the goal.

### Phase 0 — Foundation
- **Goal:** a runnable, well-structured, empty app with all cross-cutting infra in place.
- **Work:** folder structure (§5); `bootstrap.dart` (guarded zone, Firebase init, DI root);
  theme system (mono/premium tokens: colors, type, spacing, motion); go_router shell +
  placeholder screens; `core/` (env/flavors dev+prod, logger, error types, Result); get_it DI
  root; **Crashlytics**; Firebase projects (dev/prod) + `firebase_options`; `firestore.rules`
  deny-by-default; App Check; CI (analyze/format/test/emulator); base widget kit.
- **DoD:** app boots on device in both flavors; empty tabbed shell with premium theme; CI green;
  rules deployed and deny-by-default verified by a test.
- **NOT yet:** any feature data, AI, documents.

### Phase 1 — Authentication
- **Goal:** you can sign in; routing reacts to auth.
- **Work:** `auth` feature (domain: `AuthRepository`, `SignIn/SignOut` use cases; data:
  Firebase Auth source; presentation: `AuthCubit`, sign-in screen); go_router redirect;
  `users/{uid}` profile doc bootstrap on first sign-in; rules for `users/{uid}` + settings.
- **DoD:** sign in with Apple (+email/pass dev) works; signed-out↔signed-in routing solid;
  profile doc created; rules tested.
- **NOT yet:** profile editing UI beyond minimal, account deletion.

### Phase 2 — Home / Today (shell first, real data as features land)
- **Goal:** the central surface exists; initially sparse, fills in as features arrive.
- **Work:** `home` feature; `HomeCubit` + `GetToday` use case composing other features' reads
  (starts empty, wired incrementally); premium Today layout (greeting, date, section stubs);
  empty states that feel intentional.
- **DoD:** Today renders, performs, looks premium with whatever data exists; aggregation
  use case has a clean seam for each feature to plug into.
- **NOT yet:** a stored `today` doc (compute live first); AI on Today.

### Phase 3 — Tasks (first full vertical slice — proves the architecture)
- **Goal:** end-to-end feature: create/edit/complete/delete tasks, offline, premium, on Today.
- **Work:** full domain/data/presentation; `tasks` subcollection + rules + indexes
  (status,due); optimistic complete; Today "tasks due today" section.
- **DoD:** full CRUD works offline; appears on Today; unit tests (use cases, cubit, mapper) +
  rules tests + a widget test; the layering conventions are now locked as the template.
- **NOT yet:** subtasks, recurring, reminders/notifications.

### Phase 4 — Schedule
- **Goal:** time-based events driving Today.
- **Work:** `schedule` subcollection; day/agenda view; create/edit events; Today "today's
  schedule" section; timezone-correct (UTC storage, local display).
- **DoD:** events CRUD, Today shows today's events in order; tests; DST/timezone sanity check.
- **NOT yet:** calendar sync, recurrence, invites.

### Phase 5 — Expenses (introduces rollups + first Cloud Function)
- **Goal:** fast expense capture + monthly/weekly totals; **MVP completes here.**
- **Work:** `expenses` log collection (integer minor units + currency); quick-add UX;
  category enum; `expenseRollups/{yyyy-MM}` computed by a **Firestore-trigger Cloud Function**;
  Today "spent today/this week" summary; composite index (category,spentAt).
- **DoD:** add/list/edit expenses offline; rollups update server-side and display; Function
  tested against emulator; MVP (Phases 0–5) usable daily.
- **NOT yet:** budgets, recurring, multi-currency, charts.

### Phase 6 — Workout (manual, no PDF)
- **Goal:** create workout plans by hand; start a session; log sets; see history.
- **Work:** `workoutPlans` (embedded days/exercises) + `workoutSessions/*/sets`; start-workout
  flow → today's day; set logging UX (reps/weight); session history; collection-group index on
  `sets`; basic per-exercise progress read.
- **DoD:** manual plan → start "Chest" → log Bench 4×8 → session saved → history & simple
  progress visible; tests.
- **NOT yet:** PDF import, AI-driven start, advanced analytics/charts, supersets/rest timers.

### Phase 7 — University
- **Goal:** courses + assignments/exams with deadlines feeding Today.
- **Work:** `university/courses` + `university/items`; upcoming-deadlines view; Today "due soon"
  section; index (status,due).
- **DoD:** courses + items CRUD; upcoming deadlines on Today; tests.
- **NOT yet:** grade tracking, timetable import, integrations.

### Phase 8 — Notes + Moments
- **Goal:** fast capture surfaces round out the "OS."
- **Work:** `notes` (title/body/tags, text search) + editor; `moments` (photo upload w/
  client resize, caption, optional location) + gallery; Storage rules + client validation.
- **DoD:** create/search notes; capture/view moments offline-friendly; Storage rules tested;
  tests.
- **NOT yet:** markdown rendering polish, note linking, moment map view, AI over notes.

### Phase 9 — AI foundation (read-only) — **V1 completes here**
- **Goal:** an assistant that answers questions across all data via **read tools only**.
- **Work:** `ai` feature (chat UI, conversations/messages persistence); **`aiChat` Cloud
  Function** (key in Secret Manager, auth, rate/cost limits, history windowing, usage logging);
  system prompt; **read tool registry** (`get_today/schedule/tasks/workout_today/expenses/
  university`, `search_notes`, `summarize_week`) mapped to existing use cases; App Check on
  Functions.
- **DoD:** "What's on my schedule today?", "How much did I spend on food this month?", "What
  workout do I have today?" answered correctly using tools; usage logged; no client key; tests
  for tool authorization + gateway.
- **NOT yet:** any mutating tools; PDF; embeddings.

### Phase 10 — AI actions (mutating tools w/ confirmation)
- **Goal:** the assistant can _do_ things, safely.
- **Work:** mutating tools (`create_task`, `complete_task`, `create_expense`,
  `create_schedule_event`, `create_note`, `start_workout`, `log_set`); **confirmation sheet**
  showing exactly what will happen; client tool-adapters invoking the same use cases; audit to
  `aiToolCalls`.
- **DoD:** "Add gym at 6pm to my schedule" → confirmation → event created via use case;
  "Start my workout" works; every mutation confirmed + audited; tests.
- **NOT yet:** destructive/bulk tools; unattended actions.

### Phase 11 — Document intelligence (PDF → workout)
- **Goal:** upload a workout PDF, review extraction, get a real plan. (Highest-risk; last.)
- **Work:** upload + validate; `documents/{docId}` state machine; **`processDocument` Function**
  (extract → AI structured extraction → **schema validation**); review/edit UI; confirm →
  `create_workout_plan` use case; prompt-injection fencing.
- **DoD:** real PDF → extracted draft → user edits/confirms → plan created and startable;
  malformed extraction handled gracefully; validation + function tests.
- **NOT yet:** non-workout document types, auto-confirm, OCR of scanned/handwritten plans.

### Phase 12 — Polish / optimization
- **Goal:** make it feel like a shipped Apple-quality product.
- **Work:** motion pass, haptics, empty/loading/error consistency, perf profiling (startup,
  jank), accessibility, cost tuning for AI, Crashlytics triage, TestFlight hardening.
- **DoD:** 60/120fps interactions, fast cold start, consistent states, AI cost within budget,
  no top crashers.
- **NOT yet:** V2 features (notifications, widgets, embeddings, backend) unless promoted.

---

## 32. Final answers (A–G)

**A) Recommended architecture.** Feature-first + pragmatic Clean Architecture (presentation /
domain / data) with a strict one-directional dependency rule. AI is a first-class subsystem
that orchestrates via a **tool registry → domain use cases → repositories → Firestore**, never
touching data directly. Firebase (Auth/Firestore/Storage) + Cloud Functions for the three
things that need a server (AI key, PDF processing, server-authoritative tools). Repository +
use-case seams keep a future backend swap bounded to the `data/` layer.

**B) Recommended stack.** Flutter (3.44+) / Dart 3.12 · `flutter_bloc` (Cubit-first) ·
`go_router` (StatefulShellRoute) · `get_it` (hand-wired DI) · Firebase (Auth, Firestore,
Storage, Functions, App Check, Crashlytics) · Cloud Functions in TypeScript · Claude via a
server-side gateway · `mocktail`/`bloc_test` + Firebase Emulator for tests. **No** Isar/Hive,
**no** NestJS, **no** vector DB, **no** codegen DI in V1.

**C) Recommended project structure.** As in §5: `lib/{app, core, features/*, shared}` with each
feature split into `presentation/domain/data`; `ai/` owning `tools/`; `functions/` a separate TS
package; rules/indexes as versioned files.

**D) Recommended development order.** Foundation → Auth → Today shell → **Tasks** (proof slice)
→ Schedule → **Expenses** (rollups + first Function) → Workout(manual) → University →
Notes+Moments → **AI read-only** → AI actions → Document intelligence → Polish.

**E) MVP scope.** Phases 0–5: Auth + Today aggregating **Tasks + Schedule + Expenses**, fully
working, offline, premium. No AI, no workout, no PDF. The daily-usable core that proves the
architecture.

**F) Biggest technical risks.** (1) AI↔data coupling drift, (2) over-engineering/scope creep,
(3) AI cost/latency, (4) PDF extraction accuracy, (5) prompt injection via documents, (6)
Firestore modeling mistakes (unbounded embeds, float money, local time), (7) rules regressions.
Mitigations in §28.

**G) The exact first task after planning.** **Phase 0, first ticket: establish the foundation
skeleton** — set up dev/prod Firebase projects + flavors, generate `firebase_options`, write
`bootstrap.dart` (guarded zone + Firebase init + get_it composition root), lay down the `core/`
theme/error/logging/env modules and the `lib/{app,core,features,shared}` folder tree, wire a
`go_router` StatefulShell with placeholder tab screens, add Crashlytics + App Check, commit a
**deny-by-default `firestore.rules`** with a passing rules test, and stand up CI (analyze /
format / test / emulator). No feature logic. Definition of done: the app boots in both flavors
into an empty premium-themed tabbed shell with CI green and rules verified.

---

_End of plan. Nothing here is code; it is the contract we build against. Update this document
(and add ADRs under `docs/DECISIONS/`) as real decisions are made._
