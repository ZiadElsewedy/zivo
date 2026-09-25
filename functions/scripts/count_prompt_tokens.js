#!/usr/bin/env node
/**
 * Measures what the Ask coach's fixed prefix actually costs, per intent: the
 * system prompt, the tool definitions, each prompt section and each tool —
 * in REAL Anthropic tokens (the free `messages/count_tokens` endpoint), so
 * token figures stop being chars/4 estimates.
 *
 *   ANTHROPIC_API_KEY=… node scripts/count_prompt_tokens.js           # tokens
 *   node scripts/count_prompt_tokens.js --offline                    # chars
 *   … --json                                                          # JSON
 *
 * Counting is free and sends only ZIVO's own prompt/tool text — no user data.
 * Without a key it falls back to --offline (characters only) and says so.
 */

const {Intent} = require("../ai/chat/intent");
const {scopeFor, CATALOG, LOAD_TOOLS_TOOL, PROMPT_VERSION} =
  require("../ai/chat/scope");
const {MODELS} = require("../ai/routing/models");

const MODEL = MODELS["claude-sonnet"].id;
const args = new Set(process.argv.slice(2));
const asJson = args.has("--json");
const offline = args.has("--offline") || !process.env.ANTHROPIC_API_KEY;

/**
 * Every named prompt section, for the per-section breakdown.
 * @return {!Object<string, string>}
 */
function sections() {
  const out = {};
  for (const file of ["persona", "focus", "activity", "formatting", "numbers",
    "training", "coaching", "mutations", "elicitation", "quantity",
    "food_search", "meal_replacement", "workout_schedule", "safety"]) {
    const mod = require(`../ai/chat/prompt/sections/${file}`);
    for (const [name, text] of Object.entries(mod)) out[name] = text;
  }
  return out;
}

/**
 * @param {!Object} tool A catalog tool.
 * @return {!Object} The Anthropic tool shape.
 */
function wire(tool) {
  return {name: tool.name, description: tool.description,
    input_schema: tool.inputSchema};
}

/**
 * A token counter over the count_tokens endpoint (one probe message, so the
 * figures include that message's few tokens; deltas cancel it).
 * @return {function(!Object): !Promise<number>}
 */
function counter() {
  const Anthropic = require("@anthropic-ai/sdk");
  const client = new Anthropic({maxRetries: 2});
  return async ({system, tools}) => {
    const req = {model: MODEL,
      messages: [{role: "user", content: "x"}]};
    if (system) req.system = system;
    if (tools && tools.length) req.tools = tools;
    const res = await client.beta.messages.countTokens(req);
    return res.input_tokens;
  };
}

/**
 * Builds and prints the report.
 * @return {!Promise<void>}
 */
async function main() {
  const report = {model: MODEL, promptVersion: PROMPT_VERSION,
    mode: offline ? "chars" : "tokens", intents: {}, sections: {}, tools: {}};
  const count = offline ? null : counter();
  const base = count ? await count({}) : 0;

  for (const intent of Object.values(Intent)) {
    const s = scopeFor(intent);
    const tools = s.tools.map((t) => ({name: t.name,
      description: t.description, input_schema: t.inputSchema}));
    const row = {tools: s.tools.length, systemChars: s.systemChars,
      toolDefChars: s.toolDefChars};
    if (count) {
      row.systemTokens = await count({system: s.systemPrompt}) - base;
      row.toolTokens = await count({tools}) - base;
      row.prefixTokens =
        await count({system: s.systemPrompt, tools}) - base;
    }
    report.intents[intent] = row;
  }
  for (const [name, text] of Object.entries(sections())) {
    report.sections[name] = count ?
      {chars: text.length, tokens: await count({system: text}) - base} :
      {chars: text.length};
  }
  const oneToolBase = count ? await count({tools: [wire(LOAD_TOOLS_TOOL)]}) : 0;
  for (const tool of CATALOG.concat([LOAD_TOOLS_TOOL])) {
    const chars = JSON.stringify(wire(tool)).length;
    report.tools[tool.name] = count ?
      // Delta over a one-tool baseline, so the fixed tool-use preamble is
      // counted once (in the intents' toolTokens), not per tool.
      {chars, tokens: await count({tools: [wire(LOAD_TOOLS_TOOL),
        wire(tool)]}) - oneToolBase} :
      {chars};
  }
  if (count) {
    report.tools[LOAD_TOOLS_TOOL.name].tokens =
      oneToolBase - base;
  }

  if (asJson) {
    process.stdout.write(JSON.stringify(report, null, 2) + "\n");
    return;
  }
  const unit = offline ? "chars" : "tokens";
  console.log(`Model ${MODEL} · promptVersion ${PROMPT_VERSION} · ${unit}` +
    (offline ? " (no ANTHROPIC_API_KEY — character counts only)" : ""));
  console.log("\nPer intent (fixed prefix re-sent on every model call):");
  for (const [intent, r] of Object.entries(report.intents)) {
    console.log(offline ?
      `  ${intent.padEnd(10)} tools ${String(r.tools).padStart(2)}  ` +
        `system ${r.systemChars}  tools ${r.toolDefChars}  ` +
        `total ${r.systemChars + r.toolDefChars}` :
      `  ${intent.padEnd(10)} tools ${String(r.tools).padStart(2)}  ` +
        `system ${r.systemTokens}  tools ${r.toolTokens}  ` +
        `prefix ${r.prefixTokens}`);
  }
  const rows = (obj) => Object.entries(obj)
      .sort((a, b) => (b[1].tokens || b[1].chars) - (a[1].tokens || a[1].chars))
      .map(([n, v]) => `  ${n.padEnd(26)} ${offline ? v.chars : v.tokens}`);
  console.log(`\nPrompt sections (${unit}):`);
  console.log(rows(report.sections).join("\n"));
  console.log(`\nTools (${unit}):`);
  console.log(rows(report.tools).join("\n"));
}

main().catch((err) => {
  console.error(err && err.message ? err.message : err);
  process.exit(1);
});
