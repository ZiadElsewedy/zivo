/**
 * Offline unit tests for `./speech_router.js`: capability resolution and the
 * fallback-on-error policy. No network — providers are plain fakes.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {resolve, transcribe} = require("./speech_router");
const {ProviderRegistry} = require("../../providers/registry");

/**
 * A fake `SpeechToTextProvider` whose `transcribe` either resolves to
 * `response` or, when `fail` is set, rejects with an `Error` carrying `fail`
 * as its message.
 * @param {{response: !Object, fail: string}} opts
 * @return {!Object}
 */
function fakeProvider({response, fail} = {}) {
  const calls = [];
  return {
    calls,
    transcribe: async (normalizedRequest) => {
      calls.push(normalizedRequest);
      if (fail) throw new Error(fail);
      return response;
    },
  };
}

test("resolve returns the primary provider/model for speech_to_text (Gemini is the default)", () => {
  const route = resolve("speech_to_text");
  assert.equal(route.provider, "gemini");
  assert.equal(route.model, "gemini-flash-latest");
});

test("resolve throws for an unknown capability", () => {
  assert.throws(() => resolve("not_a_real_capability"));
});

test("transcribe resolves the capability's primary provider and stamps the route's model onto the request", async () => {
  const registry = new ProviderRegistry();
  const gemini = fakeProvider({response: {text: "hello"}});
  registry.register("gemini", gemini);

  const resp = await transcribe(registry, "speech_to_text", {audio: Buffer.from("x"), mimeType: "audio/m4a"});

  assert.equal(resp.text, "hello");
  assert.equal(gemini.calls[0].model, "gemini-flash-latest");
  assert.equal(gemini.calls[0].mimeType, "audio/m4a");
});

test("transcribe throws for an unknown capability without touching the registry", async () => {
  const registry = new ProviderRegistry();
  await assert.rejects(() => transcribe(registry, "unknown", {audio: Buffer.from("x"), mimeType: "audio/m4a"}));
});

test("transcribe falls back from Gemini to OpenAI when the default provider rejects", async () => {
  const registry = new ProviderRegistry();
  const gemini = fakeProvider({fail: "gemini down"});
  const openai = fakeProvider({response: {text: "hello"}});
  registry.register("gemini", gemini);
  registry.register("openai", openai);

  const resp = await transcribe(registry, "speech_to_text", {audio: Buffer.from("x"), mimeType: "audio/m4a"});

  assert.equal(resp.text, "hello");
  assert.equal(gemini.calls.length, 1);
  assert.equal(openai.calls.length, 1);
  // The fallback route stamps OpenAI's own model, not Gemini's.
  assert.equal(openai.calls[0].model, "gpt-4o-mini-transcribe");
});

test("transcribe rethrows the last route's error once every route has failed", async () => {
  const registry = new ProviderRegistry();
  registry.register("gemini", fakeProvider({fail: "gemini down"}));
  registry.register("openai", fakeProvider({fail: "openai down too"}));

  await assert.rejects(
      () => transcribe(registry, "speech_to_text", {audio: Buffer.from("x"), mimeType: "audio/m4a"}),
      (err) => err.message === "openai down too",
  );
});

test("an unregistered fallback route is skipped, not treated as a failure (Gemini-only deploy)", async () => {
  const registry = new ProviderRegistry();
  // Only Gemini is registered — the optional OpenAI fallback has no key.
  const gemini = fakeProvider({fail: "gemini down"});
  registry.register("gemini", gemini);

  // Gemini's own error surfaces — never an "unknown provider: openai" error.
  await assert.rejects(
      () => transcribe(registry, "speech_to_text", {audio: Buffer.from("x"), mimeType: "audio/m4a"}),
      (err) => err.message === "gemini down",
  );
  assert.equal(gemini.calls.length, 1);
});

test("a Gemini-only registry still succeeds on the primary route", async () => {
  const registry = new ProviderRegistry();
  registry.register("gemini", fakeProvider({response: {text: "hello"}}));

  const resp = await transcribe(registry, "speech_to_text", {audio: Buffer.from("x"), mimeType: "audio/m4a"});

  assert.equal(resp.text, "hello");
});

test("transcribe throws a clear error when no route's provider is registered", async () => {
  const registry = new ProviderRegistry();
  await assert.rejects(
      () => transcribe(registry, "speech_to_text", {audio: Buffer.from("x"), mimeType: "audio/m4a"}),
      (err) => /no registered stt provider/i.test(err.message),
  );
});
