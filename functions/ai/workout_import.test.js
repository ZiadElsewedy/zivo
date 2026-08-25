/**
 * Offline unit tests for `./workout_import.js`. No `@anthropic-ai/sdk`, no
 * network — `callModel` is scripted per test, so this runs under plain
 * `node --test`.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {
  extractWorkoutPlan,
  TOOL_NAME,
  REJECT_TOOL_NAME,
  DEFAULT_REJECTION_REASON,
} = require("./workout_import");
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

const VALID_DAY = {
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
  ],
};

test("extractWorkoutPlan: sends the PDF as a document block, offering both tools with tool_choice 'any'", async () => {
  const callModel = scriptedModel(
      toolResponse({planName: "PPL", days: [VALID_DAY]}));

  await extractWorkoutPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});

  const req = callModel.lastRequest;
  assert.equal(req.tool_choice.type, "any");
  assert.deepEqual(req.tools.map((t) => t.name), [TOOL_NAME, REJECT_TOOL_NAME]);
  assert.equal(req.messages[0].content[0].type, "document");
  assert.equal(req.messages[0].content[0].source.media_type, "application/pdf");
  assert.equal(req.messages[0].content[0].source.data, "ZmFrZS1wZGY=");
});

test("extractWorkoutPlan: maps a well-formed extraction into an {ok: true} plan", async () => {
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

  assert.equal(result.ok, true);
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

  assert.equal(result.ok, true);
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

  assert.equal(result.ok, true);
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
  const callModel = scriptedModel(toolResponse({days: [VALID_DAY]}));
  const result = await extractWorkoutPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});
  assert.equal(result.ok, true);
  assert.equal(result.planName, "Imported Split");
});

test("extractWorkoutPlan: an empty days array normalizes to an honest rejection, not a hollow success", async () => {
  const callModel = scriptedModel(toolResponse({planName: "PPL", days: []}));
  const result = await extractWorkoutPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});
  assert.equal(result.ok, false);
  assert.equal(result.reason, DEFAULT_REJECTION_REASON);
});

test("extractWorkoutPlan: every day/exercise dropped during normalization is ALSO an honest rejection", async () => {
  // Every day here fails normalize()'s own validity checks, so this is a
  // `propose_workout_split` call that degrades to nothing usable.
  const callModel = scriptedModel(toolResponse({
    planName: "Not Really A Plan",
    days: [
      {slot: "A", label: "", exercises: []},
      "garbage",
      null,
    ],
  }));
  const result = await extractWorkoutPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});
  assert.equal(result.ok, false);
  assert.equal(result.reason, DEFAULT_REJECTION_REASON);
});

test("extractWorkoutPlan: the model can explicitly decline via reject_import, with its own reason", async () => {
  const callModel = scriptedModel(
      rejectResponse("This looks like a grocery receipt, not a workout plan."));
  const result = await extractWorkoutPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});
  assert.equal(result.ok, false);
  assert.equal(result.reason, "This looks like a grocery receipt, not a workout plan.");
});

test("extractWorkoutPlan: a reject_import call with a blank reason falls back to the default message", async () => {
  const callModel = scriptedModel(rejectResponse("   "));
  const result = await extractWorkoutPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});
  assert.equal(result.ok, false);
  assert.equal(result.reason, DEFAULT_REJECTION_REASON);
});

test("extractWorkoutPlan: a refusal stop reason surfaces as a GatewayError (content-policy, not a rejection)", async () => {
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

test("extractWorkoutPlan: neither tool called in the response surfaces a GatewayError", async () => {
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

test("extractWorkoutPlan: logEvent fires an 'accepted' event with stop reason and counts on a genuine extraction", async () => {
  const callModel = scriptedModel(
      toolResponse({planName: "PPL", days: [VALID_DAY]}));
  const events = [];
  await extractWorkoutPlan({callModel, pdfBase64: "ZmFrZS1wZGY=", logEvent: (e) => events.push(e)});

  assert.equal(events.length, 1);
  assert.equal(events[0].stage, "accepted");
  assert.equal(events[0].stopReason, "tool_use");
  assert.equal(events[0].toolCalled, TOOL_NAME);
  assert.equal(events[0].dayCount, 1);
  assert.equal(events[0].exerciseCount, 1);
});

test("extractWorkoutPlan: logEvent fires a 'rejected' event with the reject reason when the model declines", async () => {
  const callModel = scriptedModel(
      rejectResponse("This looks like a grocery receipt, not a workout plan."));
  const events = [];
  await extractWorkoutPlan({callModel, pdfBase64: "ZmFrZS1wZGY=", logEvent: (e) => events.push(e)});

  assert.equal(events.length, 1);
  assert.equal(events[0].stage, "rejected");
  assert.equal(events[0].toolCalled, REJECT_TOOL_NAME);
  assert.equal(events[0].reason, "This looks like a grocery receipt, not a workout plan.");
});

test("extractWorkoutPlan: works with no logEvent provided (defaults to a no-op)", async () => {
  const callModel = scriptedModel(toolResponse({planName: "PPL", days: [VALID_DAY]}));
  const result = await extractWorkoutPlan({callModel, pdfBase64: "ZmFrZS1wZGY="});
  assert.equal(result.ok, true);
});

test("SYSTEM_PROMPT: biases toward extraction, treating reject as a last resort not a default", async () => {
  const {SYSTEM_PROMPT} = require("./workout_import");
  assert.match(SYSTEM_PROMPT, /default action is propose_workout_split/);
  assert.match(SYSTEM_PROMPT, /Do NOT reject merely because/);
});

test("extractWorkoutPlan: rejects a missing/empty pdfBase64 before calling the model", async () => {
  const callModel = scriptedModel(toolResponse({planName: "x", days: [VALID_DAY]}));
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

test("extractWorkoutPlan: an image mediaType rides as an image block", async () => {
  const callModel = scriptedModel(
      toolResponse({planName: "PPL", days: [VALID_DAY]}));

  await extractWorkoutPlan({
    callModel,
    fileBase64: "aW1n",
    mediaType: "image/jpeg",
  });

  const block = callModel.lastRequest.messages[0].content[0];
  assert.equal(block.type, "image");
  assert.equal(block.source.media_type, "image/jpeg");
  assert.equal(block.source.data, "aW1n");
});

test("extractWorkoutPlan: fileBase64 wins over the legacy pdfBase64 param", async () => {
  const callModel = scriptedModel(
      toolResponse({planName: "PPL", days: [VALID_DAY]}));

  await extractWorkoutPlan({
    callModel,
    pdfBase64: "b2xk",
    fileBase64: "bmV3",
    mediaType: "image/png",
  });

  const block = callModel.lastRequest.messages[0].content[0];
  assert.equal(block.source.data, "bmV3");
});

test("extractWorkoutPlan: rejects an unsupported media type before calling the model", async () => {
  const callModel = scriptedModel(toolResponse({planName: "x", days: [VALID_DAY]}));
  await assert.rejects(
      () => extractWorkoutPlan({
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
