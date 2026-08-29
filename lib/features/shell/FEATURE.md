# shell — feature map

> The app scaffold once signed in: the 4-tab surface and the floating bottom bar.

## Start here

- `presentation/home_shell.dart` — **`HomeShell`**: a 4-tab `IndexedStack` —
  **Today (0) · Hub (1) · Ask (2) · You (3)**. Owns `_index`, exposes `onOpenAsk`
  (used by Today to jump to Ask), and routes the quick-capture sheet result into Ask's
  composer.
- `presentation/widgets/zivo_bottom_bar.dart` — the floating "island" bottom bar with the
  spring-gliding ember capsule, plus `ZivoBottomBarMetrics`. Its `fused` slot takes a slim
  strip rendered *inside* the island's clip — today, music's `NowPlayingLozenge`.
- `presentation/widgets/bottom_chrome.dart` — **`BottomChrome`**: the measured height of
  the whole bottom object (island + fused strip), published to every tab. Any surface
  needing bottom clearance reads `BottomChrome.of(context)` — never a local constant.
- `presentation/widgets/capture_fab.dart` — the center capture FAB (opens the capture sheet).
- `presentation/widgets/coming_soon.dart` — placeholder for not-yet-built destinations.

## Gotchas

- Navigation is a **simple `IndexedStack`**, deliberately — see the constraint in
  [`AGENTS.md`](../../../AGENTS.md) against introducing `go_router` without an ADR.
- **The bottom is one object, and its height has one owner.** `HomeShell` watches the
  music streams and rebuilds only on the visibility *edge*, so the tab bodies don't
  rebuild per playback emission. Pages must not reserve their own music allowance: three
  of them used to (86 on Today, a different 86 on You, nothing on the Hub) and they
  disagreed the moment a track started.
- The "You" tab is the auth feature's `profile_page.dart` (not a shell page).
