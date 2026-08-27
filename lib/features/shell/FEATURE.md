# shell — feature map

> The app scaffold once signed in: the 4-tab surface and the floating bottom bar.

## Start here

- `presentation/home_shell.dart` — **`HomeShell`**: a 4-tab `IndexedStack` —
  **Today (0) · Hub (1) · Ask (2) · You (3)**. Owns `_index`, exposes `onOpenAsk`
  (used by Today to jump to Ask), and routes the quick-capture sheet result into Ask's
  composer.
- `presentation/widgets/zivo_bottom_bar.dart` — the floating "island" bottom bar with the
  spring-gliding ember capsule.
- `presentation/widgets/capture_fab.dart` — the center capture FAB (opens the capture sheet).
- `presentation/widgets/coming_soon.dart` — placeholder for not-yet-built destinations.

## Gotchas

- Navigation is a **simple `IndexedStack`**, deliberately — see the constraint in
  [`AGENTS.md`](../../../AGENTS.md) against introducing `go_router` without an ADR.
- `HomeShell.initState` also fires `runAutoBackupIfDue()` for the media pipeline on app open.
- The "You" tab is the auth feature's `profile_page.dart` (not a shell page).
