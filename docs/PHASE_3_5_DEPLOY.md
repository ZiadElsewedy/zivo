# Phase 3.5 — Deploy & Validation Runbook

Validates the two things Phase 3.5 shipped that **only a real deploy can confirm**:

1. **Streaming transport** (Slice C) — `aiChat` streaming over Firebase callable
   streaming (`response.sendChunk` ↔ `httpsCallable.stream()`). All logic is
   unit/widget-tested; the wire behaviour is not.
2. **Cost win** (Slice A) — prompt caching + trimming. The mechanism is tested;
   the real token/dollar numbers come from live `aiUsage` docs.

Everything else in Phase 3.5 is covered by the offline suites (251 Flutter +
39 functions tests). Do the **emulator dry-run (Step 0) first** — it catches
most transport problems without touching prod or spending much.

Project: `zivo-63f15` · Functions region: `us-central1` · Secret:
`ANTHROPIC_API_KEY` · Node 24 · `firebase-functions ^7` · `@anthropic-ai/sdk ^0.32.0`

---

## Preconditions

- [ ] Logged in: `firebase login` and `firebase use zivo-63f15`.
- [ ] `ANTHROPIC_API_KEY` secret exists for the functions:
      `firebase functions:secrets:access ANTHROPIC_API_KEY` (set it with
      `firebase functions:secrets:set ANTHROPIC_API_KEY` if missing).
- [ ] SDK/runtime actually support streaming (they should at these versions,
      but confirm before blaming your code):
  - `firebase-functions ^7` supports the streaming `onCall((request, response))`
    signature with `request.acceptsStreaming` + `response.sendChunk`.
  - `@anthropic-ai/sdk ^0.32.0` exposes `messages.stream(req)` with
    `.on('text', …)` and `.finalMessage()`.
- [ ] Functions lint passes (deploy runs it as a predeploy hook):
      `npm --prefix functions run lint`.
- [ ] Offline suites green: `(cd functions && node --test ai/*.test.js)` and
      `flutter test`.

> ⚠️ **App Check is still not enforced.** `aiChat` / `aiConfirmAction` /
> `aiCancelAction` have no `enforceAppCheck` (see the note above
> `aiConfirmAction` in `functions/index.js`). Fine for a private validation
> deploy on your own account; **before any public launch**, add
> `enforceAppCheck: true` to all three callables and verify the client's App
> Check providers in the Console first. Track as a pre-launch item, not a
> blocker here.

---

## Step 0 — Emulator dry-run (de-risk the transport locally)

Cheaper and safer than prod. Uses the real Anthropic API but no deployed
function.

1. Export the key so the emulated function can read it:
   `export ANTHROPIC_API_KEY=sk-ant-…`
2. `firebase emulators:start --only functions,firestore,auth`
3. Point the app at the emulator (Flutter `FirebaseFunctions.instanceFor(region:
   'us-central1').useFunctionsEmulator('localhost', 5001)` — add this behind a
   dev flag if not already wired) and run the app signed-in.
4. Ask a read question (below) and watch for **streamed** behaviour, not a
   single buffered reply.

**Acceptance:** the activity rail advances through real phases and text appears
incrementally (see Step 2's acceptance criteria). If the emulator delivers only
a final buffered reply, fix it here before deploying.

---

## Step 1 — Deploy

```bash
firebase deploy --only functions:aiChat,functions:aiConfirmAction,functions:aiCancelAction
```

(or `--only functions` for all). Confirm the deploy log shows `aiChat`
updated and no build/lint errors.

---

## Step 2 — Validate the streaming transport

Run the **real app** (not the demo entrypoint) signed in as a real user, so it
uses `FirebaseAiRepository` → `httpsCallable('aiChat').stream(...)`. The client
already opts into streaming (the Ask page passes `onEvent`), so no flag is
needed.

**A read turn** — send: `what's due this week?`

- [ ] The iris **activity rail** appears and shows real phases —
      `Understanding…` then `Working…` (Working only if the model actually calls
      a read tool). These are server-derived, not the old time-guess.
- [ ] The reply renders **token-by-token** in a provisional bubble, then settles
      into the durable message with **no re-type / no double bubble**.
- [ ] The durable assistant message persists (kill & reopen Ask — it's still
      there, from Firestore).

**A proposal turn** — send: `add task Submit the report`

- [ ] Rail shows `Preparing change…`, then the confirmation card renders.
- [ ] Confirm → the card collapses to `Confirmed` and the result line appends.
      (Confirm/cancel are deterministic and were never streamed — unchanged.)

**If you see only a final buffered reply (no rail phases, no incremental text):**
streaming isn't reaching the client. Check, in order:
1. The deployed function has the `(request, response)` signature (redeploy if it
   deployed from a stale build).
2. Client calls the same region (`us-central1`).
3. No intermediate proxy is buffering SSE.
The buffered path is still *correct* (Slice B typewriter fallback fires on the
durable message) — it's just not streaming.

---

## Step 3 — Verify the Slice A cost win

Usage is logged per turn at `users/{uid}/aiUsage/{autoId}` with (Slice A adds
the cache fields): `tokensIn`, `tokensOut`, `cacheReadTokens`,
`cacheWriteTokens`, `costUsd`, `iterations`, `schemaVersion: 2`.

**Confirm caching is actually working:**

- [ ] **Turn 1 (cold):** `cacheWriteTokens > 0` (the ~1,337-token tools+system
      prefix was written to cache), `cacheReadTokens = 0` — *unless* it was a
      multi-tool turn (≥2 model calls), in which case reads already appear.
- [ ] **Turn 2, same conversation, within 5 minutes:** `cacheReadTokens > 0`.
      This is the proof the static prefix reads back at 0.1×.
- [ ] If `cacheReadTokens` stays **0** across repeated turns → caching is broken
      (a silent prefix invalidator). Investigate before trusting any savings.

**Quantify it** — for any turn's doc, the caching saving vs. paying full price
for those same cached tokens is:

```
saved_usd ≈ cacheReadTokens × (3 / 1_000_000) × 0.9
```

(0.9 = the 1.0 − 0.1× read discount; input rate is the owner-confirmed
$3 / 1M in `functions/ai/gateway.js`.) `costUsd` on the doc is already the
discounted figure. Trimming (history 20→10, tool-result cap) additionally
lowers `tokensIn` vs. the pre-Slice-A build — visible as lower per-turn
`tokensIn` on multi-tool turns, though a clean A/B needs the old build.

> Note: `costUsd` is computed at the owner-confirmed $3/$15 rate. Actual Anthropic
> billing may differ (Sonnet 5 intro pricing, real cache accounting) — treat
> `costUsd` as ZIVO's internal cost signal, not the invoice.

---

## Rollback

- **Streaming misbehaves in prod:** the client streams whenever it passes
  `onEvent`. Fastest revert to buffered behaviour without a server rollback is a
  one-line client change — stop passing `onEvent` in `AskPage._send` (the
  `.call()` path in `FirebaseAiRepository.send` still works) — then ship the
  client. Slice B's typewriter covers the UX.
- **Server rollback:** redeploy the previous functions revision
  (`git checkout <pre-C.2 commit> -- functions/index.js && firebase deploy
  --only functions:aiChat`). The gateway core (C.1) is inert without the
  handler wiring, so this is safe.

---

## Known gaps / follow-ups

- **No mid-stream reconnect.** A dropped stream surfaces as a send error; the
  durable reply still lands via `watchMessages`. True reconnect (re-attach +
  dedupe) is a future slice.
- **App Check enforcement** (see Preconditions) before public launch.
- **Pricing constant** is pinned at $3/$15; revisit if the owner switches to the
  Sonnet 5 intro rate.
