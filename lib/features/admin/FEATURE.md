# admin — feature map

> The Admin Console. A lightweight, desktop-first view of who uses ZIVO and
> how, plus account suspend/re-enable/delete. It is shown **instead of** the
> normal app to an account holding the `admin` claim. Decision + rationale:
> [ADR-018](../../../docs/DECISIONS/ADR-018-admin-console.md). Backend, data
> model and owner actions: [docs/ADMIN.md](../../../docs/ADMIN.md).

## The one rule

**The console holds no authority.** It never reads Firestore. Every number and
action comes from an admin-only callable that re-checks the claim on the
server, and the server's projection (`functions/admin/queries.js`) decides
what an admin may see: counts and dates, never content. A client that forced
its way into `AdminShell` would get `permission-denied` on every call.

## Start here

| File | What it is |
|---|---|
| `domain/admin_repository.dart` | the seam (`overview`, `listUsers`, `user`, `activity`, `setDisabled`, `deleteUser`, `rebuildSummaries`) + `AdminFailure` |
| `domain/admin_models.dart` | read models mirroring the server projection; `AdminUserQuery` (one segment + at most one indexed filter + search + cursor) |
| `data/callable_admin_repository.dart` | the callables (`adminOverview`, `adminListUsers`, …) |
| `data/in_memory_admin_repository.dart` | offline/test fake that filters and pages like the server |
| `presentation/admin_shell.dart` | **`AdminShell`**: sidebar (≥1100px) · rail (≥720px) · bottom bar (phone). One `Navigator` per section, built on first visit |
| `presentation/pages/` | `admin_dashboard_page` (engagement ladder, people/training/AI figures, 14-day bars, rebuild) · `admin_users_page` (search, segments, filter menu, table/list, load more) · `admin_user_detail_page` (account/workout/usage/recent + manage; delete dialog) · `admin_activity_page` (event totals per window + feed) |
| `presentation/admin_labels.dart` | event/usage/platform labels and number formats. Server ids are never shown raw |
| `presentation/widgets/admin_ui.dart` | the console's building blocks (`AdminPageFrame`, `AdminGroup`, `AdminFigure`, `AdminLoader`, …) |

## Wiring

- `AppScope.admin` / `requireAdmin`, built in `app.dart` (`CallableAdminRepository`
  on a Firestore run).
- Routing: `AuthGate` → `_RoleGate` → `auth.hasRole('admin')`
  (`RoleAuthorization` facet on `AuthRepository`).
- `DeviceSessionGuard` now writes `appVersion` into `session/current`. That
  claim is the `app_opened` event.

## Gotchas

- **Design:** violet is the console's accent (system/meta, ADR-006). Green
  marks training figures and amber marks money. Ember is used only on Delete.
  Figures are set in Azeret Mono, structure is drawn with hairlines, not
  cards.
- **Delete** asks for the last six characters of the uid, then calls
  `auth.reauthenticate` (password or provider sheet) before `deleteUser`. The
  server refuses a stale `auth_time`.
- Admin accounts can't be suspended/deleted from the console. Use the
  `set-admin` script.
- `FakeAuthRepository.hasRole` returns a `SynchronousFuture`, so app-root tests
  don't need an extra pump for the role gate.
