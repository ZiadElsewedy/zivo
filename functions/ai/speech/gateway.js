/**
 * The `aiTranscribe` orchestration core: validates an uploaded audio clip,
 * hands it to an injected `SpeechToTextProvider`, and returns TEXT ONLY.
 * Kept free of `firebase-admin`/`openai` so it runs offline under
 * `node --test` — `provider` is the only injected seam;
 * `functions/index.js` wires the real router-backed one.
 *
 * Input only: this never calls the LLM, never speaks text back, and never
 * streams — one clip in, one transcript out. The client puts the returned
 * text in the chat composer for the user to edit/send via the existing
 * `aiChat` path; nothing here talks to that path.
 */

/** @const {!Set<string>} Mime types `record` (the client's recorder package)
 * can emit, plus a few common container/codec variants. */
const ALLOWED_MIME_TYPES = new Set([
  "audio/m4a", "audio/x-m4a", "audio/mp4", "audio/aac",
  "audio/wav", "audio/x-wav", "audio/webm", "audio/ogg", "audio/mpeg",
]);

/** @const {!Object<string, string>} normalized mime type → upload filename. */
const FILENAME_BY_MIME = {
  "audio/m4a": "audio.m4a",
  "audio/x-m4a": "audio.m4a",
  "audio/mp4": "audio.mp4",
  "audio/aac": "audio.aac",
  "audio/wav": "audio.wav",
  "audio/x-wav": "audio.wav",
  "audio/webm": "audio.webm",
  "audio/ogg": "audio.ogg",
  "audio/mpeg": "audio.mp3",
};

// Cost/abuse control, not a technical ceiling — a voice note for a chat
// composer is seconds long. Well under OpenAI's own 25MB upload limit.
const MAX_AUDIO_BYTES = 15 * 1024 * 1024;

// Error codes a provider adapter may legitimately raise (via `err.code`) for
// a call that reached it — anything else from the provider is treated as an
// opaque `transcription_failed`. Validation failures (`invalid-argument`,
// `unsupported_audio_format`, `audio_too_large`) are raised by this module
// itself, before the provider is ever called.
const KNOWN_PROVIDER_ERROR_CODES = new Set([
  "transcription_failed", "provider_unavailable", "timeout",
]);

/**
 * An error `transcribeAudio` throws for problems the caller (the `aiTranscribe`
 * `onCall` handler) should surface as a typed failure. Mirrors
 * `../gateway.js`'s `GatewayError`, but `code` is one of this module's own
 * STT-specific codes, not a raw gRPC/`HttpsError` code — the caller maps
 * `code` to both an `HttpsError` code and a wire-carried detail so the client
 * can reconstruct the exact failure reason.
 */
class SpeechError extends Error {
  /**
   * @param {string} code One of `"invalid-argument"`,
   *   `"unsupported_audio_format"`, `"audio_too_large"`,
   *   `"transcription_failed"`, `"provider_unavailable"`, `"timeout"`.
   * @param {string} message
   */
  constructor(code, message) {
    super(message);
    this.name = "SpeechError";
    this.code = code;
  }
}

/**
 * @param {*} mimeType
 * @return {string} The mime type, lowercased with any `;codecs=...`
 *   parameter stripped, or `""` if `mimeType` isn't a string.
 */
function normalizeMimeType(mimeType) {
  if (typeof mimeType !== "string") return "";
  return mimeType.split(";")[0].trim().toLowerCase();
}

/**
 * Transcribes one audio clip: validates it (mime allowlist, size cap, base64
 * decoding) BEFORE calling the provider, then maps the provider's response
 * (or failure) into a plain `{text, detectedLanguage, durationMs}` result —
 * never a provider-native object, never anything beyond text.
 *
 * @param {!Object} args
 * @param {!Object} args.provider A `SpeechToTextProvider`-shaped instance
 *   (`{transcribe(normalizedRequest)}`) — production wiring
 *   (`functions/index.js`) injects a router-backed one.
 * @param {string} args.audioBase64 The audio's bytes, base64-encoded.
 * @param {string} args.mimeType The audio's mime type, as recorded client-side.
 * @param {string=} args.languageHint Forwarded to the provider only when
 *   explicitly given — absent by default so code-switched speech isn't
 *   forced into one language.
 * @param {function(!Object): void} [args.logEvent] Optional observability
 *   sink — called once per attempt with `{bytes, latencyMs, durationMs,
 *   success, code}`. Never carries raw audio or the transcript itself (only
 *   its length would be safe to add, and even that isn't logged here — see
 *   the module doc). Defaults to a no-op.
 * @return {!Promise<{text: string, detectedLanguage: (string|undefined),
 *   durationMs: (number|undefined)}>}
 */
async function transcribeAudio({
  provider, audioBase64, mimeType, languageHint, logEvent = () => {},
}) {
  if (typeof audioBase64 !== "string" || audioBase64.trim() === "") {
    throw new SpeechError("invalid-argument", "Audio is required.");
  }

  const normalizedMime = normalizeMimeType(mimeType);
  if (!ALLOWED_MIME_TYPES.has(normalizedMime)) {
    throw new SpeechError(
        "unsupported_audio_format", "That audio format isn't supported.");
  }

  let audio;
  try {
    audio = Buffer.from(audioBase64, "base64");
  } catch (err) {
    throw new SpeechError(
        "invalid-argument", err.message || "Audio could not be decoded.");
  }
  if (audio.length === 0) {
    throw new SpeechError("invalid-argument", "Audio is required.");
  }
  if (audio.length > MAX_AUDIO_BYTES) {
    throw new SpeechError(
        "audio_too_large", "That recording is too long — try a shorter clip.");
  }

  const normalizedRequest = {
    audio,
    mimeType: normalizedMime,
    filename: FILENAME_BY_MIME[normalizedMime],
    languageHint: typeof languageHint === "string" && languageHint.trim() ?
      languageHint.trim() : undefined,
  };

  const startedAt = Date.now();
  let response;
  try {
    response = await provider.transcribe(normalizedRequest);
  } catch (err) {
    const code = err && KNOWN_PROVIDER_ERROR_CODES.has(err.code) ?
      err.code : "transcription_failed";
    logEvent({
      bytes: audio.length,
      latencyMs: Date.now() - startedAt,
      success: false,
      code,
      // The provider's own error text (never audio or a transcript) — the one
      // thing that says *why* a provider rejected the clip, e.g. an
      // unsupported mime type or a bad key. Safe to log.
      errorMessage: (err && err.message) || undefined,
    });
    throw new SpeechError(
        code,
        (err && err.message) ||
        "Couldn't transcribe that audio. Please try again.");
  }

  if (!response || typeof response.text !== "string") {
    logEvent({
      bytes: audio.length,
      latencyMs: Date.now() - startedAt,
      success: false,
      code: "transcription_failed",
    });
    throw new SpeechError(
        "transcription_failed",
        "Couldn't transcribe that audio. Please try again.");
  }

  logEvent({
    bytes: audio.length,
    latencyMs: Date.now() - startedAt,
    durationMs: response.durationMs,
    success: true,
  });

  return {
    text: response.text,
    detectedLanguage: response.detectedLanguage,
    durationMs: response.durationMs,
  };
}

module.exports = {
  transcribeAudio,
  SpeechError,
  ALLOWED_MIME_TYPES,
  MAX_AUDIO_BYTES,
};
