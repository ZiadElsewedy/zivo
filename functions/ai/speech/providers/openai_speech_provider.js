/**
 * The only real `SpeechToTextProvider` adapter: translates a ZIVO
 * `NormalizedSttRequest` into an OpenAI audio-transcriptions call and an
 * OpenAI response back into a `NormalizedSttResponse`.
 *
 * Free of the `openai` package — the client is injected as a single
 * `transcribe({buffer, filename, mimeType, model, language}) =>
 * Promise<{text, language?, duration?}>` seam, so this is
 * `node --test`-able with a plain fake. `functions/index.js` builds the real
 * seam around `OpenAI.toFile(...)` + `openai.audio.transcriptions.create()`.
 *
 * Uses the **transcriptions** endpoint, never translations: by default no
 * `language` is passed, so code-switched Arabic/English (and English fitness
 * terms inside otherwise-Arabic speech) come back verbatim rather than being
 * forced into a single target language. `language` is only ever forwarded
 * when the caller explicitly supplies a `languageHint`.
 */

const {SpeechToTextProvider} = require("./speech_provider");

/** @const {!Object<string, string>} mime type → a plausible upload filename. */
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

/** @const {string} */
const DEFAULT_MODEL = "gpt-4o-mini-transcribe";

/**
 * Classifies a seam failure into one of the STT typed error codes
 * (`../gateway.js`'s `SpeechError` codes), duck-typing on the OpenAI SDK
 * error shape (`status`, `constructor.name`) rather than importing it.
 * @param {*} err
 * @return {!Error} An `Error` with a `.code` of `"timeout"`,
 *   `"provider_unavailable"`, or `"transcription_failed"`.
 */
function classifyError(err) {
  const status = err && typeof err.status === "number" ? err.status : undefined;
  const ctorName = err && err.constructor && err.constructor.name;
  let code;
  if (ctorName === "APIConnectionTimeoutError") {
    code = "timeout";
  } else if (status === undefined || status >= 500 || status === 429) {
    // No HTTP status at all means the request never got a response
    // (connection refused/reset/DNS failure) — same bucket as a 5xx/rate
    // limit: the provider itself is the problem, not the audio.
    code = "provider_unavailable";
  } else {
    // A 4xx other than 429: OpenAI rejected the request itself (e.g.
    // unreadable/corrupt audio content) — the recording is the problem.
    code = "transcription_failed";
  }
  const tagged = new Error((err && err.message) || "Transcription failed.");
  tagged.code = code;
  return tagged;
}

/**
 * The OpenAI `SpeechToTextProvider` adapter.
 */
class OpenAiSpeechProvider extends SpeechToTextProvider {
  /**
   * @param {{transcribe: function({buffer:!Buffer, filename:string,
   *   mimeType:string, model:string, language:(string|undefined)}):
   *   !Promise<{text:string, language:(string|undefined),
   *   duration:(number|undefined)}>}} client
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
    const filename = normalizedRequest.filename ||
      FILENAME_BY_MIME[normalizedRequest.mimeType] || "audio";

    let raw;
    try {
      raw = await this._client.transcribe({
        buffer: normalizedRequest.audio,
        filename,
        mimeType: normalizedRequest.mimeType,
        model: normalizedRequest.model || DEFAULT_MODEL,
        language: normalizedRequest.languageHint || undefined,
      });
    } catch (err) {
      throw classifyError(err);
    }

    if (!raw || typeof raw.text !== "string") {
      const empty = new Error("The transcription came back empty.");
      empty.code = "transcription_failed";
      throw empty;
    }

    return {
      text: raw.text,
      detectedLanguage: typeof raw.language === "string" && raw.language ?
        raw.language : undefined,
      durationMs: typeof raw.duration === "number" ?
        Math.round(raw.duration * 1000) : undefined,
      raw,
    };
  }
}

module.exports = {OpenAiSpeechProvider, classifyError, DEFAULT_MODEL};
