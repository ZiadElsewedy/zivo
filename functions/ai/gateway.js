/**
 * `aiChat` gateway — the public facade for the Ask chat subsystem.
 *
 * The implementation used to live in this one ~1,170-line file. It now lives in
 * `./chat/`, split by concern so each part is findable on its own:
 *
 *   chat/turn.js              — runAiTurn: the model↔tool turn loop
 *   chat/actions.js           — confirmAction / cancelAction + the write dispatch
 *   chat/context.js           — the system blocks handed to the model each turn
 *   chat/config.js            — ceilings, pricing, canned user-facing messages
 *   chat/usage.js             — token accounting + cost + the daily cap
 *   chat/messages.js          — history + tool-result shaping
 *   chat/errors.js            — GatewayError + the document-id guard
 *   chat/prompt/system_prompt.js  — the coach system prompt, composed from
 *   chat/prompt/sections/*.js     — persona · focus · formatting · numbers ·
 *                                   training · coaching · mutations · safety
 *
 * This file re-exports the same surface the rest of the codebase already
 * imports (`require("./gateway")` in `index.js`, `workout_import.js`,
 * `diet_import.js`, `diet_generate.js`, and the test suites), so the split is
 * invisible to every caller. Start in `chat/turn.js` for behaviour, or
 * `chat/prompt/` for what the coach is told.
 *
 * Reads never mutate. Writes (ADR-003 V2) are two-phase and user-confirmed —
 * see `chat/turn.js` (propose) and `chat/actions.js` (confirm/execute).
 */

const {runAiTurn} = require("./chat/turn");
const {confirmAction, cancelAction} = require("./chat/actions");
const {GatewayError} = require("./chat/errors");
const {SYSTEM_PROMPT} = require("./chat/prompt/system_prompt");
const {
  DEFAULT_CONFIG,
  DAILY_LIMIT_MESSAGE,
  ITERATION_LIMIT_MESSAGE,
  TOKEN_CEILING_MESSAGE,
  REFUSAL_MESSAGE,
  PENDING_ACTION_MESSAGE,
} = require("./chat/config");

module.exports = {
  runAiTurn,
  confirmAction,
  cancelAction,
  GatewayError,
  SYSTEM_PROMPT,
  DEFAULT_CONFIG,
  DAILY_LIMIT_MESSAGE,
  ITERATION_LIMIT_MESSAGE,
  TOKEN_CEILING_MESSAGE,
  REFUSAL_MESSAGE,
  PENDING_ACTION_MESSAGE,
};
