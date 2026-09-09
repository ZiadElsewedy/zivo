/**
 * The server-side ELICITATION tool registry for the `aiChat` gateway — the
 * coach's way to PAUSE a turn and ask the user something, rather than guess.
 *
 * Like the mutating tools (`mutations.js`), these are declared to the model but
 * are **non-executing**: when the model calls one, the gateway does NOT answer
 * for the user. It `validate`s the input into a normalized card spec, appends
 * that card as an assistant message, and ends the turn. The user's answer comes
 * back as a normal next turn (a plain `aiChat` send), so — unlike a write
 * proposal — there is no confirm/execute half here and no pending-action doc:
 * a question resolves by being answered, not confirmed.
 *
 * Phase 1 ships ONE tool, `ask_choice` (option chips), the lowest-risk slice:
 * pure clarification, no persistence. `request_input` (a data-collection form
 * that can write back to the profile) is a later phase and will live here too.
 *
 * `validate` is pure and JSON-safe so it runs offline under `node --test`.
 */

/** Thrown by `validate` when a question can't be turned into a card. */
class ElicitationError extends Error {
  /** @param {string} message */
  constructor(message) {
    super(message);
    this.name = "ElicitationError";
  }
}

const MAX_PROMPT_CHARS = 300;
const MAX_LABEL_CHARS = 80;
const MAX_VALUE_CHARS = 80;
const MIN_OPTIONS = 2;
const MAX_OPTIONS = 5;

/**
 * A trimmed, non-empty string of at most `max` chars, or throws.
 * @param {*} value
 * @param {string} label
 * @param {number} max
 * @return {string}
 */
function requireText(value, label, max) {
  const text = (value == null ? "" : String(value)).trim();
  if (!text) throw new ElicitationError(`A ${label} is required.`);
  if (text.length > max) {
    throw new ElicitationError(`That ${label} is too long.`);
  }
  return text;
}

/**
 * Normalizes one raw option into `{value, label}`. Accepts a bare string
 * (used as both value and label) or an object with `value`/`label` — the model
 * is not always precise about which it sends.
 * @param {*} raw
 * @return {{value: string, label: string}}
 */
function normalizeOption(raw) {
  if (typeof raw === "string") {
    const label = requireText(raw, "option", MAX_LABEL_CHARS);
    return {value: label, label};
  }
  if (raw && typeof raw === "object") {
    const label = requireText(raw.label != null ? raw.label : raw.value,
        "option label", MAX_LABEL_CHARS);
    const value = requireText(raw.value != null ? raw.value : label,
        "option value", MAX_VALUE_CHARS);
    return {value, label};
  }
  throw new ElicitationError("Each option must be text or {value, label}.");
}

const ASK_CHOICE = {
  name: "ask_choice",
  elicits: true,
  // The assistant-message `kind` the client switches on to render chips.
  messageKind: "choice_request",
  description:
    "Ask the user a multiple-choice question when a good answer depends on a " +
    "choice only they can make — pick this over guessing, or over writing the " +
    "options out as plain text. The turn PAUSES: the user taps one option (or " +
    "more, if allowMultiple) and their pick returns as the next message for " +
    "you to continue from. Do NOT use it to ask for a fact a tool can supply " +
    "(get_today already carries the user's profile, latest weight and age). " +
    "Provide prompt (the question) and 2–5 options as {value, label}; value " +
    "is a stable key, label is what the user sees. Write both in the user's " +
    "language. At most one question per turn.",
  inputSchema: {
    type: "object",
    properties: {
      prompt: {type: "string", description: "the question to ask"},
      options: {
        type: "array",
        description: "2–5 choices",
        items: {
          type: "object",
          properties: {
            value: {type: "string", description: "stable key for the choice"},
            label: {type: "string", description: "what the user sees"},
          },
          required: ["label"],
        },
      },
      allowMultiple: {
        type: "boolean",
        description: "true to let the user pick more than one (default false)",
      },
    },
    required: ["prompt", "options"],
  },
  /**
   * @param {!Object} input
   * @return {{prompt: string, options: !Array<{value: string, label: string}>,
   *   allowMultiple: boolean}}
   */
  validate(input) {
    const prompt = requireText(input.prompt, "question", MAX_PROMPT_CHARS);
    const rawOptions = Array.isArray(input.options) ? input.options : [];
    if (rawOptions.length < MIN_OPTIONS) {
      throw new ElicitationError(
          `Give at least ${MIN_OPTIONS} options to choose from.`);
    }
    const options = [];
    const seen = new Set();
    for (const raw of rawOptions) {
      if (options.length >= MAX_OPTIONS) break;
      const opt = normalizeOption(raw);
      // Collapse duplicate values so a pick is unambiguous.
      if (seen.has(opt.value)) continue;
      seen.add(opt.value);
      options.push(opt);
    }
    if (options.length < MIN_OPTIONS) {
      throw new ElicitationError(
          `Give at least ${MIN_OPTIONS} distinct options.`);
    }
    return {prompt, options, allowMultiple: input.allowMultiple === true};
  },
  /**
   * The fallback text for a client that doesn't render the card — the question
   * itself.
   * @param {!Object} v A validated payload.
   * @return {string}
   */
  summarize(v) {
    return v.prompt;
  },
  /**
   * The structured spec the client renders the chips from.
   * @param {!Object} v A validated payload.
   * @return {!Object}
   */
  fields(v) {
    return {options: v.options, allowMultiple: v.allowMultiple};
  },
};

const elicitationTools = [ASK_CHOICE];
const elicitationToolsByName = new Map(
    elicitationTools.map((t) => [t.name, t]));

module.exports = {
  ElicitationError,
  ASK_CHOICE,
  elicitationTools,
  elicitationToolsByName,
};
