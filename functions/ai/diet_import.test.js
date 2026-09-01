/**
 * Offline unit tests for `./diet_import.js`. No `@anthropic-ai/sdk`, no
 * network — `callModel` is scripted per test, so this runs under plain
 * `node --test`. Mirrors `./workout_import.test.js`'s structure.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {
  extractDietPlan,
  TOOL_NAME,
  REJECT_TOOL_NAME,
  DEFAULT_REJECTION_REASON,
  MAX_TEXT_CHARS,
} = require("./diet_import");
const {GatewayError} = require("./gateway");

/**
 * A `callModel` fake resolving to a single scripted response, recording the
 * request it was called with.
 * @param {!Object} response
 * @return {function(!Object): !Promise<!Object>}
 */
function scriptedModel(response) {
  const fn = async (request) => {
    fn.lastRequest = request;
    return response;
  };
  return fn;
}

/**
 * A well-formed `propose_diet_plan` tool-call response.
 * @param {!Object} input
 * @return {!Object}
 */
function toolResponse(input) {
  return {
    stop_reason: "tool_use",
    content: [
      {type: "tool_use", id: "call-1", name: TOOL_NAME, input},
    ],
  };
}

/**
 * A `reject_import` tool-call response.
 * @param {string} reason
 * @return {!Object}
 */
function rejectResponse(reason) {
  return {
    stop_reason: "tool_use",
    content: [
      {type: "tool_use", id: "call-1", name: REJECT_TOOL_NAME, input: {reason}},
    ],
  };
}

const VALID_ITEM = {
  name: "Oats", quantity: 60, unit: "g",
  calories: 220, proteinG: 8, carbsG: 38, fatG: 4, estimated: false,
};

const VALID_DAY = {
  weekday: null,
  label: "Every day",
  meals: [
    {label: "Breakfast", items: [VALID_ITEM]},
  ],
};

test("extractDietPlan: sends the PDF as a document block, offering both tools with tool_choice 'any'", async () => {
  const callModel = scriptedModel(
      toolResponse({planName: "Cut", days: [VALID_DAY]}));

  await extractDietPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});

  const req = callModel.lastRequest;
  assert.equal(req.tool_choice.type, "any");
  assert.deepEqual(req.tools.map((t) => t.name), [TOOL_NAME, REJECT_TOOL_NAME]);
  assert.equal(req.messages[0].content[0].type, "document");
  assert.equal(req.messages[0].content[0].source.media_type, "application/pdf");
  assert.equal(req.messages[0].content[0].source.data, "ZmFrZS1wZGY=");
});

test("extractDietPlan: maps a well-formed extraction into an {ok: true} plan, estimated flag included", async () => {
  const callModel = scriptedModel(toolResponse({
    planName: "Cut — 2200 kcal",
    days: [
      {
        weekday: null,
        label: "Every day",
        meals: [
          {
            label: "Breakfast",
            items: [
              {
                name: "Oats", quantity: 60, unit: "g",
                calories: 220, proteinG: 8, carbsG: 38, fatG: 4,
                estimated: false,
              },
              {
                name: "Banana", quantity: 1, unit: "pcs",
                calories: 90, proteinG: 1, carbsG: 23, fatG: 0,
                estimated: true,
              },
            ],
          },
        ],
      },
    ],
  }));

  const result = await extractDietPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});

  assert.equal(result.ok, true);
  assert.equal(result.planName, "Cut — 2200 kcal");
  assert.equal(result.days.length, 1);
  const day = result.days[0];
  assert.equal(day.weekday, null);
  assert.equal(day.label, "Every day");
  assert.equal(day.meals.length, 1);
  const meal = day.meals[0];
  assert.equal(meal.label, "Breakfast");
  assert.equal(meal.items.length, 2);
  assert.deepEqual(meal.items[0], {
    name: "Oats", quantity: 60, unit: "g",
    calories: 220, proteinG: 8, carbsG: 38, fatG: 4, estimated: false,
  });
  assert.deepEqual(meal.items[1], {
    name: "Banana", quantity: 1, unit: "pcs",
    calories: 90, proteinG: 1, carbsG: 23, fatG: 0, estimated: true,
  });
});

test("extractDietPlan: a weekday-specific day round-trips its weekday", async () => {
  const callModel = scriptedModel(toolResponse({
    planName: "Split plan",
    days: [{weekday: 1, label: "Monday", meals: [{label: "Lunch", items: [VALID_ITEM]}]}],
  }));
  const result = await extractDietPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});
  assert.equal(result.days[0].weekday, 1);
});

test("extractDietPlan: a malformed day/meal/item is dropped, not thrown (partial parse survives)", async () => {
  const callModel = scriptedModel(toolResponse({
    planName: "Messy Plan",
    days: [
      {weekday: null, label: "Every day", meals: [
        {label: "Breakfast", items: [
          {name: "Oats", quantity: 60, unit: "g"}, // missing calories/macros → defaulted
          {name: "", quantity: 1, unit: "g", calories: 1, proteinG: 0, carbsG: 0, fatG: 0, estimated: false}, // no name → dropped
          null, // garbage entry → dropped
        ]},
        {label: "", items: []}, // no label → whole meal dropped
        "not a meal", // garbage → dropped
      ]},
      {weekday: null, label: "", meals: []}, // no label → whole day dropped
      "not a day", // garbage → dropped
    ],
  }));

  const result = await extractDietPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});

  assert.equal(result.ok, true);
  assert.equal(result.days.length, 1);
  assert.equal(result.days[0].meals.length, 1);
  assert.equal(result.days[0].meals[0].items.length, 1);
  const item = result.days[0].meals[0].items[0];
  assert.equal(item.name, "Oats");
  assert.equal(item.quantity, 60);
  assert.equal(item.unit, "g");
  // Missing/malformed nutrition fields on an otherwise-valid item degrade to
  // null (not fabricated), same defense-in-depth as workout's numeric fields.
  assert.equal(item.calories, null);
  assert.equal(item.proteinG, null);
  assert.equal(item.estimated, false);
});

test("extractDietPlan: an absurd calorie count is dropped to null, not passed through raw", async () => {
  const callModel = scriptedModel(toolResponse({
    planName: "X",
    days: [{weekday: null, label: "Every day", meals: [
      {label: "Lunch", items: [
        {name: "Feast", quantity: 1, unit: "pcs", calories: 999999, proteinG: 0, carbsG: 0, fatG: 0, estimated: true},
      ]},
    ]}],
  }));

  const result = await extractDietPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});
  assert.equal(result.days[0].meals[0].items[0].calories, null);
});

test("extractDietPlan: negative or non-finite numeric fields fall back to null, not passed through", async () => {
  const callModel = scriptedModel(toolResponse({
    planName: "X",
    days: [{weekday: null, label: "Every day", meals: [
      {label: "Lunch", items: [
        {
          name: "Weird item", quantity: -5, unit: "g",
          calories: -100, proteinG: NaN, carbsG: -1, fatG: Infinity,
          estimated: true,
        },
      ]},
    ]}],
  }));

  const result = await extractDietPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});
  const item = result.days[0].meals[0].items[0];

  // quantity falls back to 0 (not dropped — name/unit are still useful).
  assert.equal(item.quantity, 0);
  assert.equal(item.calories, null);
  assert.equal(item.proteinG, null);
  assert.equal(item.carbsG, null);
  assert.equal(item.fatG, null);
});

test("extractDietPlan: missing planName falls back to a default", async () => {
  const callModel = scriptedModel(toolResponse({days: [VALID_DAY]}));
  const result = await extractDietPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});
  assert.equal(result.ok, true);
  assert.equal(result.planName, "Imported Plan");
});

test("extractDietPlan: an empty days array normalizes to an honest rejection, not a hollow success", async () => {
  const callModel = scriptedModel(toolResponse({planName: "Cut", days: []}));
  const result = await extractDietPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});
  assert.equal(result.ok, false);
  assert.equal(result.reason, DEFAULT_REJECTION_REASON);
});

test("extractDietPlan: every day/meal dropped during normalization is ALSO an honest rejection", async () => {
  const callModel = scriptedModel(toolResponse({
    planName: "Not Really A Plan",
    days: [
      {weekday: null, label: "", meals: []},
      "garbage",
      null,
    ],
  }));
  const result = await extractDietPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});
  assert.equal(result.ok, false);
  assert.equal(result.reason, DEFAULT_REJECTION_REASON);
});

test("extractDietPlan: the model can explicitly decline via reject_import, with its own reason", async () => {
  const callModel = scriptedModel(
      rejectResponse("This looks like a workout plan, not a diet plan."));
  const result = await extractDietPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});
  assert.equal(result.ok, false);
  assert.equal(result.reason, "This looks like a workout plan, not a diet plan.");
});

test("extractDietPlan: a reject_import call with a blank reason falls back to the default message", async () => {
  const callModel = scriptedModel(rejectResponse("   "));
  const result = await extractDietPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});
  assert.equal(result.ok, false);
  assert.equal(result.reason, DEFAULT_REJECTION_REASON);
});

test("extractDietPlan: a refusal stop reason surfaces as a GatewayError (content-policy, not a rejection)", async () => {
  const callModel = scriptedModel({stop_reason: "refusal", content: []});
  await assert.rejects(
      () => extractDietPlan({callModel, pdfBase64: "ZmFrZS1wZGY="}),
      (err) => {
        assert.ok(err instanceof GatewayError);
        assert.equal(err.code, "failed-precondition");
        return true;
      },
  );
});

test("extractDietPlan: neither tool called in the response surfaces a GatewayError", async () => {
  const callModel = scriptedModel({stop_reason: "end_turn", content: [{type: "text", text: "hmm"}]});
  await assert.rejects(
      () => extractDietPlan({callModel, pdfBase64: "ZmFrZS1wZGY="}),
      (err) => {
        assert.ok(err instanceof GatewayError);
        assert.equal(err.code, "internal");
        return true;
      },
  );
});

test("extractDietPlan: a callModel failure surfaces as a GatewayError, not a raw throw", async () => {
  const callModel = async () => {
    throw new Error("network blew up");
  };
  await assert.rejects(
      () => extractDietPlan({callModel, pdfBase64: "ZmFrZS1wZGY="}),
      (err) => {
        assert.ok(err instanceof GatewayError);
        assert.equal(err.code, "internal");
        return true;
      },
  );
});

test("extractDietPlan: logEvent fires an 'accepted' event with stop reason and counts on a genuine extraction", async () => {
  const callModel = scriptedModel(
      toolResponse({planName: "Cut", days: [VALID_DAY]}));
  const events = [];
  await extractDietPlan({callModel, pdfBase64: "ZmFrZS1wZGY=", logEvent: (e) => events.push(e)});

  assert.equal(events.length, 1);
  assert.equal(events[0].stage, "accepted");
  assert.equal(events[0].stopReason, "tool_use");
  assert.equal(events[0].toolCalled, TOOL_NAME);
  assert.equal(events[0].dayCount, 1);
  assert.equal(events[0].mealCount, 1);
});

test("extractDietPlan: logEvent fires a 'rejected' event with the reject reason when the model declines", async () => {
  const callModel = scriptedModel(
      rejectResponse("This looks like a workout plan, not a diet plan."));
  const events = [];
  await extractDietPlan({callModel, pdfBase64: "ZmFrZS1wZGY=", logEvent: (e) => events.push(e)});

  assert.equal(events.length, 1);
  assert.equal(events[0].stage, "rejected");
  assert.equal(events[0].toolCalled, REJECT_TOOL_NAME);
  assert.equal(events[0].reason, "This looks like a workout plan, not a diet plan.");
});

test("extractDietPlan: works with no logEvent provided (defaults to a no-op)", async () => {
  const callModel = scriptedModel(toolResponse({planName: "Cut", days: [VALID_DAY]}));
  const result = await extractDietPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});
  assert.equal(result.ok, true);
});

test("SYSTEM_PROMPT: biases toward extraction, and structurally forbids leaving calories/macros blank", async () => {
  const {SYSTEM_PROMPT, IMPORT_TOOL} = require("./diet_import");
  assert.match(SYSTEM_PROMPT, /default action is propose_diet_plan/);
  assert.match(SYSTEM_PROMPT, /Do NOT reject merely because/);
  assert.match(SYSTEM_PROMPT, /NEVER leave\s+calories/);

  // The estimation requirement isn't just prompt wording — the schema
  // itself makes these non-nullable, so strict mode structurally forces a
  // value on every item.
  const itemSchema = IMPORT_TOOL.inputSchema.properties.days.items
      .properties.meals.items.properties.items.items;
  for (const field of ["calories", "proteinG", "carbsG", "fatG", "estimated"]) {
    assert.ok(itemSchema.required.includes(field), `${field} should be required`);
    if (field !== "estimated") {
      assert.ok(
          !Array.isArray(itemSchema.properties[field].type),
          `${field} should be a single non-nullable type, not a nullable union`,
      );
    }
  }
});

test("extractDietPlan: rejects a missing/empty pdfBase64 before calling the model", async () => {
  const callModel = scriptedModel(toolResponse({planName: "x", days: [VALID_DAY]}));
  await assert.rejects(
      () => extractDietPlan({callModel, pdfBase64: ""}),
      (err) => {
        assert.ok(err instanceof GatewayError);
        assert.equal(err.code, "invalid-argument");
        return true;
      },
  );
  assert.equal(callModel.lastRequest, undefined);
});

test("extractDietPlan: an image mediaType rides as an image block", async () => {
  const callModel = scriptedModel(
      toolResponse({planName: "Cut", days: [VALID_DAY]}));

  await extractDietPlan({
    callModel,
    fileBase64: "aW1n",
    mediaType: "image/jpeg",
  });

  const block = callModel.lastRequest.messages[0].content[0];
  assert.equal(block.type, "image");
  assert.equal(block.source.media_type, "image/jpeg");
  assert.equal(block.source.data, "aW1n");
});

test("extractDietPlan: fileBase64 wins over the legacy pdfBase64 param", async () => {
  const callModel = scriptedModel(
      toolResponse({planName: "Cut", days: [VALID_DAY]}));

  await extractDietPlan({
    callModel,
    pdfBase64: "b2xk",
    fileBase64: "bmV3",
    mediaType: "image/png",
  });

  const block = callModel.lastRequest.messages[0].content[0];
  assert.equal(block.source.data, "bmV3");
});

test("extractDietPlan: rejects an unsupported media type before calling the model", async () => {
  const callModel = scriptedModel(toolResponse({planName: "x", days: [VALID_DAY]}));
  await assert.rejects(
      () => extractDietPlan({
        callModel,
        fileBase64: "ZG9jeA==",
        mediaType: "application/msword",
      }),
      (err) => {
        assert.ok(err instanceof GatewayError);
        assert.equal(err.code, "invalid-argument");
        return true;
      },
  );
  assert.equal(callModel.lastRequest, undefined);
});

// --- a dictated or typed description ---------------------------------------
//
// The same extractor, different material: a transcript of someone describing
// their own meals. One schema and one review screen serve every capture
// route — four prompts producing four shapes is how they drift apart.

test("extractDietPlan: sends a description as text, with no document block", async () => {
  const callModel = scriptedModel(
      toolResponse({planName: "My plan", days: [VALID_DAY]}));

  const result = await extractDietPlan({
    callModel,
    text: "Breakfast is three eggs and 60 grams of oats.",
  });

  assert.equal(result.ok, true);
  const content = callModel.lastRequest.messages[0].content;
  assert.equal(content.length, 1);
  assert.equal(content[0].type, "text");
  assert.match(content[0].text, /three eggs and 60 grams of oats/);
  // The user's words are fenced, so the model can tell them from the
  // instruction wrapping them.
  assert.match(content[0].text, /---BEGIN DESCRIPTION---/);
  assert.equal(
      content.some((b) => b.type === "document" || b.type === "image"), false);
});

test("extractDietPlan: a description gets the description prompt, not the document one", async () => {
  const callModel = scriptedModel(
      toolResponse({planName: "My plan", days: [VALID_DAY]}));

  await extractDietPlan({callModel, text: "Lunch is rice and chicken."});
  const spoken = callModel.lastRequest.system[0].text;
  assert.match(spoken, /spoken aloud and\ntranscribed, or typed out/);
  // The rules that matter are shared, not duplicated per input kind.
  assert.match(spoken, /NEVER leave\s+calories/);
  assert.match(spoken, /labeled exactly "Supplements"/);

  await extractDietPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});
  assert.match(callModel.lastRequest.system[0].text, /Read every page/);
});

test("extractDietPlan: a description still rejects when it isn't about food", async () => {
  const callModel = scriptedModel(rejectResponse("This is a shopping list."));

  const result = await extractDietPlan({
    callModel,
    text: "Remember to call the plumber and pick up a parcel.",
  });

  assert.equal(result.ok, false);
  assert.equal(result.reason, "This is a shopping list.");
});

test("extractDietPlan: refuses both a file and a description in one call", async () => {
  const callModel = scriptedModel(
      toolResponse({planName: "Cut", days: [VALID_DAY]}));

  await assert.rejects(
      () => extractDietPlan({
        callModel, pdfBase64: "ZmFrZS1wZGY=", text: "Breakfast is eggs.",
      }),
      (err) => err instanceof GatewayError && err.code === "invalid-argument");
});

test("extractDietPlan: refuses neither, and treats a blank description as neither", async () => {
  const callModel = scriptedModel(
      toolResponse({planName: "Cut", days: [VALID_DAY]}));

  await assert.rejects(
      () => extractDietPlan({callModel}),
      (err) => err instanceof GatewayError && err.code === "invalid-argument");
  await assert.rejects(
      () => extractDietPlan({callModel, text: "   \n  "}),
      (err) => err instanceof GatewayError && err.code === "invalid-argument");
});

test("extractDietPlan: refuses a description past the length bound", async () => {
  const callModel = scriptedModel(
      toolResponse({planName: "Cut", days: [VALID_DAY]}));

  await assert.rejects(
      () => extractDietPlan({callModel, text: "a".repeat(MAX_TEXT_CHARS + 1)}),
      (err) => err instanceof GatewayError && err.code === "invalid-argument");
});

test("extractDietPlan: a description does not need a media type", async () => {
  const callModel = scriptedModel(
      toolResponse({planName: "Cut", days: [VALID_DAY]}));

  // mediaType is meaningless for text; supplying a bogus one must not be
  // validated against the file vocabulary and reject a perfectly good
  // description.
  const result = await extractDietPlan({
    callModel, text: "Dinner is 200g salmon.", mediaType: "text/plain",
  });
  assert.equal(result.ok, true);
});
