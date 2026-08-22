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
 * `fail` is set, rejects with an `Error` carrying `fail` as its message.
 * @param {{response: !Object, fail: string}} opts
 * @return {!Object}
 */
function fakeProvider({response, fail} = {}) {
  const calls = [];
  return {
    calls,
    generate: async (normalizedRequest) => {
      calls.push(normalizedRequest);
      if (fail) throw new Error(fail);
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

test("both chat and workout_import route to anthropic today", () => {
  assert.equal(resolve("chat").provider, "anthropic");
  assert.equal(resolve("workout_import").provider, "anthropic");
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
