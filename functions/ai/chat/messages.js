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
 * Tool results only survive a turn through the context ledger (fresh, latest
 * turn only — `context_ledger.js`), so without this the model would see only
 * "Which one would you like?" and nothing it could act on.
 * @param {{role: string, content: string, kind: (string|undefined),
 *   fields: (Object|undefined), status: (string|undefined),
 *   preface: (string|undefined)}} message
 * @return {{role: string, content: string}}
 */
function toNormalizedMessage(message) {
  const fields = message.fields;
  // A card's lead-in is part of what the coach said that turn.
  const said = message.preface ?
    `${message.preface}\n\n${message.content}` : message.content;
  if (message.kind === "choice_request" && fields &&
      Array.isArray(fields.options) && fields.options.length) {
    const lines = fields.options.map((o, i) => {
      const detail = o.subtitle ? ` — ${o.subtitle}` : "";
      return `${i + 1}. ${o.label}${detail} (value: ${o.value})`;
    });
    const answered = message.status === "answered" && message.selectedValue ?
      `\n[Answered: value=${message.selectedValue}]` : "";
    return {
      role: message.role,
      content: `${said}\n[Options shown to the user:\n` +
        `${lines.join("\n")}]${answered}`,
    };
  }
  // A tapped answer: its label, plus the structured pick it stands for.
  if (message.role === "user" && message.choice && message.choice.value) {
    return {
      role: message.role,
      content: `${message.content}\n[Tapped option value=` +
        `${message.choice.value} on the question above]`,
    };
  }
  if (message.kind === "action_proposal" && message.status) {
    return {
      role: message.role,
      content: `${said}\n[Proposed change — ${message.status}]`,
    };
  }
  return {role: message.role, content: message.content};
}

const SHORTENED_MARKER = "… [earlier reply shortened]";

/**
 * Whether a persisted card still waits on the user — its options or its
 * proposed change are live context, so it's never shortened or dropped ahead
 * of plain text.
 * @param {!Object} message
 * @return {boolean}
 */
function isOpenCard(message) {
  if (message.kind === "choice_request") return message.status !== "answered";
  if (message.kind === "action_proposal") {
    return !message.status || message.status === "pending";
  }
  return false;
}

/**
 * Chooses the history the model reads this turn — a CHARACTER budget, not a
 * fixed message count, so one long reply can't crowd out the conversation and
 * a run of short exchanges isn't cut off at an arbitrary tenth message.
 *
 *   1. The CURRENT turn's user message is removed: it's persisted before
 *      history is read, and the turn hands the model its own copy (with the
 *      EARLIER RESULTS block), so leaving it in sent it twice.
 *   2. The newest `verbatimMessages` messages are kept word for word — the
 *      exchange the user is continuing. They are always kept, even past the
 *      budget.
 *   3. Older messages are added newest-first while the running total stays
 *      within `charBudget`: user messages whole (what the user said is what
 *      they may refer back to), a card still awaiting the user whole (its
 *      options or proposal are live), and older replies shortened to
 *      `olderReplyChars` — the gist of what the coach said, not every word.
 *   4. The kept history starts with a user message (the API's rule); a
 *      leading reply is dropped.
 *
 * Pure. Returns the normalized messages (oldest first) and what was done, for
 * the usage record.
 *
 * @param {!Array<!Object>} history Persisted messages, oldest first.
 * @param {{clientTurnId: (string|undefined), content: string,
 *   createdAt: !Date}} current The turn's own user message, as persisted.
 * @param {{charBudget: number, verbatimMessages: number,
 *   olderReplyChars: number}} cfg
 * @return {{messages: !Array<{role: string, content: string}>,
 *   stats: {messages: number, chars: number, dropped: number,
 *     shortened: number}}}
 */
function selectHistory(history, current, cfg) {
  const all = (Array.isArray(history) ? history : []).filter(Boolean);
  const isCurrent = (m) => m.role === "user" && (current.clientTurnId ?
    m.clientTurnId === current.clientTurnId :
    m.content === current.content && m.createdAt instanceof Date &&
      m.createdAt.getTime() === current.createdAt.getTime());
  const list = all.filter((m) => !isCurrent(m));

  const picked = [];
  let chars = 0;
  let shortened = 0;
  let i = list.length - 1;
  for (let kept = 0; i >= 0 && kept < cfg.verbatimMessages; i--, kept++) {
    const n = toNormalizedMessage(list[i]);
    picked.push(n);
    chars += n.content.length;
  }
  for (; i >= 0; i--) {
    const m = list[i];
    let n = toNormalizedMessage(m);
    if (m.role === "assistant" && !isOpenCard(m) &&
        n.content.length > cfg.olderReplyChars) {
      n = {role: n.role,
        content: n.content.slice(0, cfg.olderReplyChars) + SHORTENED_MARKER};
      shortened++;
    }
    if (chars + n.content.length > cfg.charBudget) break;
    picked.push(n);
    chars += n.content.length;
  }
  picked.reverse();
  while (picked.length && picked[0].role !== "user") {
    chars -= picked.shift().content.length;
  }
  return {
    messages: picked,
    stats: {
      messages: picked.length,
      chars,
      dropped: list.length - picked.length,
      shortened,
    },
  };
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
  selectHistory,
  capToolResult,
};
