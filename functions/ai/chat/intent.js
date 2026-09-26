/**
 * The turn's INTENT — which area of the user's data a question is about —
 * decided deterministically, before any model call, so the turn can hand the
 * model only that area's prompt and tools (`./scope.js`).
 *
 * No model is involved: a wrong guess here costs the model one `load_tools`
 * call (it can always widen), whereas a classifier call would cost latency and
 * tokens on EVERY turn. When the signals don't agree, or there are none, the
 * answer is AMBIGUOUS — the full prompt and every tool, exactly what every
 * turn got before scoping existed. Only a confident signal narrows.
 *
 * Signals, strongest first:
 *   1. A tapped option bound to a change — the change's own tool says the
 *      area.
 *   2. The message's own words (English, Arabic, Arabizi). One area → that
 *      area; two or more → AMBIGUOUS.
 *   3. The app's entry point (the screen Ask was opened from), when the
 *      client sends one.
 *   4. Continuity — the tools the previous reply ran, when it's recent ("is
 *      there another option?" continues the diet conversation it follows).
 *   5. Small talk / general knowledge with no personal reference → GENERAL.
 *   Otherwise → AMBIGUOUS.
 *
 * Pure: no I/O. `turn.js` hands it what it already loaded.
 */

/** @enum {string} */
const Intent = {
  GENERAL: "general",
  TRAINING: "training",
  DIET: "diet",
  MONEY: "money",
  AMBIGUOUS: "ambiguous",
};

/** The area each tool belongs to; CORE tools ride with every area. */
const TOOL_AREAS = {
  // Training, recovery, sleep, and the workout rotation.
  get_workouts: Intent.TRAINING,
  get_last_workout: Intent.TRAINING,
  get_training_analysis: Intent.TRAINING,
  get_exercise_analysis: Intent.TRAINING,
  get_readiness: Intent.TRAINING,
  get_sleep_summary: Intent.TRAINING,
  get_workout_schedule: Intent.TRAINING,
  preview_workout_change: Intent.TRAINING,
  change_workout_day: Intent.TRAINING,
  // Diet, food and the food log. get_today leads with the diet state (the
  // day's targets, meals, what's left), so it lives here.
  get_today: Intent.DIET,
  get_diet: Intent.DIET,
  get_diet_history: Intent.DIET,
  resolve_food: Intent.DIET,
  calculate_meal_nutrition: Intent.DIET,
  search_food_alternatives: Intent.DIET,
  search_food_product: Intent.DIET,
  log_food: Intent.DIET,
  create_custom_food: Intent.DIET,
  mark_meal_eaten: Intent.DIET,
  replace_meal_item: Intent.DIET,
  // Spending.
  get_expenses: Intent.MONEY,
  summarize_week: Intent.MONEY,
  create_expense: Intent.MONEY,
  edit_expense: Intent.MONEY,
  delete_expense: Intent.MONEY,
};

/** Entry points the app may send (`aiChat`'s `entryPoint`), → area. */
const ENTRY_POINTS = {
  training: Intent.TRAINING,
  workout: Intent.TRAINING,
  readiness: Intent.TRAINING,
  sleep: Intent.TRAINING,
  diet: Intent.DIET,
  food: Intent.DIET,
  money: Intent.MONEY,
  expenses: Intent.MONEY,
};

// How recent the previous reply must be for its area to carry over.
const CONTINUITY_WINDOW_MS = 30 * 60 * 1000;

// ---------------------------------------------------------------------------
// Vocabulary. English/Arabizi words are matched as whole tokens (or, for the
// entries ending in "*", as a token prefix); Arabic words as whole tokens
// after stripping the clitics Arabic glues on (و ف ب ل ك ال).

const EN = {
  [Intent.TRAINING]: [
    "workout*", "train", "training", "trained", "gym", "session*", "split",
    "exercise*", "lift", "lifts", "lifting", "lifted", "sets", "rep",
    "reps", "bench*", "squat*", "deadlift*", "ohp", "curl*", "pullup*",
    "pull-up*", "pushup*", "push-up*",
    "pr", "prs", "1rm", "e1rm", "plateau*", "deload*", "strength",
    "strongest", "stronger", "muscle*", "hypertrophy", "volume", "cardio",
    "recovery", "recover*", "readiness", "sleep*", "slept", "tired",
    "sore*", "legs", "leg", "chest", "shoulder*", "biceps", "triceps",
    "push", "pull", "rotation", "routine",
    "tamreen", "tamrin", "etmarant", "etmaran", "at3ab",
  ],
  [Intent.DIET]: [
    "diet*", "meal*", "eat", "eats", "eating", "ate", "eaten", "food*",
    "calorie*", "kcal", "cal", "cals", "macro*", "protein*", "carb*",
    "fat", "fats", "fiber", "breakfast*", "lunch*", "dinner*", "snack*",
    "nutrition*", "hungry", "hunger", "egg", "eggs", "rice", "chicken",
    "bread", "oats", "tuna", "beef", "fish", "milk", "yogurt", "banana*",
    "apple*", "salad", "pasta", "potato*", "cheese", "koshari", "ful",
    "molokhia", "swap*", "portion*", "grams", "serving*", "supplement*",
    "creatine", "whey", "water", "fasting", "bulk*", "cutting",
    "akl", "akalt", "kalt", "fetar", "ghada", "8ada", "3asha", "dayet",
  ],
  [Intent.MONEY]: [
    "spend*", "spent", "expense*", "cost*", "paid", "pay", "paying",
    "money", "budget*", "wallet", "balance", "egp", "usd", "dollar*",
    "bought", "purchase*", "bill*", "price*", "grocer*", "rent",
    "salary", "cash",
    "sraft", "masaref", "masareef", "flos", "floos", "fulus", "geneh",
    "gneh", "ginih",
  ],
};

const AR = {
  [Intent.TRAINING]: [
    "تمرين", "تمارين", "التمرين", "اتمرن", "اتمرنت", "هتمرن", "بتمرن",
    "تمرنت", "جيم", "الجيم", "جلسه", "بنش", "سكوات", "ديدلفت", "عضل",
    "عضله", "عضلات", "رفع", "اوزان", "مجموعات", "عدات", "تكرار",
    "قوه", "نوم", "نمت", "النوم", "تعبان", "استشفاء", "كارديو", "سبليت",
    "بوش", "بول", "ليج", "صدر", "كتف", "تراي",
  ],
  [Intent.DIET]: [
    "دايت", "الدايت", "رجيم", "اكل", "اكلت", "كلت", "باكل", "هاكل",
    "اكلي", "وجبه", "وجبات", "فطار", "فطور", "غداء", "عشا", "عشاء",
    "سناك", "سعرات", "كالوري", "كالوريز", "بروتين", "كارب",
    "كاربوهيدرات", "دهون", "ملوخيه", "رز", "ارز", "فراخ", "بيض", "عيش",
    "خبز", "لحمه", "تونه", "فول", "كشري", "جرام", "مكمل", "مكملات",
    "كرياتين", "مايه", "مياه", "صيام", "جعان",
  ],
  [Intent.MONEY]: [
    "صرفت", "مصاريف", "مصروف", "مصروفات", "فلوس", "جنيه", "جنيهات",
    "دفعت", "محفظه", "ميزانيه", "اشتريت", "فاتوره", "رصيد", "مرتب",
  ],
};

// "هاي" / "thanks" — a turn that needs no data at all.
const SMALL_TALK = new Set([
  "hi", "hey", "hello", "hiya", "yo", "sup", "thanks", "thank", "thx", "ty",
  "ok", "okay", "k", "cool", "nice", "great", "awesome", "bye", "goodbye",
  "good", "morning", "night", "evening", "you", "so", "much", "lol",
  "shokran", "tamam", "ahlan", "salam", "mashy", "mashi", "7elw", "helw",
  "اهلا", "مرحبا", "هاي", "شكرا", "تمام", "ماشي", "السلام", "عليكم",
  "صباح", "مساء", "الخير", "النور", "حلو", "جميل", "باي", "تسلم",
  // Egyptian greetings — "عامل إيه", "إيه الأخبار", "إزيك يا باشا",
  // "3amel eh", "ezayak" — which fell through to AMBIGUOUS (the full prompt)
  // on the first v7 turns. Only whole-message small talk matches (every token
  // must be here), so "إيه" alone never turns a real question GENERAL.
  "عامل", "عامله", "ايه", "اخبارك", "اخباركم", "الاخبار", "ازيك", "ازيكم",
  "ازايك", "هلا", "سلام", "وعليكم", "الحمد", "لله", "الحمدلله", "كويس",
  "كويسه", "يا", "باشا", "مشكور", "ميرسي", "يسلمو",
  "3amel", "3amla", "eh", "eih", "ezayak", "ezayek", "izayak", "ezzayak",
  "akhbarak", "a5barak", "el", "akhbar", "a5bar", "kwayes", "kowayes",
  "alhamdulillah", "el7amdulillah", "7amdella", "ya", "basha", "merci",
]);

// "What is …", "explain …" — a knowledge question.
const GENERAL_OPENERS = new RegExp("^(what('?s| is| are| does)|" +
  "how (does|do|is|are)|why (do|does|is|are)|explain|define|" +
  "tell me about|who (is|was)|when (did|was)|where (is|are))\\b");

// A question about the user themselves — never GENERAL.
const PERSONAL = new Set([
  "i", "i'm", "im", "i've", "ive", "i'd", "id", "me", "my", "mine", "myself",
  "we", "our", "us", "today", "yesterday", "tonight", "week", "month",
  "should", "can", "log", "add", "delete", "remove", "change",
]);

/**
 * Normalizes Arabic letter variants so one spelling matches them all:
 * alef forms → ا, ta marbuta → ه, alef maqsura → ي; strips diacritics and
 * tatweel.
 * @param {string} s
 * @return {string}
 */
function normalizeArabic(s) {
  return s
      .replace(/[ً-ْـ]/g, "")
      .replace(/[أإآٱ]/g, "ا")
      .replace(/ة/g, "ه")
      .replace(/ى/g, "ي");
}

/**
 * The message's tokens, lower-cased and normalized.
 * @param {string} text
 * @return {!Array<string>}
 */
function tokenize(text) {
  // The Arabic comma, semicolon and question mark (، ؛ ؟) sit inside the
  // Arabic block, so they're split on explicitly: "التمرين؟" is "التمرين".
  return normalizeArabic(String(text || "").toLowerCase())
      .split(/[^a-z0-9؀-ۿ'’-]+|[،؛؟]+/)
      .map((t) => t.replace(/[’]/g, "'").replace(/^['-]+|['-]+$/g, ""))
      .filter(Boolean);
}

/**
 * The forms an Arabic token may take once its glued-on clitics are removed:
 * "والاكل" → [والاكل, الاكل, اكل, …].
 * @param {string} token
 * @return {!Array<string>}
 */
function arabicStems(token) {
  const out = new Set([token]);
  let t = token;
  for (let i = 0; i < 2; i++) {
    const m = /^[وفبلك]/.exec(t);
    if (!m || t.length <= 3) break;
    t = t.slice(1);
    out.add(t);
  }
  for (const form of [...out]) {
    if (form.startsWith("ال") && form.length > 3) out.add(form.slice(2));
    if (form.startsWith("لل") && form.length > 3) out.add(form.slice(2));
  }
  return [...out];
}

/**
 * Pre-built matchers per area: exact word sets and prefix lists.
 * @type {!Object<string, {exact: !Set<string>, prefixes: !Array<string>}>}
 */
const MATCHERS = {};
for (const area of [Intent.TRAINING, Intent.DIET, Intent.MONEY]) {
  const exact = new Set();
  const prefixes = [];
  for (const w of EN[area]) {
    if (w.endsWith("*")) prefixes.push(w.slice(0, -1));
    else exact.add(w);
  }
  for (const w of AR[area]) exact.add(normalizeArabic(w));
  MATCHERS[area] = {exact, prefixes};
}

// Figures with units that name an area on their own: "40 EGP", "100g".
const MONEY_AMOUNT = /\d+(\.\d+)?\s*(egp|le|l\.e|usd|\$|جنيه|ج\.م)/;
const FOOD_AMOUNT =
  /\d+(\.\d+)?\s*(g|gm|gr|grams?|kcal|cal|جرام|جم|سعر)(?![a-z])/;

/**
 * The areas the message's own words point at.
 * @param {string} text
 * @return {!Set<string>}
 */
function areasInText(text) {
  const found = new Set();
  const lower = normalizeArabic(String(text || "").toLowerCase());
  if (MONEY_AMOUNT.test(lower)) found.add(Intent.MONEY);
  if (FOOD_AMOUNT.test(lower)) found.add(Intent.DIET);
  for (const token of tokenize(text)) {
    const isArabic = /[؀-ۿ]/.test(token);
    const forms = isArabic ? arabicStems(token) : [token];
    for (const area of Object.keys(MATCHERS)) {
      const {exact, prefixes} = MATCHERS[area];
      if (forms.some((f) => exact.has(f)) ||
          (!isArabic && prefixes.some((p) => token.startsWith(p)))) {
        found.add(area);
      }
    }
  }
  return found;
}

/**
 * Whether the message is small talk or a general-knowledge question with no
 * personal reference — the only messages that go GENERAL.
 * @param {string} text
 * @return {boolean}
 */
function isGeneral(text) {
  const tokens = tokenize(text);
  if (!tokens.length) return false;
  if (tokens.length <= 5 && tokens.every((t) => SMALL_TALK.has(t))) {
    return true;
  }
  const lower = String(text || "").trim().toLowerCase();
  return GENERAL_OPENERS.test(lower) &&
    !tokens.some((t) => PERSONAL.has(t));
}

/**
 * The single area of a list of tool names, or null when they span several
 * areas (or name none).
 * @param {!Array<string>} toolNames
 * @return {?string}
 */
function areaOfTools(toolNames) {
  const areas = new Set(toolNames
      .map((n) => TOOL_AREAS[n])
      .filter(Boolean));
  return areas.size === 1 ? [...areas][0] : null;
}

/**
 * Classifies one turn.
 * @param {!Object} args
 * @param {string} args.message The user's words (or a tapped option's label).
 * @param {?string=} args.boundTool The tool a tapped option is bound to.
 * @param {?string=} args.entryPoint Untrusted — the screen Ask was opened from.
 * @param {!Array<!Object>=} args.history Persisted messages, oldest first
 *   (`store.getRecentMessages`), for continuity.
 * @param {!Date=} args.now
 * @return {{intent: string, reason: string}}
 */
function classifyIntent({message, boundTool, entryPoint, history, now}) {
  const boundArea = boundTool ? TOOL_AREAS[boundTool] : null;
  if (boundArea) return {intent: boundArea, reason: "bound_choice"};

  const areas = areasInText(message);
  if (areas.size === 1) return {intent: [...areas][0], reason: "keywords"};
  if (areas.size > 1) return {intent: Intent.AMBIGUOUS, reason: "multi_area"};

  const entry = typeof entryPoint === "string" ?
    ENTRY_POINTS[entryPoint.trim().toLowerCase()] : null;
  if (entry) return {intent: entry, reason: "entry_point"};

  const carried = continuityArea(history, now);
  if (carried) return {intent: carried, reason: "continuity"};

  if (isGeneral(message)) return {intent: Intent.GENERAL, reason: "general"};
  return {intent: Intent.AMBIGUOUS, reason: "no_signal"};
}

/**
 * The area the conversation was just in: the tools the latest reply ran (its
 * activity, or the change a proposal card names), when that reply is recent.
 * @param {(!Array<!Object>|undefined)} history
 * @param {(!Date|undefined)} now
 * @return {?string}
 */
function continuityArea(history, now) {
  const list = Array.isArray(history) ? history : [];
  for (let i = list.length - 1; i >= 0; i--) {
    const m = list[i];
    if (!m || m.role !== "assistant") continue;
    const at = m.createdAt instanceof Date ? m.createdAt.getTime() : NaN;
    if (now && Number.isFinite(at) &&
        now.getTime() - at > CONTINUITY_WINDOW_MS) {
      return null;
    }
    const tools = [];
    if (Array.isArray(m.activity)) {
      for (const a of m.activity) if (a && a.tool) tools.push(a.tool);
    }
    if (m.actionKind) tools.push(m.actionKind);
    if (m.context && Array.isArray(m.context.entries)) {
      for (const e of m.context.entries) if (e && e.tool) tools.push(e.tool);
    }
    return areaOfTools(tools);
  }
  return null;
}

module.exports = {
  Intent,
  TOOL_AREAS,
  ENTRY_POINTS,
  classifyIntent,
  areasInText,
  isGeneral,
  areaOfTools,
  normalizeArabic,
};
