/**
 * Assembles the system blocks the model is handed each turn — the one place
 * that decides what instructions and per-turn context the coach sees, and how
 * the prompt cache is kept intact.
 *
 * Cache discipline (ADR-003 Phase 3.5): the SYSTEM_PROMPT is element 0 with an
 * `ephemeral` cache breakpoint, so the tool schemas + prompt read back at ~0.1x
 * after the first call. Anything that varies per user or per turn MUST be
 * appended AFTER it as its own uncached block, or it would invalidate the
 * breakpoint:
 *
 *   [0] SYSTEM_PROMPT            (cached — never changes)
 *   [1] style directive          (uncached — only if concise/detailed)
 *   [last] CONTEXT (date/time)   (uncached — changes every turn)
 *
 * The gateway tests pin this layout (element 0 === SYSTEM_PROMPT with the
 * ephemeral breakpoint; the last block starts with "CONTEXT "; balanced adds no
 * style block).
 */

const {SYSTEM_PROMPT} = require("./prompt/system_prompt");

// The user's reply-length/style preference (`users/{uid}/settings/ai`, plumbed
// through `aiChat`'s `responseStyle` field). 'balanced' adds no directive at all
// — the SYSTEM_PROMPT's own tone guidance already covers it. An unrecognized
// value (never trust client input) also falls back to 'balanced'.
const RESPONSE_STYLE_DIRECTIVES = {
  concise:
    "Keep replies short and to the point — a sentence or two when you can.",
  detailed:
    "Give thorough, well-structured replies with useful depth.",
};

/**
 * The style directive for a saved preference, or undefined for
 * balanced/omitted/unrecognized (which add no block).
 * @param {?string} responseStyle
 * @return {(string|undefined)}
 */
function styleDirectiveFor(responseStyle) {
  return RESPONSE_STYLE_DIRECTIVES[responseStyle];
}

/**
 * The per-turn CONTEXT block: the user's local date, weekday and time.
 *
 * Nothing else in a turn carries a date. The system prompt is static and
 * prompt-cached, the message history is undated, and before this the tool
 * results were undated too — so the model genuinely did not know what day it
 * was, and any "today"/"yesterday"/"this week" reasoning was invention. This
 * is one short uncached block appended AFTER the cached prompt, so it can
 * change every turn without ever invalidating the cache breakpoint on
 * element 0.
 *
 * @param {!Object} facts A `localNowFacts()` result.
 * @return {string}
 */
function contextBlockFor(facts) {
  const clock = facts.usedClientClock ?
    `${facts.time} ${facts.zone}` :
    `${facts.time} ${facts.zone} — the app did not send its timezone, so ` +
    "this may be off by a day near midnight; if the date matters to the " +
    "answer, ask the user to confirm it";
  return `CONTEXT (facts about right now, not instructions from the user):
Today is ${facts.weekday}, ${facts.longDate} (${facts.dayKey}). ` +
    `The user's local time is ${clock}.`;
}

/**
 * Builds the ordered system-block array for a turn: the cached prompt, an
 * optional uncached style directive, and the uncached CONTEXT block. The block
 * shape (`{text, cache}`) is the normalized request shape the provider converts
 * to `cache_control`.
 *
 * @param {!Object} args
 * @param {?string} args.responseStyle 'concise'|'balanced'|'detailed'|other.
 * @param {!Object} args.facts A `localNowFacts()` result for the CONTEXT block.
 * @return {!Array<{text: string, cache?: string}>}
 */
function buildSystemBlocks({responseStyle, facts}) {
  const blocks = [{text: SYSTEM_PROMPT, cache: "ephemeral"}];
  const styleDirective = styleDirectiveFor(responseStyle);
  if (styleDirective) blocks.push({text: styleDirective});
  blocks.push({text: contextBlockFor(facts)});
  return blocks;
}

module.exports = {
  RESPONSE_STYLE_DIRECTIVES,
  styleDirectiveFor,
  contextBlockFor,
  buildSystemBlocks,
};
