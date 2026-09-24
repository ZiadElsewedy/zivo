/**
 * Offline unit tests for `./usage_log.js` — the one usage record every AI
 * request writes, chat or not.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {
  UsageMeter,
  buildUsageRecord,
  saveUsageRecord,
  errorKindFor,
} = require("./usage_log");
const {AiUnavailableError} = require("../providers/classify");
const {GatewayError} = require("../chat/errors");

const t0 = new Date("2026-09-23T10:00:00Z");
const t1 = new Date("2026-09-23T10:00:04Z");

const near = (a, b) => Math.abs(a - b) < 1e-12;

test("a metered request records the answering model, tokens and its cost", async () => {
  const meter = new UsageMeter();
  const provider = meter.wrap({
    generate: async () => ({
      provider: "anthropic",
      model: "claude-sonnet-5",
      modelKey: "claude-sonnet",
      usage: {inputTokens: 1000, outputTokens: 200,
        cacheReadTokens: 0, cacheWriteTokens: 0},
      attempts: [],
    }),
  });
  await provider.generate({});

  const record = buildUsageRecord({feature: "diet_generate", meter,
    dayKey: "2026-09-23", startedAt: t0, finishedAt: t1});

  assert.equal(record.feature, "diet_generate");
  assert.equal(record.status, "ok");
  assert.equal(record.provider, "anthropic");
  assert.equal(record.modelKey, "claude-sonnet");
  assert.equal(record.tokensIn, 1000);
  assert.equal(record.tokensOut, 200);
  assert.equal(record.calls, 1);
  assert.equal(record.latencyMs, 4000);
  // $2/M in + $10/M out.
  assert.ok(near(record.costUsd, 1000 * 2e-6 + 200 * 10e-6));
});

test("each call is priced at the model that answered it", async () => {
  const meter = new UsageMeter();
  meter.record({provider: "gemini", model: "gemini-flash-latest",
    modelKey: "gemini-flash",
    usage: {inputTokens: 1000000, outputTokens: 0}});

  const record = buildUsageRecord({feature: "workout_import", meter,
    dayKey: "d", startedAt: t0, finishedAt: t1});

  assert.equal(record.provider, "gemini");
  assert.equal(record.modelKey, "gemini-flash");
  assert.ok(near(record.costUsd, 0.30), "priced at Gemini Flash, not Claude");
});

test("a request whose provider failed is recorded as an error, no raw text", async () => {
  const meter = new UsageMeter();
  const attempts = [
    {provider: "gemini", model: "gemini-flash-latest", kind: "rate_limit"},
  ];
  const err = new AiUnavailableError("rate_limit", attempts,
      new Error("secret provider text"));
  const provider = meter.wrap({generate: async () => {
    throw err;
  }});
  await assert.rejects(() => provider.generate({}), AiUnavailableError);

  const record = buildUsageRecord({feature: "chat", meter, dayKey: "d",
    startedAt: t0, finishedAt: t1, error: err});

  assert.equal(record.status, "error");
  assert.equal(record.errorKind, "rate_limit");
  assert.equal(record.tokensIn, 0);
  assert.equal(record.costUsd, 0);
  assert.equal(record.provider, "gemini");
  assert.equal(JSON.stringify(record).includes("secret provider text"), false);
});

test("an unused meter reports nothing to log", () => {
  assert.equal(new UsageMeter().used, false);
});

test("errorKindFor names cancels, gateway codes and provider kinds", () => {
  assert.equal(errorKindFor(new GatewayError("cancelled", "x")), "cancelled");
  assert.equal(errorKindFor(new GatewayError("internal", "x")), "internal");
  const e = new Error("x");
  e.status = 529;
  assert.equal(errorKindFor(e), "overloaded");
});

test("saveUsageRecord never throws — logging can't fail the request", async () => {
  const warnings = [];
  await saveUsageRecord({logUsage: async () => {
    throw new Error("firestore down");
  }}, "uid", {feature: "chat"}, (msg) => warnings.push(msg));
  assert.equal(warnings.length, 1);
});
