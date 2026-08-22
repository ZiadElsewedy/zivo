/**
 * The Gemini `SpeechToTextProvider` adapter: translates a ZIVO
 * `NormalizedSttRequest` into a Gemini `generateContent` call carrying the
 * audio as an inline part plus a transcription instruction, and the Gemini
 * response back into a `NormalizedSttResponse`.
 *
 * Free of the `@google/genai` package — the client is injected as a single
 * `transcribe({buffer, mimeType, model, prompt}) => Promise<{text}>` seam, so
 * this is `node --test`-able with a plain fake. `functions/index.js` builds
 * the real seam around `ai.models.generateContent(...)` with an
 * `inlineData` audio part.
 *
 * Gemini has no dedicated transcription endpoint — transcription is a
 * multimodal `generateContent` call, so unlike OpenAI's Whisper-family
 * endpoint it reports neither a detected language nor an audio duration; both
 * come back `undefined` on the normalized response (they're optional there).
 *
 * The prompt is owned here (not the seam), because "transcribe verbatim,
 * preserve code-switching, output only the transcript" is ZIVO-normalized
 * behaviour — the counterpart of the OpenAI adapter deliberately using the
 * transcriptions endpoint and only forwarding `language` when explicitly
 * given, so code-switched Arabic/English (and English fitness terms inside
 * otherwise-Arabic speech) come back verbatim rather than translated.
 */

const {SpeechToTextProvider} = require("./speech_provider");

/** @const {string} */
const DEFAULT_MODEL = "gemini-2.5-flash";

/**
 * The base transcription instruction. Verbatim, language-preserving, and
 * transcript-only — no preamble, no commentary, no translation.
 * @const {string}
 */
const BASE_PROMPT =
  "Transcribe the following audio exactly as spoken. Preserve the original " +
  "language or languages verbatim, including any code-switching between " +
  "languages within the recording — do not translate. Output only the " +
  "transcript text itself, with no preamble, quotation marks, or commentary. " +
  "If the audio contains no discernible speech, output nothing.";

/**
 * Builds the transcription prompt, appending a soft language hint only when
 * the caller explicitly supplied one. The hint is advisory — the audio is
 * still transcribed verbatim, so a code-switched clip isn't forced into the
 * hinted language.
 * @param {string=} languageHint A BCP-47/ISO-639-1 code, or undefined.
 * @return {string}
 */
function buildPrompt(languageHint) {
  if (typeof languageHint === "string" && languageHint.trim()) {
    return `${BASE_PROMPT} The speech is primarily in "${languageHint.trim()}",` +
      " but transcribe any other languages present verbatim as well.";
  }
  return BASE_PROMPT;
}

/**
 * Classifies a seam failure into one of the STT typed error codes
 * (`../gateway.js`'s `SpeechError` codes), duck-typing on the `@google/genai`
 * SDK error shape (`status`, `name`/`constructor.name`) rather than importing
 * it.
 * @param {*} err
 * @return {!Error} An `Error` with a `.code` of `"timeout"`,
 *   `"provider_unavailable"`, or `"transcription_failed"`.
 */
function classifyError(err) {
  const status = err && typeof err.status === "number" ? err.status : undefined;
  const name = (err && (err.name || (err.constructor && err.constructor.name))) || "";
  let code;
  if (name === "AbortError" || /timeout/i.test(name) ||
      /tim(e|ed) ?out/i.test((err && err.message) || "")) {
    // A client-side deadline (fetch abort) or an SDK-reported timeout: the
    // request never got an answer in time.
    code = "timeout";
  } else if (status === undefined || status >= 500 || status === 429) {
    // No HTTP status at all means the request never got a response
    // (connection refused/reset/DNS failure) — same bucket as a 5xx/rate
    // limit: the provider itself is the problem, not the audio.
    code = "provider_unavailable";
  } else {
    // A 4xx other than 429: Gemini rejected the request itself (e.g.
    // unreadable/corrupt audio, or an unsupported mime type) — the recording
    // is the problem.
    code = "transcription_failed";
  }
  const tagged = new Error((err && err.message) || "Transcription failed.");
  tagged.code = code;
  return tagged;
}

/**
 * The Gemini `SpeechToTextProvider` adapter.
 */
class GeminiSpeechProvider extends SpeechToTextProvider {
  /**
   * @param {{transcribe: function({buffer:!Buffer, mimeType:string,
   *   model:string, prompt:string}):
   *   !Promise<{text:string}>}} client
   */
  constructor(client) {
    super();
    this._client = client;
  }

  /**
   * @param {!Object} normalizedRequest
   * @return {!Promise<!Object>}
   * @override
   */
  async transcribe(normalizedRequest) {
    let raw;
    try {
      raw = await this._client.transcribe({
        buffer: normalizedRequest.audio,
        mimeType: normalizedRequest.mimeType,
        model: normalizedRequest.model || DEFAULT_MODEL,
        prompt: buildPrompt(normalizedRequest.languageHint),
      });
    } catch (err) {
      throw classifyError(err);
    }

    // A blocked/empty Gemini response (safety filter, no discernible speech)
    // surfaces as a missing/whitespace-only `text` — the audio is the problem.
    const text = raw && typeof raw.text === "string" ? raw.text.trim() : "";
    if (!text) {
      const empty = new Error("The transcription came back empty.");
      empty.code = "transcription_failed";
      throw empty;
    }

    return {
      // Gemini reports neither a detected language nor a duration.
      text,
      detectedLanguage: undefined,
      durationMs: undefined,
      raw,
    };
  }
}

module.exports = {
  GeminiSpeechProvider,
  classifyError,
  buildPrompt,
  DEFAULT_MODEL,
  BASE_PROMPT,
};
