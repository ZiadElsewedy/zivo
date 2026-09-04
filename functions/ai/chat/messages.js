/**
 * Message plumbing for a chat turn: turning persisted history into what the
 * model sees, extracting the assistant's text, keeping thinking blocks valid on
 * the round-trip, and capping oversized tool results.
 *
 * Pure string/array helpers — no I/O, no model, no store — so the turn loop
 * (`turn.js`) reads as orchestration and these read as data-shaping.
 */

/**
 * The text of the first text content blocks in `content`, joined and
 * trimmed. Empty string if there are none.
 * @param {?Array<Object>} content
 * @return {string}
 */
function extractText(content) {
  if (!Array.isArray(content)) return "";
  return content
      .filter((b) => b && b.type === "text" && typeof b.text === "string")
      .map((b) => b.text)
      .join("\n")
      .trim();
}

/**
 * Sanitizes an assistant `content` array before it is echoed back in the
 * message history for the next model call. Drops `thinking` blocks that carry
 * no usable reasoning — a signed, non-empty thinking block must round-trip
 * verbatim, but `claude-sonnet-5` emits an empty placeholder thinking block
 * even with extended thinking off, and the streaming SDK
 * (`@anthropic-ai/sdk` finalMessage) reconstructs it with an empty signature.
 * Re-sending that block fails the API's "each thinking block must contain
 * thinking" check, breaking every multi-call (tool_use) streamed turn. The
 * buffered path keeps a valid signature, so this only bit streaming — but
 * dropping empty thinking blocks is correct for both transports while thinking
 * is not enabled. Revisit if extended thinking is turned on.
 * @param {?Array<Object>} content
 * @return {?Array<Object>}
 */
function stripEmptyThinking(content) {
  if (!Array.isArray(content)) return content;
  return content.filter((b) =>
    !(b && b.type === "thinking" && !(b.thinking && b.thinking.length)));
}

/**
 * A persisted `{role, content, createdAt}` message mapped to a
 * `NormalizedMessage` (a plain-string message needs no further translation).
 * @param {{role: string, content: string}} message
 * @return {{role: string, content: string}}
 */
function toNormalizedMessage(message) {
  return {role: message.role, content: message.content};
}

/**
 * Caps a stringified tool result at `maxChars`, appending a short truncation
 * marker when it overflows. The marker keeps the model honest about the elision
 * rather than silently handing it a partial payload.
 * @param {string} content The JSON-stringified tool result.
 * @param {number} maxChars
 * @return {string}
 */
function capToolResult(content, maxChars) {
  if (content.length <= maxChars) return content;
  const dropped = content.length - maxChars;
  return `${content.slice(0, maxChars)}…[truncated ${dropped} characters]`;
}

module.exports = {
  extractText,
  stripEmptyThinking,
  toNormalizedMessage,
  capToolResult,
};
