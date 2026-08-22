/**
 * Offline unit tests for `./openai_speech_provider.js`: request translation
 * (`NormalizedSttRequest` → the injected seam's call shape) and response
 * mapping (seam result → `NormalizedSttResponse`). The injected client is a
 * plain fake — no `openai` package, no network.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {OpenAiSpeechProvider, classifyError, DEFAULT_MODEL} =
  require("./openai_speech_provider");

/**
 * A `{transcribe}` fake that records the call and resolves to `result`.
 * @param {!Object} result
 * @return {!Object}
 */
function fakeClient(result) {
  const calls = [];
  return {
    calls,
    transcribe: async (call) => {
      calls.push(call);
      return result;
    },
  };
}

// --- request translation ----------------------------------------------

test("the audio buffer, mimeType, and default model pass through", async () => {
  const client = fakeClient({text: "hello"});
  const provider = new OpenAiSpeechProvider(client);
  const audio = Buffer.from("fake-audio-bytes");

  await provider.transcribe({audio, mimeType: "audio/m4a"});

  const call = client.calls[0];
  assert.equal(call.buffer, audio);
  assert.equal(call.mimeType, "audio/m4a");
  assert.equal(call.model, DEFAULT_MODEL);
});

test("a route-resolved model overrides the default", async () => {
  const client = fakeClient({text: "hello"});
  const provider = new OpenAiSpeechProvider(client);

  await provider.transcribe({audio: Buffer.from("x"), mimeType: "audio/wav", model: "gpt-5-transcribe"});

  assert.equal(client.calls[0].model, "gpt-5-transcribe");
});

test("no languageHint means no language is forwarded (code-switched speech stays untranslated)", async () => {
  const client = fakeClient({text: "hello"});
  const provider = new OpenAiSpeechProvider(client);

  await provider.transcribe({audio: Buffer.from("x"), mimeType: "audio/m4a"});

  assert.equal(client.calls[0].language, undefined);
});

test("an explicit languageHint is forwarded verbatim", async () => {
  const client = fakeClient({text: "hello"});
  const provider = new OpenAiSpeechProvider(client);

  await provider.transcribe({audio: Buffer.from("x"), mimeType: "audio/m4a", languageHint: "ar"});

  assert.equal(client.calls[0].language, "ar");
});

test("filename is derived from mimeType when not explicitly given", async () => {
  const client = fakeClient({text: "hi"});
  const provider = new OpenAiSpeechProvider(client);

  await provider.transcribe({audio: Buffer.from("x"), mimeType: "audio/wav"});
  assert.equal(client.calls[0].filename, "audio.wav");

  await provider.transcribe({audio: Buffer.from("x"), mimeType: "audio/mpeg"});
  assert.equal(client.calls[1].filename, "audio.mp3");
});

test("an explicit filename overrides the mimeType-derived default", async () => {
  const client = fakeClient({text: "hi"});
  const provider = new OpenAiSpeechProvider(client);

  await provider.transcribe({audio: Buffer.from("x"), mimeType: "audio/wav", filename: "clip.wav"});

  assert.equal(client.calls[0].filename, "clip.wav");
});

test("an unrecognized mimeType falls back to a generic filename", async () => {
  const client = fakeClient({text: "hi"});
  const provider = new OpenAiSpeechProvider(client);

  await provider.transcribe({audio: Buffer.from("x"), mimeType: "audio/unknown"});

  assert.equal(client.calls[0].filename, "audio");
});

// --- response mapping ----------------------------------------------------

test("text, detectedLanguage, and durationMs are mirrored from the seam result", async () => {
  const provider = new OpenAiSpeechProvider(
      fakeClient({text: "Hello world", language: "en", duration: 2.5}));

  const resp = await provider.transcribe({audio: Buffer.from("x"), mimeType: "audio/m4a"});

  assert.equal(resp.text, "Hello world");
  assert.equal(resp.detectedLanguage, "en");
  assert.equal(resp.durationMs, 2500);
});

test("a missing language/duration on the seam result maps to undefined, not null/0", async () => {
  const provider = new OpenAiSpeechProvider(fakeClient({text: "hi"}));

  const resp = await provider.transcribe({audio: Buffer.from("x"), mimeType: "audio/m4a"});

  assert.equal(resp.detectedLanguage, undefined);
  assert.equal(resp.durationMs, undefined);
});

test("the full seam result is preserved on `raw`", async () => {
  const result = {text: "hi", language: "en", duration: 1, extra: "field"};
  const provider = new OpenAiSpeechProvider(fakeClient(result));

  const resp = await provider.transcribe({audio: Buffer.from("x"), mimeType: "audio/m4a"});

  assert.equal(resp.raw, result);
});

test("a seam result with no text field throws a transcription_failed error", async () => {
  const provider = new OpenAiSpeechProvider(fakeClient({}));

  await assert.rejects(
      () => provider.transcribe({audio: Buffer.from("x"), mimeType: "audio/m4a"}),
      (err) => err.code === "transcription_failed",
  );
});

// --- error classification -------------------------------------------------

/** A stand-in for the OpenAI SDK's own `APIConnectionTimeoutError`. */
class APIConnectionTimeoutError extends Error {}

test("classifyError: a connection timeout (by constructor name) maps to 'timeout'", () => {
  const err = classifyError(new APIConnectionTimeoutError("Request timed out."));
  assert.equal(err.code, "timeout");
});

test("classifyError: no HTTP status at all (connection failure) maps to 'provider_unavailable'", () => {
  const err = classifyError(new Error("connect ECONNREFUSED"));
  assert.equal(err.code, "provider_unavailable");
});

test("classifyError: a 500-level status maps to 'provider_unavailable'", () => {
  const apiError = new Error("Internal server error");
  apiError.status = 503;
  assert.equal(classifyError(apiError).code, "provider_unavailable");
});

test("classifyError: a 429 (rate limit) maps to 'provider_unavailable'", () => {
  const rateLimited = new Error("Rate limited");
  rateLimited.status = 429;
  assert.equal(classifyError(rateLimited).code, "provider_unavailable");
});

test("classifyError: a 400 (bad request, e.g. corrupt audio) maps to 'transcription_failed'", () => {
  const badRequest = new Error("Invalid file format");
  badRequest.status = 400;
  assert.equal(classifyError(badRequest).code, "transcription_failed");
});

test("a provider/network failure surfaces as a typed error, not a raw throw", async () => {
  const client = {
    transcribe: async () => {
      const err = new Error("Internal server error");
      err.status = 500;
      throw err;
    },
  };
  const provider = new OpenAiSpeechProvider(client);

  await assert.rejects(
      () => provider.transcribe({audio: Buffer.from("x"), mimeType: "audio/m4a"}),
      (err) => err.code === "provider_unavailable",
  );
});
