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
- `presentation/widgets/todays_read_card.dart` — **Today's read**: the coaching
  engine's findings on the screen, each openable to the state fields it rests on.
- `grocery_list_page.dart` — generated grocery list (`domain/grocery_list.dart`).
- `body_profile_page.dart` — the body data behind every energy figure (height · sex ·
  activity · optional known maintenance; weight goes to the weigh-in log).
- `diet_plans_page.dart` — the **library**: every plan, its verdict, and which one is being
  followed.

## Repository (`AppScope.diet`)

- **`DietRepository`** (`domain/diet_repository.dart`) — `firestore_diet_repository.dart`
  (real) / `in_memory_diet_repository.dart` (offline). Plans API: `plans` / `watchPlans` /
  `savePlan` / `setActivePlan` / `archivePlan` / `deletePlan`, with `activePlan` derived
  from status. **"Exactly one plan is active" is the repository's invariant** — `savePlan`
  of an active plan and `setActivePlan` both archive the previous active in the same
  batched write. It is not expressible in `firestore.rules` (which cannot read sibling
  documents) and must not be left to callers. Consumption API:
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
prompt** — the model phrases findings, it doesn't decide them. `coaching/evidence.dart`
(`evidenceFor`) resolves a finding's `evidence` paths back into what the state says right
now (`remaining.proteinG` → "Protein left — 100 g") — it only *reads*, and drops a path it
doesn't recognise rather than rendering a blank. `TodaysReadCard` renders both: the same
findings the coach is handed, each with a **Why**. That identity is deliberate — a screen
that interprets the numbers independently is how a screen and a coach end up recommending
different things from identical data — and it means the coaching still works with no model
call at all.

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
vectors in `test/fixtures/nutrition_vectors.json`. The **AI coach** reaches the same
data through `functions/nutrition/resolve.js` (the server mirror of
`CompositeFoodResolver`) behind the `resolve_food` / `calculate_meal_nutrition` read tools
and the `log_food` write tool — so "I ate two eggs and 100g of rice" in chat resolves,
prices and logs through the identical rules the screen uses, never a model guess.

**Does a stated figure agree with itself?** `domain/nutrition/plausibility.dart`
(`crossCheckItem`, `nutritionCrossCheckNote`) measures a plan item's stated calories
against its own macros on the 4/4/9 Atwater factors — no catalog, no network. Absent
macros are a **floor**, not zero, so a too-low figure is reported even on partial macros
and a too-high one only when all three are present. Tolerance is wide on purpose
(max 30 kcal / 20%): a flag the user learns to ignore is worse than none. Surfaced in the
plan editor — the review gate a PDF import lands in — and it never blocks Save. Nothing is
stored; the verdict is derivable from the item.

**What a plan does to you (`domain/analysis/plan_verdict.dart`):** `analysePlan(plan,
measures)` → `PlanVerdict` — the plan's average daily calories (supplements excluded)
against maintenance, as a direction, a kcal/day delta and a projected kg/week. **Pure and
deterministic, like `coaching/rules.dart` and for the same reason** — the model phrases
findings, it doesn't decide them. Two honesty properties are load-bearing: a **±100 kcal
deadband** (`kEnergyDeadbandKcal`) below which the answer is "holding", because a
population BMR equation cannot resolve finer than that; and `estimated`, inherited from the
plan's items, so a verdict built on AI-estimated calories prints with the same "~". Returns
**null** when the plan carries no calorie figures — nothing to measure is not a weak answer.

**Body data (`domain/body_profile.dart` + `body_measures.dart`):** `BodyProfile` (height ·
sex · activity · optional `statedMaintenanceKcal`) at `bodyProfile/current`. It deliberately
holds **no weight** — that lives in the workout feature's `BodyWeightRepository`, the log the
user actually keeps — and **no age**, which is derived from `UserProfile.dateOfBirth`.
`resolveBodyMeasures` assembles those three sources into `BodyMeasures` (the complete
equation inputs, no nullable terms) or returns exactly which pieces are `MissingBodyData`, so
the UI asks for those and only those. A stated maintenance figure **replaces** the estimate
rather than blending with it, and `MaintenanceSource` records which was used. Storing body
data still implies **no target** — see the rule below, which is unchanged. Decisions:
[ADR-007](../../../docs/DECISIONS/ADR-007-diet-onboarding-body-data-and-generation.md);
the epic's remaining phases: [`docs/DIET_ONBOARDING_PLAN.md`](../../../docs/DIET_ONBOARDING_PLAN.md).

**Targets (the objective):** `diet_goal.dart` (`DietGoal`) + `nutrition_targets.dart`
(`NutritionTargets`, `TargetSource`, `TargetBasis`, `kMinimumSafeCalories`) +
`target_calculator.dart` (Mifflin-St Jeor, pure). Today measured against the objective is
`DietState` — there is no separate progress type. Set at
`presentation/pages/diet_targets_page.dart`; stored at `dietTargets/current`.
`targetSourceLabel` / `targetBasisSummary` are how a target explains itself on screen.

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
  the model fills them. (The catalog above is for *logging* food; an imported plan's own
  figures were never run through it.) `FoodItem.estimated` marks those values, and it is
  load-bearing, not decorative: `anyEstimated`/`mealEstimated`/
  `dayEstimated` in `domain/diet_format.dart` aggregate it, `dietDaySummary` returns
  `kcalLeftEstimated` alongside the number, and every surface that prints a total prefixes
  `approx(...)` ("~"). If you add a screen that shows a calorie figure, mark it too.
- **Build a new diet surface from one `DietState`, built once and passed down.** The page
  builds it per frame and hands the same object to the hero and to Today's read; a widget
  that builds its own is how two parts of one screen start disagreeing about one day. And
  a surface that prints a consumed figure must print its `ConsumedBasis` with it — the
  coach is forbidden to say "you ate" about ticked plan meals, and the screen saying it
  silently is the same claim in a louder place. Degrade to what IS known rather than to
  nothing: a day with no plan day still has an objective and a log, so the hero, target row
  and read render without one — only Meals/Supplements end with the plan day.
- The full picture of what is and isn't trustworthy here — and the plan that got it there —
  is [`docs/DIET_COACH_AUDIT.md`](../../../docs/DIET_COACH_AUDIT.md). **Phases 0–8 have all
  landed** (dates + labelling, goal/targets, the USDA catalog + resolver, the food log,
  `DietState` + shared vectors, the rules engine, the AI's state/resolver tools, the advice
  validator, and the UI above). What is *not* solved is food-catalog **coverage** — see the
  `FoodNotFound` note above; the answer to a miss is still to ask or to offer a custom
  food, never to let a model estimate through.
- A change to the import extractor is a `functions` deploy (owner's creds — see
  [`docs/STATE.md`](../../../docs/STATE.md)).
