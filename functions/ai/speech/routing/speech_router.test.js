/**
 * Offline unit tests for `./speech_router.js`: capability resolution and the
 * fallback-on-error policy. No network — providers are plain fakes.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {resolve, transcribe, SPEECH_ROUTES} = require("./speech_router");
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

test("resolve returns the primary provider/model for speech_to_text", () => {
  const route = resolve("speech_to_text");
  assert.equal(route.provider, "openai");
  assert.equal(route.model, "gpt-4o-mini-transcribe");
});

test("resolve throws for an unknown capability", () => {
  assert.throws(() => resolve("not_a_real_capability"));
});

test("transcribe resolves the capability's provider and stamps the route's model onto the request", async () => {
  const registry = new ProviderRegistry();
  const openai = fakeProvider({response: {text: "hello"}});
  registry.register("openai", openai);

  const resp = await transcribe(registry, "speech_to_text", {audio: Buffer.from("x"), mimeType: "audio/m4a"});

  assert.equal(resp.text, "hello");
  assert.equal(openai.calls[0].model, "gpt-4o-mini-transcribe");
  assert.equal(openai.calls[0].mimeType, "audio/m4a");
});

test("transcribe throws for an unknown capability without touching the registry", async () => {
  const registry = new ProviderRegistry();
  await assert.rejects(() => transcribe(registry, "unknown", {audio: Buffer.from("x"), mimeType: "audio/m4a"}));
});

test("transcribe falls back to the next route when the primary provider rejects", async () => {
  const original = SPEECH_ROUTES.speech_to_text.slice();
  SPEECH_ROUTES.speech_to_text.push({provider: "backup", model: "backup-model"});
  try {
    const registry = new ProviderRegistry();
    const primary = fakeProvider({fail: "primary down"});
    const backup = fakeProvider({response: {text: "hello"}});
    registry.register("openai", primary);
    registry.register("backup", backup);

    const resp = await transcribe(registry, "speech_to_text", {audio: Buffer.from("x"), mimeType: "audio/m4a"});

    assert.equal(resp.text, "hello");
    assert.equal(primary.calls.length, 1);
    assert.equal(backup.calls.length, 1);
    assert.equal(backup.calls[0].model, "backup-model");
  } finally {
    SPEECH_ROUTES.speech_to_text.length = 0;
    SPEECH_ROUTES.speech_to_text.push(...original);
  }
});

test("transcribe rethrows the last route's error once every route has failed", async () => {
  const original = SPEECH_ROUTES.speech_to_text.slice();
  SPEECH_ROUTES.speech_to_text.push({provider: "backup", model: "backup-model"});
  try {
    const registry = new ProviderRegistry();
    registry.register("openai", fakeProvider({fail: "primary down"}));
    registry.register("backup", fakeProvider({fail: "backup down too"}));

    await assert.rejects(
        () => transcribe(registry, "speech_to_text", {audio: Buffer.from("x"), mimeType: "audio/m4a"}),
        (err) => err.message === "backup down too",
    );
  } finally {
    SPEECH_ROUTES.speech_to_text.length = 0;
    SPEECH_ROUTES.speech_to_text.push(...original);
  }
});
