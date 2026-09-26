/**
 * REPLY SHAPE — how much a reply should say, decided from the message before
 * the model writes a word.
 *
 * The prompt's LENGTH policy (`prompt/sections/length.js`) makes short the
 * default. What it can't know from a static prompt is which KIND of message
 * this turn is, and two kinds need a different shape:
 *
 *   - DECISION — "should I train today?", "أروح الجيم النهارده؟", "ينفع آكل
 *     بيتزا؟". The user wants a call, not a survey: the verdict goes on the
 *     first line, then the few facts that decided it, then the next action.
 *   - DETAIL — "explain", "why", "بالتفصيل", "اشرح". The user asked for depth,
 *     so it's welcome, even when their saved preference is short replies.
 *
 * Everything else gets no directive; the prompt's default (answer first,
 * concise) applies. Like `intent.js` this is deterministic and free: a missed
 * cue costs nothing but the default shape, and a false one only reorders a
 * reply, so it never needs a model call. The length is decided BEFORE
 * generation — nothing is ever truncated after it.
 *
 * The directive is an uncached per-turn system block (`context.js`), so the
 * cached prompt prefix is untouched.
 *
 * Pure: no I/O.
 */

/** @enum {string} */
const ReplyShape = {
  DEFAULT: "default",
  DECISION: "decision",
  DETAIL: "detail",
  DECISION_DETAIL: "decision_detail",
};

// "Should I…?" in English and Arabizi. Matched on the lowercased message;
// "how can I…" is a how-to, not a call.
const DECISION_EN = new RegExp(
    "\\b(should i|shall i|(?<!how )can i|(?<!how )could i|do i need to|" +
    "must i|is it (ok|okay|fine|bad|good) (to|if)|am i (allowed|good) to|" +
    "worth it|or not|yes or no|yenfa3|ynfa3|a2dar|aroo7|aro7|atmaran)\\b");

/**
 * Arabic cues, each matched at the START of a word (an optional "و" — "and"
 * — allowed): as bare substrings "ليه" (why) would fire inside "عليه".
 * @param {!Array<string>} words
 * @return {!RegExp}
 */
function arabicCues(words) {
  return new RegExp(`(?:^|[^\\u0600-\\u06FF])و?(?:${words.join("|")})`);
}

// Egyptian/Standard Arabic "should I / is it OK to / do I … or not". A
// statement of what was done ("اتمرنت", "أكلت") is not one of these forms.
const DECISION_AR = arabicCues([
  "ينفع", "المفروض", "هل ينبغي", "هل يجب", "ولا لأ", "ولا لا", "لازم أ",
  "أقدر أ", "اقدر ا", "أروح", "اروح", "أتمرن", "اتمرن ولا", "أمشي على",
  "امشي على", "ألتزم", "التزم ولا", "أكمل ولا", "اكمل ولا", "أريّح",
  "أريح", "اريح", "آكل ولا", "اكل ولا",
]);

// "Explain / why / in detail" in English and Arabizi.
const DETAIL_EN = new RegExp(
    "\\b(explain|explanation|in detail|detailed|details|elaborate|why|" +
    "break (it )?down|breakdown|step by step|analy[sz]e|analysis|compare|" +
    "comparison|tell me more|full plan|deep dive|walk me through|" +
    "leh|lih|eshra7|eshrah|bel tafsil|bltafsil)\\b");
const DETAIL_AR = arabicCues([
  "اشرح", "إشرح", "شرح", "بالتفصيل", "تفاصيل", "تفصيل", "ليه", "لماذا",
  "ليش", "حلل", "تحليل", "وضح", "وضّح", "قارن", "مقارنة", "خطة كاملة",
]);

/**
 * @param {string} message The user's words.
 * @return {string} A `ReplyShape`.
 */
function replyShapeFor(message) {
  const text = String(message || "").trim();
  if (!text) return ReplyShape.DEFAULT;
  const lower = text.toLowerCase();
  const decision = DECISION_EN.test(lower) || DECISION_AR.test(text);
  const detail = DETAIL_EN.test(lower) || DETAIL_AR.test(text);
  if (decision && detail) return ReplyShape.DECISION_DETAIL;
  if (decision) return ReplyShape.DECISION;
  if (detail) return ReplyShape.DETAIL;
  return ReplyShape.DEFAULT;
}

const DECISION_DIRECTIVE =
  "REPLY SHAPE for this message — it asks you to make a call. Line 1 is " +
  "the decision, in the user's language: yes, no, or yes-but-modified " +
  "(\"Yes — train today, keep it moderate.\" / \"أيوه، اتمرن النهارده بس " +
  "خففها شوية.\"). Then one to three short sentences naming the facts that " +
  "decided it, then the one thing to do next. Decide only from data you " +
  "read this turn or in EARLIER RESULTS; if what the call depends on isn't " +
  "there, read it first — and if it doesn't exist, say you can't make the " +
  "call and what's missing, instead of deciding anyway.";

const DETAIL_DIRECTIVE =
  "REPLY SHAPE for this message — the user asked for explanation or detail, " +
  "so depth is welcome here (this overrides a short-reply preference). " +
  "Still lead with the answer, then explain in short, separated paragraphs " +
  "or • bullets, and stay on what they asked.";

/**
 * The per-turn directive for a shape, or undefined for the default (which
 * adds no block).
 * @param {string} shape A `ReplyShape`.
 * @return {(string|undefined)}
 */
function replyShapeDirective(shape) {
  switch (shape) {
    case ReplyShape.DECISION:
      return DECISION_DIRECTIVE;
    case ReplyShape.DETAIL:
      return DETAIL_DIRECTIVE;
    case ReplyShape.DECISION_DETAIL:
      return `${DECISION_DIRECTIVE} The user also asked for the reasoning: ` +
        "after the decision, explain it more fully than usual.";
    default:
      return undefined;
  }
}

module.exports = {ReplyShape, replyShapeFor, replyShapeDirective};
