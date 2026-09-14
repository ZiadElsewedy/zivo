/**
 * The weekly coach report — a PROACTIVE digest pushed into the user's most
 * recent Ask conversation by the scheduled `weeklyCoachReport` function, so
 * the assistant speaks first with specifics instead of only answering when
 * asked. Mirrors the rest of `./ai/`: pure and store-seamed here (no SDK
 * imports), so it runs offline under `node --test`.
 *
 * Delivery is deliberately conservative: a user with NO conversation hasn't
 * used Ask at all, and a silent new conversation appearing in their list
 * would be surprising — they're skipped. There is no push notification yet
 * (the app has no FCM wiring); opening Ask shows the recap waiting there.
 *
 * The window is the trailing 7 days ending "now" (the scheduler's run time),
 * computed in the server's UTC day boundaries — the same convention as every
 * other date computation in this backend (`./dates.js`'s header note).
 *
 * The text is a deterministic template on purpose: no model call means zero
 * cost per user per week, fully testable output, and it can't hallucinate
 * numbers. The live coach elaborates when the user replies to it.
 */

const {dayKeyFor, resolveDietDay} = require("./dates");
const {dayNutrition} = require("./tools");

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Aggregates one user's trailing-7-day week across the three surfaces worth
 * coaching on: training done, diet adherence (checked-off meals vs planned,
 * kcal consumed vs targeted), and spending.
 * @param {!Object} store
 * @param {string} uid
 * @param {!Date} now
 * @return {!Promise<!Object>} stats — all numbers may be 0/null; `text` is
 *   always renderable.
 */
async function buildWeeklyReport({store, uid, now}) {
  const fromMs = now.getTime() - 7 * DAY_MS;
  const range = {fromMs, toMs: now.getTime()};

  const [workouts, expenses, plan] = await Promise.all([
    store.listWorkouts(uid, range),
    store.listExpenses(uid, range),
    store.getActiveDietPlan(uid),
  ]);

  // Diet adherence walks each of the 7 days individually: which meals that
  // day's plan slot prescribed, and how many of them are checked off.
  let daysCovered = 0;
  let mealsPlanned = 0;
  let mealsEaten = 0;
  let kcalTarget = null;
  let kcalConsumed = null;
  if (plan) {
    for (let i = 0; i < 7; i++) {
      const day = new Date(now.getTime() - i * DAY_MS);
      const dietDay = resolveDietDay(plan.days, day);
      if (!dietDay || dietDay.meals.length === 0) continue;
      daysCovered++;
      mealsPlanned += dietDay.meals.length;
      const entries = await store.listDietEntries(uid, dayKeyFor(day));
      const eatenIds = new Set(
          entries.filter((e) => e.eaten).map((e) => e.mealId),
      );
      mealsEaten += dietDay.meals.filter((m) => eatenIds.has(m.id)).length;
      const totals = dayNutrition(dietDay.meals);
      if (totals.kcal != null) {
        kcalTarget = (kcalTarget || 0) + totals.kcal;
        kcalConsumed =
          (kcalConsumed || 0) +
          dietDay.meals
              .filter((m) => eatenIds.has(m.id))
              .reduce(
                  (sum, m) => sum + (sumMealKcal(m.items) || 0), 0);
      }
    }
  }

  // Spend: sum per currency (never mix units); the dominant currency leads
  // the rendered line and any minority currencies are listed after it.
  const totalMinorByCurrency = {};
  const categoryMinorByCurrency = {};
  for (const e of expenses) {
    const c = e.currency || "EGP";
    totalMinorByCurrency[c] = (totalMinorByCurrency[c] || 0) + e.amountMinor;
    const byCategory = categoryMinorByCurrency[c] ||
      (categoryMinorByCurrency[c] = {});
    byCategory[e.category] = (byCategory[e.category] || 0) + e.amountMinor;
  }

  return {
    rangeEnd: now,
    workouts: {
      count: workouts.length,
      totalMinutes: workouts.reduce((n, w) => n + (w.durationMinutes || 0), 0),
    },
    diet: {
      active: !!plan && daysCovered > 0,
      daysCovered,
      mealsPlanned,
      mealsEaten,
      kcalTarget,
      kcalConsumed,
    },
    spendByCurrency: Object.fromEntries(
        Object.entries(totalMinorByCurrency).map(([c, minor]) => [
          c,
          {
            totalMinor: minor,
            topCategory: topKey(categoryMinorByCurrency[c] || {}),
          },
        ]),
    ),
  };
}

/**
 * Sums an items array's stated calories, or null when none state any — the
 * same honest-null rule as `dayNutrition`.
 * @param {!Array<Object>} items
 * @return {?number}
 */
function sumMealKcal(items) {
  let total = 0;
  let stated = false;
  for (const item of items || []) {
    if (typeof item.calories === "number" && Number.isFinite(item.calories)) {
      total += item.calories;
      stated = true;
    }
  }
  return stated ? total : null;
}

/**
 * The category key holding the largest value in a minor-unit map.
 * @param {!Object<string, number>} byCategory
 * @return {?string}
 */
function topKey(byCategory) {
  let best = null;
  for (const key of Object.keys(byCategory)) {
    if (best === null || byCategory[key] > byCategory[best]) best = key;
  }
  return best;
}

/**
 * Renders the deterministic recap text — an assistant message the user reads
 * directly, written to be coach-voiced but strictly number-honest.
 * @param {!Object} stats From `buildWeeklyReport`.
 * @return {string}
 */
function renderWeeklyReport(stats) {
  const lines = [];

  lines.push(`Weekly recap — ${rangeLabel(stats.rangeEnd)}`);

  if (stats.workouts.count > 0) {
    lines.push(
        `Training: ${stats.workouts.count} session` +
        `${stats.workouts.count === 1 ? "" : "s"}` +
        (stats.workouts.totalMinutes > 0 ?
          ` · ${stats.workouts.totalMinutes} min total` : "") +
        ".");
  } else {
    lines.push("Training: no sessions logged this week.");
  }

  if (!stats.diet.active) {
    lines.push("Diet: no active plan to check against.");
  } else if (stats.diet.mealsPlanned === 0) {
    lines.push("Diet: your plan had no meals scheduled this week.");
  } else {
    const pct =
      Math.round(stats.diet.mealsEaten / stats.diet.mealsPlanned * 100);
    let line = "Diet: you checked off " +
      `${stats.diet.mealsEaten} of ${stats.diet.mealsPlanned} planned meals ` +
      `(${pct}%)`;
    if (stats.diet.kcalTarget != null) {
      line += ` · ~${grouped(stats.diet.kcalConsumed)} of ` +
        `~${grouped(stats.diet.kcalTarget)} kcal`;
    }
    lines.push(line + ".");
  }

  const currencies = Object.keys(stats.spendByCurrency);
  if (currencies.length === 0) {
    lines.push("Spend: nothing logged this week.");
  } else {
    const parts = currencies.map((c) => {
      const s = stats.spendByCurrency[c];
      const major = (s.totalMinor / 100).toFixed(2);
      return s.topCategory ?
        `${major} ${c} (most on ${s.topCategory})` :
        `${major} ${c}`;
    });
    lines.push(`Spend: ${parts.join(" · ")}.`);
  }

  lines.push("");
  lines.push("Reply with anything you want to dig into — I have the details.");

  return lines.join("\n");
}

/**
 * 'Aug 18–24' style label for the 7 days ending at `end` (UTC month names —
 * matches the server-side date convention); the month is omitted on the
 * right side when both ends share it.
 * @param {!Date} end
 * @return {string}
 */
function rangeLabel(end) {
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const start = new Date(end.getTime() - 6 * DAY_MS);
  const startPart = `${months[start.getUTCMonth()]} ${start.getUTCDate()}`;
  const endPart = start.getUTCMonth() === end.getUTCMonth() ?
    `${end.getUTCDate()}` :
    `${months[end.getUTCMonth()]} ${end.getUTCDate()}`;
  return `${startPart}–${endPart}`;
}

/**
 * Thousands-separated integer, e.g. 15400 → '15,400'.
 * @param {number} value
 * @return {string}
 */
function grouped(value) {
  return Math.round(value).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

/**
 * Builds the report and appends it as an assistant message in the user's
 * most recent conversation (bumping its `updatedAt` so it sorts back to the
 * top). Users with no conversations are skipped entirely — see the module
 * header.
 * @param {!Object} store
 * @param {string} uid
 * @param {!Date} now
 * @return {!Promise<boolean>} Whether a message was delivered.
 */
async function deliverWeeklyReport({store, uid, now}) {
  const conversationId = await store.latestConversationId(uid);
  if (!conversationId) return false;

  const stats = await buildWeeklyReport({store, uid, now});
  const text = renderWeeklyReport(stats);

  await store.appendMessage(uid, conversationId, {
    role: "assistant",
    kind: "coach_report",
    content: text,
    createdAt: now,
  });
  // Bumps updatedAt so the conversation resurfaces at the top of the list;
  // the create path never runs (we just read the id).
  await store.touchConversation(uid, conversationId, {
    title: "",
    createdAt: now,
    updatedAt: now,
  });
  return true;
}

module.exports = {buildWeeklyReport, renderWeeklyReport, deliverWeeklyReport};
