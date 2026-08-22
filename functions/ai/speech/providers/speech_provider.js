/**
 * The `SpeechToTextProvider` contract and the ZIVO-owned normalized STT
 * request/response shape every STT adapter speaks.
 *
 * Speech-to-text is a SEPARATE capability from the LLM stack
 * (`../../providers/provider.js`'s `AiProvider`) — a `SpeechToTextProvider`
 * is `.transcribe(normalizedRequest)`-shaped, not `.generate(...)`-shaped,
 * and nothing here is wired into `../../routing/router.js` or the chat/
 * workout-import gateways. The two stacks share only the generic
 * `../../providers/registry.js` `ProviderRegistry` (name → instance is
 * capability-agnostic), each with its own router.
 */

/**
 * @typedef {Object} NormalizedSttRequest
 * @property {!Buffer} audio The raw audio bytes.
 * @property {string} mimeType e.g. `"audio/m4a"`.
 * @property {string=} languageHint A BCP-47/ISO-639-1 language code. Omit to
 *   let the provider auto-detect (needed for code-switched speech) — never
 *   pass this "just in case", only when the caller genuinely knows the
 *   language.
 * @property {string=} filename A filename hint (extension matters to some
 *   provider SDKs' multipart upload; content is what actually gets read).
 * @property {string=} model Provider-native model id. Stamped on by
 *   `../routing/speech_router.js` from its capability table.
 */

/**
 * @typedef {Object} NormalizedSttResponse
 * @property {string} text The transcript. Never provider-native shape —
 *   plain text only.
 * @property {string=} detectedLanguage The provider's own guess at the
 *   spoken language, if it reports one.
 * @property {number=} durationMs The audio's duration, if the provider
 *   reports one.
 * @property {*=} raw The full provider-native response, for anything a
 *   normalized reader doesn't cover. Never leaked past the adapter into
 *   `../gateway.js`'s return value.
 */

/**
 * The contract every STT adapter implements. Duck-typed — nothing checks
 * `instanceof SpeechToTextProvider`; the base class only documents the shape.
 */
class SpeechToTextProvider {
  /**
   * Resolves to a `NormalizedSttResponse`.
   * @param {!NormalizedSttRequest} normalizedRequest
   */
  transcribe(normalizedRequest) { // eslint-disable-line no-unused-vars
    throw new Error("SpeechToTextProvider.transcribe is not implemented.");
  }
}

module.exports = {SpeechToTextProvider};
