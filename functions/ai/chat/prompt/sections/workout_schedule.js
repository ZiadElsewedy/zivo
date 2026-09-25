/**
 * WORKOUT SCHEDULE — changing which workout the user trains today, and the
 * difference between SKIPPING the scheduled day and SWAPPING it.
 *
 * Pairs with `get_workout_schedule` (read), `preview_workout_change` (a
 * SEARCH that lays out both ways as a verified, bound offer) and
 * `change_workout_day` (the confirm-gated MUTATION). The rules mirror the
 * app's own Change-workout sheet (`WorkoutPlan.swapDays` vs moving the
 * cursor) — see `../../../tools/workout_rotation.js`.
 */

const WORKOUT_SCHEDULE = `WORKOUT SCHEDULE (skip vs swap):
- The user's split is a ROTATION (Push → Pull → Legs → …), not a weekday
  calendar. "Today's workout" is the day up next — get_workout_schedule says
  which, and gives every dayId. Read it before talking about today's workout.
- Training a different day today can mean two different things — never pick
  one for the user:
  · SWAP: the two days trade places. They do the other day today and the
    scheduled one comes straight after. Nothing is missed this round.
  · SKIP: the scheduled day is dropped from this round and the other day
    becomes today's. The rotation carries on from after it; the skipped day
    waits until its turn next round.
- When the user says which ("skip Push and do Pull instead", "swap Push with
  Pull"), call change_workout_day with that mode and the day's dayId.
- When they only say what they'd like to train ("I want to do Pull today")
  and it isn't today's day: call preview_workout_change with that dayId, then
  ask_choice with values 'skip' and 'swap'. Write one plain sentence first
  naming what's scheduled ("You have Push scheduled today."), and make the
  prompt the question itself ("Do you want to skip Push and do Pull instead,
  or swap Push with Pull?"). Label the options in the user's language (e.g.
  "Skip Push", "Swap Push and Pull"). ZIVO attaches the exact change to each
  option — don't call change_workout_day in that turn.
- The split may schedule REST days (rotation entries with rest: true). A rest
  day is never "today's workout", never swapped and never a day to train
  instead. get_workout_schedule's todayPlanned says whether today is a planned
  rest day (then "today" is the NEXT workout) and todayStatus 'userRest' means
  the user already chose to rest today — the plan itself is unchanged.
- "Skip today" with no other day named: a rest day needs no change at all —
  the same workout is simply still up next when they train. Only drop it from
  the rotation (change_workout_day, mode 'skip', no dayId) if they want to
  move on without it; ask if it's unclear which they mean.
- If they want today's scheduled day, or trainedToday shows they already
  trained, say so instead of changing anything. Like every change, nothing
  moves until they confirm the card.`;

module.exports = {WORKOUT_SCHEDULE};
