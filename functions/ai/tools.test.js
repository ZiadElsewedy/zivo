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
            {amountMinor: 500, currency: "USD", category: "coffee",
              note: null, spentAt: new Date("2026-08-16T09:00:00")},
            {amountMinor: 300, currency: "USD", category: "coffee",
              note: null, spentAt: new Date("2026-08-15T09:00:00")},
            {amountMinor: 1200, currency: "USD", category: "groceries",
              note: "weekly shop", spentAt: new Date("2026-08-14T09:00:00")},
          ];
        },
      };

      const result = await tool.execute(store, UID, {}, NOW);

      assert.equal(result.totalMinor, 2000);
      assert.deepEqual(result.totalByCategory, {coffee: 800, groceries: 1200});
      assert.equal(result.currency, "USD");
      assert.equal(result.items.length, 3);
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

test("search_notes matches case-insensitively and returns a snippet",
    async () => {
      const tool = toolsByName.get("search_notes");
      const store = {
        searchNotes: async (uid, query) => {
          assert.equal(uid, UID);
          assert.equal(query, "wifi");
          return [
            {
              id: "n1",
              title: "Airbnb notes",
              body: "The router password / WiFi is on a sticker under the " +
                "TV.",
              updatedAt: new Date("2026-08-10T00:00:00"),
            },
          ];
        },
      };

      const result = await tool.execute(store, UID, {query: "wifi"});

      assert.equal(result.matches.length, 1);
      assert.match(result.matches[0].snippet, /WiFi/);
      assert.equal(result.matches[0].title, "Airbnb notes");
    });

test("search_notes returns no matches for an empty query without querying " +
    "the store", async () => {
  const tool = toolsByName.get("search_notes");
  let called = false;
  const store = {searchNotes: async () => {
    called = true;
    return [];
  }};

  const result = await tool.execute(store, UID, {query: "   "});

  assert.deepEqual(result.matches, []);
  assert.equal(called, false);
});

test("get_tasks defaults to open tasks and can filter to done/all",
    async () => {
      const tool = toolsByName.get("get_tasks");
      const store = {
        listTasks: async () => [
          {title: "Open task", done: false, priority: false, due: null},
          {title: "Done task", done: true, priority: false, due: null},
        ],
      };

      const open = await tool.execute(store, UID, {});
      assert.deepEqual(open.tasks.map((t) => t.title), ["Open task"]);

      const done = await tool.execute(store, UID, {filter: "done"});
      assert.deepEqual(done.tasks.map((t) => t.title), ["Done task"]);

      const all = await tool.execute(store, UID, {filter: "all"});
      assert.equal(all.tasks.length, 2);
    });

test("get_diet returns null plan when there is none", async () => {
  const tool = toolsByName.get("get_diet");
  const store = {getActiveDietPlan: async () => null};

  const result = await tool.execute(store, UID, {}, NOW);

  assert.deepEqual(result, {plan: null});
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

      assert.deepEqual(result.nutrition.target, {
        kcal: 550, proteinG: 70, carbsG: 38, fatG: 11,
      });
      // Only breakfast is checked off, so only its macros count as consumed.
      assert.deepEqual(result.nutrition.consumed, {
        kcal: 220, proteinG: 8, carbsG: 38, fatG: 4,
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
    kcal: null, proteinG: null, carbsG: null, fatG: null,
  });
  assert.deepEqual(result.nutrition.consumed, {
    kcal: null, proteinG: null, carbsG: null, fatG: null,
  });
});

test("get_today's diet snapshot carries per-meal kcal and adherence totals",
    async () => {
      const tool = toolsByName.get("get_today");
      const store = {
        listSchedule: async () => [],
        listTasks: async () => [],
        listUniversity: async () => [],
        listWorkouts: async () => [],
        getActiveDietPlan: async () => DIET_PLAN,
        listDietEntries: async () => [{mealId: "breakfast", eaten: true}],
      };

      const result = await tool.execute(store, UID, {}, NOW);

      assert.deepEqual(result.diet.nutrition.target.kcal, 550);
      assert.deepEqual(result.diet.nutrition.consumed.kcal, 220);
      assert.deepEqual(result.diet.meals, [
        {id: "breakfast", label: "Breakfast", eaten: true, kcal: 220},
        {id: "dinner", label: "Dinner", eaten: false, kcal: 330},
      ]);
    });
