# capture — feature map

> The quick-capture sheet reached from the shell's center FAB, plus the shared capture UI
> widgets reused across feature capture screens.

## Start here

- `presentation/quick_capture_sheet.dart` — the capture sheet + its `CaptureChoice` options
  (route into workout / diet / expense / moment / etc. capture flows).
- `presentation/widgets/capture_widgets.dart` — shared `CaptureTopBar` / `PillButton` /
  `SelectChip` used by the per-feature capture pages.
- `presentation/import/` — **the shared plan-import flow**, used by both the workout and
  diet importers so they can't drift on file types, error copy, or the analyse/reject
  screens:
  - `plan_import_file.dart` — `pickImportFile`, `kMaxImportFileBytes`,
    `kImportAllowedExtensions`, `importErrorMessage` (the one differing clause is a param).
  - `import_flow_states.dart` — the select/analyze/reject/error phase widgets +
    `importProgressLine`. (Each importer keeps its own state machine; the workout preview/
    done screens stay in `workout_import_page.dart`.)
  - `plan_describe_page.dart` — the shared **say-it / type-it** screen (record → transcribe
    → edit → extract); `DietDictatePage` and `WorkoutDescribePage` are thin wrappers over
    it. `keyPrefix` lets each host keep its own stable test keys.
  - `add_plan_route_tile.dart` — one row for the "Add a plan" sheets (`showAddDietSheet`,
    `showAddWorkoutSheet`).

## Gotchas

- Feature capture pages (e.g. `expenses/.../expense_capture_page.dart`,
  `workout/.../workout_capture_page.dart`) should **reuse** these shared widgets rather than
  rolling their own — it's what keeps capture consistent.
- A **new plan-import flow** (another importer, another capture route) reuses
  `presentation/import/` rather than copying a page — that shared module exists precisely
  because the workout and diet importers had drifted as copy-paste twins.
