/**
 * Offline unit tests for `./diet_generate.js`. No `@anthropic-ai/sdk`, no
 * network — `callModel` is scripted. The nutrition catalog IS real (it's a
 * bundled JSON file), which is the point: these tests prove a generated plan's
 * calories come from the catalog rather than from the model.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {
  generateDietPlan,
  buildPlan,
  buildRequest,
  TOOL_NAME,
  REJECT_TOOL_NAME,
  CHOOSE_TOOL_NAME,
} = require("./diet_generate");
const {GatewayError} = require("./gateway");

/**
 * A `callModel` fake. The first call gets [response]; any later call is the
 * disambiguation pass, answered by [chooser] — which by default declines
 * every ambiguous food (`foodId: null`), so a test that doesn't care about
 * disambiguation gets the honest "estimate" fallback rather than a surprise.
 * @param {!Object} response
 * @param {function(!Object): !Object=} chooser
 * @return {function(!Object): !Promise<!Object>}
 */
function scriptedModel(response, chooser) {
  const fn = async (request) => {
    fn.calls = (fn.calls || 0) + 1;
    fn.lastRequest = request;
    if (fn.calls === 1) {
      fn.planRequest = request;
      return response;
    }
    fn.chooseRequest = request;
    return chooser ? chooser(request) : chooseResponse([]);
  };
  return fn;
}

/**
 * A `choose_foods` tool response.
 * @param {!Array<!Object>} choices
 * @return {!Object}
 */
function chooseResponse(choices) {
  return {
    stop_reason: "tool_use",
    content: [{
      type: "tool_use", id: "c2", name: CHOOSE_TOOL_NAME, input: {choices},
    }],
  };
}

/**
 * Picks the FIRST candidate offered for every ambiguous item — standing in for
 * a model that resolves its own foods.
 * @param {!Object} request
 * @return {!Object}
 */
function chooseFirstCandidate(request) {
  const text = request.messages[0].content[0].text;
  const choices = [];
  let current = null;
  for (const line of text.split("\n")) {
    const header = line.match(/^#(\d+):/);
    if (header) {
      current = {index: Number(header[1]), taken: false};
      choices.push(current);
      continue;
    }
    const candidate = line.match(/^\s{4}(\S+) — /);
    if (candidate && current && !current.taken) {
      current.taken = true;
      current.foodId = candidate[1];
    }
  }
  return chooseResponse(
      choices
          .filter((c) => c.foodId)
          .map((c) => ({itemIndex: c.index, foodId: c.foodId})));
}

/**
 * @param {!Object} input
 * @return {!Object}
 */
function toolResponse(input) {
  return {
    stop_reason: "tool_use",
    content: [{type: "tool_use", id: "c1", name: TOOL_NAME, input}],
  };
}

/**
 * An item as the model proposes it: a searchable name, an amount, and a
 * fallback estimate that is deliberately WRONG here, so any test that sees it
 * knows the catalog wasn't used.
 * @param {string} name
 * @param {number} quantity
 * @param {string=} unit
 * @param {string=} preparation
 * @return {!Object}
 */
function proposed(name, quantity, unit = "g", preparation = "cooked") {
  return {
    name,
    quantity,
    unit,
    preparation,
    estimatedCalories: 9999,
    estimatedProteinG: 99,
    estimatedCarbsG: 99,
    estimatedFatG: 99,
  };
}

const PREFS = {
  mealsPerDay: 3,
  likes: ["chicken", "rice"],
  avoid: [],
  allergies: [],
};

test("the model is told the preferences and the target, as fenced data", async () => {
  const callModel = scriptedModel(toolResponse({
    planName: "Simple",
    days: [{
      weekday: null,
      label: "Every day",
      meals: [{label: "Lunch", items: [proposed("Chicken breast", 200)]}],
    }],
  }));

  await generateDietPlan({
    callModel,
    preferences: {
      mealsPerDay: 4,
      likes: ["eggs"],
      avoid: ["liver"],
      allergies: ["peanuts"],
      cuisine: "Egyptian",
    },
    targets: {calories: 2400, proteinG: 180, goal: "muscleGain"},
  });

  const text = callModel.planRequest.messages[0].content[0].text;
  assert.match(text, /---BEGIN PREFERENCES---/);
  assert.match(text, /Meals per day: 4/);
  assert.match(text, /Will not eat: liver/);
  assert.match(text, /ALLERGIC — must never appear in any form: peanuts/);
  assert.match(text, /Daily calorie target: 2400 kcal/);
  assert.match(text, /Protein target: 180 g/);
  // Both tools offered, model must call one of them.
  assert.equal(callModel.planRequest.tool_choice.type, "any");
});

test("buildRequest omits what the user didn't give rather than inventing it", () => {
  const text = buildRequest({mealsPerDay: 3}, null);
  assert.match(text, /Meals per day: 3/);
  assert.doesNotMatch(text, /Daily calorie target/);
  assert.doesNotMatch(text, /ALLERGIC/);
});

test("calories come from the catalog, not from the model's estimate", async () => {
  // "Chicken breast" is ambiguous in USDA (a roll, a breaded tender, sliced
  // fat-free), so this exercises the whole two-pass path: propose, pick a
  // row, price from it.
  const callModel = scriptedModel(toolResponse({
    planName: "Simple",
    days: [{
      weekday: null,
      label: "Every day",
      meals: [{
        label: "Lunch",
        items: [proposed("Chicken breast", 200)],
      }],
    }],
  }), chooseFirstCandidate);

  const result = await generateDietPlan({callModel, preferences: PREFS});

  assert.equal(result.ok, true);
  assert.equal(callModel.calls, 2, "one plan call, one disambiguation call");
  const item = result.days[0].meals[0].items[0];
  // The model said 9999 kcal. The catalog says otherwise, and the catalog wins.
  assert.notEqual(item.calories, 9999);
  assert.ok(item.calories > 50 && item.calories < 900, `got ${item.calories}`);
  assert.equal(item.estimated, false, "a looked-up figure is not an estimate");
  assert.equal(result.disambiguated, 1);
});

test("an ambiguous food the model won't pin falls back to its estimate", async () => {
  // The default chooser answers with no choices at all — the model declining
  // to say which row it meant. A wrong row is worse than an estimate.
  const callModel = scriptedModel(toolResponse({
    planName: "Simple",
    days: [{
      weekday: null,
      label: "Every day",
      meals: [{
        label: "Lunch",
        items: [{...proposed("Chicken breast", 200), estimatedCalories: 330}],
      }],
    }],
  }));

  const result = await generateDietPlan({callModel, preferences: PREFS});

  const item = result.days[0].meals[0].items[0];
  assert.equal(item.calories, 330);
  assert.equal(item.estimated, true);
  assert.equal(result.disambiguated, 0);
});

test("a foodId the model invents is refused, not priced", async () => {
  const callModel = scriptedModel(
      toolResponse({
        planName: "Simple",
        days: [{
          weekday: null,
          label: "Every day",
          meals: [{
            label: "Lunch",
            items: [{
              ...proposed("Chicken breast", 200), estimatedCalories: 330,
            }],
          }],
        }],
      }),
      () => chooseResponse([{itemIndex: 0, foodId: "usda:00000000"}]));

  const result = await generateDietPlan({callModel, preferences: PREFS});

  // Priced as the model's estimate, not as a row nobody offered.
  assert.equal(result.days[0].meals[0].items[0].estimated, true);
  assert.equal(result.disambiguated, 0);
});

test("a food the catalog doesn't have keeps the estimate — and says so", async () => {
  const callModel = scriptedModel(toolResponse({
    planName: "Egyptian",
    days: [{
      weekday: null,
      label: "Every day",
      meals: [{
        label: "Lunch",
        items: [{
          ...proposed("Koshari with extra dakka", 300),
          estimatedCalories: 450,
          estimatedProteinG: 12,
          estimatedCarbsG: 80,
          estimatedFatG: 8,
        }],
      }],
    }],
  }));

  const result = await generateDietPlan({callModel, preferences: PREFS});

  const item = result.days[0].meals[0].items[0];
  assert.equal(item.calories, 450, "the model's figure, since USDA has none");
  // Marked, so every surface prints it with the same "~" an import gets.
  assert.equal(item.estimated, true);
});

test("the day is fitted to the calorie target by scaling weighable amounts", async () => {
  // Two foods the catalog resolves outright, so this test is about the
  // arithmetic and not about disambiguation: 100 g of rolled oats is 379 kcal
  // and 100 g of Greek yogurt is 82 — a 461 kcal day as proposed.
  const plan = () => toolResponse({
    planName: "Simple",
    days: [{
      weekday: null,
      label: "Every day",
      meals: [{
        label: "Breakfast",
        items: [proposed("Rolled oats", 100), proposed("Greek yogurt", 100)],
      }],
    }],
  });

  const asProposed = await generateDietPlan({
    callModel: scriptedModel(plan()),
    preferences: PREFS,
  });
  assert.equal(asProposed.kcalPerDay, 461);
  assert.equal(asProposed.fitted, false, "no target, nothing to fit to");

  const fitted = await generateDietPlan({
    callModel: scriptedModel(plan()),
    preferences: PREFS,
    targets: {calories: 700},
  });

  assert.equal(fitted.fitted, true);
  // Within what 5 g portion steps allow — the plan stays weighable.
  assert.ok(
      Math.abs(fitted.kcalPerDay - 700) <= 20,
      `landed on ${fitted.kcalPerDay}`);
  const amounts = fitted.days[0].meals[0].items.map((i) => i.quantity);
  assert.deepEqual(amounts, [150, 150], "1.52x, rounded to 5 g");
});

test("with no target the portions are left exactly as proposed", async () => {
  const callModel = scriptedModel(toolResponse({
    planName: "Simple",
    days: [{
      weekday: null,
      label: "Every day",
      meals: [{label: "Breakfast", items: [proposed("Rolled oats", 80)]}],
    }],
  }));

  const result = await generateDietPlan({callModel, preferences: PREFS});

  assert.equal(result.days[0].meals[0].items[0].quantity, 80);
});

test("an allergen in the generated plan is refused, not quietly served", async () => {
  const callModel = scriptedModel(toolResponse({
    planName: "Simple",
    days: [{
      weekday: null,
      label: "Every day",
      meals: [{
        label: "Breakfast",
        items: [proposed("Peanut butter", 30)],
      }],
    }],
  }));

  const result = await generateDietPlan({
    callModel,
    preferences: {...PREFS, allergies: ["peanuts"]},
  });

  // The prompt asks; this GATE refuses. A safety limit is not a request.
  assert.equal(result.ok, false);
  assert.match(result.reason, /Peanut butter/);
  assert.match(result.reason, /allergic/i);
});

test("an explicit rejection from the model is passed through", async () => {
  const callModel = scriptedModel({
    stop_reason: "tool_use",
    content: [{
      type: "tool_use",
      id: "c1",
      name: REJECT_TOOL_NAME,
      input: {reason: "Everything you eat is on your avoid list."},
    }],
  });

  const result = await generateDietPlan({callModel, preferences: PREFS});

  assert.equal(result.ok, false);
  assert.equal(result.reason, "Everything you eat is on your avoid list.");
});

test("no tool call at all is a technical failure, not an empty plan", async () => {
  const callModel = scriptedModel({
    stop_reason: "end_turn",
    content: [{type: "text", text: "Here is a plan!"}],
  });

  await assert.rejects(
      () => generateDietPlan({callModel, preferences: PREFS}),
      (err) => err instanceof GatewayError && err.code === "internal");
});

test("missing preferences are refused before a model call is made", async () => {
  let called = false;
  const callModel = async () => {
    called = true;
    return toolResponse({planName: "x", days: []});
  };

  await assert.rejects(
      () => generateDietPlan({callModel, preferences: null}),
      (err) => err instanceof GatewayError && err.code === "invalid-argument");
  assert.equal(called, false, "no spend on an unanswerable request");
});

test("a proposal that normalizes to nothing is rejected, not returned empty", async () => {
  const built = await buildPlan(
      {planName: "Empty", days: [{weekday: null, label: "Day", meals: []}]},
      {targets: null, customFoods: [], allergies: []});

  assert.equal(built.ok, false);
});

test("items without a name or a positive amount are dropped", async () => {
  const built = await buildPlan({
    planName: "Simple",
    days: [{
      weekday: null,
      label: "Every day",
      meals: [{
        label: "Lunch",
        items: [
          proposed("Chicken breast", 200),
          {...proposed("Rice", 0)},
          {...proposed("", 100)},
        ],
      }],
    }],
  }, {targets: null, customFoods: [], allergies: []});

  assert.equal(built.ok, true);
  assert.equal(built.days[0].meals[0].items.length, 1);
});

test("a user's own food is used ahead of the USDA catalog", async () => {
  const callModel = scriptedModel(toolResponse({
    planName: "Mine",
    days: [{
      weekday: null,
      label: "Every day",
      meals: [{label: "Lunch", items: [proposed("Koshari", 100)]}],
    }],
  }));

  const result = await generateDietPlan({
    callModel,
    preferences: PREFS,
    customFoods: [{
      id: "k1",
      name: "Koshari",
      preparation: "cooked",
      kcalPer100g: 150,
      proteinPer100g: 5,
      carbsPer100g: 27,
      fatPer100g: 3,
    }],
  });

  const item = result.days[0].meals[0].items[0];
  assert.equal(item.calories, 150, "priced from the user's own definition");
  assert.equal(item.estimated, false);
});
