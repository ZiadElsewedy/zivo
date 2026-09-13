/**
 * Unit tests for per-provider cost pricing (`usage.js` `costUsd` + `config.js`
 * `pricingFor`). The turn is priced at the rate of the provider that actually
 * answered; a turn with no provider stamp prices at the default (Anthropic), so
 * the legacy `callModel` seam and buffered fakes are unchanged.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {TurnUsage} = require("./usage");
const {
  pricingFor,
  PRICING,
  DEFAULT_PRICING_PROVIDER,
  INPUT_COST_PER_TOKEN_USD,
  OUTPUT_COST_PER_TOKEN_USD,
  CACHE_WRITE_MULTIPLIER,
  CACHE_READ_MULTIPLIER,
} = require("./config");

const near = (a, b) => Math.abs(a - b) < 1e-12;

/**
 * Shared bucket fixture: 100 uncached in, 2000 cache-write, 4000 cache-read,
 * 10 out. Cache buckets don't occur for Gemini in practice, but exercising the
 * full formula proves each provider's multipliers apply to its own rate.
 * @return {!TurnUsage}
 */
function usageWith() {
  const u = new TurnUsage();
  u.add({inputTokens: 100, cacheWriteTokens: 2000,
    cacheReadTokens: 4000, outputTokens: 10});
  return u;
}

test("Anthropic pricing is unchanged and is the default when no provider given",
    async () => {
      const u = usageWith();
      const inRate = INPUT_COST_PER_TOKEN_USD;
      const outRate = OUTPUT_COST_PER_TOKEN_USD;
      const expected =
        100 * inRate +
        2000 * inRate * CACHE_WRITE_MULTIPLIER +
        4000 * inRate * CACHE_READ_MULTIPLIER +
        10 * outRate;
      // Explicit 'anthropic', the default provider, and no-arg all agree — the
      // pre-existing behaviour is preserved byte-for-byte.
      assert.ok(near(u.costUsd("anthropic"), expected));
      assert.ok(near(u.costUsd(DEFAULT_PRICING_PROVIDER), expected));
      assert.ok(near(u.costUsd(), expected));
    });

test("Gemini is priced at its own (lower) rates, not Anthropic's", async () => {
  const u = usageWith();
  const g = PRICING.gemini;
  const expected =
    100 * g.inputPerToken +
    2000 * g.inputPerToken * g.cacheWriteMultiplier +
    4000 * g.inputPerToken * g.cacheReadMultiplier +
    10 * g.outputPerToken;
  assert.ok(near(u.costUsd("gemini"), expected));
  // And it must actually differ from the Anthropic figure — the whole point.
  assert.ok(u.costUsd("gemini") < u.costUsd("anthropic"));
});

test("a realistic no-cache Gemini turn costs input+output at Gemini rates",
    async () => {
      // The validation turn: 21,648 uncached in, 600 out, no cache tokens.
      const u = new TurnUsage();
      u.add({inputTokens: 21648, outputTokens: 600,
        cacheReadTokens: 0, cacheWriteTokens: 0});
      const g = PRICING.gemini;
      const expected = 21648 * g.inputPerToken + 600 * g.outputPerToken;
      assert.ok(near(u.costUsd("gemini"), expected));
      // Same buckets priced as Anthropic would be markedly higher — this is the
      // mispricing the fix removes.
      assert.ok(u.costUsd("anthropic") > u.costUsd("gemini") * 3);
    });

test("an unknown or omitted provider falls back to the default rates",
    async () => {
      const u = usageWith();
      const dflt = u.costUsd(DEFAULT_PRICING_PROVIDER);
      assert.ok(near(u.costUsd("openai"), dflt));
      assert.ok(near(u.costUsd(null), dflt));
      assert.ok(near(u.costUsd(undefined), dflt));
    });

test("pricingFor returns each provider's entry and defaults safely", async () => {
  assert.equal(pricingFor("anthropic"), PRICING.anthropic);
  assert.equal(pricingFor("gemini"), PRICING.gemini);
  assert.equal(pricingFor("nope"), PRICING[DEFAULT_PRICING_PROVIDER]);
  assert.equal(pricingFor(undefined), PRICING[DEFAULT_PRICING_PROVIDER]);
  // Anthropic's entry reuses the exported constants — one source of truth.
  assert.equal(PRICING.anthropic.inputPerToken, INPUT_COST_PER_TOKEN_USD);
  assert.equal(PRICING.anthropic.outputPerToken, OUTPUT_COST_PER_TOKEN_USD);
});
