/**
 * Offline unit tests for `./router.js`: the active model answers a request;
 * a TRANSIENT failure retries once then falls back to the other provider; a
 * PERMANENT one fails immediately, named, on neither provider tried twice.
 * No network — providers are plain fakes.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {
  resolve, generate, stickyProvider, CAPABILITY_DEFAULTS,
} = require("./router");
const {ProviderRegistry} = require("../providers/registry");
const {AiUnavailableError} = require("../providers/classify");

/**
 * A fake provider whose `generate` either resolves to `response` or, when
 * `fail` is set, rejects — for the first `failCount` calls only (default
 * `Infinity`: always fails), then succeeds with `response`. `fail` may be a
 * string (a status-less Error) or `{message, status}` to simulate an HTTP
 * status.
 * @param {{response: !Object, fail: (string|!Object), failCount: number}} opts
 * @return {!Object}
 */
function fakeProvider({response, fail, failCount = Infinity} = {}) {
  const calls = [];
  return {
    calls,
    generate: async (normalizedRequest) => {
      calls.push(normalizedRequest);
      if (fail && calls.length <= failCount) {
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

test("the retired 'auto', Gemini Pro, Claude Haiku and junk fall back to " +
    "the default model", () => {
  assert.equal(resolve("chat", {preferModel: "gemini-pro"}).model,
      "claude-sonnet-5");
  // Removed 2026-09-24 — ZIVO offers one model per provider now.
  assert.equal(resolve("chat", {preferModel: "claude-haiku"}).model,
      "claude-sonnet-5");
  assert.equal(resolve("chat", {preferModel: "gpt-9"}).model,
      "claude-sonnet-5");
  assert.equal(resolve("chat", {preferModel: undefined}).model,
      "claude-sonnet-5");
});

test("food_search is Gemini-grounded whatever the active model", () => {
  assert.equal(resolve("food_search", {preferModel: "claude-sonnet"}).provider,
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

test("a transient failure on BOTH providers surfaces the fallback's own " +
    "kind, having tried the primary's retry first", async () => {
  for (const [status, kind] of [[529, "overloaded"], [429, "rate_limit"],
    [503, "overloaded"], [500, "server"]]) {
    const gemini = fakeProvider({fail: {status, message: "x"}});
    const anthropic = fakeProvider({fail: {status, message: "x"}});
    const registry = new ProviderRegistry()
        .register("gemini", gemini).register("anthropic", anthropic);
    await assert.rejects(
        () => generate(registry, "chat", REQ, undefined,
            {preferModel: "gemini-flash"}),
        (err) => err instanceof AiUnavailableError && err.kind === kind);
    // Primary retried once (2 calls), fallback tried once with no retry of
    // its own (1 call) — 3 attempts total, not an unbounded loop.
    assert.equal(gemini.calls.length, 2, kind);
    assert.equal(anthropic.calls.length, 1, kind);
  }
});

test("a transient failure retries the SAME provider once before giving up " +
    "on it", async () => {
  const gemini = fakeProvider({
    fail: {status: 503, message: "overloaded"},
    failCount: 1,
    response: {stopReason: "end"},
  });
  const registry = new ProviderRegistry().register("gemini", gemini);

  const resp = await generate(registry, "chat", REQ, undefined,
      {preferModel: "gemini-flash"});

  assert.equal(gemini.calls.length, 2, "failed once, retried, succeeded");
  assert.equal(resp.provider, "gemini");
  assert.equal(resp.fallbackOccurred, undefined, "no fallback needed");
});

test("still-transient after the retry falls back to the other provider, " +
    "and the response says so", async () => {
  const gemini = fakeProvider({fail: {status: 503, message: "overloaded"}});
  const anthropic = fakeProvider({response: {stopReason: "end"}});
  const registry = new ProviderRegistry()
      .register("gemini", gemini).register("anthropic", anthropic);

  const resp = await generate(registry, "chat", REQ, undefined,
      {preferModel: "gemini-flash"});

  assert.equal(gemini.calls.length, 2, "primary tried, then retried");
  assert.equal(anthropic.calls.length, 1, "fallback tried once, no retry");
  assert.equal(resp.provider, "anthropic");
  assert.equal(resp.modelKey, "claude-sonnet");
  assert.equal(resp.fallbackOccurred, true);
  assert.equal(resp.fallbackReason, "overloaded");
  assert.equal(resp.requestedProvider, "gemini");
  assert.equal(resp.requestedModel, "gemini-flash-latest");
});

test("food_search never falls back, even for a transient Gemini failure — " +
    "Claude can't ground a search", async () => {
  const gemini = fakeProvider({fail: {status: 503, message: "overloaded"}});
  const anthropic = fakeProvider({response: {stopReason: "end"}});
  const registry = new ProviderRegistry()
      .register("gemini", gemini).register("anthropic", anthropic);

  await assert.rejects(
      () => generate(registry, "food_search", REQ),
      (err) => err instanceof AiUnavailableError && err.kind === "overloaded");
  assert.equal(anthropic.calls.length, 0, "never tried — wrong tool for it");
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

test("a hung provider is abandoned at attemptTimeoutMs as a clean timeout " +
    "— on both providers, once the retry and fallback are exhausted too", async () => {
  const signals = [];
  const makeHung = () => ({
    generate: (_req, opts) => {
      signals.push(opts && opts.signal);
      return new Promise(() => {});
    },
  });
  const registry = new ProviderRegistry()
      .register("anthropic", makeHung()).register("gemini", makeHung());

  await assert.rejects(
      () => generate(registry, "chat", REQ, undefined, {attemptTimeoutMs: 20}),
      (err) => err instanceof AiUnavailableError && err.kind === "timeout");
  // Primary (retried once) + fallback = 3 hung calls, each abandoned on its
  // own deadline rather than left to hang forever.
  assert.equal(signals.length, 3);
  assert.ok(signals.every((s) => s.aborted), "every hung call was aborted");
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

test("Gemini down → retried → Claude: onFallback fires before the fallback " +
    "runs, with model keys only", async () => {
  const order = [];
  const gemini = fakeProvider({fail: {status: 503, message: "overloaded"}});
  const anthropic = {
    calls: [],
    generate: async (req) => {
      order.push("anthropic");
      anthropic.calls.push(req);
      return {stopReason: "end"};
    },
  };
  const registry = new ProviderRegistry()
      .register("gemini", gemini).register("anthropic", anthropic);
  const seen = [];
  await generate(registry, "chat", REQ, {onFallback: (info) => {
    order.push("onFallback");
    seen.push(info);
  }}, {preferModel: "gemini-flash"});
  assert.deepEqual(order, ["onFallback", "anthropic"]);
  assert.deepEqual(seen,
      [{from: "gemini-flash", to: "claude-sonnet", reason: "overloaded"}]);
});

test("Claude down → retried → Gemini, the other way round", async () => {
  const anthropic = fakeProvider({fail: {status: 529, message: "overloaded"}});
  const gemini = fakeProvider({response: {stopReason: "end"}});
  const registry = new ProviderRegistry()
      .register("gemini", gemini).register("anthropic", anthropic);
  const seen = [];
  const resp = await generate(registry, "chat", REQ,
      {onFallback: (info) => seen.push(info)}, {preferModel: "claude-sonnet"});
  assert.equal(anthropic.calls.length, 2);
  assert.equal(resp.modelKey, "gemini-flash");
  assert.equal(resp.fallbackOccurred, true);
  assert.deepEqual(seen.map((i) => [i.from, i.to]),
      [["claude-sonnet", "gemini-flash"]]);
});

test("a permanent failure never falls back, and onFallback never fires",
    async () => {
      const anthropic = fakeProvider({fail: {status: 401, message: "bad key"}});
      const gemini = fakeProvider({response: {stopReason: "end"}});
      const registry = new ProviderRegistry()
          .register("gemini", gemini).register("anthropic", anthropic);
      let fired = false;
      await assert.rejects(() => generate(registry, "chat", REQ,
          {onFallback: () => {
            fired = true;
          }}, {preferModel: "claude-sonnet"}), AiUnavailableError);
      assert.equal(fired, false);
      assert.equal(gemini.calls.length, 0);
    });

test("stickyProvider: after one fallback, the rest of the request goes " +
    "straight to the model that answered", async () => {
  const gemini = fakeProvider({fail: {status: 503, message: "overloaded"}});
  const anthropic = fakeProvider({response: {stopReason: "end"}});
  const registry = new ProviderRegistry()
      .register("gemini", gemini).register("anthropic", anthropic);
  const provider = stickyProvider(registry, "chat",
      {preferModel: "gemini-flash"});

  const first = await provider.generate(REQ);
  const second = await provider.generate(REQ);
  assert.equal(first.fallbackOccurred, true);
  assert.equal(second.modelKey, "claude-sonnet");
  assert.equal(gemini.calls.length, 2, "only the first call tried Gemini");
  assert.equal(anthropic.calls.length, 2);
});
