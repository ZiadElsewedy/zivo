/**
 * The `AiProvider` contract and the ZIVO-owned NormalizedRequest/
 * NormalizedResponse shape that every provider adapter speaks. Adding a
 * second real provider means writing one new adapter file (implementing
 * `generate`) plus one row in `../routing/router.js` — nothing else in
 * `../gateway.js` or `../services/workout_import.js` should need to change.
 *
 * Anthropic's own content-block vocabulary (`text`, `tool_use`, `thinking`,
 * …) is deliberately reused as the normalized content-block `type` rather
 * than invented anew — it's already provider-agnostic in shape, and every
 * block carries a `raw` escape hatch (see `NormalizedContentBlock` below) so
 * fields a normalized reader doesn't know about (e.g. a signed `thinking`
 * block's `signature`) still round-trip losslessly back into the next
 * request's history.
 */

/**
 * @typedef {Object} NormalizedUsage
 * @property {number} inputTokens Non-cached input tokens for this call.
 * @property {number} outputTokens
 * @property {number} cacheReadTokens
 * @property {number} cacheWriteTokens
 */

/**
 * @typedef {Object} NormalizedContentBlock
 * @property {string} type Provider-native block type (e.g. `"text"`,
 *   `"tool_use"`, `"thinking"`). Convenience fields below are mirrored from
 *   the provider's own block for the common cases; anything else lives on
 *   `raw`.
 * @property {string=} text Present on `type: "text"`.
 * @property {string=} id Present on `type: "tool_use"` (the tool-call id).
 * @property {string=} name Present on `type: "tool_use"` (the tool name).
 * @property {!Object=} input Present on `type: "tool_use"`.
 * @property {string=} thinking Present on `type: "thinking"`.
 * @property {*} raw The exact provider-native block. Callers that need to
 *   round-trip assistant content back into a later request's message history
 *   (e.g. to preserve a signed `thinking` block's signature) should pass
 *   `raw` through a `NormalizedRawPart` rather than reconstruct the block
 *   from the convenience fields above.
 */

/**
 * @typedef {Object} NormalizedResponse
 * @property {string} stopReason One of `"tool_use"`, `"end"`, `"refusal"`,
 *   `"max_tokens"`, `"other"`.
 * @property {!Array<!NormalizedContentBlock>} content
 * @property {!NormalizedUsage} usage
 * @property {*} raw The full provider-native response, for anything a
 *   normalized reader doesn't cover.
 */

/**
 * @typedef {Object} NormalizedSystemBlock
 * @property {string} text
 * @property {string=} cache Set to `"ephemeral"` to mark this block as a
 *   prompt-caching breakpoint.
 */

/**
 * @typedef {Object} NormalizedTool
 * @property {string} name
 * @property {string} description
 * @property {!Object} inputSchema
 * @property {boolean=} strict
 */

/**
 * @typedef {Object} NormalizedTextPart
 * @property {string} type `"text"`.
 * @property {string} text
 */

/**
 * @typedef {Object} NormalizedDocumentPart
 * @property {string} type `"document"`.
 * @property {string} mediaType e.g. `"application/pdf"`.
 * @property {string} dataBase64
 */

/**
 * @typedef {Object} NormalizedToolResultPart
 * @property {string} type `"tool_result"`.
 * @property {string} toolUseId
 * @property {string} content
 * @property {boolean=} isError
 */

/**
 * @typedef {Object} NormalizedRawPart
 * @property {string} type `"raw"`.
 * @property {*} raw A provider-native content block, passed through to the
 *   wire request unchanged. This is the round-trip escape hatch: build one
 *   from a `NormalizedContentBlock.raw` to re-send a prior assistant turn.
 */

/**
 * @typedef {Object} NormalizedMessage
 * @property {string} role `"user"` or `"assistant"`.
 * @property {(string|!Array<(!NormalizedTextPart|!NormalizedDocumentPart|
 *   !NormalizedToolResultPart|!NormalizedRawPart)>)} content
 */

/**
 * @typedef {Object} NormalizedRequest
 * @property {string=} model Provider-native model id. The router fills this
 *   in from its capability table; callers that build a provider directly may
 *   also set it explicitly.
 * @property {number} maxTokens
 * @property {!Array<!NormalizedSystemBlock>=} system
 * @property {!Array<!NormalizedTool>=} tools
 * @property {('auto'|'any'|'none'|{type: string, name: string})=} toolChoice
 *   Omit for the provider's default (Anthropic: `auto`). `none` keeps the
 *   tools declared but forbids calling one — the chat loop's final step.
 * @property {!Array<!NormalizedMessage>} messages
 * @property {string=} modelKey A catalog key (`../routing/models.js`) the
 *   server's reasoning policy picked for this request. The router honours it
 *   only for a model of the user's own provider; otherwise it's ignored.
 * @property {('low'|'medium'|'high')=} reasoning The policy's reasoning
 *   level. The provider turns it into the answering model's own setting
 *   (`ModelSpec.reasoning`: effort + thinking together); omit for the API
 *   defaults. Anthropic only; Gemini ignores it.
 * @property {string=} cacheTail Set to `"ephemeral"` to add a prompt-caching
 *   breakpoint on the last message's last block, so a follow-up call that
 *   re-sends this conversation reads it back from cache (the chat loop's
 *   tool steps). Anthropic only; Gemini ignores it, as it does `cache`.
 * @property {{googleSearch: boolean}=} grounding Gemini-only: set
 *   `{googleSearch: true}` to ground the reply in a live Google Search instead
 *   of declaring function-calling tools. Gemini does not support combining
 *   search grounding with `tools`/`toolChoice` in the same call, so a request
 *   with `grounding` set must not also set `tools` — see
 *   `../providers/gemini_provider.js`'s `toGeminiRequest`. Anthropic has no
 *   equivalent and never receives this field in practice (see
 *   `../routing/router.js`'s `food_search` capability, which has no
 *   Anthropic route).
 */

/**
 * The contract every provider adapter implements. Duck-typed — nothing in
 * `../gateway.js`/`../services/workout_import.js`/`../routing/router.js` checks
 * `instanceof AiProvider`, so a provider only needs to expose a matching
 * `generate` method. The base class exists purely to document the contract
 * in one place.
 */
class AiProvider {
  /**
   * `onText`, when given on `opts`, is the streaming sink for text deltas;
   * when absent the call is buffered and resolves once with the full
   * response.
   * @param {!NormalizedRequest} normalizedRequest
   * @param {{onText: (function(string): void)}=} opts
   */
  generate(normalizedRequest, opts = {}) { // eslint-disable-line no-unused-vars
    throw new Error("AiProvider.generate is not implemented.");
  }
}

module.exports = {AiProvider};
