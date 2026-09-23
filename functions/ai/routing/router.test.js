/**
 * Offline unit tests for `./router.js`: one active model per request, no
 * fallback, and a clear, classified failure when that model can't answer.
 * No network — providers are plain fakes.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {resolve, generate, CAPABILITY_DEFAULTS} = require("./router");
const {ProviderRegistry} = require("../providers/registry");
const {AiUnavailableError} = require("../providers/classify");

/**
 * A fake provider whose `generate` either resolves to `response` or, when
 * `fail` is set, rejects. `fail` may be a string (a status-less Error) or
 * `{message, status}` to simulate an HTTP status.
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
      return Object.assign({}, response);
    },
  };
}

/**
 * @return {{registry: !ProviderRegistry, anthropic: !Object, gemini: !Object}}
 */
function bothHealthy() {
  const anthropic = fakeProvider({response: {stopReason: "end"}});
  const gemini = fakeProvider({response: {stopReason: "end"}});
  const registry = new ProviderRegistry()
      .register("anthropic", anthropic)
      .register("gemini", gemini);
  return {registry, anthropic, gemini};
}

const REQ = {maxTokens: 10, messages: []};

test("with no selection every user-facing capability defaults to Claude Sonnet", () => {
  for (const cap of ["chat", "workout_import", "diet_import", "diet_generate"]) {
    assert.equal(resolve(cap).model, "claude-sonnet-5", cap);
    assert.equal(CAPABILITY_DEFAULTS[cap], "claude-sonnet");
  }
});

test("the active model answers — and only it is called", async () => {
  const {registry, anthropic, gemini} = bothHealthy();

  const resp = await generate(registry, "chat", REQ, undefined,
      {preferModel: "gemini-flash"});

  assert.equal(gemini.calls.length, 1);
  assert.equal(gemini.calls[0].model, "gemini-flash-latest");
  assert.equal(anthropic.calls.length, 0);
  assert.equal(resp.provider, "gemini");
  assert.equal(resp.modelKey, "gemini-flash");
});

test("Claude Haiku as the active model is sent its own id", async () => {
  const {registry, anthropic} = bothHealthy();
  const resp = await generate(registry, "diet_generate", REQ, undefined,
      {preferModel: "claude-haiku"});
  assert.equal(anthropic.calls[0].model, "claude-haiku-4-5-20251001");
  assert.equal(resp.modelKey, "claude-haiku");
});

test("the retired 'auto', Gemini Pro and junk fall back to the default model", () => {
  assert.equal(resolve("chat", {preferModel: "gemini-pro"}).model,
      "claude-sonnet-5");
  assert.equal(resolve("chat", {preferModel: "gpt-9"}).model,
      "claude-sonnet-5");
  assert.equal(resolve("chat", {preferModel: undefined}).model,
      "claude-sonnet-5");
});

test("food_search is Gemini-grounded whatever the active model", () => {
  assert.equal(resolve("food_search", {preferModel: "claude-haiku"}).provider,
      "gemini");
});

test("an unknown capability throws", async () => {
  assert.throws(() => resolve("not_a_real_capability"));
  await assert.rejects(() => generate(new ProviderRegistry(), "nope", REQ));
});

test("Claude out of credit (a 400!) is NOT re-run on Gemini — it fails, named", async () => {
  const anthropic = fakeProvider({fail: {status: 400, message:
    "400 {\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\"," +
    "\"message\":\"Your credit balance is too low to access the Anthropic " +
    "API.\"}}"}});
  const gemini = fakeProvider({response: {stopReason: "end"}});
  const registry = new ProviderRegistry()
      .register("anthropic", anthropic).register("gemini", gemini);

  await assert.rejects(
      () => generate(registry, "chat", REQ, undefined,
          {preferModel: "claude-sonnet"}),
      (err) => err instanceof AiUnavailableError &&
        err.kind === "billing" &&
        err.attempts[0].provider === "anthropic" &&
        err.attempts[0].model === "claude-sonnet-5");
  assert.equal(gemini.calls.length, 0, "no silent second provider");
});

test("an overloaded or rate-limited Gemini fails with its own kind", async () => {
  for (const [status, kind] of [[529, "overloaded"], [429, "rate_limit"],
    [503, "overloaded"], [500, "server"]]) {
    const registry = new ProviderRegistry()
        .register("gemini", fakeProvider({fail: {status, message: "x"}}));
    await assert.rejects(
        () => generate(registry, "chat", REQ, undefined,
            {preferModel: "gemini-flash"}),
        (err) => err instanceof AiUnavailableError && err.kind === kind);
  }
});

test("a malformed request is rethrown as-is (our bug, not the provider's)", async () => {
  const registry = new ProviderRegistry().register("anthropic",
      fakeProvider({fail: {status: 400, message: "bad schema"}}));
  await assert.rejects(() => generate(registry, "chat", REQ),
      (err) => !(err instanceof AiUnavailableError) &&
        err.message === "bad schema");
});

test("a provider with no bound key is unavailable, not a crash", async () => {
  const registry = new ProviderRegistry()
      .register("anthropic", fakeProvider({response: {stopReason: "end"}}));
  await assert.rejects(
      () => generate(registry, "chat", REQ, undefined,
          {preferModel: "gemini-flash"}),
      (err) => err instanceof AiUnavailableError &&
        err.attempts[0].provider === "gemini");
});

test("a hung provider is abandoned at attemptTimeoutMs as a clean timeout", async () => {
  let sawSignal = null;
  const hung = {
    generate: (_req, opts) => {
      sawSignal = opts && opts.signal;
      return new Promise(() => {});
    },
  };
  const registry = new ProviderRegistry().register("anthropic", hung);

  await assert.rejects(
      () => generate(registry, "chat", REQ, undefined, {attemptTimeoutMs: 20}),
      (err) => err instanceof AiUnavailableError && err.kind === "timeout");
  assert.equal(sawSignal.aborted, true, "the hung call was told to abort");
});

test("a user cancel is rethrown unchanged", async () => {
  const controller = new AbortController();
  const anthropic = {
    generate: async () => {
      controller.abort();
      const err = new Error("aborted");
      err.name = "AbortError";
      throw err;
    },
  };
  const registry = new ProviderRegistry().register("anthropic", anthropic);

  await assert.rejects(
      () => generate(registry, "chat", REQ, {signal: controller.signal}),
      (err) => err.name === "AbortError");
});
