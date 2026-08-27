# PRODUCT — what ZIVO is and what makes it different

> Agent-neutral positioning doc. Read this to work in the product's spirit — new work
> should protect and deepen the differentiation below, not dilute it into a generic
> tracker. Positioning is a **direction**, not a status report; for what's actually built
> right now see [`STATE.md`](STATE.md).

## One line

**ZIVO is an AI-powered gym / training tracker** — a training app built *around* a coach
that actually knows your numbers, not a workout log with a chatbot bolted on top.

## Who it's for

Someone who trains seriously enough to care about progression — following a real split,
logging real sets, watching real trends — and wants the app to feel like a coach in their
corner rather than a spreadsheet with nicer fonts.

## The anti-positioning (what we are NOT)

- Not "another gym tracker with AI added on top." The AI is the spine, not a feature tab.
- Not a generic chatbot that answers fitness trivia. It reads and acts on **your own**
  training/diet/body data, and its writes are confirmation-gated.
- Not a cold data-entry grid. Design (warm, dark, calm, spring-physical motion) is part of
  the product — checking in should take seconds, not willpower.

## What makes it different (built today — protect these)

These already exist in the codebase and are the wedge. Deepen them before adding breadth.

1. **A coach that knows your numbers.** The "Ask" assistant is tool-mediated over your own
   Firestore data (splits, logged sets, body-weight, diet), streams its answers, and
   proposes writes you confirm. Not a generic LLM chat. → [`ai/FEATURE.md`](../lib/features/ai/FEATURE.md),
   [ADR-001](DECISIONS/ADR-001-ai-assistant.md) / [ADR-003](DECISIONS/ADR-003-ai-mutations-v2.md).
2. **Guided live sessions**, not a static log — server-authoritative session phases, rest
   policy, real-time set logging. → [`workout/FEATURE.md`](../lib/features/workout/FEATURE.md).
3. **Progression intelligence.** Day-progress analysis, progress comparison, week-over-week
   trends, scoped to the active split — the app has an opinion about whether you're
   improving, not just a history list.
4. **Bring your own plan (PDF import).** AI extracts a real, structured multi-day split from
   a coach's PDF — removing the biggest onboarding wall: re-typing a program. Diet plans
   import the same way.
5. **First-class training model.** A real multi-split data model with an exercise-identity
   invariant — structured, analyzable data, not freeform notes.
6. **Training-anchored sensory detail** — a Spotify now-playing companion that lives in the
   session, with an album-artwork color-adaptive Now Playing screen.
7. **Privacy as the model.** Your data in your account; the AI only ever acts on your own
   data; media backs up to *your* Google Drive.

## Directions to explore (aspirational — not built; mark clearly if you pursue one)

Ideas that would push ZIVO further from a generic tracker. None are committed; each needs an
owner decision (and an ADR) before implementation.

- **Coach as the primary surface** — proactive rather than on-demand: notice a stalled lift
  and suggest a deload, flag a missed session, edit the plan conversationally.
- **Adaptive progression** — auto-propose next-session targets from logged performance and
  rest, instead of the user deciding the jump.
- **Explainable coaching** — every suggestion cites the numbers behind it (transparency as a
  trust feature).
- **Readiness signals** — fold already-captured data (body-weight trend, step count) into
  coaching and session recommendations.
- **The weekly coach report as a narrative** — turn `functions/ai/coach_report.js` output
  into a story of your training block, not a stat dump.

## How the surrounding areas fit the training story

Diet is training fuel (calories/macros against your day). The music companion is for the
session itself. Moments and expenses are lightweight life-capture that share the shell and
design language. The center of gravity is **training + the AI coach**; peripheral areas
should support that story, and new breadth is weighed against it.
