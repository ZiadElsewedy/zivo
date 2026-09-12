/**
 * The Gemini `AiProvider` adapter: translates a ZIVO `NormalizedRequest`
 * (see `./provider.js`) into a Gemini `generateContent` call and the Gemini
 * response back into a `NormalizedResponse`. It is the second real provider,
 * added exactly the way `./provider.js`/`../routing/router.js` were designed
 * for — one new adapter file plus one route entry, nothing in `../chat/turn.js`
 * changes.
 *
 * Free of the `@google/genai` package — the client is injected as the same
 * `{models: {generateContent, generateContentStream}}` shape a real
 * `GoogleGenAI` instance exposes (so `functions/index.js` passes the real
 * client straight through, and `node --test` passes a plain fake). This
 * mirrors how `./anthropic_provider.js` takes an SDK-shaped
 * `{messages:{create,stream}}` client.
 *
 * Provider-specific differences that this adapter reconciles (all documented at
 * the point they're handled below):
 *   - Gemini has no dedicated cache-control on system blocks — it does implicit
 *     caching — so the normalized `cache: 'ephemeral'` breakpoints are dropped.
 *   - Gemini matches a tool result to its call by function NAME (+ id on newer
 *     API), not by an opaque `tool_use_id`, so this adapter correlates the two.
 *   - Gemini's tool schema is an OpenAPI-3.0 subset, not full JSON Schema, so a
 *     few unsupported keywords are stripped before the tools are sent.
 *   - Gemini reports no separate "tool_use" stop reason — a turn that wants a
 *     tool simply returns `functionCall` parts with `finishReason: STOP`, so
 *     the stop reason is derived from the parts, not the finish reason.
 */

const {AiProvider} = require("./provider");

/**
 * A rolling alias fallback if a route somehow resolves without a model. The
 * real model comes from `../routing/router.js`'s capability table.
 * @const {string}
 */
const DEFAULT_MODEL = "gemini-2.5-pro";

/**
 * JSON-Schema keywords Gemini's function-declaration schema (an OpenAPI 3.0
 * subset) rejects. Stripped recursively so a ZIVO tool schema written for
 * Anthropic (which accepts full JSON Schema) doesn't 400 the Gemini request.
 * @const {!Array<string>}
 */
const UNSUPPORTED_SCHEMA_KEYS = [
  "$schema", "$id", "$ref", "$defs", "definitions", "additionalProperties",
  "patternProperties", "const", "examples", "default",
];

/**
 * Recursively copies a JSON Schema, dropping the keywords Gemini can't parse.
 * @param {*} schema
 * @return {*}
 */
function sanitizeSchema(schema) {
  if (Array.isArray(schema)) return schema.map(sanitizeSchema);
  if (!schema || typeof schema !== "object") return schema;
  const out = {};
  for (const [key, value] of Object.entries(schema)) {
    if (UNSUPPORTED_SCHEMA_KEYS.includes(key)) continue;
    out[key] = sanitizeSchema(value);
  }
  return out;
}

/**
 * @param {!Object} tool A `NormalizedTool`.
 * @return {!Object} A Gemini `FunctionDeclaration`.
 */
function toGeminiFunctionDeclaration(tool) {
  return {
    name: tool.name,
    description: tool.description,
    parameters: sanitizeSchema(tool.inputSchema),
  };
}

/**
 * @param {(string|{type: string, name: string}|undefined)} toolChoice
 * @return {(!Object|undefined)} A Gemini `toolConfig`, or undefined for the
 *   provider default (AUTO).
 */
function toGeminiToolConfig(toolChoice) {
  if (toolChoice === undefined) return undefined;
  if (toolChoice === "auto") {
    return {functionCallingConfig: {mode: "AUTO"}};
  }
  if (toolChoice === "any") {
    return {functionCallingConfig: {mode: "ANY"}};
  }
  // {type: 'tool'|'function', name}: force exactly this one function.
  return {
    functionCallingConfig: {mode: "ANY", allowedFunctionNames: [toolChoice.name]},
  };
}

/**
 * Parses a tool-result's JSON string content back into the object Gemini's
 * `functionResponse.response` expects. Falls back to wrapping a non-JSON
 * string so a result is never lost.
 * @param {string} content
 * @param {boolean=} isError
 * @return {!Object}
 */
function toFunctionResponsePayload(content, isError) {
  let parsed;
  try {
    parsed = JSON.parse(content);
  } catch (_e) {
    parsed = {result: content};
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    parsed = {result: parsed};
  }
  return isError ? {error: parsed} : parsed;
}

/**
 * True when a round-tripped `raw` block is already a Gemini-native content
 * part (as opposed to an Anthropic-native block that needs translating).
 * @param {*} raw
 * @return {boolean}
 */
function isGeminiPart(raw) {
  return Boolean(raw && typeof raw === "object" &&
    (raw.functionCall || raw.functionResponse || raw.inlineData ||
      (raw.text !== undefined && raw.type === undefined)));
}

/**
 * Translates one normalized message-content part into its Gemini shape.
 * Returns `null` for a part that has no Gemini equivalent (e.g. an Anthropic
 * `thinking` block being round-tripped to Gemini), which the caller filters
 * out.
 * @param {(string|!Object)} part
 * @param {!Map<string, string>} nameByToolId call-id → function-name, for
 *   turning a `tool_result` into a `functionResponse` Gemini can match.
 * @return {(!Object|null)}
 */
function toGeminiPart(part, nameByToolId) {
  if (part && part.type === "text") return {text: part.text};
  if (part && (part.type === "document" || part.type === "image")) {
    return {inlineData: {mimeType: part.mediaType, data: part.dataBase64}};
  }
  if (part && part.type === "tool_result") {
    return {
      functionResponse: {
        id: part.toolUseId,
        name: nameByToolId.get(part.toolUseId) || part.toolUseId,
        response: toFunctionResponsePayload(part.content, part.isError),
      },
    };
  }
  if (part && part.type === "raw") {
    const raw = part.raw;
    // A prior Gemini turn's own part round-tripping straight back.
    if (isGeminiPart(raw)) return raw;
    // An Anthropic-native block being re-sent to Gemini (a mid-turn fallback
    // from Claude to Gemini). Translate the two shapes that carry meaning; a
    // `thinking`/`redacted_thinking` block has no Gemini equivalent and is
    // dropped (thoughts don't round-trip across providers).
    if (raw && raw.type === "text") return {text: raw.text};
    if (raw && raw.type === "tool_use") {
      return {
        functionCall: {id: raw.id, name: raw.name, args: raw.input || {}},
      };
    }
    return null;
  }
  throw new Error(`Unsupported normalized content part type: ${part && part.type}`);
}

/**
 * @param {!Object} message A `NormalizedMessage`.
 * @param {!Map<string, string>} nameByToolId
 * @return {!Object} A Gemini `Content` (`{role, parts}`).
 */
function toGeminiContent(message, nameByToolId) {
  // Gemini's assistant role is "model"; "user" is shared.
  const role = message.role === "assistant" ? "model" : "user";
  if (typeof message.content === "string") {
    return {role, parts: [{text: message.content}]};
  }
  const parts = message.content
      .map((p) => toGeminiPart(p, nameByToolId))
      .filter((p) => p !== null);
  return {role, parts};
}

/**
 * Scans every message for tool CALLS so a later tool RESULT can be matched to
 * its function name (Gemini keys `functionResponse` by name, not by the opaque
 * id ZIVO's normalized `tool_result` carries). Covers both a Gemini-native
 * round-tripped `functionCall` and an Anthropic-native `tool_use` block, so
 * name resolution survives a mid-turn Claude→Gemini fallback.
 * @param {!Array<!Object>} messages
 * @return {!Map<string, string>} call-id → function-name.
 */
function buildToolNameMap(messages) {
  const map = new Map();
  for (const message of messages) {
    if (!Array.isArray(message.content)) continue;
    for (const part of message.content) {
      if (!part || part.type !== "raw") continue;
      const raw = part.raw;
      if (raw && raw.functionCall && raw.functionCall.id) {
        map.set(raw.functionCall.id, raw.functionCall.name);
      } else if (raw && raw.type === "tool_use" && raw.id) {
        map.set(raw.id, raw.name);
      }
    }
  }
  return map;
}

/**
 * @param {!Object} normalizedRequest
 * @return {!Object} A Gemini `generateContent` request (`{model, contents,
 *   config}`).
 */
function toGeminiRequest(normalizedRequest) {
  const nameByToolId = buildToolNameMap(normalizedRequest.messages);
  const contents = normalizedRequest.messages.map(
      (m) => toGeminiContent(m, nameByToolId));

  const config = {maxOutputTokens: normalizedRequest.maxTokens};

  if (normalizedRequest.system && normalizedRequest.system.length > 0) {
    // Gemini has one systemInstruction, not per-block cache breakpoints — join
    // the blocks and drop `cache` (Gemini caches implicitly).
    config.systemInstruction = normalizedRequest.system
        .map((b) => b.text)
        .join("\n\n");
  }
  if (normalizedRequest.tools && normalizedRequest.tools.length > 0) {
    config.tools = [{
      functionDeclarations:
        normalizedRequest.tools.map(toGeminiFunctionDeclaration),
    }];
  }
  const toolConfig = toGeminiToolConfig(normalizedRequest.toolChoice);
  if (toolConfig !== undefined) config.toolConfig = toolConfig;

  return {model: normalizedRequest.model || DEFAULT_MODEL, contents, config};
}

/** @const {!Object<string, string>} Gemini finishReason → normalized. */
const FINISH_REASON_MAP = {
  STOP: "end",
  MAX_TOKENS: "max_tokens",
  SAFETY: "refusal",
  RECITATION: "refusal",
  PROHIBITED_CONTENT: "refusal",
  BLOCKLIST: "refusal",
  SPII: "refusal",
  IMAGE_SAFETY: "refusal",
};

/**
 * @param {!Array<!Object>} parts The candidate's content parts.
 * @param {?string} finishReason
 * @param {?Object} promptFeedback
 * @return {string} Normalized stop reason.
 */
function normalizeStopReason(parts, finishReason, promptFeedback) {
  // Gemini signals a tool turn by returning functionCall parts, NOT by a
  // distinct finishReason — so the parts decide first.
  if (parts.some((p) => p && p.functionCall)) return "tool_use";
  // A prompt blocked before any candidate was produced is a refusal.
  if (promptFeedback && promptFeedback.blockReason) return "refusal";
  if (!finishReason) return "other";
  return FINISH_REASON_MAP[finishReason] || "other";
}

/**
 * @param {?Object} usageMetadata A Gemini `usageMetadata` (may be absent).
 * @return {!Object} `NormalizedUsage`.
 */
function normalizeUsage(usageMetadata) {
  const u = usageMetadata || {};
  const cached = u.cachedContentTokenCount || 0;
  const prompt = u.promptTokenCount || 0;
  return {
    // Anthropic's `inputTokens` is the NON-cached input; Gemini's prompt count
    // includes the cached slice, so subtract it out to keep the accounting
    // consistent across providers (`../chat/usage.js` sums the two back).
    inputTokens: Math.max(0, prompt - cached),
    // Thinking tokens (2.5 models) are billed as output.
    outputTokens: (u.candidatesTokenCount || 0) + (u.thoughtsTokenCount || 0),
    cacheReadTokens: cached,
    // Gemini caches implicitly — there is no separate cache-write bucket.
    cacheWriteTokens: 0,
  };
}

/**
 * Wraps a Gemini content part as a `NormalizedContentBlock`. A `functionCall`
 * becomes a `tool_use` block; ZIVO's turn loop keys a tool result off
 * `block.id`, so a synthetic id is stamped when Gemini didn't supply one — and
 * mirrored into `raw` so the id round-trips into the next request's history
 * (where `buildToolNameMap` reads it back).
 * @param {!Object} part
 * @param {number} index Position of this part, for a stable synthetic id.
 * @return {!Object} `NormalizedContentBlock`.
 */
function normalizeContentBlock(part, index) {
  if (part && part.functionCall) {
    const fc = part.functionCall;
    const id = fc.id || `gemini-tool-${index}`;
    const rawWithId = Object.assign({}, part, {
      functionCall: Object.assign({}, fc, {id}),
    });
    return {
      type: "tool_use",
      id,
      name: fc.name,
      input: fc.args || {},
      raw: rawWithId,
    };
  }
  if (part && typeof part.text === "string") {
    return {type: "text", text: part.text, raw: part};
  }
  // Anything else (e.g. an inlineData part in a reply) round-trips via `raw`.
  return {type: (part && part.type) || "other", raw: part};
}

/**
 * @param {!Object} raw A Gemini `GenerateContentResponse` (or a synthetic one
 *   assembled from a stream — same shape).
 * @return {!Object} `NormalizedResponse`.
 */
function toNormalizedResponse(raw) {
  const candidate = raw && raw.candidates && raw.candidates[0];
  const parts =
    (candidate && candidate.content && candidate.content.parts) || [];
  const finishReason = candidate && candidate.finishReason;
  const promptFeedback = raw && raw.promptFeedback;
  return {
    stopReason: normalizeStopReason(parts, finishReason, promptFeedback),
    content: parts.map(normalizeContentBlock),
    usage: normalizeUsage(raw && raw.usageMetadata),
    raw,
  };
}

/**
 * The Gemini `AiProvider` adapter.
 */
class GeminiProvider extends AiProvider {
  /**
   * @param {!Object} client A `GoogleGenAI`-shaped client — it must expose
   *   `models.generateContent(req)` and, for streaming, an optional
   *   `models.generateContentStream(req)` returning an async iterable.
   */
  constructor(client) {
    super();
    this._client = client;
  }

  /**
   * `opts.onText` streams assistant TEXT deltas — the chat path. Gemini's
   * streaming yields partial `GenerateContentResponse` chunks; this
   * accumulates their text (and any functionCall parts) into a single final
   * response so the caller gets the same normalized shape either way. A client
   * without `generateContentStream`, or a buffered call (no `onText`), takes
   * the plain `generateContent` path.
   *
   * (`onInputJson`, the importers' partial-tool-input progress sink, is not
   * emitted here — Gemini fallback is wired for the `chat` capability only;
   * see `../routing/router.js`. A future import route would degrade to
   * buffered progress, exactly as the Anthropic adapter degrades a client
   * without `stream`.)
   * @param {!Object} normalizedRequest
   * @param {{onText: (function(string): void)}=} opts
   * @return {!Promise<!Object>}
   * @override
   */
  async generate(normalizedRequest, opts = {}) {
    const geminiReq = toGeminiRequest(normalizedRequest);
    const wantsText = typeof opts.onText === "function";
    const canStream =
      typeof this._client.models.generateContentStream === "function";

    if (wantsText && canStream) {
      const stream = await this._client.models.generateContentStream(geminiReq);
      const parts = [];
      let finishReason;
      let usageMetadata;
      let promptFeedback;
      for await (const chunk of stream) {
        const candidate = chunk && chunk.candidates && chunk.candidates[0];
        const chunkParts =
          (candidate && candidate.content && candidate.content.parts) || [];
        for (const part of chunkParts) {
          if (part && typeof part.text === "string") {
            opts.onText(part.text);
          }
          parts.push(part);
        }
        if (candidate && candidate.finishReason) {
          finishReason = candidate.finishReason;
        }
        if (chunk && chunk.usageMetadata) usageMetadata = chunk.usageMetadata;
        if (chunk && chunk.promptFeedback) {
          promptFeedback = chunk.promptFeedback;
        }
      }
      // Reassemble the accumulated stream into the one response shape
      // `toNormalizedResponse` reads — text parts included verbatim, so the
      // final normalized content matches what was streamed.
      return toNormalizedResponse({
        candidates: [{content: {parts}, finishReason}],
        usageMetadata,
        promptFeedback,
      });
    }

    const raw = await this._client.models.generateContent(geminiReq);
    return toNormalizedResponse(raw);
  }
}

module.exports = {
  GeminiProvider,
  toGeminiRequest,
  toNormalizedResponse,
  normalizeStopReason,
  sanitizeSchema,
  DEFAULT_MODEL,
};
