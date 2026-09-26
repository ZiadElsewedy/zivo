/**
 * The daily diet record through the real `FirestoreStore` methods —
 * `setMealTick`, `writeFoodLog`, `rebuildDietDay`, `listDietDays` — over a
 * small in-memory Firestore that implements only what those methods use
 * (collections, equality/range `where`, `orderBy`, batches, transactions).
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");
const {Timestamp} = require("firebase-admin/firestore");

const {FirestoreStore, localMidnightFor} = require("./store");
const {buildDietDayTriggers, daysTouched} = require("../../diet/triggers");

/**
 * A minimal Firestore: docs keyed by path, queries evaluated in memory.
 * @return {!Object}
 */
function fakeDb() {
  const docs = new Map();
  const snap = (path) => ({
    id: path.split("/").pop(),
    exists: docs.has(path),
    data: () => docs.get(path),
    ref: docRef(path),
  });
  const write = (path, data, opts) => {
    const base = opts && opts.merge ? docs.get(path) || {} : {};
    docs.set(path, Object.assign({}, base, data));
  };
  const query = (path, filters, order, limit) => ({
    where: (f, op, v) => query(path, [...filters, [f, op, v]], order, limit),
    orderBy: (f, dir) => query(path, filters, [f, dir], limit),
    limit: (n) => query(path, filters, order, n),
    get: async () => {
      const prefix = `${path}/`;
      let rows = [...docs.keys()]
          .filter((k) => k.startsWith(prefix) &&
            !k.slice(prefix.length).includes("/"))
          .map(snap)
          .filter((s) => filters.every(([f, op, v]) => {
            const x = s.data()[f];
            return op === "==" ? x === v : op === ">=" ? x >= v :
              op === "<=" ? x <= v : false;
          }));
      if (order) {
        rows = rows.sort((a, b) => (a.data()[order[0]] < b.data()[order[0]] ?
          -1 : 1) * (order[1] === "desc" ? -1 : 1));
      }
      return {docs: limit ? rows.slice(0, limit) : rows};
    },
  });
  const docRef = (path) => ({
    id: path.split("/").pop(),
    path,
    collection: (name) => collRef(`${path}/${name}`),
    get: async () => snap(path),
    set: async (data, opts) => write(path, data, opts),
  });
  const collRef = (path) => Object.assign(query(path, [], null, 0), {
    doc: (id) => docRef(`${path}/${id}`),
  });
  return {
    docs,
    collection: (name) => collRef(name),
    batch: () => {
      const ops = [];
      return {
        set: (ref, data, opts) => ops.push(() => write(ref.path, data, opts)),
        delete: (ref) => ops.push(() => docs.delete(ref.path)),
        commit: async () => ops.forEach((op) => op()),
      };
    },
    runTransaction: async (fn) => {
      const ops = [];
      const result = await fn({
        get: (target) => target.get(),
        set: (ref, data) => ops.push(() => write(ref.path, data)),
        delete: (ref) => ops.push(() => docs.delete(ref.path)),
      });
      ops.forEach((op) => op());
      return result;
    },
  };
}

const UID = "u1";
const DAY = "2026-09-25";
const CAIRO = 180;

const PLAN = {
  name: "Cut", status: "active", createdAt: 1,
  days: [{weekday: null, label: "Every day", meals: [
    {id: "p1-d0-m0", label: "Breakfast", items: [
      {name: "Oats", quantity: 60, unit: "g", calories: 228, proteinG: 8,
        carbsG: 40, fatG: 4},
      {name: "Milk", quantity: 200, unit: "ml", calories: 100, proteinG: 7,
        carbsG: 10, fatG: 3},
    ]},
    {id: "p1-d0-m1", label: "Dinner", items: [
      {name: "Eggs", quantity: 2, unit: "piece", calories: 140, proteinG: 12,
        carbsG: 1, fatG: 10},
    ]},
  ]}],
};

/**
 * A store over a fake db holding PLAN.
 * @return {{db: !Object, store: !FirestoreStore}}
 */
function setup() {
  const db = fakeDb();
  db.docs.set(`users/${UID}/dietPlans/p1`, JSON.parse(JSON.stringify(PLAN)));
  return {db, store: new FirestoreStore(db)};
}

// 10:00 in Cairo on the 25th, and on the 26th.
const ON_DAY = new Date("2026-09-25T07:00:00Z");
const NEXT_DAY = new Date("2026-09-26T07:00:00Z");

test("a tick from Ask writes the tick AND its foods, as the app does",
    async () => {
      const {db, store} = setup();
      const breakfast = PLAN.days[0].meals[0];
      await store.setMealTick(UID, DAY, breakfast, "eaten", CAIRO);
      const entry = db.docs.get(`users/${UID}/dietEntries/${DAY}__p1-d0-m0`);
      assert.equal(entry.eaten, true);
      assert.equal(entry.status, "eaten");
      // The user's own local midnight, exactly as the app stores `date`.
      assert.equal(entry.date.toDate().toISOString(),
          "2026-09-24T21:00:00.000Z");
      const logs = [...db.docs.keys()].filter((k) => k.includes("/foodLogs/"));
      assert.deepEqual(logs.sort(), [
        `users/${UID}/foodLogs/${DAY}__p1-d0-m0-0`,
        `users/${UID}/foodLogs/${DAY}__p1-d0-m0-1`,
      ]);
      const oats = db.docs.get(`users/${UID}/foodLogs/${DAY}__p1-d0-m0-0`);
      assert.equal(oats.origin, "plannedMeal");
      assert.equal(oats.foodId, "plan:p1-d0-m0#0");
      assert.equal(oats.kcal, 228);

      // Un-ticking removes exactly those rows.
      await store.setMealTick(UID, DAY, breakfast, "unmarked", CAIRO);
      assert.equal([...db.docs.keys()]
          .filter((k) => k.includes("/foodLogs/")).length, 0);
    });

test("rebuildDietDay writes the record, then does nothing when unchanged, " +
    "then deletes it when the day empties", async () => {
  const {store} = setup();
  const breakfast = PLAN.days[0].meals[0];
  await store.setMealTick(UID, DAY, breakfast, "eaten", CAIRO);
  const localMidnight = localMidnightFor(DAY, CAIRO);
  assert.equal(await store.rebuildDietDay(UID, DAY,
      {now: ON_DAY, localMidnight}), "written");
  const rec = await store.getDietDay(UID, DAY);
  assert.equal(rec.offsetMinutes, CAIRO);
  assert.equal(rec.meals[0].status, "eaten");
  assert.equal(rec.meals[1].status, "unmarked");
  assert.equal(rec.consumed.kcal, 328);
  assert.equal(rec.plannedReconstructed, false);

  assert.equal(await store.rebuildDietDay(UID, DAY,
      {now: ON_DAY, localMidnight}), "unchanged");

  await store.setMealTick(UID, DAY, breakfast, "unmarked", CAIRO);
  assert.equal(await store.rebuildDietDay(UID, DAY,
      {now: ON_DAY, localMidnight}), "deleted");
  assert.equal(await store.getDietDay(UID, DAY), null);
});

test("editing the plan today never rewrites yesterday's record", async () => {
  const {db, store} = setup();
  await store.setMealTick(UID, DAY, PLAN.days[0].meals[0], "eaten", CAIRO);
  await store.rebuildDietDay(UID, DAY,
      {now: ON_DAY, localMidnight: localMidnightFor(DAY, CAIRO)});

  // Next morning: breakfast doubled in the plan, then the user ticks
  // yesterday's dinner late — which rebuilds yesterday.
  const plan = db.docs.get(`users/${UID}/dietPlans/p1`);
  plan.days[0].meals[0].items[0].calories = 500;
  await store.setMealTick(UID, DAY, PLAN.days[0].meals[1], "eaten", CAIRO);
  await store.rebuildDietDay(UID, DAY,
      {now: NEXT_DAY, localMidnight: localMidnightFor(DAY, CAIRO)});

  const rec = await store.getDietDay(UID, DAY);
  assert.equal(rec.meals[0].planned.kcal, 328, "yesterday's plan, as it was");
  assert.equal(rec.meals[1].status, "eaten");
  assert.equal(rec.consumed.kcal, 328 + 140);
});

test("a skip is recorded as skipped, with no foods", async () => {
  const {db, store} = setup();
  await store.setMealTick(UID, DAY, PLAN.days[0].meals[1], "skipped", CAIRO);
  await store.rebuildDietDay(UID, DAY, {now: ON_DAY, localMidnight: null});
  const rec = await store.getDietDay(UID, DAY);
  assert.equal(rec.meals[1].status, "skipped");
  assert.equal(rec.adherence.skipped, 1);
  assert.equal(rec.consumed.basis, "nothingLogged");
  assert.equal([...db.docs.keys()]
      .filter((k) => k.includes("/foodLogs/")).length, 0);
});

test("listDietDays reads one small doc per day in the range", async () => {
  const {store} = setup();
  for (const day of ["2026-09-23", "2026-09-24", "2026-09-25"]) {
    await store.setMealTick(UID, day, PLAN.days[0].meals[1], "eaten", CAIRO);
    await store.rebuildDietDay(UID, day, {now: NEXT_DAY, localMidnight: null});
  }
  const days = await store.listDietDays(UID, "2026-09-24", "2026-09-25");
  assert.deepEqual(days.map((d) => d.dayKey), ["2026-09-24", "2026-09-25"]);
});

test("a food logged from Ask stores the user's local midnight", async () => {
  const {db, store} = setup();
  await store.writeFoodLog(UID, [{id: "a1__0", dayKey: DAY, foodId: "usda:1",
    foodName: "Apple", quantity: 1, unit: "piece", grams: 182, kcal: 94.6,
    proteinG: 0.5, carbsG: 25, fatG: 0.3, source: "usdaFdc",
    sourceRef: "1", origin: "logged", estimated: false}], CAIRO);
  const row = db.docs.get(`users/${UID}/foodLogs/a1__0`);
  assert.ok(row.date instanceof Timestamp);
  assert.equal(row.date.toDate().toISOString(), "2026-09-24T21:00:00.000Z");
  assert.equal(row.kcal, 95);
});

// --- the triggers ------------------------------------------------------------

/**
 * A v2 Firestore event for a write from `before` to `after`.
 * @param {?Object} before
 * @param {?Object} after
 * @return {!Object}
 */
function writeEvent(before, after) {
  const snap = (d) => ({exists: !!d, data: () => d});
  return {params: {uid: UID}, data: {before: snap(before), after: snap(after)}};
}

test("a write touches its day — and the old day, if it moved", () => {
  const date = Timestamp.fromDate(localMidnightFor(DAY, CAIRO));
  assert.deepEqual(daysTouched(null, {dayKey: DAY, date}),
      [{dayKey: DAY, localMidnight: date.toDate()}]);
  assert.deepEqual(
      daysTouched({dayKey: "2026-09-24"}, {dayKey: DAY}).map((d) => d.dayKey),
      [DAY, "2026-09-24"]);
  // A delete still rebuilds the day it left.
  assert.deepEqual(daysTouched({dayKey: DAY}, null).map((d) => d.dayKey),
      [DAY]);
  assert.deepEqual(daysTouched({dayKey: "bad"}, null), []);
});

test("the foodLog / dietEntry triggers rebuild the day they touched",
    async () => {
      const {db, store} = setup();
      const triggers = buildDietDayTriggers({store, now: () => ON_DAY});
      await store.setMealTick(UID, DAY, PLAN.days[0].meals[1], "eaten", CAIRO);
      const entry = db.docs.get(`users/${UID}/dietEntries/${DAY}__p1-d0-m1`);
      await triggers.dietDayOnDietEntry.run(writeEvent(null, entry));
      const rec = await store.getDietDay(UID, DAY);
      assert.equal(rec.meals[1].status, "eaten");
      assert.equal(rec.offsetMinutes, CAIRO);
    });

test("a plan edit refreshes today's record, and only today's", async () => {
  const {db, store} = setup();
  const triggers = buildDietDayTriggers({store, now: () => NEXT_DAY});
  const TODAY = "2026-09-26";
  for (const day of [DAY, TODAY]) {
    await store.setMealTick(UID, day, PLAN.days[0].meals[0], "eaten", CAIRO);
    await store.rebuildDietDay(UID, day, {now: NEXT_DAY,
      localMidnight: localMidnightFor(day, CAIRO)});
  }
  const plan = db.docs.get(`users/${UID}/dietPlans/p1`);
  plan.days[0].meals[1].items[0].calories = 210;
  await triggers.dietDayOnPlan.run(writeEvent(plan, plan));
  assert.equal((await store.getDietDay(UID, TODAY)).meals[1].planned.kcal, 210);
  assert.equal((await store.getDietDay(UID, DAY)).meals[1].planned.kcal, 140);
});

test("a plan edit for a user with no records writes nothing", async () => {
  const {db, store} = setup();
  const triggers = buildDietDayTriggers({store, now: () => NEXT_DAY});
  const plan = db.docs.get(`users/${UID}/dietPlans/p1`);
  await triggers.dietDayOnPlan.run(writeEvent(null, plan));
  assert.equal([...db.docs.keys()].some((k) => k.includes("/dietDays/")),
      false);
});
