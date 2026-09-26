/**
 * PREFETCH — the read a confidently-routed turn is all but certain to make
 * first, run by the server BEFORE the first model call, so the model finds it
 * already done instead of spending a whole step asking for it.
 *
 * Why. A fresh diet question ("how much protein do I have left?") always
 * opened with the same round trip: step 1 re-read the cached prefix only to
 * emit a diet read, then step 2 answered. The aiUsage v7 turns bear it out —
 * every DIET turn with nothing carried over opened with get_today/get_diet,
 * while TRAINING turns opened with a different read each time (analysis,
 * schedule, readiness), so they're not guessed at. Running the one certain
 * read up front saves that step's latency and its prefix re-read; a wrong
 * guess costs only the result's input tokens, never a wrong answer.
 *
 * The result goes into the turn's CONTEXT LEDGER (`context_ledger.js`) as if
 * the model had called it: the same EARLIER RESULTS block, the same fencing,
 * the same validator seeding, and it's carried to the next turn like any
 * other lookup.
 *
 * Only a CONFIDENT signal prefetches:
 *   - DIET from the message's own words, the entry point, or continuity →
 *     `get_diet` for today. Not `get_today`: that one lists items only for
 *     meals already eaten, so a swap or "mark my lunch" question would still
 *     need `get_diet` after it; `get_diet` carries the same targets,
 *     remaining and findings plus every meal's items and ids. Skipped when
 *     the message names another day (then the model wants `get_diet(day)` /
 *     `get_diet_history`, and today's state would be wasted input).
 *   - The readiness entry point (the Readiness page's "Ask about it") →
 *     `get_readiness` (~100 chars; it's what that screen is).
 * Never when the ledger already holds the answer, never for a tapped option
 * (bound choices run no model), and never for AMBIGUOUS or GENERAL.
 *
 * Pure: no I/O. `turn.js` runs the tool.
 */

const {Intent} = require("./intent");

/**
 * Whether a ledger entry already answers "what's today's diet state": a
 * get_today, or a get_diet for today (no `day` — a past day's read doesn't).
 * @param {{tool: string, input: string}} e
 * @return {boolean}
 */
function isTodaysDietState(e) {
  return e.tool === "get_today" || (e.tool === "get_diet" && e.input === "{}");
}

// A message about another day, or a span of days — today's snapshot isn't
// what it needs. English/Arabizi as whole words; Arabic as substrings (the
// clitics make whole-word matching unreliable, and these don't occur inside
// unrelated words).
const OTHER_DAY_EN = new RegExp("\\b(yesterday|last|week|weeks|weekly|" +
  "month|history|ago|monday|tuesday|wednesday|thursday|friday|saturday|" +
  "sunday|embare7|embareh|mbare7|imbarih)\\b");
const OTHER_DAY_AR =
  /امبارح|إمبارح|أمس|الاسبوع|الأسبوع|اسبوع|أسبوع|الشهر/;

/**
 * Whether the message asks about a day other than today.
 * @param {string} text
 * @return {boolean}
 */
function namesOtherDay(text) {
  const s = String(text || "").toLowerCase();
  return OTHER_DAY_EN.test(s) || OTHER_DAY_AR.test(s);
}

/**
 * The read to run before the first model call, or null.
 * @param {!Object} args
 * @param {{intent: string, reason: string}} args.routed `classifyIntent`'s
 *   answer for this turn.
 * @param {?string=} args.entryPoint Untrusted — the screen Ask was opened from.
 * @param {string} args.message The user's words.
 * @param {!Object} args.ledger The turn's `ContextLedger` (after
 *   `retainTools`), to skip a read it already carries.
 * @return {?{tool: string, input: !Object}}
 */
function prefetchFor({routed, entryPoint, message, ledger}) {
  if (!routed || routed.reason === "bound_choice") return null;
  const entry = typeof entryPoint === "string" ?
    entryPoint.trim().toLowerCase() : "";
  if (routed.intent === Intent.TRAINING && entry === "readiness") {
    return ledger.entries.some((e) => e.tool === "get_readiness") ? null :
      {tool: "get_readiness", input: {}};
  }

  if (routed.intent === Intent.DIET) {
    if (ledger.entries.some(isTodaysDietState) || namesOtherDay(message)) {
      return null;
    }
    return {tool: "get_diet", input: {}};
  }
  return null;
}

module.exports = {prefetchFor, namesOtherDay};
