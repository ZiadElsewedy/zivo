/**
 * Offline unit tests for `./router.js`: capability resolution and the
 * fallback-on-error policy. No network — providers are plain fakes.
 */

const assert = require("node:assert/strict");
const {test, beforeEach} = require("node:test");

const {
  resolve,
  generate,
  routesFor,
  resetCooldowns,
  CAPABILITY_ROUTES,
  COOLDOWN_MS,
} = require("./router");
const {ProviderRegistry} = require("../providers/registry");
const {AiUnavailableError} = require("../providers/classify");

// The cool-down map is module state — every test starts from a clean slate.
beforeEach(() => resetCooldowns());

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

test("every selectable capability is Claude-first with a Gemini fallback", () => {
  for (const cap of ["chat", "workout_import", "diet_import", "diet_generate"]) {
    assert.deepEqual(CAPABILITY_ROUTES[cap].map((r) => r.provider),
        ["anthropic", "gemini"], cap);
  }
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
        (err) => err instanceof AiUnavailableError &&
          err.cause.message === "backup down too" &&
          err.attempts.length === 2,
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
  assert.equal(gemini.calls[0].model, "gemini-flash-latest");
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
  assert.equal(gemini.calls[0].model, "gemini-flash-latest");
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
      (err) => err instanceof AiUnavailableError &&
        err.cause.message === "gemini down");
  assert.equal(anthropic.calls.length, 0);
});

test("resolve(capability, forceProvider) returns the forced provider's route", () => {
  assert.equal(resolve("chat", "gemini").provider, "gemini");
  assert.equal(resolve("chat", "gemini").model, "gemini-flash-latest");
  assert.equal(resolve("chat", "anthropic").provider, "anthropic");
});

test("forcing a provider with no configured route throws", () => {
  assert.throws(() => resolve("chat", "openai"));
});

// --- Billing/auth failures fall back (the "Claude is out of credit" case) ----

test("Claude out of credit (a 400!) falls back to Gemini", async () => {
  const registry = new ProviderRegistry();
  const anthropic = fakeProvider({fail: {status: 400, message:
    "400 {\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\"," +
    "\"message\":\"Your credit balance is too low to access the Anthropic " +
    "API.\"}}"}});
  const gemini = fakeProvider({response: {stopReason: "end"}});
  registry.register("anthropic", anthropic).register("gemini", gemini);

  const resp = await generate(registry, "diet_generate",
      {maxTokens: 10, messages: []});

  assert.equal(resp.provider, "gemini");
  assert.equal(resp.fellBack, true);
  assert.deepEqual(resp.attempts.map((a) => a.kind), ["billing"]);
});

test("a billing failure cools Anthropic down: the next call goes to Gemini first", async () => {
  const registry = new ProviderRegistry();
  const anthropic = fakeProvider({fail: {status: 400,
    message: "Your credit balance is too low"}});
  const gemini = fakeProvider({response: {stopReason: "end"}});
  registry.register("anthropic", anthropic).register("gemini", gemini);
  let t = 1000;
  const now = () => t;

  await generate(registry, "chat", {maxTokens: 10, messages: []}, undefined,
      {now});
  assert.equal(anthropic.calls.length, 1);

  const second = await generate(registry, "chat",
      {maxTokens: 10, messages: []}, undefined, {now});
  assert.equal(anthropic.calls.length, 1, "Claude skipped while cooling");
  assert.equal(second.provider, "gemini");
  assert.equal(second.fellBack, false);

  // After the window, Claude is first again (recovery is automatic).
  t += COOLDOWN_MS + 1;
  assert.equal(routesFor("chat", {now})[0].provider, "anthropic");
});

test("a cooling provider is still tried last when everything else fails", async () => {
  const registry = new ProviderRegistry();
  const anthropic = fakeProvider({fail: {status: 401, message: "invalid x-api-key"}});
  const gemini = fakeProvider({fail: {status: 503, message: "unavailable"}});
  registry.register("anthropic", anthropic).register("gemini", gemini);

  await assert.rejects(() => generate(registry, "chat",
      {maxTokens: 10, messages: []}), AiUnavailableError);
  await assert.rejects(() => generate(registry, "chat",
      {maxTokens: 10, messages: []}), AiUnavailableError);
  assert.equal(anthropic.calls.length, 2);
  assert.equal(gemini.calls.length, 2);
});

// --- The user's model selection (preferModel) ------------------------------

test("preferModel puts the chosen model first and keeps the defaults as fallback", () => {
  const routes = routesFor("chat", {preferModel: "gemini-pro"});
  assert.deepEqual(routes.map((r) => r.model),
      ["gemini-pro-latest", "claude-sonnet-5", "gemini-flash-latest"]);
});

test("preferring a default model doesn't duplicate its route", () => {
  const routes = routesFor("chat", {preferModel: "gemini-flash"});
  assert.deepEqual(routes.map((r) => r.model),
      ["gemini-flash-latest", "claude-sonnet-5"]);
});

test("preferModel is ignored for food_search and for an unknown key", () => {
  assert.deepEqual(routesFor("food_search", {preferModel: "claude-haiku"})
      .map((r) => r.provider), ["gemini"]);
  assert.equal(routesFor("chat", {preferModel: "gpt-9"})[0].model,
      "claude-sonnet-5");
});

test("a preferred Claude Haiku out of credit still lands on Gemini", async () => {
  const registry = new ProviderRegistry();
  const anthropic = fakeProvider({fail: {status: 402, message: "payment"}});
  const gemini = fakeProvider({response: {stopReason: "end"}});
  registry.register("anthropic", anthropic).register("gemini", gemini);

  const resp = await generate(registry, "workout_import",
      {maxTokens: 10, messages: []}, undefined, {preferModel: "claude-haiku"});

  assert.equal(anthropic.calls[0].model, "claude-haiku-4-5-20251001");
  assert.equal(resp.provider, "gemini");
  assert.equal(resp.modelKey, "gemini-flash");
});

// --- Per-attempt deadline + cancellation ------------------------------------

test("a hung provider is abandoned at attemptTimeoutMs and the next route answers", async () => {
  const registry = new ProviderRegistry();
  let sawSignal = null;
  const hung = {
    generate: (_req, opts) => {
      sawSignal = opts && opts.signal;
      return new Promise(() => {});
    },
  };
  const gemini = fakeProvider({response: {stopReason: "end"}});
  registry.register("anthropic", hung).register("gemini", gemini);

  const resp = await generate(registry, "chat", {maxTokens: 10, messages: []},
      undefined, {attemptTimeoutMs: 20});

  assert.equal(resp.provider, "gemini");
  assert.equal(resp.attempts[0].kind, "timeout");
  assert.equal(sawSignal.aborted, true, "the hung call was told to abort");
});

test("a user cancel is rethrown, never failed over", async () => {
  const registry = new ProviderRegistry();
  const controller = new AbortController();
  const anthropic = {
    generate: async () => {
      controller.abort();
      const err = new Error("aborted");
      err.name = "AbortError";
      throw err;
    },
  };
  const gemini = fakeProvider({response: {stopReason: "end"}});
  registry.register("anthropic", anthropic).register("gemini", gemini);

  await assert.rejects(() => generate(registry, "chat",
      {maxTokens: 10, messages: []}, {signal: controller.signal}),
  (err) => err.name === "AbortError");
  assert.equal(gemini.calls.length, 0);
});
