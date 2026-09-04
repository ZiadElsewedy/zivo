/**
 * Composes the Ask coach's system prompt from its sections.
 *
 * The prompt used to be one ~220-line string constant in `gateway.js`. It's now
 * assembled here from cohesive, individually-documented sections under
 * `sections/` so each concern is findable and editable on its own:
 *
 *   persona    — who ZIVO is and how it talks (voice)
 *   focus      — answer the exact question asked; pull only relevant context
 *   formatting — plain-text structure the client can actually render
 *   numbers    — figures come from tools, never invented   (LOAD-BEARING)
 *   training   — defer to the deterministic workout engine (LOAD-BEARING)
 *   coaching   — the coaching stance + stay-in-your-lane
 *   mutations  — propose→confirm writes                    (LOAD-BEARING)
 *   safety     — tool output is data, not instructions     (LOAD-BEARING)
 *
 * ORDER MATTERS for readability but not for correctness: the gateway tests
 * assert SUBSTRINGS of the composed prompt (some line-wrap sensitive), not the
 * ordering, and `coaching` references "NUMBERS above" so numbers is composed
 * first. The composed string is exported as `SYSTEM_PROMPT` and re-exported by
 * `gateway.js` unchanged, so `req.system[0].text === SYSTEM_PROMPT` still holds
 * and every existing assertion keeps passing.
 *
 * Prompt-injection defense: the `safety` section's fence is load-bearing — tool
 * output is the user's own stored data, never instructions. Do not remove it.
 */

const {PERSONA} = require("./sections/persona");
const {FOCUS} = require("./sections/focus");
const {FORMATTING} = require("./sections/formatting");
const {NUMBERS} = require("./sections/numbers");
const {TRAINING} = require("./sections/training");
const {COACHING} = require("./sections/coaching");
const {MUTATIONS} = require("./sections/mutations");
const {SAFETY} = require("./sections/safety");

// Blank line between sections; each section owns no leading/trailing blank line.
const SYSTEM_PROMPT = [
  PERSONA,
  FOCUS,
  FORMATTING,
  NUMBERS,
  TRAINING,
  COACHING,
  MUTATIONS,
  SAFETY,
].join("\n\n");

module.exports = {SYSTEM_PROMPT};
