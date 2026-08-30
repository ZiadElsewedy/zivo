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
  `watchConsumed` / `setMealEaten`, plus `dietDaySummary`. Targets API:
  `currentTargets` / `watchTargets` / `saveTargets` / `clearTargets`.

## Domain model (`domain/`)

`diet_plan.dart` → `diet_day.dart` → `meal.dart` → `food_item.dart` (calories + macros).
Ledger: `diet_entry.dart`, `diet_summary.dart`. Import: `diet_import_result.dart`,
`diet_plan_from_import.dart`, `diet_source.dart` (`DietSource.pdf`), `diet_plan_status.dart`.

**The coaching engine (what the coach decides to say):** `domain/coaching/finding.dart`
(`CoachingFinding` — kind · severity · deterministic text · the state fields it rests on)
and `coaching/rules.dart` (`coachingFindings`). Pure: `DietState` in, at most three ranked
findings out. Mirrored in `functions/diet/rules.js`, pinned by
`test/fixtures/coaching_vectors.json` (both suites). **Add coaching logic here, not to the
prompt** — the model phrases findings, it doesn't decide them.

**`DietState` — the one structured picture, and the thing to reach for first:**
`domain/diet_state.dart` + `diet_state_builder.dart`. Goal · targets · consumed (with its
`ConsumedBasis`) · remaining · meals · history · `DietQuality` flags. The Diet screen
renders it, Today's glance renders it, and the coach is handed it — mirrored in
`functions/diet/state.js` and pinned by `test/fixtures/diet_state_vectors.json`, which
**both** suites run. Build new diet surfaces from this, not from raw plan/log reads.

**The food log (what was actually eaten):** `domain/nutrition/food_log_entry.dart`
(`FoodLogEntry`, `FoodLogOrigin`, `totalsOf`), `planned_meal_log.dart`
(`entriesForPlannedMeal` — ticking a meal materialises its items into the log),
`custom_food.dart` + `composite_food_resolver.dart` (the user's own foods, layered over
USDA). Stored at `foodLogs/` and `customFoods/`. UI:
`presentation/widgets/log_food_sheet.dart`.

**Nutrition data (the source of truth for what a food is worth):**
`domain/nutrition/food_reference.dart` (`FoodReference`, `NutritionSource`,
`FoodPreparation`, `FoodPortion`), `resolved_food.dart` (`FoodMatch` — the sealed
`FoodResolved` / `FoodAmbiguous` / `FoodNotFound`), `food_resolver.dart` (the seam),
`nutrition_calculator.dart` (`nutritionFor` — the **only** place a food + an amount
becomes calories). Implementation: `data/bundled_food_database.dart` over
[`assets/nutrition/foods.json`](../../../assets/nutrition/README.md), a USDA subset.
Mirrored server-side in `functions/nutrition/food_db.js`; both run the shared golden
vectors in `test/fixtures/nutrition_vectors.json`.

**Targets (the objective):** `diet_goal.dart` (`DietGoal`) + `nutrition_targets.dart`
(`NutritionTargets`, `TargetSource`, `TargetBasis`, `kMinimumSafeCalories`) +
`target_calculator.dart` (Mifflin-St Jeor, pure) + `target_progress.dart`
(`buildTargetProgress` — today measured against the objective). Set at
`presentation/pages/diet_targets_page.dart`; stored at `dietTargets/current`.

## Gotchas

- The problem space here is **presentation**, not the model — the entities already carry
  calories/macros; build on them rather than reshaping the model.
- Diet import mirrors the Workout PDF import pipeline (extractor in `functions/ai/`, review
  UI on device) — keep them parallel.
- **Consumption is the log, not the plan.** `buildDietState` sums `foodLogs` when
  the day has any, and falls back to the planned figures of ticked meals only when it
  doesn't — reporting which through `ConsumedBasis` (`logged` / `tickedPlanMeals` /
  `nothingLogged`). Ticking a
  meal writes both `dietEntries` (unchanged, still the tick state) **and** one `foodLogs`
  entry per item, tagged `origin: plannedMeal` and `source: dietPlan`. Removing one item
  of a ticked meal leaves it ticked — that is what a half-eaten meal looks like; removing
  the last one un-ticks it.
- **A calorie figure enters ZIVO through `FoodResolver` or not at all.** The catalog is
  a build artifact from USDA FoodData Central; every row carries its real `fdcId`, and
  nothing in it was hand-written. `FoodNotFound` and `FoodAmbiguous` are **normal
  outcomes, not errors** — USDA covers regional cooking poorly, and raw vs cooked is a
  ~3× fork (raw rice 365 kcal/100g, cooked 130). The right response is to ask or to
  offer a custom food, never to substitute something close. Volumes are refused unless
  the source recorded that measure for that exact food: ZIVO does not assume densities.
- **ZIVO never invents a target.** `NutritionTargets` is null until the user sets one,
  and null is a real state every caller handles: the Diet hero falls back to counting down
  the day's plan and labels itself `KCAL LEFT OF PLAN`, Today's glance says "of plan", and
  the coach is told `targets: null` and instructed to say so. Do **not** add a default, and
  do **not** auto-derive one from body weight on first run — an unrequested number the user
  never approved is the same trust failure as an invented calorie, wearing a formula.
  `TargetSource` records where each target came from; editing a calculated figure by hand
  demotes it to `manual` and drops the basis, because the stored explanation would
  otherwise be a lie.
- **Every calorie in an imported plan was generated by the model**, not looked up —
  `functions/ai/diet_import.js` makes calories/macros required schema fields precisely so
  the model fills them. There is **no nutrition database** in ZIVO yet. `FoodItem.estimated`
  marks those values, and it is load-bearing, not decorative: `anyEstimated`/`mealEstimated`/
  `dayEstimated` in `domain/diet_format.dart` aggregate it, `dietDaySummary` returns
  `kcalLeftEstimated` alongside the number, and every surface that prints a total prefixes
  `approx(...)` ("~"). If you add a screen that shows a calorie figure, mark it too.
- The full picture of what is and isn't trustworthy here — and the phased plan to fix it —
  is [`docs/DIET_COACH_AUDIT.md`](../../../docs/DIET_COACH_AUDIT.md). Phase 0 (labelling,
  dates, verified meal ids) has landed; Phases 1+ (goal/targets, a food database, a real
  food log, a validator) have not.
- A change to the import extractor is a `functions` deploy (owner's creds — see
  [`docs/STATE.md`](../../../docs/STATE.md)).
