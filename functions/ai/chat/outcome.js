/**
 * How a turn ENDS — the agent loop's explicit terminal states, the tool-retry
 * classification, and the factual "here's what I did, here's what failed"
 * reply for a turn that couldn't finish.
 *
 * `turn.js` runs the loop; this module decides what to call where it stopped
 * and what to tell the user about it. Kept pure (no store, no provider) so the
 * copy and the classification can be tested without running a turn.
 *
 * Two budgets are deliberately kept apart (see `turn.js`):
 *   - a PROVIDER retry (`../routing/router.js`) re-sends one model call after a
 *     transient provider failure. It never counts as an agent step and never
 *     re-runs a tool.
 *   - an AGENT step is one model call inside the loop. `maxAgentSteps` bounds
 *     them; retries inside a step don't add steps.
 */

/**
 * Every way a turn can stop. The loop always ends in exactly one of these —
 * there is no path that keeps calling the model without a bound.
 * @enum {string}
 */
const TerminalState = Object.freeze({
  // The model produced its answer (validated, or replaced by the validator's
  // deterministic text — either way the user got an answer).
  COMPLETED: "completed",
  // The turn handed control to the user: a write awaiting Confirm, a question
  // card, or an already-pending card the user must resolve first.
  NEEDS_USER_INPUT: "needs_user_input",
  // The step budget (or the per-turn token budget) ran out before an answer.
  MAX_STEPS_REACHED: "max_steps_reached",
  // A tool kept failing (a transient error survived its one retry, or the
  // same tool failed twice) — stopped rather than looping on it.
  TOOL_ERROR: "tool_error",
  // The model provider couldn't answer even after the router's own retry and
  // fallback. Thrown to the caller; the app shows "Switch model / Retry".
  PROVIDER_ERROR: "provider_error",
  // The caller went away (the stream was closed) — no further model calls.
  CANCELLED: "cancelled",
  // The user's daily Ask cap was already used up; the model never ran.
  DAILY_LIMIT: "daily_limit",
});

// The turn's legacy wire `status` → its terminal state. `status` stays as-is
// (the app and the usage log already read it); `terminalState` is the coarse,
// closed set a dashboard or the client can switch on.
const STATUS_TO_TERMINAL = Object.freeze({
  "ok": TerminalState.COMPLETED,
  "replayed": TerminalState.COMPLETED,
  "refusal": TerminalState.COMPLETED,
  "validated-fallback": TerminalState.COMPLETED,
  "safety-intercept": TerminalState.COMPLETED,
  "proposed": TerminalState.NEEDS_USER_INPUT,
  "awaiting-input": TerminalState.NEEDS_USER_INPUT,
  "proposal-blocked": TerminalState.NEEDS_USER_INPUT,
  "iteration-limit": TerminalState.MAX_STEPS_REACHED,
  "token-ceiling": TerminalState.MAX_STEPS_REACHED,
  "tool-error": TerminalState.TOOL_ERROR,
  "cancelled": TerminalState.CANCELLED,
  "daily-limit": TerminalState.DAILY_LIMIT,
});

/**
 * @param {string} status A `runAiTurn` status.
 * @return {string} Its `TerminalState`.
 */
function terminalStateFor(status) {
  return STATUS_TO_TERMINAL[status] || TerminalState.COMPLETED;
}

// gRPC codes (Firestore Admin) and their string forms that mean "the backend
// hiccupped, the same read may well succeed a moment later": DEADLINE_EXCEEDED
// (4), RESOURCE_EXHAUSTED (8), ABORTED (10), INTERNAL (13), UNAVAILABLE (14).
const TRANSIENT_CODES = new Set([
  4, 8, 10, 13, 14,
  "deadline-exceeded", "resource-exhausted", "aborted", "internal",
  "unavailable", "DEADLINE_EXCEEDED", "RESOURCE_EXHAUSTED", "ABORTED",
  "INTERNAL", "UNAVAILABLE", "ETIMEDOUT", "ECONNRESET", "EAI_AGAIN",
]);

/**
 * Whether a tool's thrown error is worth ONE immediate retry. Only backend
 * hiccups qualify — a tool that rejected its input (a bad date, an unknown
 * exercise) would fail identically again, so that goes back to the model to
 * correct instead.
 * @param {*} err
 * @return {boolean}
 */
function isTransientToolError(err) {
  if (!err) return false;
  if (err.transient === true) return true;
  return TRANSIENT_CODES.has(err.code);
}

// What each read tool accomplished (past tense, a clause after "I") and what
// it would have fetched (a noun phrase) — the vocabulary of the outcome reply.
// A tool missing here is simply not named, never shown by its identifier.
const TOOL_PHRASES = Object.freeze({
  en: {
    get_today: ["checked your day", "today's details"],
    get_diet: ["checked your diet", "your diet details"],
    get_workouts: ["checked your workouts", "your workout details"],
    get_last_workout: ["checked your last workout", "your last workout"],
    get_training_analysis: ["reviewed your training", "your training analysis"],
    get_exercise_analysis: ["checked that exercise's history",
      "that exercise's history"],
    get_expenses: ["checked your spending", "your spending"],
    summarize_week: ["summarised your week", "your weekly summary"],
    get_readiness: ["checked your readiness", "your readiness"],
    get_sleep_summary: ["checked your sleep", "your sleep"],
    resolve_food: ["looked up the food", "the food details"],
    calculate_meal_nutrition: ["worked out the nutrition",
      "the nutrition numbers"],
    search_food_product: ["searched for the product", "that product's details"],
    search_food_alternatives: ["looked for alternatives",
      "food alternatives"],
    get_workout_schedule: ["checked your workout schedule",
      "your workout schedule"],
    preview_workout_change: ["looked at how to rearrange your workouts",
      "the options for today's workout"],
  },
  ar: {
    get_today: ["راجعت يومك", "تفاصيل يومك"],
    get_diet: ["راجعت نظامك الغذائي", "تفاصيل نظامك الغذائي"],
    get_workouts: ["راجعت تمارينك", "تفاصيل تمارينك"],
    get_last_workout: ["راجعت آخر تمرين لك", "آخر تمرين لك"],
    get_training_analysis: ["راجعت تحليل تمرينك", "تحليل تمرينك"],
    get_exercise_analysis: ["راجعت سجل هذا التمرين", "سجل هذا التمرين"],
    get_expenses: ["راجعت مصروفاتك", "مصروفاتك"],
    summarize_week: ["لخصت أسبوعك", "ملخص أسبوعك"],
    get_readiness: ["راجعت جاهزيتك", "جاهزيتك"],
    get_sleep_summary: ["راجعت نومك", "بيانات نومك"],
    resolve_food: ["بحثت عن الطعام", "تفاصيل الطعام"],
    calculate_meal_nutrition: ["حسبت القيم الغذائية", "القيم الغذائية"],
    search_food_product: ["بحثت عن المنتج", "تفاصيل المنتج"],
    search_food_alternatives: ["بحثت عن بدائل", "بدائل مناسبة"],
    get_workout_schedule: ["راجعت جدول تمارينك", "جدول تمارينك"],
    preview_workout_change: ["راجعت طرق تغيير تمرين اليوم",
      "اختيارات تمرين اليوم"],
  },
});

const ARABIC_SCRIPT = /[؀-ۿ]/;

/**
 * The language the outcome reply is written in: Arabic when the user wrote
 * in Arabic script, English otherwise. The model mirrors the user's language
 * on its own; this text is written by the server, so it has to choose.
 * @param {string} message The user's message.
 * @return {('ar'|'en')}
 */
function replyLanguageFor(message) {
  return ARABIC_SCRIPT.test(message || "") ? "ar" : "en";
}

/**
 * "A", "A and B", "A, B and C" (or the Arabic "A وB" / "A، B وC").
 * @param {!Array<string>} parts
 * @param {string} lang
 * @return {string}
 */
function joinClauses(parts, lang) {
  if (parts.length <= 1) return parts.join("");
  const head = parts.slice(0, -1);
  const last = parts[parts.length - 1];
  return lang === "ar" ?
    `${head.join("، ")} و${last}` :
    `${head.join(", ")} and ${last}`;
}

/**
 * The distinct "what I did" clauses for the steps that succeeded, in order.
 * @param {!Array<{tool: string, status: string}>} activity
 * @param {string} lang
 * @return {!Array<string>}
 */
function doneClauses(activity, lang) {
  const table = TOOL_PHRASES[lang];
  const seen = new Set();
  const out = [];
  for (const step of activity) {
    if (step.status !== "ok") continue;
    const phrase = table[step.tool];
    if (!phrase || seen.has(phrase[0])) continue;
    seen.add(phrase[0]);
    out.push(phrase[0]);
  }
  return out;
}

/**
 * The factual reply for a turn that stopped without an answer: what was
 * checked, what failed, and what the user can do next. Never vague, never a
 * raw tool name, never the model's reasoning — only the loop's real record.
 *
 * @param {{
 *   terminalState: string,
 *   activity: !Array<{tool: string, status: string}>,
 *   failedTool: (?string|undefined),
 *   lang: ('ar'|'en'),
 * }} args
 * @return {string}
 */
function describeUnfinishedTurn({terminalState, activity, failedTool, lang}) {
  const done = doneClauses(activity || [], lang);
  const didSome = done.length > 0;
  const did = joinClauses(done, lang);
  const failedPhrase = failedTool && TOOL_PHRASES[lang][failedTool];

  if (lang === "ar") {
    if (terminalState === TerminalState.TOOL_ERROR) {
      const failed = failedPhrase ?
        `لم أتمكن من الحصول على ${failedPhrase[1]}` :
        "فشلت إحدى الخطوات التي أحتاجها";
      return didSome ?
        `${did}، لكن ${failed} — فشلت المحاولة مرتين، فتوقفت بدلًا من ` +
          "التخمين. حاول مرة أخرى بعد قليل." :
        `${failed}، فتوقفت بدلًا من التخمين. حاول مرة أخرى بعد قليل.`;
    }
    return didSome ?
      "لم أتمكن من إكمال هذا الطلب ضمن عدد الخطوات المتاح لسؤال واحد. " +
        `${did}، لكنني لم أصل إلى إجابة كاملة. ` +
        "جرّب أن تسأل عن شيء واحد في كل مرة — مثلًا وجبة واحدة أو تمرين واحد." :
      "لم أتمكن من إكمال هذا الطلب ضمن عدد الخطوات المتاح لسؤال واحد. " +
        "جرّب أن تسأل عن شيء واحد في كل مرة.";
  }

  if (terminalState === TerminalState.TOOL_ERROR) {
    if (!failedPhrase) {
      return didSome ?
        `I ${did}, but one of the steps I needed kept failing, so I stopped ` +
          "rather than guess. Try again in a moment." :
        "One of the steps I needed kept failing, so I stopped rather than " +
          "guess. Try again in a moment.";
    }
    const what = failedPhrase[1];
    return didSome ?
      `I ${did}, but I couldn't get ${what} — that lookup failed twice, so ` +
        "I stopped rather than guess. Try again in a moment." :
      `I tried to get ${what}, but that lookup failed, so I stopped rather ` +
        "than guess. Try again in a moment.";
  }
  return didSome ?
    "I couldn't complete this request within the steps I can take for one " +
      `question. I ${did}, but I didn't get to a complete answer. Try ` +
      "asking about one thing at a time — for example one meal or one lift." :
    "I couldn't complete this request within the steps I can take for one " +
      "question. Try asking about one thing at a time.";
}

module.exports = {
  TerminalState,
  terminalStateFor,
  isTransientToolError,
  replyLanguageFor,
  describeUnfinishedTurn,
  TOOL_PHRASES,
};
