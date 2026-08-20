/**
 * Offline unit tests for `./workout_import.js`. No `@anthropic-ai/sdk`, no
 * network — `callModel` is scripted per test, so this runs under plain
 * `node --test`.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {extractWorkoutPlan, TOOL_NAME} = require("./workout_import");
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
 * A well-formed `propose_workout_split` tool-call response.
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

test("extractWorkoutPlan: sends the PDF as a document block with a forced tool call", async () => {
  const callModel = scriptedModel(
      toolResponse({planName: "PPL", days: []}));

  await extractWorkoutPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});

  const req = callModel.lastRequest;
  assert.equal(req.tool_choice.type, "tool");
  assert.equal(req.tool_choice.name, TOOL_NAME);
  assert.equal(req.messages[0].content[0].type, "document");
  assert.equal(req.messages[0].content[0].source.media_type, "application/pdf");
  assert.equal(req.messages[0].content[0].source.data, "ZmFrZS1wZGY=");
});

test("extractWorkoutPlan: maps a well-formed extraction into the plan shape", async () => {
  const callModel = scriptedModel(toolResponse({
    planName: "Push Pull Legs",
    days: [
      {
        slot: "A",
        label: "Push",
        exercises: [
          {
            name: "Bench Press",
            muscleGroup: "Chest",
            sets: 3,
            repsMin: 8,
            repsMax: 12,
            toFailure: false,
            targetWeightKg: 60,
            restSeconds: 90,
          },
          {
            name: "Push-up",
            muscleGroup: null,
            sets: 3,
            repsMin: null,
            repsMax: null,
            toFailure: true,
            targetWeightKg: null,
            restSeconds: null,
          },
        ],
      },
    ],
  }));

  const result = await extractWorkoutPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});

  assert.equal(result.planName, "Push Pull Legs");
  assert.equal(result.days.length, 1);
  const day = result.days[0];
  assert.equal(day.slot, "A");
  assert.equal(day.label, "Push");
  assert.equal(day.exercises.length, 2);
  assert.deepEqual(day.exercises[0], {
    name: "Bench Press",
    muscleGroup: "Chest",
    sets: 3,
    repsMin: 8,
    repsMax: 12,
    toFailure: false,
    targetWeightKg: 60,
    restSeconds: 90,
  });
  assert.deepEqual(day.exercises[1], {
    name: "Push-up",
    muscleGroup: null,
    sets: 3,
    repsMin: null,
    repsMax: null,
    toFailure: true,
    targetWeightKg: null,
    restSeconds: null,
  });
});

test("extractWorkoutPlan: a malformed day/exercise is dropped, not thrown (partial parse survives)", async () => {
  const callModel = scriptedModel(toolResponse({
    planName: "Messy Split",
    days: [
      {slot: "A", label: "Push", exercises: [
        {name: "Bench Press", sets: 3}, // missing optional fields → defaulted
        {name: "", sets: 3}, // no name → dropped
        null, // garbage entry → dropped
      ]},
      {slot: "B", label: "", exercises: []}, // no label → whole day dropped
      "not a day", // garbage → dropped
    ],
  }));

  const result = await extractWorkoutPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});

  assert.equal(result.days.length, 1);
  assert.equal(result.days[0].exercises.length, 1);
  assert.equal(result.days[0].exercises[0].name, "Bench Press");
  assert.equal(result.days[0].exercises[0].sets, 3);
  assert.equal(result.days[0].exercises[0].muscleGroup, null);
});

test("extractWorkoutPlan: an absurd sets count is clamped, not passed through raw", async () => {
  const callModel = scriptedModel(toolResponse({
    planName: "X",
    days: [
      {slot: "A", label: "Push", exercises: [
        {name: "Bench Press", sets: 500, repsMin: 8, repsMax: 8, toFailure: false},
      ]},
    ],
  }));

  const result = await extractWorkoutPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});

  assert.equal(result.days[0].exercises[0].sets, 20);
});

test("extractWorkoutPlan: negative or non-finite numeric fields fall back to null, not passed through", async () => {
  const callModel = scriptedModel(toolResponse({
    planName: "X",
    days: [
      {slot: "A", label: "Push", exercises: [
        {
          name: "Bench Press",
          sets: 3,
          repsMin: -5,
          repsMax: -1,
          toFailure: false,
          targetWeightKg: NaN,
          restSeconds: -90,
        },
      ]},
    ],
  }));

  const result = await extractWorkoutPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});
  const exercise = result.days[0].exercises[0];

  assert.equal(exercise.repsMin, null);
  assert.equal(exercise.repsMax, null);
  assert.equal(exercise.targetWeightKg, null);
  assert.equal(exercise.restSeconds, null);
});

test("extractWorkoutPlan: missing planName falls back to a default", async () => {
  const callModel = scriptedModel(toolResponse({days: []}));
  const result = await extractWorkoutPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});
  assert.equal(result.planName, "Imported Split");
});

test("extractWorkoutPlan: a refusal stop reason surfaces as a GatewayError", async () => {
  const callModel = scriptedModel({stop_reason: "refusal", content: []});
  await assert.rejects(
      () => extractWorkoutPlan({callModel, pdfBase64: "ZmFrZS1wZGY="}),
      (err) => {
        assert.ok(err instanceof GatewayError);
        assert.equal(err.code, "failed-precondition");
        return true;
      },
  );
});

test("extractWorkoutPlan: no tool call in the response surfaces a GatewayError", async () => {
  const callModel = scriptedModel({stop_reason: "end_turn", content: [{type: "text", text: "hmm"}]});
  await assert.rejects(
      () => extractWorkoutPlan({callModel, pdfBase64: "ZmFrZS1wZGY="}),
      (err) => {
        assert.ok(err instanceof GatewayError);
        assert.equal(err.code, "internal");
        return true;
      },
  );
});

test("extractWorkoutPlan: a callModel failure surfaces as a GatewayError, not a raw throw", async () => {
  const callModel = async () => {
    throw new Error("network blew up");
  };
  await assert.rejects(
      () => extractWorkoutPlan({callModel, pdfBase64: "ZmFrZS1wZGY="}),
      (err) => {
        assert.ok(err instanceof GatewayError);
        assert.equal(err.code, "internal");
        return true;
      },
  );
});

test("extractWorkoutPlan: rejects a missing/empty pdfBase64 before calling the model", async () => {
  const callModel = scriptedModel(toolResponse({planName: "x", days: []}));
  await assert.rejects(
      () => extractWorkoutPlan({callModel, pdfBase64: ""}),
      (err) => {
        assert.ok(err instanceof GatewayError);
        assert.equal(err.code, "invalid-argument");
        return true;
      },
  );
  assert.equal(callModel.lastRequest, undefined);
});
