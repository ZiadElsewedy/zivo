# Diet onboarding — the phased plan

> **What this is:** the implementation plan for the two questions Diet couldn't answer —
> *"what is my current diet doing to me?"* and *"build me one"* — plus the multi-source
> capture and multi-plan library they need. The **decisions** behind it are
> [ADR-007](DECISIONS/ADR-007-diet-onboarding-body-data-and-generation.md); the rules this
> must not break are in [`lib/features/diet/FEATURE.md`](../lib/features/diet/FEATURE.md)
> and [`DIET_COACH_AUDIT.md`](DIET_COACH_AUDIT.md). Current status lives in
> [`STATE.md`](STATE.md), not here.

## The flow being built

```
Diet ─┬─ "I already have a plan"  → capture (PDF · photo · dictate · type)
      │                           → review + edit → save
      │                           → BODY DATA  → VERDICT: "this is ~+380 kcal/day
      │                                          over your maintenance → gaining
      │                                          ~0.35 kg/week"
      │                           → one tap: adopt a target
      │
      └─ "Build me one"           → BODY DATA + goal
                                  → preferences (meals/day · foods you like ·
                                     foods you won't eat · allergies · cuisine)
                                  → generate (AI picks foods, the catalog prices them,
                                     a scaler fits them to the target)
                                  → same review + edit → save
```

Both branches converge on the same review editor and the same saved `DietPlan`. The verdict
runs on **any** plan, generated or imported, because it is arithmetic over the plan.

## The data ZIVO actually needs

Decided deliberately — every field below has to earn its place, because each one is another
question between the user and a working plan.

**Required for a verdict** (there is no honest answer without these):

| Field | Why it is required | Where it comes from |
|---|---|---|
| Weight | The dominant BMR term, and the thing the projection is about | the workout **weigh-in log** (existing) |
| Height | BMR term | asked once, stored in `BodyProfile` |
| Age | BMR term | derived from `UserProfile.dateOfBirth` — never asked again |
| Sex | Mifflin-St Jeor has two forms (≈166 kcal apart) | asked once, stored |
| Activity level | The multiplier from BMR to maintenance; the single largest source of error | asked once, stored |

**Optional, and better when given:**

- **Known maintenance / TDEE.** If the user already knows their maintenance figure (a lab
  test, a coach, or their own tracking), it *replaces* the equation — a measurement of this
  person beats a population estimate of people like them. Stored on `BodyProfile`, and the
  verdict says which of the two it used.
- **Goal** (fat loss · maintain · muscle gain · recomp). Required for a *target*, not for a
  verdict: "this plan makes you gain" is true regardless of what you wanted.

**Additionally required to generate a plan:** meals per day · foods the user likes · foods
they won't eat · allergies (a safety input, not a preference) · cuisine/region. Optional:
cooking effort, budget, training-day vs rest-day split.

**Deliberately not collected:** body-fat %, measurements, medical conditions. The first two
don't change any number here; the third is clinical territory ZIVO stays out of.

---

## Phases

Each phase is shippable on its own and gated by `make gates` (`flutter analyze && flutter
test`) plus its own tests. Phases are ordered so the owner sees the verdict — the thing that
was actually missing — before the generator is built.

### Phase A — Body data + the verdict *(no AI, no backend)*

The whole point of the epic, and it needs no model call.

- `domain/body_profile.dart` — `BodyProfile` (height · sex · activity · optional stated
  maintenance). No weight, no age: see ADR-007.
- `domain/body_measures.dart` — `BodyMeasures` + `resolveBodyMeasures(...)`: assembles the
  profile, the latest weigh-in and the date of birth into the equation inputs, or reports
  exactly **which** pieces are missing (`MissingBodyData`) so the UI can ask for those and
  nothing else.
- `domain/analysis/plan_verdict.dart` — pure `analysePlan(...)` → `PlanVerdict`
  (plan kcal/day · maintenance + its source · delta · direction with a ±100 kcal deadband ·
  projected kg/week · protein g/kg · `estimated` · days it could not count).
- `DietRepository.watchBodyProfile` / `saveBodyProfile` / `clearBodyProfile`, both impls,
  `users/{uid}/bodyProfile/current` + a `firestore.rules` block + a rules test.
- UI: a **body data** screen (`body_profile_page.dart`); a **verdict card** on Diet, with
  the missing-data prompt in its place when body data is short; the target calculator now
  prefills height/sex/activity from the stored profile instead of asking again.
- Tests: `test/diet/plan_verdict_test.dart` (the arithmetic, the deadband, the honesty
  flags) and `test/diet/plan_verdict_card_test.dart` (the card's states + the body data
  screen). Plain Dart tests, not shared vectors — vectors exist to pin two implementations
  against each other, and the server mirror of the verdict arrives in Phase E; the vectors
  land with it.

  **Deferred to Phase B:** the "No daily target set" card's one-tap answers. Adopting the
  plan's own total still needs a goal from the user, so it is a small sheet rather than a
  tap, and it belongs next to the plan library work.

### Phase B — A library of plans

- `DietRepository`: `plans` / `watchPlans` / `setActivePlan` / `archivePlan`; `activePlan`
  derived from `status`. **The "exactly one active" invariant lives in the repository**, in
  a batched write — not in the rules, which cannot read sibling documents to check it, and
  not in callers, who would each have to remember. The rules pin each document's shape and
  its status vocabulary; a rules test covers the library shape.
- `diet_plans_page.dart` — every plan with its source, its daily figure, its verdict and
  its status, with follow / stop following / delete. **Archiving is offered first**: the
  consumption log still refers to a plan's meal ids, and "I stopped following this" is not
  "this never happened".
- The Diet screen's empty state distinguishes *no plans* from *nothing being followed*, and
  offers the way back into the library. Header gains the library button, reachable even
  with no active plan — the case where it matters most.
- The deferred Phase A piece landed here: the "No daily target set" card offers **the
  plan's own daily figure** as a target (`TargetSource.planDerived`, previously an unused
  affordance). It's a sheet, not one tap, because a target is a goal *plus* numbers and only
  the user knows the goal.
- `planDailyEnergy(plan)` in `plan_verdict.dart` is now the **one basis** for every "this
  plan is N kcal a day" figure — the verdict, the library card and the adopt sheet all call
  it, so they cannot disagree.
- `BodyMeasuresBuilder` — the one place a screen assembles body data from its three
  repositories; the Diet screen and the library both use it.
- Migration: an existing single plan is already `active` — no data migration needed.
- Tests: `test/diet/diet_plans_library_test.dart` (invariant + library screen + adoption),
  new cases in `firestore_diet_repository_test.dart`, and the rules suite.

### Phase C — Capture from anywhere

- One **"Add a diet"** sheet: PDF · Photo · **Dictate** · Type it out. (Photo already works
  end-to-end; only the entry point calls itself "PDF".)
- Dictation: the Ask feature's recorder + transcription → transcript → the same extractor,
  via a `text` input on `aiImportDietPlan`.
- `functions/ai/diet_import.js` accepts `text` alongside `fileBytes` (one schema, one
  review UI). **Owner action: deploy.**

### Phase D — Generation

- `domain/plan_preferences.dart` + a preferences wizard (meals/day, likes, won't-eats,
  allergies, cuisine).
- `functions/ai/diet_generate.js` (`aiGenerateDietPlan`): model proposes foods/portions →
  **`functions/nutrition/resolve.js` prices them** → deterministic scaler fits the day to
  the target → unresolved items keep an estimate and are marked. Unit tests offline, same
  as its `diet_import.js` sibling. **Owner action: deploy.**
- Output opens in the existing review editor; nothing is saved unreviewed.

### Phase E — The coach knows all of it

- `PlanVerdict` + `BodyProfile` into `DietState` (and its `functions/diet/state.js` mirror
  + shared vectors), so Today's glance and the coach read the same verdict the screen does.
- A coaching rule for **plan vs goal disagreement** ("your plan runs ~380 over maintenance
  and your goal is fat loss").
- **Calibration** (the real prize): with ≥2 weigh-ins over ≥2 weeks and a food log, observed
  weight change is a *measurement* of maintenance. When reality and the equation disagree,
  reality wins and the verdict says so.
