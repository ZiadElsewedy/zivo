/**
 * Offline unit tests for the `aiTranscribe` core (`./gateway.js`). No
 * `openai` package, no network — `provider` is a plain fake scripted per
 * test, so this runs under plain `node --test`.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {transcribeAudio, SpeechError} = require("./gateway");

const VALID_AUDIO_BASE64 = Buffer.from("fake-m4a-bytes").toString("base64");

/**
 * A `provider` fake that resolves to `response` (or throws `fail`),
 * recording every request it was called with.
 * @param {{response: !Object, fail: !Error}} opts
 * @return {!Object}
 */
function fakeProvider({response, fail} = {}) {
  const calls = [];
  return {
    calls,
    transcribe: async (normalizedRequest) => {
      calls.push(normalizedRequest);
      if (fail) throw fail;
      return response;
    },
  };
}

test("rejects missing audio before calling the provider", async () => {
  const provider = fakeProvider({response: {text: "hi"}});
  await assert.rejects(
      () => transcribeAudio({provider, audioBase64: "", mimeType: "audio/m4a"}),
      (err) => err instanceof SpeechError && err.code === "invalid-argument",
  );
  assert.equal(provider.calls.length, 0);
});

test("rejects a blank audioBase64 before calling the provider", async () => {
  const provider = fakeProvider({response: {text: "hi"}});
  await assert.rejects(
      () => transcribeAudio({provider, audioBase64: "   ", mimeType: "audio/m4a"}),
      (err) => err instanceof SpeechError && err.code === "invalid-argument",
  );
  assert.equal(provider.calls.length, 0);
});

test("rejects an unsupported mime type before calling the provider", async () => {
  const provider = fakeProvider({response: {text: "hi"}});
  await assert.rejects(
      () => transcribeAudio({provider, audioBase64: VALID_AUDIO_BASE64, mimeType: "video/mp4"}),
      (err) => err instanceof SpeechError && err.code === "unsupported_audio_format",
  );
  assert.equal(provider.calls.length, 0);
});

test("accepts every mime type record can emit", async () => {
  const mimeTypes = [
    "audio/m4a", "audio/x-m4a", "audio/mp4", "audio/aac",
    "audio/wav", "audio/x-wav", "audio/webm", "audio/ogg", "audio/mpeg",
  ];
  for (const mimeType of mimeTypes) {
    const provider = fakeProvider({response: {text: "hi"}});
    const result = await transcribeAudio(
        {provider, audioBase64: VALID_AUDIO_BASE64, mimeType});
    assert.equal(result.text, "hi");
  }
});

test("a mime type with a codecs parameter is normalized before the allowlist check", async () => {
  const provider = fakeProvider({response: {text: "hi"}});
  const result = await transcribeAudio({
    provider, audioBase64: VALID_AUDIO_BASE64, mimeType: "audio/webm;codecs=opus",
  });
  assert.equal(result.text, "hi");
  assert.equal(provider.calls[0].mimeType, "audio/webm");
});

test("rejects audio over the size cap before calling the provider", async () => {
  const provider = fakeProvider({response: {text: "hi"}});
  const bigBase64 = Buffer.alloc(16 * 1024 * 1024, 1).toString("base64");
  await assert.rejects(
      () => transcribeAudio({provider, audioBase64: bigBase64, mimeType: "audio/m4a"}),
      (err) => err instanceof SpeechError && err.code === "audio_too_large",
  );
  assert.equal(provider.calls.length, 0);
});

test("a provider failure with a known code surfaces as the matching SpeechError", async () => {
  const failure = new Error("connect ECONNREFUSED");
  failure.code = "provider_unavailable";
  const provider = fakeProvider({fail: failure});
  await assert.rejects(
      () => transcribeAudio({provider, audioBase64: VALID_AUDIO_BASE64, mimeType: "audio/m4a"}),
      (err) => err instanceof SpeechError && err.code === "provider_unavailable",
  );
});

test("a provider failure with a timeout code surfaces as a timeout SpeechError", async () => {
  const failure = new Error("Request timed out.");
  failure.code = "timeout";
  const provider = fakeProvider({fail: failure});
  await assert.rejects(
      () => transcribeAudio({provider, audioBase64: VALID_AUDIO_BASE64, mimeType: "audio/m4a"}),
      (err) => err instanceof SpeechError && err.code === "timeout",
  );
});

test("a provider failure with an unrecognized code defaults to transcription_failed", async () => {
  const failure = new Error("something odd");
  failure.code = "some_unrelated_code";
  const provider = fakeProvider({fail: failure});
  await assert.rejects(
      () => transcribeAudio({provider, audioBase64: VALID_AUDIO_BASE64, mimeType: "audio/m4a"}),
      (err) => err instanceof SpeechError && err.code === "transcription_failed",
  );
});

test("a provider failure with no code at all defaults to transcription_failed", async () => {
  const provider = fakeProvider({fail: new Error("boom")});
  await assert.rejects(
      () => transcribeAudio({provider, audioBase64: VALID_AUDIO_BASE64, mimeType: "audio/m4a"}),
      (err) => err instanceof SpeechError && err.code === "transcription_failed",
  );
});

test("a provider response with no text also surfaces as transcription_failed", async () => {
  const provider = fakeProvider({response: {}});
  await assert.rejects(
      () => transcribeAudio({provider, audioBase64: VALID_AUDIO_BASE64, mimeType: "audio/m4a"}),
      (err) => err instanceof SpeechError && err.code === "transcription_failed",
  );
});

test("happy path: normalizes the provider's response into {text, detectedLanguage, durationMs}", async () => {
  const provider = fakeProvider({
    response: {text: "Hello there", detectedLanguage: "en", durationMs: 1500},
  });
  const result = await transcribeAudio({provider, audioBase64: VALID_AUDIO_BASE64, mimeType: "audio/m4a"});
  assert.deepEqual(result, {text: "Hello there", detectedLanguage: "en", durationMs: 1500});
});

test("no languageHint is forwarded to the provider unless explicitly given", async () => {
  const provider = fakeProvider({response: {text: "hi"}});
  await transcribeAudio({provider, audioBase64: VALID_AUDIO_BASE64, mimeType: "audio/m4a"});
  assert.equal(provider.calls[0].languageHint, undefined);
});

test("an explicit languageHint is trimmed and forwarded to the provider", async () => {
  const provider = fakeProvider({response: {text: "hi"}});
  await transcribeAudio({
    provider, audioBase64: VALID_AUDIO_BASE64, mimeType: "audio/m4a", languageHint: " ar ",
  });
  assert.equal(provider.calls[0].languageHint, "ar");
});

test("the provider receives a decoded Buffer, not the base64 string", async () => {
  const provider = fakeProvider({response: {text: "hi"}});
  await transcribeAudio({provider, audioBase64: VALID_AUDIO_BASE64, mimeType: "audio/m4a"});
  const sent = provider.calls[0].audio;
  assert.ok(Buffer.isBuffer(sent));
  assert.equal(sent.toString(), "fake-m4a-bytes");
});

test("logEvent fires once on success with bytes/latency/duration but no text or audio", async () => {
  const provider = fakeProvider({response: {text: "a secret-looking transcript", durationMs: 900}});
  const events = [];
  await transcribeAudio({
    provider, audioBase64: VALID_AUDIO_BASE64, mimeType: "audio/m4a",
    logEvent: (e) => events.push(e),
  });

  assert.equal(events.length, 1);
  assert.equal(events[0].success, true);
  assert.equal(events[0].durationMs, 900);
  assert.equal(typeof events[0].bytes, "number");
  assert.equal(typeof events[0].latencyMs, "number");
  const serialized = JSON.stringify(events[0]);
  assert.doesNotMatch(serialized, /secret-looking transcript/);
  assert.doesNotMatch(serialized, /fake-m4a-bytes/);
});

test("logEvent fires once on provider failure with success:false and the resolved code", async () => {
  const failure = new Error("Rate limited");
  failure.code = "provider_unavailable";
  const provider = fakeProvider({fail: failure});
  const events = [];
  await assert.rejects(() => transcribeAudio({
    provider, audioBase64: VALID_AUDIO_BASE64, mimeType: "audio/m4a",
    logEvent: (e) => events.push(e),
  }));

  assert.equal(events.length, 1);
  assert.equal(events[0].success, false);
  assert.equal(events[0].code, "provider_unavailable");
});

test("logEvent never fires for a validation failure (nothing was attempted)", async () => {
  const provider = fakeProvider({response: {text: "hi"}});
  const events = [];
  await assert.rejects(() => transcribeAudio({
    provider, audioBase64: "", mimeType: "audio/m4a",
    logEvent: (e) => events.push(e),
  }));
  assert.equal(events.length, 0);
});

test("works with no logEvent provided (defaults to a no-op)", async () => {
  const provider = fakeProvider({response: {text: "hi"}});
  const result = await transcribeAudio({provider, audioBase64: VALID_AUDIO_BASE64, mimeType: "audio/m4a"});
  assert.equal(result.text, "hi");
});
