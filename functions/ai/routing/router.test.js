/**
 * Offline unit tests for `./router.js`: capability resolution and the
 * fallback-on-error policy. No network — providers are plain fakes.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {resolve, generate, CAPABILITY_ROUTES} = require("./router");
const {ProviderRegistry} = require("../providers/registry");

/**
 * A fake provider whose `generate` either resolves to `response` or, when
 * `fail` is set, rejects. `fail` may be a string (a status-less Error, treated
 * as a provider failure) or `{message, status}` to simulate an HTTP status
 * (e.g. 400 = a request error the router must NOT fall back on).
 * @param {{response: !Object, fail: (string|!Object)}} opts
 * @return {!Object}
 */
function fakeProvider({response, fail} = {}) {
  const calls = [];
  return {
    calls,
    generate: async (normalizedRequest) => {
      calls.push(normalizedRequest);
      if (fail) {
        const spec = typeof fail === "string" ? {message: fail} : fail;
        const err = new Error(spec.message || "failed");
        if (spec.status !== undefined) err.status = spec.status;
        throw err;
      }
      return response;
    },
  };
}

test("resolve returns the primary provider/model for a known capability", () => {
  const route = resolve("chat");
  assert.equal(route.provider, "anthropic");
  assert.equal(route.model, "claude-sonnet-5");
});

test("resolve throws for an unknown capability", () => {
  assert.throws(() => resolve("not_a_real_capability"));
});

test("chat, workout_import, and diet_import all route to anthropic today", () => {
  assert.equal(resolve("chat").provider, "anthropic");
  assert.equal(resolve("workout_import").provider, "anthropic");
  assert.equal(resolve("diet_import").provider, "anthropic");
});

test("generate resolves the capability's provider and stamps the route's model onto the request", async () => {
  const registry = new ProviderRegistry();
  const anthropic = fakeProvider({response: {stopReason: "end"}});
  registry.register("anthropic", anthropic);

  const resp = await generate(registry, "chat", {maxTokens: 10, messages: []});

  assert.equal(resp.stopReason, "end");
  assert.equal(anthropic.calls[0].model, "claude-sonnet-5");
  assert.equal(anthropic.calls[0].maxTokens, 10);
});

test("generate throws for an unknown capability without touching the registry", async () => {
  const registry = new ProviderRegistry();
  await assert.rejects(() => generate(registry, "unknown", {maxTokens: 10, messages: []}));
});

test("generate falls back to the next route when the primary provider's generate rejects", async () => {
  // Temporarily add a second route to exercise the fallback path without
  // mutating the real capability table for other tests.
  const original = CAPABILITY_ROUTES.chat.slice();
  CAPABILITY_ROUTES.chat.push({provider: "backup", model: "backup-model"});
  try {
    const registry = new ProviderRegistry();
    const primary = fakeProvider({fail: "primary down"});
    const backup = fakeProvider({response: {stopReason: "end"}});
    registry.register("anthropic", primary);
    registry.register("backup", backup);

    const resp = await generate(registry, "chat", {maxTokens: 10, messages: []});

    assert.equal(resp.stopReason, "end");
    assert.equal(primary.calls.length, 1);
    assert.equal(backup.calls.length, 1);
    assert.equal(backup.calls[0].model, "backup-model");
  } finally {
    CAPABILITY_ROUTES.chat.length = 0;
    CAPABILITY_ROUTES.chat.push(...original);
  }
});

test("generate rethrows the last route's error once every route has failed", async () => {
  const original = CAPABILITY_ROUTES.chat.slice();
  CAPABILITY_ROUTES.chat.push({provider: "backup", model: "backup-model"});
  try {
    const registry = new ProviderRegistry();
    registry.register("anthropic", fakeProvider({fail: "primary down"}));
    registry.register("backup", fakeProvider({fail: "backup down too"}));

    await assert.rejects(
        () => generate(registry, "chat", {maxTokens: 10, messages: []}),
        (err) => err.message === "backup down too",
    );
  } finally {
    CAPABILITY_ROUTES.chat.length = 0;
    CAPABILITY_ROUTES.chat.push(...original);
  }
});

// --- The chat route is Anthropic → Gemini (requirements #1–#4) --------------

test("chat routes Anthropic primary, Gemini fallback", () => {
  assert.deepEqual(CAPABILITY_ROUTES.chat.map((r) => r.provider),
      ["anthropic", "gemini"]);
});

test("#1 Auto: Claude succeeds, Gemini is never called", async () => {
  const registry = new ProviderRegistry();
  const anthropic = fakeProvider({response: {stopReason: "end"}});
  const gemini = fakeProvider({response: {stopReason: "end"}});
  registry.register("anthropic", anthropic).register("gemini", gemini);

  const resp = await generate(registry, "chat", {maxTokens: 10, messages: []});

  assert.equal(anthropic.calls.length, 1);
  assert.equal(gemini.calls.length, 0);
  // The response is stamped with the route that produced it.
  assert.equal(resp.provider, "anthropic");
  assert.equal(resp.model, "claude-sonnet-5");
});

test("#2 Auto: Claude fails with a provider failure, Gemini answers", async () => {
  const registry = new ProviderRegistry();
  const anthropic = fakeProvider({fail: {message: "overloaded", status: 529}});
  const gemini = fakeProvider({response: {stopReason: "end"}});
  registry.register("anthropic", anthropic).register("gemini", gemini);

  const resp = await generate(registry, "chat", {maxTokens: 10, messages: []});

  assert.equal(anthropic.calls.length, 1);
  assert.equal(gemini.calls.length, 1);
  assert.equal(gemini.calls[0].model, "gemini-2.5-pro");
  assert.equal(resp.provider, "gemini");
});

test("Auto: Claude fails with a 4xx request error — NO fallback, rethrow", async () => {
  const registry = new ProviderRegistry();
  const anthropic = fakeProvider({fail: {message: "bad request", status: 400}});
  const gemini = fakeProvider({response: {stopReason: "end"}});
  registry.register("anthropic", anthropic).register("gemini", gemini);

  await assert.rejects(
      () => generate(registry, "chat", {maxTokens: 10, messages: []}),
      (err) => err.message === "bad request");
  // Gemini must NOT be tried — the request itself was the problem.
  assert.equal(gemini.calls.length, 0);
});

test("#3 Manual Claude: only Anthropic is called (fallback bypassed)", async () => {
  const registry = new ProviderRegistry();
  const anthropic = fakeProvider({response: {stopReason: "end"}});
  const gemini = fakeProvider({response: {stopReason: "end"}});
  registry.register("anthropic", anthropic).register("gemini", gemini);

  const resp = await generate(
      registry, "chat", {maxTokens: 10, messages: []}, undefined,
      {forceProvider: "anthropic"});

  assert.equal(anthropic.calls.length, 1);
  assert.equal(gemini.calls.length, 0);
  assert.equal(resp.provider, "anthropic");
});

test("#4 Manual Gemini: request goes straight to Gemini, Claude never called", async () => {
  const registry = new ProviderRegistry();
  const anthropic = fakeProvider({response: {stopReason: "end"}});
  const gemini = fakeProvider({response: {stopReason: "end"}});
  registry.register("anthropic", anthropic).register("gemini", gemini);

  const resp = await generate(
      registry, "chat", {maxTokens: 10, messages: []}, undefined,
      {forceProvider: "gemini"});

  assert.equal(gemini.calls.length, 1);
  assert.equal(gemini.calls[0].model, "gemini-2.5-pro");
  assert.equal(anthropic.calls.length, 0);
  assert.equal(resp.provider, "gemini");
});

test("Manual Gemini failure does NOT fall back to Claude", async () => {
  const registry = new ProviderRegistry();
  const anthropic = fakeProvider({response: {stopReason: "end"}});
  const gemini = fakeProvider({fail: {message: "gemini down", status: 503}});
  registry.register("anthropic", anthropic).register("gemini", gemini);

  await assert.rejects(
      () => generate(registry, "chat", {maxTokens: 10, messages: []}, undefined,
          {forceProvider: "gemini"}),
      (err) => err.message === "gemini down");
  assert.equal(anthropic.calls.length, 0);
});

test("resolve(capability, forceProvider) returns the forced provider's route", () => {
  assert.equal(resolve("chat", "gemini").provider, "gemini");
  assert.equal(resolve("chat", "gemini").model, "gemini-2.5-pro");
  assert.equal(resolve("chat", "anthropic").provider, "anthropic");
});

test("forcing a provider with no configured route throws", () => {
  assert.throws(() => resolve("chat", "openai"));
});
