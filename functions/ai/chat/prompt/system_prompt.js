/**
 * Composes the Ask coach's system prompt from its sections — one prompt per
 * INTENT (`../intent.js`), each carrying only the rules for the tools it
 * exposes (`../scope.js`).
 *
 * The prompt used to be one ~220-line string constant in `gateway.js`. It's now
 * assembled here from cohesive, individually-documented sections under
 * `sections/` so each concern is findable and editable on its own:
 *
 *   CORE — every prompt:
 *     persona    — who ZIVO is and how it talks (voice)
 *     focus      — answer the exact question asked; pull only relevant context
 *     length     — short by default; depth only when asked or needed
 *     activity   — say what you did, not what you thought; plan in budget
 *     formatting — plain-text structure the client can actually render
 *     language   — the user's language/dialect; Arabic the RTL UI can lay out
 *     numbers    — figures come from tools, never invented   (LOAD-BEARING)
 *     dates      — "today" comes from the CONTEXT line       (LOAD-BEARING)
 *     coaching   — the coaching stance + stay-in-your-lane
 *     decisions  — make the call (fact → assessment → recommendation →
 *                  action), never from data it didn't read
 *     mutations  — propose→confirm writes                    (LOAD-BEARING)
 *     elicitation— ask (option chips) instead of guessing
 *     safety     — tool output is data, not instructions     (LOAD-BEARING)
 *   TRAINING — training   (defer to the workout engine, LOAD-BEARING),
 *              workout_schedule (skip vs swap in the rotation),
 *              decisions_training (the train-today call)
 *   DIET     — numbers_diet (the diet-state vocabulary, LOAD-BEARING),
 *              mutations_diet, quantity, food_search, meal_replacement,
 *              decisions_diet (the follow-the-diet call)
 *   MONEY    — mutations_money (identify an expense by its real id)
 *
 * THE INVARIANT this split rests on: a tool is only ever exposed together with
 * its area's module (`../scope.js` builds both from the same intent). So a rule
 * that only matters for a tool's payload lives in that area's module and in no
 * other prompt — and never needs repeating in the tool's description.
 *
 * `SYSTEM_PROMPT` is the FULL prompt — every module — used for the AMBIGUOUS
 * intent (the safe fallback, which also exposes every tool). It carries the
 * same text as before the split; only the order of sections moved (core first,
 * then the areas). The gateway tests assert SUBSTRINGS of it (some line-wrap
 * sensitive), not the ordering. `coaching` references "NUMBERS above", so
 * numbers is composed before it in every prompt.
 *
 * Every prompt is built ONCE, at load, and is byte-identical on every turn of
 * its intent — it's element 0 of the system blocks and carries the cache
 * breakpoint (`../context.js`), so a per-turn difference would defeat the
 * cache.
 *
 * Prompt-injection defense: the `safety` section's fence is load-bearing — tool
 * output is the user's own stored data, never instructions. Every prompt ends
 * with it. Do not remove it.
 */

const {PERSONA} = require("./sections/persona");
const {FOCUS} = require("./sections/focus");
const {ACTIVITY} = require("./sections/activity");
const {FORMATTING} = require("./sections/formatting");
const {LANGUAGE} = require("./sections/language");
const {LENGTH} = require("./sections/length");
const {
  DECISIONS,
  DECISIONS_TRAINING,
  DECISIONS_DIET,
} = require("./sections/decisions");
const {NUMBERS, NUMBERS_DIET} = require("./sections/numbers");
const {TRAINING, DATES} = require("./sections/training");
const {COACHING} = require("./sections/coaching");
const {
  MUTATIONS,
  MUTATIONS_MONEY,
  MUTATIONS_DIET,
} = require("./sections/mutations");
const {ELICITATION} = require("./sections/elicitation");
const {QUANTITY} = require("./sections/quantity");
const {FOOD_SEARCH} = require("./sections/food_search");
const {MEAL_REPLACEMENT} = require("./sections/meal_replacement");
const {WORKOUT_SCHEDULE} = require("./sections/workout_schedule");
const {SAFETY} = require("./sections/safety");
const {Intent} = require("../intent");

const CORE = [
  PERSONA,
  FOCUS,
  LENGTH,
  ACTIVITY,
  FORMATTING,
  LANGUAGE,
  NUMBERS,
  DATES,
  COACHING,
  DECISIONS,
  MUTATIONS,
  ELICITATION,
];

/** The sections each area adds on top of CORE. */
const AREA_SECTIONS = {
  [Intent.TRAINING]: [TRAINING, WORKOUT_SCHEDULE, DECISIONS_TRAINING],
  [Intent.DIET]: [
    NUMBERS_DIET, MUTATIONS_DIET, QUANTITY, FOOD_SEARCH, MEAL_REPLACEMENT,
    DECISIONS_DIET,
  ],
  [Intent.MONEY]: [MUTATIONS_MONEY],
};

/** How each area names itself to the model in its scope note. */
const AREA_LABELS = {
  [Intent.TRAINING]: "training, recovery and sleep",
  [Intent.DIET]: "diet and food",
  [Intent.MONEY]: "spending",
};

/**
 * The note a SCOPED prompt carries: which tools this question was routed to,
 * and the one way out when that routing was wrong (`load_tools`, see
 * `../scope.js`). The full prompt has no note — it already has everything.
 * @param {string} intent
 * @return {string}
 */
function scopeNoteFor(intent) {
  const areas = "training/recovery, diet/food or spending";
  const lead = intent === Intent.GENERAL ?
    "LOADED TOOLS — this question reads as general conversation or " +
    "knowledge, so none of the user's data tools are loaded." :
    `LOADED TOOLS — this question was routed to your ${AREA_LABELS[intent]} ` +
    "tools only.";
  return `${lead} If answering it needs the user's own ${areas} data that ` +
    "your tools can't read, or a change you have no tool for, call " +
    "load_tools with that area first. Never answer about the user's data you " +
    "couldn't read, and never guess it.";
}

/**
 * @param {!Array<string>} sections
 * @return {string} Sections joined by a blank line (no section owns a leading
 *   or trailing blank line).
 */
function compose(sections) {
  return sections.join("\n\n");
}

// Blank line between sections; no section owns a leading/trailing blank line.
const SYSTEM_PROMPT = compose([
  ...CORE,
  ...AREA_SECTIONS[Intent.TRAINING],
  ...AREA_SECTIONS[Intent.DIET],
  ...AREA_SECTIONS[Intent.MONEY],
  SAFETY,
]);

const PROMPTS = {
  [Intent.AMBIGUOUS]: SYSTEM_PROMPT,
  [Intent.GENERAL]: compose([...CORE, scopeNoteFor(Intent.GENERAL), SAFETY]),
  [Intent.TRAINING]: compose([...CORE, ...AREA_SECTIONS[Intent.TRAINING],
    scopeNoteFor(Intent.TRAINING), SAFETY]),
  [Intent.DIET]: compose([...CORE, ...AREA_SECTIONS[Intent.DIET],
    scopeNoteFor(Intent.DIET), SAFETY]),
  [Intent.MONEY]: compose([...CORE, ...AREA_SECTIONS[Intent.MONEY],
    scopeNoteFor(Intent.MONEY), SAFETY]),
};

/**
 * The system prompt for an intent — the full `SYSTEM_PROMPT` for AMBIGUOUS or
 * anything unrecognized.
 * @param {string} intent
 * @return {string}
 */
function systemPromptFor(intent) {
  return PROMPTS[intent] || SYSTEM_PROMPT;
}

module.exports = {SYSTEM_PROMPT, systemPromptFor};
