# diet — feature map

> Editable meal plans + a daily "did I eat this" ledger, plus AI PDF import, a grocery
> list, and AI calorie/macro help. **Not greenfield** — the plan model + consumption
> tracking predate the premium UI/import work.

## Start here

- `presentation/pages/diet_plan_page.dart` — main diet surface (the plan + today).
- `presentation/today_diet.dart` — the Diet glance embedded in Today (calorie ring,
  macro chips, completion state).
- `diet_plan_edit_page.dart`, `meal_detail_page.dart` — edit plan / drill into a meal.
- `diet_pdf_import_page.dart` — AI PDF import → review (pairs with `functions/ai/diet_import.js`).
- `grocery_list_page.dart` — generated grocery list (`domain/grocery_list.dart`).

## Repository (`AppScope.diet`)

- **`DietRepository`** (`domain/diet_repository.dart`) — `firestore_diet_repository.dart`
  (real) / `in_memory_diet_repository.dart` (offline). Consumption API:
  `watchConsumed` / `setMealEaten`, plus `dietDaySummary`.

## Domain model (`domain/`)

`diet_plan.dart` → `diet_day.dart` → `meal.dart` → `food_item.dart` (calories + macros).
Ledger: `diet_entry.dart`, `diet_summary.dart`. Import: `diet_import_result.dart`,
`diet_plan_from_import.dart`, `diet_source.dart` (`DietSource.pdf`), `diet_plan_status.dart`.

## Gotchas

- The problem space here is **presentation**, not the model — the entities already carry
  calories/macros; build on them rather than reshaping the model.
- Diet import mirrors the Workout PDF import pipeline (extractor in `functions/ai/`, review
  UI on device) — keep them parallel.
- AI calorie/macro estimation is filled server-side and marked "approx"; a change there is
  a `functions` deploy (owner's creds — see [`docs/STATE.md`](../../../docs/STATE.md)).
