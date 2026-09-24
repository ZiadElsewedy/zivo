/**
 * The Ask CHOICE contract — the generic half of `ask_choice` that makes a
 * question card something the server can RESOLVE, not just render.
 *
 * A `choice_request` assistant message is:
 *
 *   {kind: 'choice_request', content: <question>, requestId, status,
 *    fields: {options: [{value, label, subtitle?, metadata?}], allowMultiple},
 *    bindings?: {<value>: {tool, input}},     // server-side resolution
 *    selectedValue?: <value>}                 // once answered
 *
 * `value` is the option's stable id. Every option the user can tap is keyed by
 * it, and the answer comes back as `{requestId, value}` — never as text for
 * the model to re-parse. Three things live here:
 *
 *   1. VERIFIED OFFERS. A search tool may declare `choiceOffer(result, input)`
 *      returning the options its (priced, real) result supports, each with a
 *      `binding` — the exact mutating-tool call that choosing it means
 *      (`search_food_alternatives` → `replace_meal_item` with the foodId and
 *      portion it priced). `bindOfferedOptions` pins an `ask_choice` to those:
 *      options that aren't in the offer are dropped, and every number shown is
 *      the server's, never the model's.
 *   2. THE SAFETY NET. When a turn offered options but the model answered in
 *      prose (listing them as bullets), `cardFromOffer` builds the card from
 *      the offer itself — "here are three options" never ships without them.
 *   3. THE ANSWER. `resolveChoiceAnswer` loads the card by requestId, rejects
 *      a missing / already-answered / unknown option safely, and returns the
 *      exact option and its binding. The turn loop proposes a bound choice's
 *      change directly (no model call, nothing to guess) and hands an unbound
 *      one to the model as structured context (`selectionNote`).
 *
 * Pure except `resolveChoiceAnswer` (one store read), so it runs offline.
 */

const {GatewayError} = require("./errors");
const {ElicitationError} = require("../tools/elicitations");

// A verified offer shows at most this many options — the card is a choice,
// not a catalog. The search tool may price more; the best-fit first ones win.
const MAX_OFFER_OPTIONS = 4;
const MIN_OPTIONS = 2;

// The one option ZIVO adds itself to a card built from a verified offer: "none
// of these — show me others". Unbound (it means no change), so a tap reaches
// the model, which already holds the plan in its EARLIER RESULTS and only has
// to search again (`selectionNote`). The value is a reserved id no catalog
// food can have.
const MORE_OPTIONS_VALUE = "__more__";
const MORE_OPTIONS_LABEL = {
  en: "Other options",
  ar: "اختيارات تانية",
};

/**
 * Appends the "other options" choice to a card pinned to a verified offer.
 * A card with no bindings (a plain question) is returned unchanged — there
 * is nothing to search again for.
 * @param {{spec: !Object, bindings: ?Object}} bound
 * @param {string} lang 'en' | 'ar'
 * @return {{spec: !Object, bindings: ?Object}}
 */
function withMoreOption(bound, lang) {
  if (!bound.bindings) return bound;
  if (bound.spec.options.some((o) => o.value === MORE_OPTIONS_VALUE)) {
    return bound;
  }
  const more = {
    value: MORE_OPTIONS_VALUE,
    label: MORE_OPTIONS_LABEL[lang] || MORE_OPTIONS_LABEL.en,
  };
  return {
    spec: Object.assign({}, bound.spec,
        {options: bound.spec.options.concat([more])}),
    bindings: bound.bindings,
  };
}

/**
 * A lower-cased, trimmed comparison key.
 * @param {*} s
 * @return {string}
 */
function norm(s) {
  return String(s == null ? "" : s).trim().toLowerCase();
}

/**
 * The offer option an `ask_choice` option refers to: by value (the id the
 * offer handed the model), else by a name the offer knows it by.
 * @param {!Object} option A validated ask_choice option.
 * @param {!Array<!Object>} offerOptions
 * @return {?Object}
 */
function matchOffer(option, offerOptions) {
  const byValue = offerOptions.find((o) => o.value === option.value);
  if (byValue) return byValue;
  const keys = [norm(option.value), norm(option.label)];
  return offerOptions.find((o) =>
    (o.aliases || []).some((a) => keys.includes(norm(a)))) || null;
}

/**
 * Pins a validated `ask_choice` spec to the options a search tool actually
 * verified this turn. Returns the spec unchanged when nothing was offered
 * (a plain question — "which plan?", "Recommended or Higher protein?").
 *
 * When an offer exists:
 *   - an option that matches an offered one keeps the model's LABEL (it's in
 *     the user's language) but takes the offer's value, subtitle, metadata
 *     and binding — every figure is the server's;
 *   - an option that matches nothing is DROPPED (it was never verified);
 *   - fewer than two survivors throws, so the model is told to use the
 *     options it was given rather than shipping an invented one.
 *
 * @param {{prompt: string, options: !Array<!Object>, allowMultiple: boolean}}
 *   spec
 * @param {?{tool: string, options: !Array<!Object>}} offer
 * @return {{spec: !Object, bindings: ?Object}}
 */
function bindOfferedOptions(spec, offer) {
  if (!offer || !offer.options.length) return {spec, bindings: null};
  const options = [];
  const bindings = {};
  for (const option of spec.options) {
    const match = matchOffer(option, offer.options);
    if (!match || bindings[match.value]) continue;
    options.push(publicOption(Object.assign({}, match, {label: option.label})));
    if (match.binding) bindings[match.value] = match.binding;
    if (options.length >= MAX_OFFER_OPTIONS) break;
  }
  if (options.length < MIN_OPTIONS) {
    const ids = offer.options.map((o) => `${o.label} (value ${o.value})`)
        .join("; ");
    throw new ElicitationError(
        `Those options aren't the ones ${offer.tool} verified. Offer ` +
        `2–${MAX_OFFER_OPTIONS} of exactly these, with value = the id ` +
        `shown: ${ids}.`);
  }
  return {
    spec: Object.assign({}, spec, {options, allowMultiple: false}),
    bindings: Object.keys(bindings).length ? bindings : null,
  };
}

/**
 * The client-visible shape of an offer option (no aliases / binding).
 * @param {!Object} o
 * @return {!Object}
 */
function publicOption(o) {
  const out = {value: o.value, label: o.label};
  if (o.subtitle) out.subtitle = o.subtitle;
  if (o.metadata) out.metadata = o.metadata;
  return out;
}

// The question the safety-net card asks when the model's prose was nothing
// but the list it should have shown as a card.
const DEFAULT_PROMPT = {
  en: "Which one would you like?",
  ar: "تحب أي واحد فيهم؟",
};

/**
 * Lines that are the options themselves, written as text — a bullet, a
 * numbered item, or a line that is only an offered option's label.
 * @param {string} line
 * @param {!Array<!Object>} offerOptions
 * @return {boolean}
 */
function isListedOptionLine(line, offerOptions) {
  const t = line.trim();
  if (!t) return true;
  if (/^([-*•·]|\d+[.)]|[٠-٩]+[.)])\s+/.test(t)) return true;
  return offerOptions.some((o) =>
    [o.label].concat(o.aliases || []).some((a) => norm(t).startsWith(norm(a))));
}

/**
 * The safety net: a card built from the offer itself, for a turn that found
 * options but answered in prose. The prose minus the listed options becomes
 * the question (so an intro like "I found 3 swaps close to the original
 * calories." survives), else a default question in the user's language.
 *
 * @param {{tool: string, options: !Array<!Object>}} offer
 * @param {string} text The model's final reply.
 * @param {string} lang 'en' | 'ar'
 * @return {{spec: !Object, bindings: ?Object}}
 */
function cardFromOffer(offer, text, lang) {
  const kept = String(text || "").split("\n")
      .filter((line) => !isListedOptionLine(line, offer.options))
      .join("\n").trim();
  const prompt = (kept && kept.length <= 300 ? kept : "") ||
    DEFAULT_PROMPT[lang] || DEFAULT_PROMPT.en;
  const chosen = offer.options.slice(0, MAX_OFFER_OPTIONS);
  const bindings = {};
  for (const o of chosen) if (o.binding) bindings[o.value] = o.binding;
  return {
    spec: {prompt, options: chosen.map(publicOption), allowMultiple: false},
    bindings: Object.keys(bindings).length ? bindings : null,
  };
}

/**
 * Resolves a tapped answer `{requestId, value}` against the stored card.
 * Rejects — with a user-safe message, and before anything is persisted — a
 * card that doesn't exist, one already answered with a different option, and
 * a value that isn't one of its options. The same value re-sent for an
 * already-answered card is accepted only as a retry of the SAME turn
 * (`isRetry`), so a network retry never double-applies and a stale card can
 * never be answered twice.
 *
 * @param {!Object} args
 * @param {!Object} args.store
 * @param {string} args.uid
 * @param {string} args.conversationId
 * @param {*} args.choice The untrusted `{requestId, value}` from the client.
 * @param {boolean} args.isRetry
 * @return {!Promise<{requestId: string, prompt: string, option: !Object,
 *   binding: ?Object}>}
 */
async function resolveChoiceAnswer({
  store, uid, conversationId, choice, isRetry,
}) {
  const requestId = choice && typeof choice.requestId === "string" ?
    choice.requestId.trim() : "";
  const value = choice && typeof choice.value === "string" ?
    choice.value.trim() : "";
  if (!requestId || !value || requestId.length > 200 || value.length > 200) {
    throw new GatewayError("invalid-argument", "That choice isn't valid.");
  }
  const card = await store.getChoiceRequest(uid, conversationId, requestId);
  if (!card || card.kind !== "choice_request") {
    throw new GatewayError(
        "not-found", "That question is no longer available — ask again.");
  }
  const options = card.fields && Array.isArray(card.fields.options) ?
    card.fields.options : [];
  const option = options.find((o) => o && o.value === value);
  if (!option) {
    throw new GatewayError(
        "invalid-argument", "That option isn't one of the choices.");
  }
  if (card.status === "answered" &&
      !(isRetry && card.selectedValue === value)) {
    throw new GatewayError(
        "failed-precondition",
        "You already answered that question — ask again to change it.");
  }
  const binding = card.bindings && card.bindings[value] ?
    card.bindings[value] : null;
  return {requestId, prompt: card.content || "", option, binding, options};
}

/**
 * What the model reads for a tapped answer: the option's label (as the user
 * saw it) plus the structured pick, so it continues from the exact option —
 * never from re-reading its own earlier text.
 * @param {{prompt: string, option: !Object}} resolved
 * @return {string}
 */
function selectionNote(resolved) {
  const o = resolved.option;
  if (o.value === MORE_OPTIONS_VALUE) {
    const shown = (resolved.options || [])
        .filter((x) => x && x.value !== MORE_OPTIONS_VALUE)
        .map((x) => x.label).join(", ");
    return `${o.label}\n[The user tapped "${o.label}" on the question ` +
      `"${resolved.prompt}": none of these suit them (${shown}). Find ` +
      "DIFFERENT ones — don't repeat these — reusing what EARLIER RESULTS " +
      "already holds instead of re-reading it, then ask again.]";
  }
  const meta = o.metadata ? ` ${JSON.stringify(o.metadata)}` : "";
  return `${o.label}\n[The user tapped this option on the question ` +
    `"${resolved.prompt}": value=${o.value}${meta}. This is their answer — ` +
    "continue from it; don't ask the same question again.]";
}

module.exports = {
  MAX_OFFER_OPTIONS,
  MORE_OPTIONS_VALUE,
  withMoreOption,
  bindOfferedOptions,
  cardFromOffer,
  resolveChoiceAnswer,
  selectionNote,
};
