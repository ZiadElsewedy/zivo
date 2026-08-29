/**
 * Offline unit tests for the read-only tool registry (`./tools.js`), each
 * against a plain in-memory fake `store`. No Firestore, no network.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {toolsByName} = require("./tools");

const UID = "user-1";
const NOW = new Date("2026-08-17T12:00:00");

test("get_expenses totals amounts by category for the requested range",
    async () => {
      const tool = toolsByName.get("get_expenses");
      const store = {
        listExpenses: async (uid, range) => {
          assert.equal(uid, UID);
          assert.equal(typeof range.fromMs, "number");
          assert.equal(typeof range.toMs, "number");
          return [
            {id: "e1", amountMinor: 500, currency: "USD", category: "coffee",
              note: null, spentAt: new Date("2026-08-16T09:00:00")},
            {id: "e2", amountMinor: 300, currency: "USD", category: "coffee",
              note: null, spentAt: new Date("2026-08-15T09:00:00")},
            {id: "e3", amountMinor: 1200, currency: "USD", category: "groceries",
              note: "weekly shop", spentAt: new Date("2026-08-14T09:00:00")},
          ];
        },
      };

      const result = await tool.execute(store, UID, {}, NOW);

      assert.equal(result.totalMinor, 2000);
      assert.deepEqual(result.totalByCategory, {coffee: 800, groceries: 1200});
      assert.equal(result.currency, "USD");
      assert.equal(result.items.length, 3);
      // Each item surfaces its stable id — the handle edit/delete target.
      assert.deepEqual(result.items.map((e) => e.id), ["e1", "e2", "e3"]);
    });

test("get_expenses filters by category when given", async () => {
  const tool = toolsByName.get("get_expenses");
  const store = {
    listExpenses: async () => [
      {amountMinor: 500, currency: "USD", category: "coffee", note: null,
        spentAt: new Date("2026-08-16T09:00:00")},
      {amountMinor: 1200, currency: "USD", category: "groceries", note: null,
        spentAt: new Date("2026-08-14T09:00:00")},
    ],
  };

  const result = await tool.execute(store, UID, {category: "coffee"}, NOW);

  assert.equal(result.totalMinor, 500);
  assert.deepEqual(result.totalByCategory, {coffee: 500});
  assert.equal(result.items.length, 1);
});

test("get_diet returns null plan when there is none", async () => {
  const tool = toolsByName.get("get_diet");
  const store = {getActiveDietPlan: async () => null};

  const result = await tool.execute(store, UID, {}, NOW);

  // The date is always stated: nothing else in a turn tells the model what
  // day the answer is about.
  assert.deepEqual(result, {date: "2026-08-17", plan: null});
});

const DIET_PLAN = {
  name: "Cut",
  status: "active",
  days: [
    {
      weekday: null,
      label: "Every day",
      meals: [
        {
          id: "breakfast",
          label: "Breakfast",
          items: [
            {name: "Oats", quantity: 60, unit: "g", calories: 220,
              proteinG: 8, carbsG: 38, fatG: 4},
          ],
        },
        {
          id: "dinner",
          label: "Dinner",
          items: [
            {name: "Chicken", quantity: 200, unit: "g", calories: 330,
              proteinG: 62, carbsG: 0, fatG: 7},
          ],
        },
      ],
    },
  ],
};

test("get_diet reports target-vs-consumed nutrition for the resolved day",
    async () => {
      const tool = toolsByName.get("get_diet");
      const store = {
        getActiveDietPlan: async () => DIET_PLAN,
        listDietEntries: async (uid, dayKey) => {
          assert.equal(uid, UID);
          assert.equal(dayKey, "2026-08-17");
          return [{mealId: "breakfast", eaten: true}];
        },
      };

      const result = await tool.execute(store, UID, {}, NOW);

      assert.equal(result.date, "2026-08-17");
      assert.deepEqual(result.nutrition.target, {
        kcal: 550, proteinG: 70, carbsG: 38, fatG: 11, estimated: false,
      });
      // Only breakfast is checked off, so only its macros count as consumed.
      assert.deepEqual(result.nutrition.consumed, {
        kcal: 220, proteinG: 8, carbsG: 38, fatG: 4, estimated: false,
      });
      assert.equal(result.meals[0].eaten, true);
      assert.equal(result.meals[1].eaten, false);
    });

test("get_diet leaves nutrients null when no item states them", async () => {
  const tool = toolsByName.get("get_diet");
  const store = {
    getActiveDietPlan: async () => ({
      name: "Handwritten",
      status: "active",
      days: [{
        weekday: null,
        label: "Every day",
        meals: [{
          id: "m1",
          label: "Lunch",
          items: [{name: "Rice", quantity: 1, unit: "plate",
            calories: null, proteinG: null, carbsG: null, fatG: null}],
        }],
      }],
    }),
    listDietEntries: async () => [],
  };

  const result = await tool.execute(store, UID, {}, NOW);

  assert.deepEqual(result.nutrition.target, {
    kcal: null, proteinG: null, carbsG: null, fatG: null, estimated: false,
  });
  assert.deepEqual(result.nutrition.consumed, {
    kcal: null, proteinG: null, carbsG: null, fatG: null, estimated: false,
  });
});

test("get_today's diet snapshot carries per-meal kcal and adherence totals",
    async () => {
      const tool = toolsByName.get("get_today");
      const store = {
        listWorkouts: async () => [],
        getActiveDietPlan: async () => DIET_PLAN,
        listDietEntries: async () => [{mealId: "breakfast", eaten: true}],
      };

      const result = await tool.execute(store, UID, {}, NOW);

      assert.equal(result.date, "2026-08-17");
      assert.deepEqual(result.diet.nutrition.target.kcal, 550);
      assert.deepEqual(result.diet.nutrition.consumed.kcal, 220);
      assert.deepEqual(result.diet.meals, [
        {id: "breakfast", label: "Breakfast", eaten: true, kcal: 220,
          estimated: false},
        {id: "dinner", label: "Dinner", eaten: false, kcal: 330,
          estimated: false},
      ]);
    });

test("get_today serializes diet BEFORE workouts so truncation can't eat it",
    async () => {
      // Tool results are capped and truncated from the END. Whatever is
      // serialized last is what silently disappears on a rich plan, and the
      // nutrition block is the one thing that must never be half-delivered.
      const tool = toolsByName.get("get_today");
      const store = {
        listWorkouts: async () => [{title: "Push", performedAt: NOW}],
        getActiveDietPlan: async () => DIET_PLAN,
        listDietEntries: async () => [],
      };

      const result = await tool.execute(store, UID, {}, NOW);
      const keys = Object.keys(result);

      assert.deepEqual(keys, ["date", "diet", "workouts"]);
    });

test("the registry carries no tools for deleted features", async () => {
  // get_tasks/get_schedule/get_university/search_notes read collections the
  // app stopped writing when those features were removed (ADR-004): they could
  // only ever return empty, while costing a schema in every cached prefix and
  // four awaited reads inside get_today.
  for (const gone of
    ["get_tasks", "get_schedule", "get_university", "search_notes"]) {
    assert.equal(toolsByName.get(gone), undefined, `${gone} should be gone`);
  }
});

test("diet figures carry their estimated provenance to the model",
    async () => {
      // An AI-estimated calorie value must not reach the coach looking
      // identical to one the user's own plan stated.
      const tool = toolsByName.get("get_diet");
      const store = {
        getActiveDietPlan: async () => ({
          name: "Imported",
          status: "active",
          days: [{
            weekday: null,
            label: "Every day",
            meals: [{
              id: "m1",
              label: "Lunch",
              items: [
                {name: "Rice", quantity: 100, unit: "g", calories: 130,
                  proteinG: 2, carbsG: 28, fatG: 0, estimated: true},
                {name: "Chicken", quantity: 200, unit: "g", calories: 330,
                  proteinG: 62, carbsG: 0, fatG: 7, estimated: false},
              ],
            }],
          }],
        }),
        listDietEntries: async () => [],
      };

      const result = await tool.execute(store, UID, {}, NOW);

      assert.equal(result.meals[0].items[0].estimated, true);
      assert.equal(result.meals[0].items[1].estimated, false);
      // One estimated item makes the whole total an estimate.
      assert.equal(result.meals[0].estimated, true);
      assert.equal(result.nutrition.target.estimated, true);
    });

test("get_diet resolves 'today' in the user's timezone, not the server's",
    async () => {
      // 2026-08-17T22:30Z is already 2026-08-18 for a UTC+3 user. Without the
      // offset the coach read the wrong day's entries for the first hours of
      // every local day.
      const tool = toolsByName.get("get_diet");
      const lateEvening = new Date("2026-08-17T22:30:00Z");
      const asked = [];
      const store = {
        getActiveDietPlan: async () => DIET_PLAN,
        listDietEntries: async (uid, dayKey) => {
          asked.push(dayKey);
          return [];
        },
      };

      const result = await tool.execute(store, UID, {}, lateEvening, 180);

      assert.equal(result.date, "2026-08-18");
      assert.deepEqual(asked, ["2026-08-18"]);
    });
