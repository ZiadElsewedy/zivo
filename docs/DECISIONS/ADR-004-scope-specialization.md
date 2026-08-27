# ADR-004: Scope specialization — an AI-powered gym tracker

**Status:** Accepted (2026-08-24; Music clause amended 2026-08-25; repositioned 2026-08-27)
**Deciders:** Ziad (owner)
**Relates to:** [`docs/PRODUCT.md`](../PRODUCT.md) (positioning + differentiation) and
[`docs/STATE.md`](../STATE.md) (current scope).

> This ADR records a **standing product decision** so no future agent has to rediscover it
> from git archaeology or from one machine's local memory.

## Context

ZIVO began as a broad "personal OS" with eight feature areas. Maintaining that surface
diluted focus. The owner narrowed it — and then sharpened the framing further (2026-08-27):
ZIVO is an **AI-powered gym / training tracker**, built to feel meaningfully different from
a typical workout log, with the AI coach + guided sessions + progression intelligence as
the center of gravity (see [`docs/PRODUCT.md`](../PRODUCT.md)). It is no longer positioned
as a general personal app.

## Decision

**Center of gravity:** training + the AI coach (Workout + AI "Ask"). Everything else exists
to support the training story or shares the shell/design language.

**Keep:** Workout, Diet, Expenses, Moments, the AI "Ask" assistant (including the voice
recorder), Music (see amendment), and the core surfaces (auth/profile, shell, capture,
media, home/Today, hub, device/steps).

**Remove (2026-08-24):** Schedule, Tasks, University, Notes — including their code, tests,
Firestore rules/indexes, and any unused dependencies.

### Amendment (2026-08-25) — Music is kept, reshaped

Music/Spotify was deleted in the same 2026-08-24 pass, but the owner clarified that its
removal was **not** an intended decision. Music is **restored and in scope**, reshaped
from a standalone tab into a **workout-anchored now-playing companion** plus an immersive
**Now Playing** screen (album-artwork color-adaptive background + subtle mini-bar tint).
See [`lib/features/music/FEATURE.md`](../../lib/features/music/FEATURE.md).

## Consequences

- **Schedule / Tasks / University / Notes are gone, not paused.** Do not resurrect them
  from git history unless the owner explicitly asks. Treat them as out of scope.
- **Music/Spotify is a first-class feature**, not a settled deletion.
- New feature work should fit the gym-tracker / AI-coach framing in [`docs/PRODUCT.md`](../PRODUCT.md)
  and deepen the differentiation rather than add generic breadth; anything outside it
  warrants its own ADR and an owner decision first.
- Any dependency freed by the removals stays removed unless a kept feature needs it (Music's
  `spotify_sdk` was re-added for the restore).
