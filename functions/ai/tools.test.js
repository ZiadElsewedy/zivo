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
