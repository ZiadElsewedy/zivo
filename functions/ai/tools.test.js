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
  const store = {
    getActiveDietPlan: async () => null,
    getDietTargets: async () => null,
    listFoodLogs: async () => [],
    listFoodLogRange: async () => [],
  };

  const result = await tool.execute(store, UID, {}, NOW);

  // The date is always stated: nothing else in a turn tells the model what
  // day the answer is about.
  assert.equal(result.date, "2026-08-17");
  assert.equal(result.targets, null);
  assert.equal(result.plan, null);
  assert.deepEqual(result.logEntries, []);
  // The state says what it doesn't know rather than leaving the model to
  // infer it.
  assert.equal(result.quality.targetsUnset, true);
  assert.equal(result.quality.noPlanForDay, true);
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
        getDietTargets: async () => null,
        listFoodLogs: async () => [],
        listFoodLogRange: async () => [],
        listDietEntries: async (uid, dayKey) => {
          assert.equal(uid, UID);
          assert.equal(dayKey, "2026-08-17");
          return [{mealId: "breakfast", eaten: true}];
        },
      };

      const result = await tool.execute(store, UID, {}, NOW);

      assert.equal(result.date, "2026-08-17");
      // The plan's own daily sum, reported apart from any target.
      assert.equal(result.plannedKcal, 550);
      // Only breakfast is checked off, so only its figures count as consumed.
      assert.equal(result.consumed.kcal, 220);
      assert.equal(result.consumed.proteinG, 8);
      assert.equal(result.consumed.basis, "tickedPlanMeals");
      assert.equal(result.meals[0].eaten, true);
      assert.equal(result.meals[1].eaten, false);
      assert.equal(result.mealsEaten, 1);
      assert.equal(result.mealsTotal, 2);
    });

test("get_diet leaves nutrients null when no item states them", async () => {
  const tool = toolsByName.get("get_diet");
  const store = {
    getDietTargets: async () => null,
    listFoodLogs: async () => [],
    listFoodLogRange: async () => [],
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

  // A plan that states no calories reports none — absent, never zero.
  assert.equal(result.plannedKcal, null);
  assert.equal(result.meals[0].kcal, null);
  assert.equal(result.consumed.kcal, 0);
  assert.equal(result.consumed.basis, "nothingLogged");
});

test("get_today's diet snapshot carries per-meal kcal and adherence totals",
    async () => {
      const tool = toolsByName.get("get_today");
      const store = {
        listWorkouts: async () => [],
        getActiveDietPlan: async () => DIET_PLAN,
        getDietTargets: async () => null,
        listFoodLogs: async () => [],
        listFoodLogRange: async () => [],
        listDietEntries: async () => [{mealId: "breakfast", eaten: true}],
      };

      const result = await tool.execute(store, UID, {}, NOW);

      assert.equal(result.date, "2026-08-17");
      assert.equal(result.plannedKcal, 550);
      assert.equal(result.consumed.kcal, 220);
      assert.deepEqual(result.meals, [
        {id: "breakfast", label: "Breakfast", eaten: true, kcal: 220,
          estimated: false, isSupplement: false},
        {id: "dinner", label: "Dinner", eaten: false, kcal: 330,
          estimated: false, isSupplement: false},
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
        getDietTargets: async () => null,
        listFoodLogs: async () => [],
        listFoodLogRange: async () => [],
        listDietEntries: async () => [],
      };

      const result = await tool.execute(store, UID, {}, NOW);
      const keys = Object.keys(result);

      // The state leads, then what the rules concluded; workouts trail.
      // Truncation eats the end.
      assert.deepEqual(
          keys.slice(0, 6),
          ["date", "targets", "consumed", "remaining", "findings", "quality"]);
      assert.equal(keys.at(-1), "workouts");
    });

test("get_workouts surfaces REAL per-set actuals, warm-ups marked, "+
    "skipped/pending sets dropped", async () => {
  const tool = toolsByName.get("get_workouts");
  const store = {
    listWorkoutSessions: async (uid, range) => {
      assert.equal(uid, UID);
      assert.equal(typeof range.fromMs, "number");
      return [{
        dayLabel: "Push",
        status: "completed",
        startedAt: new Date("2026-08-17T10:00:00"),
        completedAt: new Date("2026-08-17T11:00:00"),
        pausedAccumMs: 0,
        exercises: [{
          name: "Bench Press",
          muscleGroup: "Chest",
          sets: [
            {actualReps: 10, actualWeightKg: 40, type: "warmup", outcome: "completed"},
            {actualReps: 8, actualWeightKg: 100, type: "working", outcome: "completed"},
            {actualReps: 5, actualWeightKg: 110, type: "working", outcome: "completed"},
            {actualReps: null, actualWeightKg: null, type: "working", outcome: "pending"},
            {actualReps: 6, actualWeightKg: 100, type: "working", outcome: "skipped"},
          ],
        }],
      }];
    },
  };

  const result = await tool.execute(store, UID, {}, NOW);
  const sets = result.workouts[0].exercises[0].sets;
  // Only the three COMPLETED sets survive; pending/skipped are dropped.
  assert.equal(sets.length, 3);
  // The warm-up is present but explicitly typed so the model won't count it.
  assert.deepEqual(sets[0], {set: 1, weightKg: 40, reps: 10, type: "warmup"});
  assert.deepEqual(sets[1], {set: 2, weightKg: 100, reps: 8, type: "working"});
  assert.deepEqual(sets[2], {set: 3, weightKg: 110, reps: 5, type: "working"});
  assert.equal(result.workouts[0].durationMinutes, 60);
});

test("get_training_analysis returns deterministic findings, never raw math",
    async () => {
      const tool = toolsByName.get("get_training_analysis");
      // Four progressing bench sessions → 'progressing', with a fact finding.
      const at = (d) => new Date(NOW.getTime() - d * 24 * 60 * 60 * 1000);
      const mk = (id, day, weight) => ({
        id, dayLabel: "Push", status: "completed",
        startedAt: at(day), completedAt: at(day),
        exercises: [{
          name: "Bench Press", exerciseId: "bench", muscleGroup: "Chest",
          sets: [{actualReps: 5, actualWeightKg: weight, type: "working",
            outcome: "completed"}],
        }],
      });
      // Spans >12 weeks so the recent-6wk vs prior-6wk strength window has
      // data on both sides (prior ~104kg, recent 110kg → up ~6%).
      const store = {
        listWorkoutSessions: async () => [
          mk("s1", 75, 100), mk("s2", 65, 102), mk("s3", 50, 104),
          mk("s4", 7, 108), mk("s5", 1, 110),
        ],
      };

      const result = await tool.execute(store, UID, {}, NOW);
      assert.equal(result.overallStatus, "progressing");
      const bench = result.exercises.find((e) => e.exerciseId === "bench");
      assert.equal(bench.status, "progressing");
      // Findings carry a confidence so the model keeps fact vs interpretation.
      assert.ok(result.findings.length > 0);
      assert.ok(result.findings.every((f) => ["fact", "interpretation"].includes(f.confidence)));
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
        getDietTargets: async () => null,
        listFoodLogs: async () => [],
        listFoodLogRange: async () => [],
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

      assert.equal(result.planItems[0].items[0].estimated, true);
      assert.equal(result.planItems[0].items[1].estimated, false);
      // One estimated item makes the whole meal an estimate.
      assert.equal(result.meals[0].estimated, true);
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
        getDietTargets: async () => null,
        listFoodLogs: async () => [],
        listFoodLogRange: async () => [],
        listDietEntries: async (uid, dayKey) => {
          asked.push(dayKey);
          return [];
        },
      };

      const result = await tool.execute(store, UID, {}, lateEvening, 180);

      assert.equal(result.date, "2026-08-18");
      assert.deepEqual(asked, ["2026-08-18"]);
    });

const TARGETS = {
  goal: "fatLoss",
  calories: 2200,
  proteinG: 160,
  carbsG: 250,
  fatG: 73,
  source: "calculated",
};

test("get_diet reports the user's OWN targets and what's left of them",
    async () => {
      // The coach's most important input. Before this it could describe a plan
      // but had no idea what the user was trying to do, which made every
      // recommendation generic by construction.
      const tool = toolsByName.get("get_diet");
      const store = {
        getActiveDietPlan: async () => DIET_PLAN,
        getDietTargets: async () => TARGETS,
        listFoodLogs: async () => [],
        listFoodLogRange: async () => [],
        listDietEntries: async () => [{mealId: "breakfast", eaten: true}],
      };

      const result = await tool.execute(store, UID, {}, NOW);

      assert.deepEqual(result.targets, TARGETS);
      // Breakfast (220 kcal / P8 / C38 / F4) is ticked off.
      assert.equal(result.remaining.kcal, 2200 - 220);
      assert.equal(result.consumed.basis, "tickedPlanMeals");
      assert.equal(result.remaining.proteinG, 152);
      assert.equal(result.remaining.carbsG, 212);
      assert.equal(result.remaining.fatG, 69);
      // The estimate flag lives with the figures it qualifies, not on the
      // remainder derived from them.
      assert.equal(result.consumed.estimated, false);
      // The honest caveat travels with the numbers.
      assert.match(result.consumed.basisLabel, /not weighed/);
      assert.equal(result.quality.consumedIsAssumed, true);
    });

test("a macro with no target stays null in remaining — never zero",
    async () => {
      // "You didn't set a carb target" and "you have 0g of carbs left" are
      // opposite statements; conflating them would have the coach inventing a
      // constraint the user never set.
      const tool = toolsByName.get("get_diet");
      const store = {
        getActiveDietPlan: async () => DIET_PLAN,
        getDietTargets: async () => ({
          goal: "maintain", calories: 2000, proteinG: 150,
          carbsG: null, fatG: null, source: "manual",
        }),
        listFoodLogs: async () => [],
        listFoodLogRange: async () => [],
        listDietEntries: async () => [],
      };

      const result = await tool.execute(store, UID, {}, NOW);

      assert.equal(result.remaining.proteinG, 150);
      assert.equal(result.remaining.carbsG, null);
      assert.equal(result.remaining.fatG, null);
    });

test("targets are null when the user hasn't set an objective", async () => {
  // Null must survive all the way to the model: ZIVO never invents a target,
  // and the plan's own sum is not one.
  const tool = toolsByName.get("get_diet");
  const store = {
    getActiveDietPlan: async () => DIET_PLAN,
    getDietTargets: async () => null,
    listFoodLogs: async () => [],
    listFoodLogRange: async () => [],
    listDietEntries: async () => [],
  };

  const result = await tool.execute(store, UID, {}, NOW);

  assert.equal(result.targets, null);
  assert.equal(result.remaining, null);
  // The plan's own daily sum is still reported — under its own name.
  assert.equal(result.plannedKcal, 550);
  assert.deepEqual(result.quality.untrackedMacros, ["protein", "carbs", "fat"]);
});

test("get_today leads with the targets, then what's left, then the plan",
    async () => {
      const tool = toolsByName.get("get_today");
      const store = {
        listWorkouts: async () => [],
        getActiveDietPlan: async () => DIET_PLAN,
        getDietTargets: async () => TARGETS,
        listFoodLogs: async () => [],
        listFoodLogRange: async () => [],
        listDietEntries: async () => [{mealId: "breakfast", eaten: true}],
      };

      const result = await tool.execute(store, UID, {}, NOW);

      assert.equal(result.targets.goal, "fatLoss");
      assert.equal(result.remaining.kcal, 1980);
      assert.equal(Object.keys(result).at(-1), "workouts");
      // A week of history, summarised rather than dumped.
      assert.equal(result.history.days, 7);
    });

test("remaining goes negative rather than clamping at zero", async () => {
  // Over-target is a real state a coach has to be able to name. Clamping it
  // would hide the one situation where the advice most needs to change.
  const tool = toolsByName.get("get_diet");
  const store = {
    getActiveDietPlan: async () => DIET_PLAN,
    getDietTargets: async () => ({
      goal: "fatLoss", calories: 400, proteinG: 10,
      carbsG: null, fatG: null, source: "manual",
    }),
    listFoodLogs: async () => [],
    listFoodLogRange: async () => [],
    listDietEntries: async () => [
      {mealId: "breakfast", eaten: true},
      {mealId: "dinner", eaten: true},
    ],
  };

  const result = await tool.execute(store, UID, {}, NOW);

  assert.equal(result.remaining.kcal, 400 - 550);
  assert.equal(result.remaining.proteinG, 10 - 70);
});

const LOG_ENTRY = {
  id: "e1", foodId: "usda:171477", foodName: "Chicken breast, roasted",
  quantity: 200, unit: "g", grams: 200,
  kcal: 330, proteinG: 62, carbsG: 0, fatG: 7.2,
  source: "usdaFdc", sourceRef: "171477", origin: "logged",
  estimated: false, mealId: null, loggedAt: NOW,
};

test("consumption comes from the food log when there is one", async () => {
  // The log is what the user actually recorded. Before it existed, "consumed"
  // was the planned figures of ticked meals — an assumption wearing a number's
  // clothes (docs/DIET_COACH_AUDIT.md, T6).
  const tool = toolsByName.get("get_diet");
  const store = {
    getActiveDietPlan: async () => DIET_PLAN,
    getDietTargets: async () => TARGETS,
    // Breakfast is ticked (220 kcal planned) but the log says otherwise.
    listDietEntries: async () => [{mealId: "breakfast", eaten: true}],
    listFoodLogs: async () => [LOG_ENTRY],
    listFoodLogRange: async () => [],
  };

  const result = await tool.execute(store, UID, {}, NOW);

  assert.equal(result.consumed.kcal, 330, "the log wins over the plan");
  assert.equal(result.consumed.loggedCount, 1);
  assert.equal(result.remaining.kcal, 2200 - 330);
  assert.equal(result.consumed.basis, "logged");
  assert.match(result.consumed.basisLabel, /logged by you/);
  // And the coach can see the items, not just the totals.
  assert.equal(result.logEntries.length, 1);
  assert.equal(result.logEntries[0].food, "Chicken breast, roasted");
});

test("a day of only ticked meals says so rather than claiming a measurement",
    async () => {
      const tool = toolsByName.get("get_diet");
      const store = {
        getActiveDietPlan: async () => DIET_PLAN,
        getDietTargets: async () => TARGETS,
        listDietEntries: async () => [{mealId: "breakfast", eaten: true}],
        listFoodLogs: async () => [{
          ...LOG_ENTRY, id: "p1", origin: "plannedMeal", mealId: "breakfast",
          kcal: 220, proteinG: 8, carbsG: 38, fatG: 4,
          source: "dietPlan", estimated: true,
        }],
        listFoodLogRange: async () => [],
      };

      const result = await tool.execute(store, UID, {}, NOW);

      assert.equal(result.consumed.kcal, 220);
      assert.equal(result.consumed.loggedCount, 0);
      assert.equal(result.consumed.entryCount, 1);
      assert.equal(result.consumed.basis, "tickedPlanMeals");
      // The estimate provenance survives the trip through the ledger.
      assert.equal(result.consumed.estimated, true);
      assert.equal(result.quality.hasEstimatedValues, true);
    });

test("an empty log on a day with ticked meals falls back, and admits it",
    async () => {
      // Days recorded before the log existed. Falling back is right; passing
      // the fallback off as a measurement is not.
      const tool = toolsByName.get("get_diet");
      const store = {
        getActiveDietPlan: async () => DIET_PLAN,
        getDietTargets: async () => TARGETS,
        listDietEntries: async () => [{mealId: "breakfast", eaten: true}],
        listFoodLogs: async () => [],
        listFoodLogRange: async () => [],
      };

      const result = await tool.execute(store, UID, {}, NOW);

      assert.equal(result.consumed.kcal, 220);
      assert.equal(result.consumed.entryCount, 0);
      assert.equal(result.consumed.basis, "tickedPlanMeals");
      assert.equal(result.quality.consumedIsAssumed, true);
    });

test("logged food counts even with no plan at all", async () => {
  // Someone with no diet plan can still log what they ate and see it against
  // their target.
  const tool = toolsByName.get("get_diet");
  const store = {
    getActiveDietPlan: async () => null,
    getDietTargets: async () => TARGETS,
    listDietEntries: async () => [],
    listFoodLogs: async () => [LOG_ENTRY],
    listFoodLogRange: async () => [],
  };

  const result = await tool.execute(store, UID, {}, NOW);

  assert.equal(result.plan, null);
  assert.equal(result.consumed.kcal, 330);
  assert.equal(result.remaining.kcal, 1870);
});

test("the diet payload carries the rules engine's conclusions", async () => {
  // The coach is handed decisions, not just data. Without this it would be
  // back to deriving "what should I say" from raw numbers — which is exactly
  // the reasoning this design moved into code.
  const tool = toolsByName.get("get_diet");
  const store = {
    getActiveDietPlan: async () => DIET_PLAN,
    getDietTargets: async () => TARGETS,
    listDietEntries: async () => [],
    listFoodLogs: async () => [{
      ...LOG_ENTRY, kcal: 1850, proteinG: 125, carbsG: 200, fatG: 60,
    }],
    listFoodLogRange: async () => [],
  };

  // 19:00 for a UTC+3 user — late enough that a protein gap is a real squeeze.
  const evening = new Date("2026-08-17T16:00:00Z");
  const result = await tool.execute(store, UID, {}, evening, 180);

  const codes = result.findings.map((f) => f.code);
  assert.ok(codes.includes("protein_shortfall"), codes.join(","));
  const shortfall = result.findings.find(
      (f) => f.code === "protein_shortfall");
  assert.equal(shortfall.kind, "recommendation");
  // Every finding says what it rests on.
  for (const finding of result.findings) {
    assert.ok(finding.evidence.length > 0, finding.code);
  }
});

test("an explicit past day gets no time-sensitive findings", async () => {
  // "What hour is it" doesn't apply to a date the user asked about.
  const tool = toolsByName.get("get_diet");
  const store = {
    getActiveDietPlan: async () => DIET_PLAN,
    getDietTargets: async () => TARGETS,
    listDietEntries: async () => [],
    listFoodLogs: async () => [],
    listFoodLogRange: async () => [],
  };

  const result = await tool.execute(
      store, UID, {day: "2026-08-10"}, new Date("2026-08-17T20:00:00Z"), 180);

  const nothing = result.findings.find((f) => f.code === "nothing_logged");
  assert.ok(nothing);
  // Info, not the evening nudge — the hour of *now* says nothing about a day
  // a week ago.
  assert.equal(nothing.severity, "info");
});

// --- Phase 6: resolve_food + calculate_meal_nutrition -----------------------

// A store with no custom foods — the common case; the resolver falls through
// to the bundled USDA catalog.
const NO_CUSTOM = {listCustomFoods: async () => []};

test("resolve_food returns a resolved food with its foodId and measures",
    async () => {
      const tool = toolsByName.get("resolve_food");
      const result = await tool.execute(NO_CUSTOM, UID, {
        query: "chicken broilers fryers breast meat only cooked roasted",
      });
      assert.equal(result.outcome, "resolved");
      assert.equal(result.food.foodId, "usda:171477");
      assert.equal(result.food.per100g.kcal, 165);
      assert.ok(Array.isArray(result.food.measures));
    });

test("resolve_food reports the raw/cooked fork as ambiguous, not a pick",
    async () => {
      const tool = toolsByName.get("resolve_food");
      const result = await tool.execute(
          NO_CUSTOM, UID, {query: "rice white long-grain regular"});
      assert.equal(result.outcome, "ambiguous");
      assert.ok(result.candidates.length > 1);
      // Each candidate is pickable by id, and the note says to ask.
      assert.ok(result.candidates.every((c) => c.foodId));
      assert.match(result.note, /Ask which/);
    });

test("resolve_food says notFound for a food the catalog lacks", async () => {
  const tool = toolsByName.get("resolve_food");
  const result = await tool.execute(NO_CUSTOM, UID, {query: "koshari"});
  assert.equal(result.outcome, "notFound");
  assert.match(result.note, /custom food/);
});

test("resolve_food prefers the user's own food over the catalog", async () => {
  const tool = toolsByName.get("resolve_food");
  const store = {
    listCustomFoods: async () => [{
      id: "kosh", name: "Koshari", kcalPer100g: 150, proteinPer100g: 5,
      carbsPer100g: 27, fatPer100g: 3, preparation: "cooked", portions: [],
      createdAt: new Date("2026-08-01T00:00:00Z"),
    }],
  };
  const result = await tool.execute(store, UID, {query: "koshari"});
  assert.equal(result.outcome, "resolved");
  assert.equal(result.food.foodId, "custom:kosh");
});

test("calculate_meal_nutrition totals a resolvable meal", async () => {
  const tool = toolsByName.get("calculate_meal_nutrition");
  const result = await tool.execute(NO_CUSTOM, UID, {items: [
    {foodId: "usda:171477", quantity: 200, unit: "g"}, // 330 kcal
    {query: "rice white long-grain regular", preparation: "cooked",
      quantity: 150, unit: "g"}, // 130 kcal/100g × 1.5 = 195
  ]});
  assert.equal(result.allResolved, true);
  assert.equal(result.items.length, 2);
  assert.equal(result.items[0].outcome, "computed");
  assert.equal(result.total.kcal, 330 + 195);
});

test("calculate_meal_nutrition withholds the total when an item is unresolved",
    async () => {
      const tool = toolsByName.get("calculate_meal_nutrition");
      const result = await tool.execute(NO_CUSTOM, UID, {items: [
        {foodId: "usda:171477", quantity: 200, unit: "g"},
        {query: "koshari", quantity: 1, unit: "bowl"}, // notFound
      ]});
      assert.equal(result.allResolved, false);
      // A partial sum would look whole but isn't, so there is no total.
      assert.equal(result.total, null);
      assert.equal(result.items[1].outcome, "notFound");
    });

test("calculate_meal_nutrition flags a bad item rather than throwing",
    async () => {
      const tool = toolsByName.get("calculate_meal_nutrition");
      const result = await tool.execute(NO_CUSTOM, UID, {items: [
        {query: "egg whole raw fresh", quantity: 0, unit: "g"}, // invalid qty
      ]});
      assert.equal(result.allResolved, false);
      assert.equal(result.items[0].outcome, "invalid");
    });
