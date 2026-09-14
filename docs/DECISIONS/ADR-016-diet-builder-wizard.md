# ADR-016 — The Diet Builder: one guided, number-free wizard

**Status:** accepted · **Date:** 2026-09-14 · **Supersedes nothing; extends
[ADR-007](ADR-007-diet-onboarding-body-data-and-generation.md).**

## Context

"Build me a plan" already had every part it needed — a deterministic target
(`calculateTargets`), a generator that picks foods the catalog prices and a
scaler fits (`functions/ai/diet_generate.js` + `plan_fitting.js`), body-data
assembly (`resolveBodyMeasures`), and the review-and-save editor. But the parts
were scattered across separate screens reached from the "Add a diet" sheet:
a chip-based preferences page, a body-data page, a goal/targets page. A user
with no plan had to assemble the flow themselves, and every screen showed its
working — calories, macros, activity multipliers — which is the opposite of
what the feature is for.

The owner's brief was a single linear flow that asks *what you're trying to do
and how you live*, and does the arithmetic behind the scenes:

> Goal → About you → How you eat → What you avoid → How many meals → Build →
> the finished plan. No calories, no protein grams, no BMR, no TDEE. The user
> shouldn't have to know any of that.

## Decision

A new `DietBuilderPage` (a stepped `PageView` driven by a
`DietBuilderController`, per [ADR-008](ADR-008-presentation-controllers.md)) is
the primary "build me one" entry. It **only gathers**; the existing engine does
everything after Build. Three choices are worth recording because they set, or
deliberately reverse, earlier positions:

1. **Free text + voice over chips, for how-you-eat / dislikes / allergies.**
   The old preferences page argued that chips give the generator a stronger,
   cleaner steer than prose ("a generator with no steer produces the same
   chicken-and-broccoli plan"). The wizard reverses that for the intake: a
   large text field with a 🎙 voice option (the `PlanDescribePage` machinery,
   extracted into an inline `VoiceCaptureField`) lets people describe their real
   eating in their own words, which is a *richer* steer than a fixed list, not
   a weaker one. The trade-off is parsing: dislikes/allergies prose is split
   into tokens (`splitNaturalFoodList`) and how-you-eat/schedule are folded into
   the generator's existing free-text `notes`. **Allergen chips are kept** under
   the free-text allergies field as an optional quick-add, because the server's
   allergen gate is a deterministic stem match and clean tokens make it safer —
   an allergy is a safety limit, not a preference, and that half stays belt-and
   -braces.

2. **Numbers stay hidden until the reveal, and the target is computed but not
   saved.** The wizard computes the target on-device from goal + body data,
   sizes the generation to it, and shows it — kcal and macros — only on the
   finished plan, where it's useful context rather than a hurdle. This honors
   ADR-007's rule that **ZIVO never invents a target the user didn't approve**:
   the number is silent during intake, and *Save on the reveal is the approval*.
   `DietImportPage` gained a `targetOverride` so generation can be sized to a
   target that isn't in the repository yet.

3. **Nothing is persisted before the reveal's Save.** Body data, the target and
   the plan are written together, in one commit, only when the user saves the
   finished plan — matching the brief's "nothing should be saved before the user
   reviews it". The reveal's Edit route opens the existing editor with
   `autosave: false`, so it returns an edited plan without writing it, keeping
   Save the single commit point.

The chip-based `DietPreferencesPage` and the manual `DietTargetsPage` are
retained (the latter is still where a target is edited by hand); the wizard
supersedes the former as the generate intake but it is left in place, still
tested, rather than deleted in the same change.

## Consequences

- **No backend deploy is required.** Folding the free-text answers into the
  generator's existing `notes` field means `diet_generate.js` reads them today,
  unchanged. `PlanPreferences` gained `eatingHabits`/`scheduleNotes` for clarity
  at the call site; `toPayload()` composes them into `notes`.
- **Age.** The wizard computes the target from the age it collects (prefilled
  from the account's date of birth when known, and shown read-only-ish with a
  note then). It does not write date of birth back — that stays owned by the
  profile/auth module.
- **The safety floor is surfaced, never clamped**, on the reveal — the same
  deterministic warning the Targets page uses.
- The engine (`calculateTargets`, the generator, the review editor, the coaching
  and verdict layers) is untouched; this is intake and presentation only.
