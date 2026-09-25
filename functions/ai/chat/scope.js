/**
 * What the model is handed for one INTENT (`./intent.js`): the system prompt
 * for that area and the tools that go with it — built from the same intent, so
 * a tool is never exposed without its area's rules (`prompt/system_prompt.js`
 * explains why that invariant matters).
 *
 *   GENERAL   → core prompt · core tools (ask_choice, request_input) ·
 *               load_tools
 *   TRAINING  → core + training · training tools + core · load_tools
 *   DIET      → core + diet     · diet tools + core     · load_tools
 *   MONEY     → core + money    · expense tools + core  · load_tools
 *   AMBIGUOUS → the FULL prompt · every tool — exactly what every turn got
 *               before scoping, so an unclear question loses nothing.
 *
 * `load_tools` is the way out of a wrong guess: the model calls it with the
 * area it needs and the turn continues with the WIDER scope (that area's
 * prompt + tools added, or everything for "all"). It reads nothing and changes
 * nothing, so it costs one model step, never correctness.
 *
 * Every scope is built once, at load, from the tool catalog's own order — so a
 * given intent's tool list and prompt are byte-identical on every turn (the
 * prompt cache keys on them) and a new tool can't be silently dropped: every
 * tool must name its area in `TOOL_AREAS` (a test enforces it).
 */

const crypto = require("crypto");
const {tools: readTools} = require("../tools/read");
const {mutatingTools} = require("../tools/mutations");
const {elicitationTools} = require("../tools/elicitations");
const {foodSearchTools} = require("../tools/food_search_product");
const {SYSTEM_PROMPT, systemPromptFor} = require("./prompt/system_prompt");
const {Intent, TOOL_AREAS} = require("./intent");

/** The name of the scope-widening meta tool. */
const LOAD_TOOLS = "load_tools";

/** Every executable tool, in the catalog's fixed order. */
const CATALOG = readTools.concat(mutatingTools).concat(elicitationTools)
    .concat(foodSearchTools);

/** Tools every scope carries — asking the user never depends on the area. */
const CORE_TOOL_NAMES = new Set(elicitationTools.map((t) => t.name));

const LOAD_TOOLS_TOOL = {
  name: LOAD_TOOLS,
  meta: true,
  description:
    "Load the tools for another area of the user's data when this question " +
    "needs data or a change your current tools can't reach. area: " +
    "'training' (workouts, progress, readiness, sleep, the workout " +
    "schedule), 'diet' (meals, food log, calories, food lookup), 'money' " +
    "(expenses, spending), or 'all' when it spans several. Reads nothing " +
    "itself — call it, then continue with the tools it loads.",
  inputSchema: {
    type: "object",
    properties: {
      area: {type: "string", enum: ["training", "diet", "money", "all"]},
    },
    required: ["area"],
  },
};

/**
 * @param {!Object} t A catalog tool.
 * @return {{name: string, description: string, inputSchema: !Object}}
 */
function normalized(t) {
  return {name: t.name, description: t.description, inputSchema: t.inputSchema};
}

/**
 * The catalog tools an intent exposes, in catalog order.
 * @param {string} intent
 * @return {!Array<!Object>}
 */
function catalogToolsFor(intent) {
  if (intent === Intent.AMBIGUOUS) return CATALOG.slice();
  return CATALOG.filter((t) =>
    CORE_TOOL_NAMES.has(t.name) || TOOL_AREAS[t.name] === intent);
}

/**
 * @typedef {Object} Scope
 * @property {string} intent
 * @property {string} systemPrompt Element 0 of the system blocks.
 * @property {!Array<!Object>} tools The normalized tool list sent to the model.
 * @property {!Set<string>} toolNames Names in `tools` (incl. load_tools).
 * @property {number} systemChars
 * @property {number} toolDefChars The JSON size of `tools`.
 */

/**
 * @param {string} intent
 * @param {!Array<!Object>} catalogTools
 * @param {string} systemPrompt
 * @param {boolean} withLoadTools
 * @return {!Scope}
 */
function buildScope(intent, catalogTools, systemPrompt, withLoadTools) {
  const tools = catalogTools.map(normalized);
  if (withLoadTools) tools.push(normalized(LOAD_TOOLS_TOOL));
  return {
    intent,
    systemPrompt,
    tools,
    toolNames: new Set(tools.map((t) => t.name)),
    systemChars: systemPrompt.length,
    toolDefChars: JSON.stringify(tools).length,
  };
}

const SCOPES = {};
for (const intent of Object.values(Intent)) {
  SCOPES[intent] = buildScope(intent, catalogToolsFor(intent),
      systemPromptFor(intent), intent !== Intent.AMBIGUOUS);
}

// The scope a turn widens to with load_tools('all') — every tool AND
// load_tools, because the conversation already holds a load_tools call and a
// tool the history calls must stay declared.
const EXPANDED_ALL = buildScope(Intent.AMBIGUOUS, CATALOG, SYSTEM_PROMPT, true);

/**
 * @param {string} intent
 * @return {!Scope}
 */
function scopeFor(intent) {
  return SCOPES[intent] || SCOPES[Intent.AMBIGUOUS];
}

/**
 * The scope after `load_tools(area)` from `current`: the current area plus
 * the requested one. Two different areas (or 'all') widen to everything —
 * there is no two-area prompt, and the full one is the safe superset.
 * @param {!Scope} current
 * @param {string} area 'training' | 'diet' | 'money' | 'all'
 * @return {!Scope}
 */
function widen(current, area) {
  if (current.intent === area) return current;
  if (current.intent === Intent.GENERAL &&
      [Intent.TRAINING, Intent.DIET, Intent.MONEY].includes(area)) {
    return SCOPES[area];
  }
  return EXPANDED_ALL;
}

/**
 * A short fingerprint of everything the model is instructed by — the full
 * prompt, every intent's prompt, and every tool definition — so usage records
 * can be compared before/after a prompt or tool change. Changes whenever any
 * of that text changes; stable across deploys that don't touch it.
 */
const PROMPT_VERSION = crypto.createHash("sha256")
    .update(JSON.stringify({
      prompts: Object.values(Intent).map((i) => scopeFor(i).systemPrompt),
      tools: CATALOG.map(normalized).concat([normalized(LOAD_TOOLS_TOOL)]),
      areas: TOOL_AREAS,
    }))
    .digest("hex")
    .slice(0, 12);

module.exports = {
  LOAD_TOOLS,
  LOAD_TOOLS_TOOL,
  CATALOG,
  CORE_TOOL_NAMES,
  PROMPT_VERSION,
  scopeFor,
  widen,
};
