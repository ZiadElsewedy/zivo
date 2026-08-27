# capture — feature map

> The quick-capture sheet reached from the shell's center FAB, plus the shared capture UI
> widgets reused across feature capture screens.

## Start here

- `presentation/quick_capture_sheet.dart` — the capture sheet + its `CaptureChoice` options
  (route into workout / diet / expense / moment / etc. capture flows).
- `presentation/widgets/capture_widgets.dart` — shared `CaptureTopBar` / `PillButton` /
  `SelectChip` used by the per-feature capture pages.

## Gotchas

- Feature capture pages (e.g. `expenses/.../expense_capture_page.dart`,
  `workout/.../workout_capture_page.dart`) should **reuse** these shared widgets rather than
  rolling their own — it's what keeps capture consistent.
