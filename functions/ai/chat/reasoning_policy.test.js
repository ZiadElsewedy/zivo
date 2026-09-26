/**
 * Offline tests for the reasoning policy (`reasoning_policy.js`): each turn
 * gets ONE coherent tier, and no tier can name a setting the catalog lacks.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {planTurn, tierFor, assertTiers, DEFAULT_TIERS} =
  require("./reasoning_policy");

const routed = (intent, reason = "keywords") => ({intent, reason});
const auto = {mode: "auto"};

test("general → lookup; a change → standard; a decision → deep; a plain " +
    "contextual read → standard", () => {
  const cases = [
    ["hi", "general", "lookup", "general"],
    ["Log 2 boiled eggs", "diet", "standard", "change"],
    ["سجل ٢ بيض", "diet", "standard", "change"],
    ["should I train hard today?", "training", "deep", "decision"],
    ["حابب اعرف عادي متمرنش انهرده ولا هقع", "ambiguous", "deep", "decision"],
    ["How is my training going?", "training", "deep", "decision"],
    ["what's my next meal?", "diet", "standard", "contextual"],
    ["how much did I spend this week?", "money", "standard", "contextual"],
    ["انا عملت ايه انهرده", "ambiguous", "standard", "ambiguous"],
  ];
  for (const [message, intent, tier, reason] of cases) {
    assert.deepEqual(tierFor({routed: routed(intent), message}),
        {tier, reason}, message);
  }
  assert.deepEqual(tierFor({routed: routed("diet"), message: "Tuna",
    picked: true}), {tier: "standard", reason: "picked_option"});
});

test("a plan is a tier's (model, level) — off by default", () => {
  assert.deepEqual(planTurn({cfg: auto, provider: "anthropic",
    routed: routed("general", "general"), message: "hi"}),
  {tier: "lookup", model: "claude-haiku", level: "low", reason: "general"});
  assert.equal(planTurn({cfg: {mode: "off"}, provider: "anthropic",
    routed: routed("general"), message: "hi"}), null);
  assert.equal(planTurn({cfg: undefined, provider: "anthropic",
    routed: routed("general"), message: "hi"}), null);
});

test("tiers can be re-pointed; a tier on another provider's model or an " +
    "override the catalog lacks yields no plan", () => {
  const cfg = {mode: "auto",
    tiers: {lookup: {model: "claude-sonnet", level: "low"}}};
  assert.equal(planTurn({cfg, provider: "anthropic",
    routed: routed("general"), message: "hi"}).model, "claude-sonnet");
  assert.equal(planTurn({cfg: auto, provider: "gemini",
    routed: routed("general"), message: "hi"}), null);
  assert.equal(planTurn({cfg: {override: {model: "claude-haiku",
    level: "high"}}, provider: "anthropic", routed: routed("diet"),
  message: "x"}), null);
  assert.deepEqual(planTurn({cfg: {override: {model: "claude-sonnet",
    level: "medium"}}, provider: "anthropic", routed: routed("diet"),
  message: "x"}), {tier: null, model: "claude-sonnet", level: "medium",
    reason: "override"});
});

test("the tier table only names settings the catalog offers", () => {
  assert.doesNotThrow(() => assertTiers(DEFAULT_TIERS));
  assert.throws(() => assertTiers({deep: {model: "claude-haiku",
    level: "high"}}), /not a model\/level/);
  assert.throws(() => assertTiers({deep: {model: "gemini-flash",
    level: "high"}}), /not a model\/level/);
});
