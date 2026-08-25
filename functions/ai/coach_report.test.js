/**
 * Offline unit tests for `./coach_report.js` — the weekly recap builder,
 * renderer, and deliverer. Plain in-memory store fakes; no Firestore, no
 * scheduler, no network.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {
  buildWeeklyReport,
  renderWeeklyReport,
  deliverWeeklyReport,
} = require("./coach_report");

const UID = "user-1";
// A Monday noon UTC — the trailing 7-day window is Tue..Mon.
const NOW = new Date("2026-08-24T12:00:00Z");

/**
 * A plan mirroring the importer's shape: one every-day template.
 * @param {!Array<Object>} meals
 * @return {!Object}
 */
function planWith(meals) {
  return {
    id: "plan-1",
    name: "Cut",
    status: "active",
    days: [{weekday: null, label: "Every day", meals}],
  };
}

const BREAKFAST = {
  id: "breakfast",
  label: "Breakfast",
  items: [{name: "Oats", quantity: 60, unit: "g", calories: 220,
    proteinG: 8, carbsG: 38, fatG: 4}],
};
const DINNER = {
  id: "dinner",
  label: "Dinner",
  items: [{name: "Chicken", quantity: 200, unit: "g", calories: 330,
    proteinG: 62, carbsG: 0, fatG: 7}],
};

test("buildWeeklyReport aggregates workouts, adherence, and spend", async () => {
  const store = {
    listWorkouts: async (uid, range) => {
      assert.equal(uid, UID);
      // Trailing 7 days ending at NOW.
      assert.equal(range.toMs, NOW.getTime());
      return [
        {title: "Push", durationMinutes: 55},
        {title: "Pull", durationMinutes: 50},
        {title: "Legs", durationMinutes: 40},
      ];
    },
    listExpenses: async () => [
      {amountMinor: 12000, currency: "EGP", category: "groceries"},
      {amountMinor: 4000, currency: "EGP", category: "coffee"},
      {amountMinor: 2500, currency: "EGP", category: "coffee"},
    ],
    getActiveDietPlan: async () => planWith([BREAKFAST, DINNER]),
    listDietEntries: async (uid, dayKey) => {
      // Breakfast eaten every day, dinner never.
      assert.match(dayKey, /^\d{4}-\d{2}-\d{2}$/);
      return [{mealId: "breakfast", eaten: true}];
    },
  };

  const stats = await buildWeeklyReport({store, uid: UID, now: NOW});

  assert.deepEqual(stats.workouts, {count: 3, totalMinutes: 145});
  assert.equal(stats.diet.active, true);
  assert.equal(stats.diet.daysCovered, 7);
  assert.equal(stats.diet.mealsPlanned, 14);
  assert.equal(stats.diet.mealsEaten, 7);
  assert.equal(stats.diet.kcalTarget, 7 * 550);
  assert.equal(stats.diet.kcalConsumed, 7 * 220);
  assert.deepEqual(stats.spendByCurrency, {
    EGP: {totalMinor: 18500, topCategory: "groceries"},
  });
});

test("renderWeeklyReport speaks in concrete numbers", async () => {
  const text = renderWeeklyReport({
    rangeEnd: NOW,
    workouts: {count: 3, totalMinutes: 145},
    diet: {
      active: true, daysCovered: 7, mealsPlanned: 14, mealsEaten: 7,
      kcalTarget: 3850, kcalConsumed: 1540,
    },
    spendByCurrency: {EGP: {totalMinor: 18500, topCategory: "groceries"}},
  });

  assert.match(text, /Weekly recap — Aug 18–24/);
  assert.match(text, /3 sessions · 145 min total/);
  assert.match(text, /checked off 7 of 14 planned meals \(50%\)/);
  assert.match(text, /~1,540 of ~3,850 kcal/);
  assert.match(text, /185\.00 EGP \(most on groceries\)/);
});

test("an empty week renders honest zeros, not fabricated activity", async () => {
  const store = {
    listWorkouts: async () => [],
    listExpenses: async () => [],
    getActiveDietPlan: async () => null,
    listDietEntries: async () => [],
  };

  const stats = await buildWeeklyReport({store, uid: UID, now: NOW});
  const text = renderWeeklyReport(stats);

  assert.match(text, /no sessions logged this week/);
  assert.match(text, /no active plan to check against/);
  assert.match(text, /nothing logged this week/);
});

test("a plan whose items state no calories skips the kcal clause entirely",
    async () => {
      const store = {
        listWorkouts: async () => [],
        listExpenses: async () => [],
        getActiveDietPlan: async () => planWith([{
          id: "m1",
          label: "Lunch",
          items: [{name: "Rice", quantity: 1, unit: "plate",
            calories: null, proteinG: null, carbsG: null, fatG: null}],
        }]),
        listDietEntries: async () => [{mealId: "m1", eaten: true}],
      };

      const stats = await buildWeeklyReport({store, uid: UID, now: NOW});
      const text = renderWeeklyReport(stats);

      // Meals are still counted — only the unstated nutrient stays silent.
      assert.match(text, /checked off 7 of 7 planned meals \(100%\)/);
      assert.doesNotMatch(text, /kcal/);
      assert.equal(stats.diet.kcalTarget, null);
      assert.equal(stats.diet.kcalConsumed, null);
    });

test("deliverWeeklyReport appends to the latest conversation and bumps it",
    async () => {
      const writes = [];
      const store = {
        latestConversationId: async (uid) => {
          assert.equal(uid, UID);
          return "convo-9";
        },
        listWorkouts: async () => [],
        listExpenses: async () => [],
        getActiveDietPlan: async () => null,
        listDietEntries: async () => [],
        appendMessage: async (uid, conversationId, message) => {
          writes.push({uid, conversationId, message});
          return "msg-1";
        },
        touchConversation: async (uid, conversationId, fields) => {
          writes.push({uid, conversationId, fields});
        },
      };

      const delivered = await deliverWeeklyReport({
        store, uid: UID, now: NOW,
      });

      assert.equal(delivered, true);
      assert.equal(writes.length, 2);
      assert.equal(writes[0].conversationId, "convo-9");
      assert.equal(writes[0].message.role, "assistant");
      assert.equal(writes[0].message.kind, "coach_report");
      assert.match(writes[0].message.content, /Weekly recap — /);
    });

test("a user with no conversations is skipped without any write", async () => {
  let wrote = false;
  const store = {
    latestConversationId: async () => null,
    appendMessage: async () => {
      wrote = true;
    },
  };

  const delivered = await deliverWeeklyReport({store, uid: UID, now: NOW});

  assert.equal(delivered, false);
  assert.equal(wrote, false);
});
