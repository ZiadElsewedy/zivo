/**
 * The only real `AiProvider` adapter: translates a ZIVO `NormalizedRequest`
 * into an Anthropic Messages API request and an Anthropic response back into
 * a `NormalizedResponse`.
 *
 * Free of `@anthropic-ai/sdk` — the client is injected as
 * `{messages: {create, stream}}` (exactly the shape of a real `Anthropic`
 * instance), so this is `node --test`-able with a plain fake. `create(req)`
 * resolves to an Anthropic message; `stream(req)` returns an object exposing
 * `.on("text", cb)` and `.finalMessage()` (the real SDK's `MessageStream`
 * shape).
 */

const {AiProvider} = require("./provider");

/** @const {!Object<string, string>} Anthropic stop_reason → normalized. */
const STOP_REASON_MAP = {
  tool_use: "tool_use",
  refusal: "refusal",
  max_tokens: "max_tokens",
};

/**
 * @param {?string} stopReason
 * @return {string} One of `"tool_use"`, `"refusal"`, `"max_tokens"`,
 *   `"end"`, `"other"`.
 */
function normalizeStopReason(stopReason) {
  if (stopReason === "end_turn" || stopReason === "stop_sequence") return "end";
  return STOP_REASON_MAP[stopReason] || (stopReason ? "other" : "other");
}

/**
 * Wraps an Anthropic content block as a `NormalizedContentBlock`: the type
 * and common fields are mirrored for direct use, and `raw` carries the exact
 * original block for lossless round-tripping (e.g. a signed `thinking`
 * block's `signature`).
 * @param {!Object} block
 * @return {!Object}
 */
function normalizeContentBlock(block) {
  return Object.assign({}, block, {raw: block});
}

/**
 * @param {?Object} usage An Anthropic `usage` object (may be absent).
 * @return {!Object} `NormalizedUsage`.
 */
function normalizeUsage(usage) {
  const u = usage || {};
  return {
    inputTokens: u.input_tokens || 0,
    outputTokens: u.output_tokens || 0,
    cacheReadTokens: u.cache_read_input_tokens || 0,
    cacheWriteTokens: u.cache_creation_input_tokens || 0,
  };
}

/**
 * @param {!Object} raw An Anthropic Messages API response.
 * @return {!Object} `NormalizedResponse`.
 */
function toNormalizedResponse(raw) {
  return {
    stopReason: normalizeStopReason(raw.stop_reason),
    content: Array.isArray(raw.content) ?
      raw.content.map(normalizeContentBlock) : [],
    usage: normalizeUsage(raw.usage),
    raw,
  };
}

/**
 * Translates one normalized message-content part into its Anthropic shape.
 * @param {(string|!Object)} part
 * @return {(string|!Object)}
 */
function toAnthropicPart(part) {
  if (part && part.type === "raw") return part.raw;
  if (part && part.type === "text") return {type: "text", text: part.text};
  if (part && part.type === "document") {
    return {
      type: "document",
      source: {
        type: "base64",
        media_type: part.mediaType,
        data: part.dataBase64,
      },
    };
  }
  if (part && part.type === "image") {
    return {
      type: "image",
      source: {
        type: "base64",
        media_type: part.mediaType,
        data: part.dataBase64,
      },
    };
  }
  if (part && part.type === "tool_result") {
    const block = {
      type: "tool_result",
      tool_use_id: part.toolUseId,
      content: part.content,
    };
    if (part.isError) block.is_error = true;
    return block;
  }
  throw new Error(`Unsupported normalized content part type: ${part && part.type}`);
}

/**
 * @param {!Object} message A `NormalizedMessage`.
 * @return {!Object} `{role, content}` in Anthropic shape.
 */
function toAnthropicMessage(message) {
  if (typeof message.content === "string") {
    return {role: message.role, content: message.content};
  }
  return {role: message.role, content: message.content.map(toAnthropicPart)};
}

/**
 * @param {!Object} tool A `NormalizedTool`.
 * @return {!Object} Anthropic tool schema.
 */
function toAnthropicTool(tool) {
  const t = {
    name: tool.name,
    description: tool.description,
    input_schema: tool.inputSchema,
  };
  if (tool.strict !== undefined) t.strict = tool.strict;
  return t;
}

/**
 * @param {(string|{type: string, name: string}|undefined)} toolChoice
 * @return {(!Object|undefined)}
 */
function toAnthropicToolChoice(toolChoice) {
  if (toolChoice === undefined) return undefined;
  if (typeof toolChoice === "string") return {type: toolChoice};
  return toolChoice;
}

/**
 * @param {!Object} normalizedRequest
 * @return {!Object} An Anthropic Messages API request.
 */
function toAnthropicRequest(normalizedRequest) {
  const req = {
    model: normalizedRequest.model,
    max_tokens: normalizedRequest.maxTokens,
    messages: normalizedRequest.messages.map(toAnthropicMessage),
  };
  if (normalizedRequest.system && normalizedRequest.system.length > 0) {
    req.system = normalizedRequest.system.map((block) => {
      const b = {type: "text", text: block.text};
      if (block.cache) b.cache_control = {type: block.cache};
      return b;
    });
  }
  if (normalizedRequest.tools && normalizedRequest.tools.length > 0) {
    req.tools = normalizedRequest.tools.map(toAnthropicTool);
  }
  const toolChoice = toAnthropicToolChoice(normalizedRequest.toolChoice);
  if (toolChoice !== undefined) req.tool_choice = toolChoice;
  return req;
}

/**
 * @typedef {Object} AnthropicClient An injected Anthropic client — the same
 *   shape a real `Anthropic` SDK instance exposes.
 * @property {{create: function(!Object): !Promise<!Object>,
 *   stream: (function(!Object): !Object)=}} messages
 */

/**
 * The Anthropic `AiProvider` adapter.
 */
class AnthropicProvider extends AiProvider {
  /**
   * @param {!AnthropicClient} client
   */
  constructor(client) {
    super();
    this._client = client;
  }

  /**
   * `opts.onText` streams assistant TEXT deltas — the chat path.
   * `opts.onInputJson` streams a tool call's accumulating INPUT, which is
   * where a structured-output turn (the PDF importers) does all its work:
   * those turns emit no text at all, so `onText` never fires for them. It is
   * called with `(partialJson, snapshot)` — the delta and the cumulative JSON
   * so far, the latter being what a progress scanner actually wants.
   * @param {!Object} normalizedRequest
   * @param {{onText: (function(string): void),
   *   onInputJson: (function(string, string): void)}=} opts
   * @return {!Promise<!Object>}
   * @override
   */
  async generate(normalizedRequest, opts = {}) {
    const anthropicReq = toAnthropicRequest(normalizedRequest);
    const wantsText = typeof opts.onText === "function";
    const wantsInputJson = typeof opts.onInputJson === "function";
    // A client with no `stream` (the legacy `callModel`-only seam, and every
    // buffered test fake) degrades to a buffered call rather than throwing.
    // Callers get the same final response either way — only the live progress
    // is lost, which is the correct thing to trade for not failing the import.
    const canStream = typeof this._client.messages.stream === "function";
    if ((wantsText || wantsInputJson) && canStream) {
      const stream = this._client.messages.stream(anthropicReq);
      if (wantsText) stream.on("text", opts.onText);
      if (wantsInputJson) stream.on("inputJson", opts.onInputJson);
      const raw = await stream.finalMessage();
      return toNormalizedResponse(raw);
    }
    const raw = await this._client.messages.create(anthropicReq);
    return toNormalizedResponse(raw);
  }
}

module.exports = {
  AnthropicProvider,
  toAnthropicRequest,
  toNormalizedResponse,
  normalizeStopReason,
};
