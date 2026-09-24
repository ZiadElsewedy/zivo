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
 * `NormalizedMessage`. A plain message is its text. A CARD carries more than
 * its text, and the next turn needs it:
 *
 *   - a question card (`choice_request`) lists the options the user saw,
 *     NUMBERED as the app numbers them, with each option's value — so "option
 *     2", "the second one" or a tapped label resolves to the exact choice
 *     (e.g. a foodId) instead of the model re-searching or guessing;
 *   - a proposal card (`action_proposal`) says whether it was applied,
 *     cancelled or is still pending.
 *
 * Tool results are not persisted, so without this the model would see only
 * "Which one would you like?" and nothing it could act on.
 * @param {{role: string, content: string, kind: (string|undefined),
 *   fields: (Object|undefined), status: (string|undefined)}} message
 * @return {{role: string, content: string}}
 */
function toNormalizedMessage(message) {
  const fields = message.fields;
  if (message.kind === "choice_request" && fields &&
      Array.isArray(fields.options) && fields.options.length) {
    const lines = fields.options.map((o, i) => {
      const detail = o.subtitle ? ` — ${o.subtitle}` : "";
      return `${i + 1}. ${o.label}${detail} (value: ${o.value})`;
    });
    return {
      role: message.role,
      content: `${message.content}\n[Options shown to the user:\n` +
        `${lines.join("\n")}]`,
    };
  }
  if (message.kind === "action_proposal" && message.status) {
    return {
      role: message.role,
      content: `${message.content}\n[Proposed change — ${message.status}]`,
    };
  }
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
