# Admin Console — backend, data model, operations

Decision: [ADR-018](DECISIONS/ADR-018-admin-console.md). Client map:
[`lib/features/admin/FEATURE.md`](../lib/features/admin/FEATURE.md).

## Flow

```
sign-in ─► AuthGate ─► _RoleGate: token has admin claim?
                          ├─ yes ─► AdminShell ──callables──► functions/admin (assertAdmin every call)
                          └─ no  ─► _SessionGate ─► HomeShell (unchanged)

existing writes ──triggers──► adminEvents/{id} + adminUsers/{uid} (counters)
```

## Collections (Admin-SDK only; denied to every client)

| Path | Shape |
|---|---|
| `adminUsers/{uid}` | `displayName`, `nameLower`, `emailMasked`, `emailLower` (search only, never returned), `createdAt`, `lastActiveAt`, `lastEvent{name,at}`, `platform`, `appVersion`, `status` (`active`/`disabled`), `hasWorkoutPlan`, `workoutPlans`, `workoutPlanCreatedAt`, `workoutsStarted/Completed/Abandoned`, `lastWorkoutAt`, `aiRequests`, `aiTokensIn/Out`, `aiCostUsd`, `usage{app_opened, ai_<feature>, diet_imported, …}` |
| `adminEvents/{id}` | `{uid, name, at, props, expireAt}`. `id` is deterministic per source doc. TTL on `expireAt` (180 d) |
| `adminAudit/{id}` | `{actorUid, action, targetUid, at}` |

## Events (`functions/admin/events.js`)

| Event | Derived from |
|---|---|
| `account_created` | Auth `user().onCreate` |
| `app_opened` | `users/{uid}/session/current` gets a new `sessionId` (one claim per launch). Carries `platform` and `appVersion` |
| `workout_started` / `workout_completed` / `workout_abandoned` / `workout_voided` | `workoutSessions` status transitions only. Completed carries `durationMinutes` |
| `workout_plan_created` | `workoutPlans` created. Carries `source` |
| `diet_imported` / `diet_plan_created` | `dietPlans` created (imported/generated vs manual) |
| `ai_request` | `aiUsage` created. Carries `feature`, `provider`, `status`, `tokensIn/Out`, `costUsd` |
| `account_disabled` / `account_enabled` / `account_deleted` | admin actions and account erasure. These don't count as the user being active |

## Callables (all `us-central1`, all admin-only)

`adminOverview` · `adminListUsers` · `adminGetUser` · `adminActivity` ·
`adminSetUserDisabled` · `adminDeleteUser` (needs recent `auth_time`) ·
`adminRebuildSummaries` (pages through Auth, 50 accounts per call).

## Metrics

- Users: `count()` on `adminUsers`. Totals come straight from it; the
  new/active windows are range counts on `createdAt`/`lastActiveAt`, using the
  admin's local midnight for "today".
- Workouts completed today and AI requests today: counts on `adminEvents` by
  `name` + `at`.
- AI 30 d: `count` and `sum(props.tokensIn|tokensOut|costUsd)` over `ai_request`
  events. AI all-time: `sum` over the summaries. Cost is the estimate
  `aiUsage` already records (list price of the answering model).
- Chart: per-day counts of `workout_completed` and `app_opened` for the last 14
  local days.

## Owner actions (need owner credentials)

1. `firebase deploy --only firestore:rules,firestore:indexes` (new rules, 11
   composite indexes, the `expireAt` TTL).
2. `firebase deploy --only functions` (7 callables, 7 triggers; the
   `deleteAccount` refactor).
3. Grant the role: `cd functions && node scripts/set-admin.js grant <email>`
   (Application Default Credentials). Then sign out and back in on that
   account.
4. Open the console → Dashboard → **Rebuild summaries** once, so existing
   accounts get their counters.

Revoke with `node scripts/set-admin.js revoke <email>`. This also revokes the
account's sessions.
