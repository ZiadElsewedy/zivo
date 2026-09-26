# ADR-018 — Admin Console: a server-enforced admin role, derived events, callables only

**Status:** accepted · 2026-09-25 · branch `upgrades`

## Context

The owner needs to see how ZIVO is used: how many people, who is active, whether
they build plans and actually train, and what AI costs. They also need to suspend
or delete an account. ZIVO had no role system (the uid was the only ownership key,
docs/AUTH.md §4), no analytics, and per-user AI usage in `users/{uid}/aiUsage`.

## Decision

1. **Role = the `admin` custom claim.** Set only by the owner's
   `functions/scripts/set-admin.js`, with owner credentials. Never granted
   from the app or a callable. This is the use AUTH.md reserved claims for.
2. **Same app, separate shell.** `AuthGate` checks the claim (cached token, no
   network) once per uid: admin → `AdminShell`, anyone else → the unchanged
   `_SessionGate` → `HomeShell`. No second app or separate backend.
3. **The client never reads admin data from Firestore.** Every admin read and
   action goes through admin-only callables (`functions/admin/`). Each one
   checks the token claim **and** re-reads the Auth record, so a revoked or
   disabled admin is refused at once rather than when the token expires. The
   rules deny `adminUsers` / `adminEvents` / `adminAudit` to every client,
   admins included. No rule branches on a role, and an admin token gets no
   extra access to anyone's `users/{uid}` data (pinned by rule tests).
4. **Events are derived on the server, not sent by the client.** Firestore/Auth
   triggers turn writes ZIVO already makes into a short list of product events:
   account creation; a device-session claim (= app opened); a workout
   session's status changes; plan creation; diet plans; `aiUsage` records.
   There is no client analytics code and no new client write channel, and no
   event can be forged. Only status/counts/dates are copied, never content.
   Each event gets a deterministic id, so a trigger that fires twice records it
   only once.
5. **Incremental summaries plus server aggregations.** Each event updates a
   per-account `adminUsers/{uid}` summary with counters and dates. Dashboard
   figures come from `count()`/`sum()` aggregations. The users table runs
   indexed, cursor-paginated queries. Nothing downloads every user.
6. **Least privilege in the projection.** `functions/admin/queries.js` decides
   what leaves the server: masked email, profile name, dates, platform,
   version, counters, event names with whitelisted scalar properties.
   Conversations, notes, photos, and workout/meal/expense contents are never
   read.
7. **Deletion reuses the one erasure.** `deleteAccount`'s body became
   `eraseAccount(uid)`. The user's own deletion and `adminDeleteUser` both run
   it. The admin path also requires a fresh `auth_time`
   (`requireRecentAuth`), the uid repeated as confirmation, a typed code in
   the UI, and it refuses to act on the caller or on another admin. Every
   admin action is written to `adminAudit`.

## Consequences

- Accounts that existed before the triggers have no event history. **Rebuild
  summaries** recounts their counters from source data. The event history
  starts from the day the triggers were deployed.
- "Last active" is the latest meaningful event: an app launch, a workout, or
  an AI request. A session left open in the background for days does not
  refresh it.
- A new claim reaches the client only after sign-out/in (token refresh). A
  revoked claim stops server access immediately.
- A suspended account's current ID token stays valid for up to an hour after
  `revokeRefreshTokens`. The Firestore rules do not re-check `disabled`.
- Each `workoutSessions` write invokes a trigger (set-by-set updates included),
  but only status changes do any work. At ZIVO's scale this cost is fine. If
  it isn't later, move the session trigger to a status field mirror.
- Events expire after 180 days (TTL on `expireAt`). Summaries keep lifetime
  counters.
