/**
 * Offline unit tests for `./gemini_speech_provider.js`: request translation
 * (`NormalizedSttRequest` → the injected seam's call shape, including the
 * ZIVO-owned transcription prompt) and response mapping (seam result →
 * `NormalizedSttResponse`). The injected client is a plain fake — no
 * `@google/genai` package, no network.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {
  GeminiSpeechProvider, classifyError, buildPrompt, DEFAULT_MODEL, BASE_PROMPT,
} = require("./gemini_speech_provider");

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
  const provider = new GeminiSpeechProvider(client);
  const audio = Buffer.from("fake-audio-bytes");

  await provider.transcribe({audio, mimeType: "audio/m4a"});

  const call = client.calls[0];
  assert.equal(call.buffer, audio);
  assert.equal(call.mimeType, "audio/m4a");
  assert.equal(call.model, DEFAULT_MODEL);
});

test("a route-resolved model overrides the default", async () => {
  const client = fakeClient({text: "hello"});
  const provider = new GeminiSpeechProvider(client);

  await provider.transcribe({audio: Buffer.from("x"), mimeType: "audio/wav", model: "gemini-2.5-pro"});

  assert.equal(client.calls[0].model, "gemini-2.5-pro");
});

test("no languageHint sends the base transcription prompt (code-switched speech stays untranslated)", async () => {
  const client = fakeClient({text: "hello"});
  const provider = new GeminiSpeechProvider(client);

  await provider.transcribe({audio: Buffer.from("x"), mimeType: "audio/m4a"});

  assert.equal(client.calls[0].prompt, BASE_PROMPT);
});

test("an explicit languageHint is woven into the prompt as an advisory hint, still verbatim", async () => {
  const client = fakeClient({text: "hello"});
  const provider = new GeminiSpeechProvider(client);

  await provider.transcribe({audio: Buffer.from("x"), mimeType: "audio/m4a", languageHint: "ar"});

  const prompt = client.calls[0].prompt;
  assert.match(prompt, /"ar"/);
  // Still instructs verbatim, non-translating transcription.
  assert.match(prompt, /verbatim/i);
  assert.notEqual(prompt, BASE_PROMPT);
});

test("buildPrompt returns the base prompt for missing/blank hints", () => {
  assert.equal(buildPrompt(undefined), BASE_PROMPT);
  assert.equal(buildPrompt(""), BASE_PROMPT);
  assert.equal(buildPrompt("   "), BASE_PROMPT);
});

// --- response mapping ----------------------------------------------------

test("text is mirrored (trimmed) from the seam result", async () => {
  const provider = new GeminiSpeechProvider(fakeClient({text: "  Hello world  "}));

  const resp = await provider.transcribe({audio: Buffer.from("x"), mimeType: "audio/m4a"});

  assert.equal(resp.text, "Hello world");
});

test("detectedLanguage and durationMs are always undefined (Gemini reports neither)", async () => {
  const provider = new GeminiSpeechProvider(fakeClient({text: "hi"}));

  const resp = await provider.transcribe({audio: Buffer.from("x"), mimeType: "audio/m4a"});

  assert.equal(resp.detectedLanguage, undefined);
  assert.equal(resp.durationMs, undefined);
});

test("the full seam result is preserved on `raw`", async () => {
  const result = {text: "hi", finishReason: "STOP", extra: "field"};
  const provider = new GeminiSpeechProvider(fakeClient(result));

  const resp = await provider.transcribe({audio: Buffer.from("x"), mimeType: "audio/m4a"});

  assert.equal(resp.raw, result);
});

test("a seam result with no text field throws a transcription_failed error", async () => {
  const provider = new GeminiSpeechProvider(fakeClient({}));

  await assert.rejects(
      () => provider.transcribe({audio: Buffer.from("x"), mimeType: "audio/m4a"}),
      (err) => err.code === "transcription_failed",
  );
});

test("a blocked/empty (whitespace-only) transcript throws transcription_failed", async () => {
  const provider = new GeminiSpeechProvider(fakeClient({text: "   "}));

  await assert.rejects(
      () => provider.transcribe({audio: Buffer.from("x"), mimeType: "audio/m4a"}),
      (err) => err.code === "transcription_failed",
  );
});

// --- error classification -------------------------------------------------

/** A stand-in for a fetch abort / client-side deadline. */
class AbortError extends Error {
  /** @param {string} message */
  constructor(message) {
    super(message);
    this.name = "AbortError";
  }
}

test("classifyError: an abort/timeout (by name) maps to 'timeout'", () => {
  assert.equal(classifyError(new AbortError("The operation was aborted.")).code, "timeout");
});

test("classifyError: a message-reported timeout maps to 'timeout'", () => {
  assert.equal(classifyError(new Error("request timed out")).code, "timeout");
});

test("classifyError: no HTTP status at all (connection failure) maps to 'provider_unavailable'", () => {
  assert.equal(classifyError(new Error("connect ECONNREFUSED")).code, "provider_unavailable");
});

test("classifyError: a 500-level status maps to 'provider_unavailable'", () => {
  const apiError = new Error("Internal server error");
  apiError.status = 503;
  assert.equal(classifyError(apiError).code, "provider_unavailable");
});

test("classifyError: a 429 (rate limit) maps to 'provider_unavailable'", () => {
  const rateLimited = new Error("Resource exhausted");
  rateLimited.status = 429;
  assert.equal(classifyError(rateLimited).code, "provider_unavailable");
});

test("classifyError: a 400 (bad request, e.g. corrupt audio) maps to 'transcription_failed'", () => {
  const badRequest = new Error("Invalid argument");
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
  const provider = new GeminiSpeechProvider(client);

  await assert.rejects(
      () => provider.transcribe({audio: Buffer.from("x"), mimeType: "audio/m4a"}),
      (err) => err.code === "provider_unavailable",
  );
});
