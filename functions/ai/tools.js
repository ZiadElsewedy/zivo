/**
 * The server-side read-only tool registry for the `aiChat` gateway
 * (`functions/ai/gateway.js`). Every tool is `uid`-scoped and reads through
 * the injected `store` seam (`functions/ai/store.js` in production, a plain
 * in-memory fake in tests) — nothing here touches Firestore or any SDK
 * directly, so it runs offline under `node --test`.
 *
 * Strictly READ-ONLY: no tool writes, creates, or deletes anything.
 */

const {
  dayKeyFor,
  dayRangeMs,
  weekRangeMs,
  monthRangeMs,
  resolveDietDay,
} = require("./dates");

/**
 * ISO string for `date`, or null.
 * @param {?Date} date
 * @return {?string}
 */
function iso(date) {
  return date ? date.toISOString() : null;
}

/**
 * A short excerpt of `body` centered on the first case-insensitive match of
 * `query`, ellipsized at either end when truncated.
 * @param {string} body
 * @param {string} query
 * @return {string}
 */
function snippetAround(body, query) {
  const lower = body.toLowerCase();
  const idx = lower.indexOf(query.toLowerCase());
  if (idx === -1) return body.slice(0, 140);
  const radius = 60;
  const start = Math.max(0, idx - radius);
  const end = Math.min(body.length, idx + query.length + radius);
  const prefix = start > 0 ? "…" : "";
  const suffix = end < body.length ? "…" : "";
  return `${prefix}${body.slice(start, end)}${suffix}`;
}

/**
 * `tasks` filtered by 'open' (default, not done) | 'done' | 'all'.
 * @param {!Array<Object>} tasks
 * @param {string} filter
 * @return {!Array<Object>}
 */
function filterTasks(tasks, filter) {
  if (filter === "done") return tasks.filter((t) => t.done);
  if (filter === "all") return tasks;
  return tasks.filter((t) => !t.done);
}

const TODAY_TOOL = {
  name: "get_today",
  description:
    "A composed snapshot of 'today': schedule events, tasks due today or " +
    "overdue (and still open), university items due today, today's " +
    "workout(s), and today's diet plan with which meals are eaten.",
  inputSchema: {type: "object", properties: {}},
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @param {Date} now
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input, now) {
    const {fromMs, toMs} = dayRangeMs(now);
    const [schedule, tasks, university, workouts, plan] = await Promise.all([
      store.listSchedule(uid, {fromMs, toMs}),
      store.listTasks(uid),
      store.listUniversity(uid),
      store.listWorkouts(uid, {fromMs, toMs}),
      store.getActiveDietPlan(uid),
    ]);

    const tasksDueTodayOrOverdue = tasks.filter(
        (t) => !t.done && t.due && t.due.getTime() < toMs,
    );
    const universityDueToday = university.filter(
        (u) =>
          !u.done && u.due && u.due.getTime() >= fromMs &&
          u.due.getTime() < toMs,
    );

    const dietDay = resolveDietDay(plan ? plan.days : [], now);
    let diet = null;
    if (plan && dietDay) {
      const entries = await store.listDietEntries(uid, dayKeyFor(now));
      const eaten = new Set(
          entries.filter((e) => e.eaten).map((e) => e.mealId),
      );
      diet = {
        planName: plan.name,
        dayLabel: dietDay.label,
        meals: dietDay.meals.map((m) => ({
          id: m.id,
          label: m.label,
          eaten: eaten.has(m.id),
        })),
      };
    }

    return {
      schedule: schedule.map((e) => ({title: e.title, start: iso(e.start)})),
      tasksDueOrOverdue: tasksDueTodayOrOverdue.map((t) => ({
        title: t.title,
        priority: t.priority,
        due: iso(t.due),
      })),
      universityDueToday: universityDueToday.map((u) => ({
        title: u.title,
        type: u.type,
        due: iso(u.due),
        courseName: u.courseName,
      })),
      workouts: workouts.map((w) => ({
        title: w.title,
        performedAt: iso(w.performedAt),
        durationMinutes: w.durationMinutes,
      })),
      diet,
    };
  },
};

const TASKS_TOOL = {
  name: "get_tasks",
  description:
    "List the user's tasks. filter: 'open' (default, not done), 'done', " +
    "or 'all'.",
  inputSchema: {
    type: "object",
    properties: {filter: {type: "string", enum: ["open", "done", "all"]}},
  },
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input) {
    const tasks = await store.listTasks(uid);
    const filtered = filterTasks(tasks, input.filter || "open");
    return {
      tasks: filtered.map((t) => ({
        title: t.title,
        done: t.done,
        priority: t.priority,
        due: iso(t.due),
      })),
    };
  },
};

const SCHEDULE_TOOL = {
  name: "get_schedule",
  description: "List schedule events. range: 'today' (default) or 'week'.",
  inputSchema: {
    type: "object",
    properties: {range: {type: "string", enum: ["today", "week"]}},
  },
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @param {Date} now
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input, now) {
    const range = input.range === "week" ? weekRangeMs(now) : dayRangeMs(now);
    const events = await store.listSchedule(uid, range);
    return {
      range: input.range === "week" ? "week" : "today",
      events: events.map((e) => ({title: e.title, start: iso(e.start)})),
    };
  },
};

const EXPENSES_TOOL = {
  name: "get_expenses",
  description:
    "List expenses and totals by category. range: 'week' (default) or " +
    "'month'. category: optional exact-match filter.",
  inputSchema: {
    type: "object",
    properties: {
      range: {type: "string", enum: ["week", "month"]},
      category: {type: "string"},
    },
  },
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @param {Date} now
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input, now) {
    const range =
      input.range === "month" ? monthRangeMs(now) : weekRangeMs(now);
    const all = await store.listExpenses(uid, range);
    const items = input.category ?
      all.filter((e) => e.category === input.category) :
      all;

    const totalByCategory = {};
    let totalMinor = 0;
    let currency = null;
    for (const e of items) {
      totalByCategory[e.category] =
        (totalByCategory[e.category] || 0) + e.amountMinor;
      totalMinor += e.amountMinor;
      currency = currency || e.currency;
    }

    return {
      range: input.range === "month" ? "month" : "week",
      currency,
      totalMinor,
      totalByCategory,
      items: items.map((e) => ({
        amountMinor: e.amountMinor,
        currency: e.currency,
        category: e.category,
        note: e.note || null,
        spentAt: iso(e.spentAt),
      })),
    };
  },
};

const UNIVERSITY_TOOL = {
  name: "get_university",
  description:
    "List university items (assignments/exams). filter: 'open' " +
    "(default, not done) or 'all'.",
  inputSchema: {
    type: "object",
    properties: {filter: {type: "string", enum: ["open", "all"]}},
  },
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input) {
    const items = await store.listUniversity(uid);
    const filtered =
      input.filter === "all" ? items : items.filter((i) => !i.done);
    return {
      items: filtered.map((i) => ({
        title: i.title,
        type: i.type,
        due: iso(i.due),
        courseName: i.courseName,
        done: i.done,
      })),
    };
  },
};

const WORKOUTS_TOOL = {
  name: "get_workouts",
  description:
    "List workout sessions with exercise summaries. range: 'week' " +
    "(default) or 'month'.",
  inputSchema: {
    type: "object",
    properties: {range: {type: "string", enum: ["week", "month"]}},
  },
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @param {Date} now
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input, now) {
    const range =
      input.range === "month" ? monthRangeMs(now) : weekRangeMs(now);
    const workouts = await store.listWorkouts(uid, range);
    return {
      range: input.range === "month" ? "month" : "week",
      workouts: workouts.map((w) => ({
        title: w.title,
        performedAt: iso(w.performedAt),
        durationMinutes: w.durationMinutes,
        exercises: (w.exercises || []).map((e) => ({
          name: e.name,
          sets: e.sets,
          reps: e.reps,
          weightKg: e.weightKg,
        })),
      })),
    };
  },
};

const DIET_TOOL = {
  name: "get_diet",
  description:
    "The active diet plan's meals for a day (default today), with " +
    "calories/macros and which meals are already eaten. day: optional " +
    "'yyyy-MM-dd'.",
  inputSchema: {
    type: "object",
    properties: {day: {type: "string"}},
  },
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @param {Date} now
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input, now) {
    const date = input.day ? new Date(`${input.day}T00:00:00`) : now;
    const plan = await store.getActiveDietPlan(uid);
    if (!plan) return {plan: null};

    const dietDay = resolveDietDay(plan.days, date);
    if (!dietDay) return {plan: plan.name, day: null};

    const entries = await store.listDietEntries(uid, dayKeyFor(date));
    const eaten = new Set(
        entries.filter((e) => e.eaten).map((e) => e.mealId),
    );

    return {
      plan: plan.name,
      day: dietDay.label,
      meals: dietDay.meals.map((m) => ({
        id: m.id,
        label: m.label,
        eaten: eaten.has(m.id),
        items: m.items.map((it) => ({
          name: it.name,
          quantity: it.quantity,
          unit: it.unit,
          calories: it.calories,
          proteinG: it.proteinG,
          carbsG: it.carbsG,
          fatG: it.fatG,
        })),
      })),
    };
  },
};

const SEARCH_NOTES_TOOL = {
  name: "search_notes",
  description:
    "Case-insensitive substring search over the user's note bodies (not " +
    "full-text). Returns matching snippets.",
  inputSchema: {
    type: "object",
    properties: {query: {type: "string"}},
    required: ["query"],
  },
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input) {
    const query = (input.query || "").trim();
    if (!query) return {matches: []};
    const matches = await store.searchNotes(uid, query);
    return {
      matches: matches.map((n) => ({
        title: n.title || null,
        snippet: snippetAround(n.body || "", query),
        updatedAt: iso(n.updatedAt),
      })),
    };
  },
};

const SUMMARIZE_WEEK_TOOL = {
  name: "summarize_week",
  description:
    "A composed digest of the current week across schedule, tasks, " +
    "university, expenses, workouts, and diet.",
  inputSchema: {type: "object", properties: {}},
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @param {Date} now
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input, now) {
    const week = weekRangeMs(now);
    const [schedule, tasks, university, expenses, workouts, plan] =
      await Promise.all([
        store.listSchedule(uid, week),
        store.listTasks(uid),
        store.listUniversity(uid),
        store.listExpenses(uid, week),
        store.listWorkouts(uid, week),
        store.getActiveDietPlan(uid),
      ]);

    const openTasksDueThisWeek = tasks.filter(
        (t) =>
          !t.done && t.due && t.due.getTime() >= week.fromMs &&
          t.due.getTime() < week.toMs,
    );
    const universityDueThisWeek = university.filter(
        (u) =>
          !u.done && u.due && u.due.getTime() >= week.fromMs &&
          u.due.getTime() < week.toMs,
    );

    let totalMinor = 0;
    const totalByCategory = {};
    let currency = null;
    for (const e of expenses) {
      totalMinor += e.amountMinor;
      totalByCategory[e.category] =
        (totalByCategory[e.category] || 0) + e.amountMinor;
      currency = currency || e.currency;
    }

    return {
      schedule: schedule.map((e) => ({title: e.title, start: iso(e.start)})),
      openTasksDueThisWeek: openTasksDueThisWeek.map((t) => ({
        title: t.title,
        due: iso(t.due),
      })),
      universityDueThisWeek: universityDueThisWeek.map((u) => ({
        title: u.title,
        type: u.type,
        due: iso(u.due),
      })),
      expenses: {currency, totalMinor, totalByCategory},
      workouts: workouts.map((w) => ({
        title: w.title,
        performedAt: iso(w.performedAt),
      })),
      dietPlan: plan ? plan.name : null,
    };
  },
};

const tools = [
  TODAY_TOOL,
  TASKS_TOOL,
  SCHEDULE_TOOL,
  EXPENSES_TOOL,
  UNIVERSITY_TOOL,
  WORKOUTS_TOOL,
  DIET_TOOL,
  SEARCH_NOTES_TOOL,
  SUMMARIZE_WEEK_TOOL,
];

const toolsByName = new Map(tools.map((t) => [t.name, t]));

module.exports = {tools, toolsByName};
