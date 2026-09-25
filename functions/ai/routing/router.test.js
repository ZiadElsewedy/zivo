/**
 * Offline unit tests for `./router.js`: the SELECTED model answers a request
 * — Gemini selected → Gemini only, Claude selected → Claude only. A TRANSIENT
 * failure is retried on the same provider; any failure that survives is
 * returned as THAT provider's error. Nothing ever falls back to the other
 * provider (owner decision 2026-09-26). No network — providers are fakes.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {
  resolve, generate, stickyProvider, CAPABILITY_DEFAULTS,
  CROSS_PROVIDER_FALLBACK,
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

// No backoff in tests — the retry COUNT is what's under test, not the wait.
const FAST = {retryBackoffMs: [0]};

test("cross-provider fallback is off", () => {
  assert.equal(CROSS_PROVIDER_FALLBACK, false);
});

test("(a) Gemini selected and healthy → Gemini answers, Claude is never called",
    async () => {
      const {registry, anthropic, gemini} = bothHealthy();
      const resp = await generate(registry, "chat", REQ, undefined,
          {preferModel: "gemini-flash"});
      assert.equal(gemini.calls.length, 1);
      assert.equal(anthropic.calls.length, 0);
      assert.equal(resp.provider, "gemini");
      assert.equal(resp.fallbackOccurred, undefined);
      assert.deepEqual(resp.tries.map((t) => [t.provider, t.ok]),
          [["gemini", true]]);
    });

test("(c) Claude selected and healthy → Claude answers, Gemini is never called",
    async () => {
      const {registry, anthropic, gemini} = bothHealthy();
      const resp = await generate(registry, "chat", REQ, undefined,
          {preferModel: "claude-sonnet"});
      assert.equal(anthropic.calls.length, 1);
      assert.equal(anthropic.calls[0].model, "claude-sonnet-5");
      assert.equal(gemini.calls.length, 0);
      assert.equal(resp.provider, "anthropic");
      assert.equal(resp.modelKey, "claude-sonnet");
    });

test("(b) Gemini's quota 429 (the production failure) returns GEMINI's " +
    "error — not retried, and Claude is never called", async () => {
  const gemini = fakeProvider({fail: {status: 429, message:
    "{\"error\":{\"code\":429,\"message\":\"You exceeded your current " +
    "quota, please check your plan and billing details.\",\"status\":" +
    "\"RESOURCE_EXHAUSTED\"}}"}});
  const anthropic = fakeProvider({response: {stopReason: "end"}});
  const registry = new ProviderRegistry()
      .register("gemini", gemini).register("anthropic", anthropic);
  const seen = [];
  await assert.rejects(
      () => generate(registry, "chat", REQ,
          {onFallback: (info) => seen.push(info)},
          {preferModel: "gemini-flash"}),
      (err) => err instanceof AiUnavailableError && err.kind === "quota" &&
        err.attempts.length === 1 && err.attempts[0].provider === "gemini" &&
        err.attempts[0].model === "gemini-flash-latest");
  assert.equal(gemini.calls.length, 1, "quota is not retried");
  assert.equal(anthropic.calls.length, 0, "Claude is never called");
  assert.deepEqual(seen, [], "no fallback is announced");
});

test("(b) every kind of Gemini failure is returned as Gemini's, with no " +
    "Claude call", async () => {
  for (const [fail, kind] of [
    [{status: 529, message: "x"}, "overloaded"],
    [{status: 429, message: "x"}, "rate_limit"],
    [{status: 500, message: "x"}, "server"],
    [{status: 401, message: "API key not valid"}, "auth"],
    [{status: 402, message: "payment required"}, "billing"],
    [{status: 404, message: "model not found"}, "model_unavailable"],
    ["socket hang up", "network"],
  ]) {
    const gemini = fakeProvider({fail});
    const anthropic = fakeProvider({response: {stopReason: "end"}});
    const registry = new ProviderRegistry()
        .register("gemini", gemini).register("anthropic", anthropic);
    await assert.rejects(
        () => generate(registry, "chat", REQ, FAST,
            {preferModel: "gemini-flash"}),
        (err) => err instanceof AiUnavailableError && err.kind === kind &&
          err.attempts.every((a) => a.provider === "gemini"), kind);
    assert.equal(anthropic.calls.length, 0, kind);
  }
});

test("(d) Claude out of credit (a 400!) returns CLAUDE's billing error — " +
    "no retry, and Gemini is never called", async () => {
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
      (err) => err instanceof AiUnavailableError && err.kind === "billing" &&
        err.attempts[0].provider === "anthropic" &&
        err.attempts[0].model === "claude-sonnet-5");
  assert.equal(anthropic.calls.length, 1, "billing is not retried");
  assert.equal(gemini.calls.length, 0, "Gemini is never called");
});

test("(d) Claude overloaded: retried on Claude, then Claude's error — " +
    "Gemini is never called", async () => {
  const anthropic = fakeProvider({fail: {status: 529, message: "overloaded"}});
  const gemini = fakeProvider({response: {stopReason: "end"}});
  const registry = new ProviderRegistry()
      .register("gemini", gemini).register("anthropic", anthropic);
  await assert.rejects(
      () => generate(registry, "chat", REQ, FAST,
          {preferModel: "claude-sonnet"}),
      (err) => err instanceof AiUnavailableError &&
        err.kind === "overloaded" && err.tries.length === 3 &&
        err.tries.every((t) => t.provider === "anthropic" && !t.ok));
  assert.equal(anthropic.calls.length, 3, "one call + two retries");
  assert.equal(gemini.calls.length, 0);
});

test("(e) the explicit selection decides, whatever the default is", () => {
  assert.equal(resolve("chat", {preferModel: "gemini-flash"}).provider,
      "gemini");
  assert.equal(resolve("chat", {preferModel: "claude-sonnet"}).provider,
      "anthropic");
  for (const cap of ["workout_import", "diet_import", "diet_generate"]) {
    assert.equal(resolve(cap, {preferModel: "gemini-flash"}).provider,
        "gemini", cap);
  }
});

test("(e) stickyProvider never switches: every call of a request goes to " +
    "the selected model, failing or not", async () => {
  const gemini = fakeProvider({fail: {status: 503, message: "overloaded"}});
  const anthropic = fakeProvider({response: {stopReason: "end"}});
  const registry = new ProviderRegistry()
      .register("gemini", gemini).register("anthropic", anthropic);
  const provider = stickyProvider(registry, "chat",
      {preferModel: "gemini-flash"});
  await assert.rejects(() => provider.generate(REQ, FAST), AiUnavailableError);
  await assert.rejects(() => provider.generate(REQ, FAST), AiUnavailableError);
  assert.equal(anthropic.calls.length, 0);
  assert.equal(gemini.calls.length, 6, "3 tries per call, Gemini only");
});

test("a malformed request is never re-sent anywhere, and carries its tries",
    async () => {
      const anthropic = fakeProvider({fail: {status: 400, message:
        "messages.0.content: field required"}});
      const gemini = fakeProvider({response: {stopReason: "end"}});
      const registry = new ProviderRegistry()
          .register("anthropic", anthropic).register("gemini", gemini);
      await assert.rejects(() => generate(registry, "chat", REQ, undefined,
          {preferModel: "claude-sonnet"}), (err) => err.status === 400 &&
          !(err instanceof AiUnavailableError) &&
          err.tries.length === 1 && err.tries[0].kind === "bad_request");
      assert.equal(anthropic.calls.length, 1);
      assert.equal(gemini.calls.length, 0);
    });

test("a transient failure retries the SAME provider before giving up on it",
    async () => {
      const gemini = fakeProvider({
        fail: {status: 503, message: "overloaded"},
        failCount: 2,
        response: {stopReason: "end"},
      });
      const registry = new ProviderRegistry().register("gemini", gemini);
      const resp = await generate(registry, "chat", REQ, FAST,
          {preferModel: "gemini-flash"});
      assert.equal(gemini.calls.length, 3, "failed twice, retried, succeeded");
      assert.equal(resp.provider, "gemini");
      assert.equal(resp.fallbackOccurred, undefined);
      // Every provider request is recorded, failures included.
      assert.deepEqual(resp.tries.map((t) => t.ok), [false, false, true]);
      assert.ok(resp.tries.every((t) => typeof t.latencyMs === "number"));
    });

test("food_search never leaves Gemini — Claude can't ground a search",
    async () => {
      const gemini = fakeProvider({fail: {status: 503, message: "x"}});
      const anthropic = fakeProvider({response: {stopReason: "end"}});
      const registry = new ProviderRegistry()
          .register("gemini", gemini).register("anthropic", anthropic);
      await assert.rejects(() => generate(registry, "food_search", REQ, FAST),
          (err) => err instanceof AiUnavailableError &&
            err.kind === "overloaded");
      assert.equal(anthropic.calls.length, 0);
    });

test("a selected provider with no bound key is unavailable (auth), naming " +
    "it — the other provider is not tried", async () => {
  const anthropic = fakeProvider({response: {stopReason: "end"}});
  const registry = new ProviderRegistry().register("anthropic", anthropic);
  await assert.rejects(
      () => generate(registry, "chat", REQ, undefined,
          {preferModel: "gemini-flash"}),
      (err) => err instanceof AiUnavailableError && err.kind === "auth" &&
        err.attempts.length === 1 && err.attempts[0].provider === "gemini");
  assert.equal(anthropic.calls.length, 0);
});

test("a hung provider is abandoned at attemptTimeoutMs as a clean timeout, " +
    "retried once on the same provider — never three deadlines", async () => {
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
      () => generate(registry, "chat", REQ, FAST, {attemptTimeoutMs: 20}),
      (err) => err instanceof AiUnavailableError && err.kind === "timeout");
  assert.equal(signals.length, 2, "the call + one retry, both Claude");
  assert.ok(signals.every((sig) => sig.aborted), "every hung call aborted");
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
