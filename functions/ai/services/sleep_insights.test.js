/**
 * Cover for the sleep AI layer's one job: refusing anything it cannot trace.
 *
 * Every test here is a way a fluent, plausible, wrong sentence could reach a
 * user. The model is not the adversary — a good model produces these
 * occasionally, and the gate is what makes that safe rather than a reason to
 * avoid using one.
 */

const {test, describe} = require("node:test");
const assert = require("node:assert");
const {
  groundedNumerals,
  validateResponse,
  generateSleepInsights,
  systemPrompt,
} = require("./sleep_insights");

const sheet = {
  windowNights: 7,
  nightsWithData: 6,
  facts: [
    {id: "meanDuration", value: 412, unit: "minutes", nights: 6},
    {id: "weekOverWeekDelta", value: 34, unit: "minutes", nights: 6},
    {id: "midpointVariability", value: 48, unit: "minutes", nights: 6},
  ],
  insufficient: ["trend"],
};

describe("the numeral gate", () => {
  test("accepts a sentence built from the sheet", () => {
    assert.ok(groundedNumerals(
        "You averaged 6h 52m across 6 nights.", sheet));
  });

  test("accepts the delta as written", () => {
    assert.ok(groundedNumerals("That is 34 minutes more than last week.",
        sheet));
  });

  test("rejects an invented figure", () => {
    assert.ok(!groundedNumerals("Your deep sleep rose 19% this week.", sheet));
  });

  test("rejects a plausible but wrong delta", () => {
    assert.ok(!groundedNumerals("You slept 47 minutes more than last week.",
        sheet));
  });

  test("rejects a derived number the model computed itself", () => {
    // 412 - 34 = 378 is arithmetically correct and still forbidden: the
    // moment the model computes, the gate is the only thing standing between
    // a user and a number nobody validated.
    assert.ok(!groundedNumerals("Last week you averaged 378 minutes.", sheet));
  });

  test("accepts a leading-zero clock time", () => {
    assert.ok(groundedNumerals("Lights out around 07:00.", sheet));
  });

  test("accepts prose with no numbers at all", () => {
    assert.ok(groundedNumerals("Your bedtime held steady this week.", sheet));
  });
});

describe("response validation", () => {
  const wrap = (insights) => JSON.stringify({insights});

  test("keeps a well-formed, grounded, attributed insight", () => {
    const {insights, rejected} = validateResponse(wrap([{
      kind: "duration",
      text: "You averaged 6h 52m a night.",
      basedOn: ["meanDuration"],
    }]), sheet);

    assert.strictEqual(insights.length, 1);
    assert.strictEqual(rejected, 0);
    assert.strictEqual(insights[0].nights, 6);
  });

  test("drops an insight that cites nothing", () => {
    const {insights, rejected} = validateResponse(wrap([{
      kind: "duration",
      text: "You slept well this week.",
      basedOn: [],
    }]), sheet);

    assert.strictEqual(insights.length, 0);
    assert.strictEqual(rejected, 1);
  });

  test("drops an insight citing a metric that failed its gate", () => {
    // Citing `trend` is the same offence as inventing a number: it claims
    // knowledge the data does not contain.
    const {insights, rejected} = validateResponse(wrap([{
      kind: "trend",
      text: "Your nights are getting longer.",
      basedOn: ["trend"],
    }]), sheet);

    assert.strictEqual(insights.length, 0);
    assert.strictEqual(rejected, 1);
  });

  test("drops an ungrounded insight and keeps its grounded sibling", () => {
    const {insights, rejected} = validateResponse(wrap([
      {kind: "duration", text: "You averaged 412 minutes.",
        basedOn: ["meanDuration"]},
      {kind: "consistency", text: "Your REM rose 12%.",
        basedOn: ["midpointVariability"]},
    ]), sheet);

    assert.strictEqual(insights.length, 1);
    assert.strictEqual(insights[0].kind, "duration");
    assert.strictEqual(rejected, 1);
  });

  test("survives a non-JSON response without throwing", () => {
    const {insights} = validateResponse("I'm afraid I can't do that.", sheet);
    assert.strictEqual(insights.length, 0);
  });

  test("caps at three insights", () => {
    const many = Array.from({length: 6}, () => ({
      kind: "duration",
      text: "You averaged 6h 52m.",
      basedOn: ["meanDuration"],
    }));
    assert.strictEqual(validateResponse(wrap(many), sheet).insights.length, 3);
  });
});

describe("generation", () => {
  test("retries once when the first attempt is ungrounded", async () => {
    let call = 0;
    const callModel = async () => {
      call++;
      return call === 1 ?
        JSON.stringify({insights: [{kind: "duration",
          text: "You averaged 9h 99m.", basedOn: ["meanDuration"]}]}) :
        JSON.stringify({insights: [{kind: "duration",
          text: "You averaged 6h 52m.", basedOn: ["meanDuration"]}]});
    };

    const result = await generateSleepInsights({factSheet: sheet, callModel});
    assert.strictEqual(result.attempts, 2);
    assert.strictEqual(result.insights.length, 1);
    assert.strictEqual(result.rejected, 1);
  });

  test("returns nothing rather than loosening the gate", async () => {
    // An empty result is correct, not a failure to handle: the client always
    // has its deterministic tier, so this degrades the wording and never the
    // truthfulness.
    const callModel = async () => JSON.stringify({
      insights: [{kind: "duration", text: "You slept 500 minutes.",
        basedOn: ["meanDuration"]}],
    });

    const result = await generateSleepInsights({factSheet: sheet, callModel});
    assert.strictEqual(result.insights.length, 0);
    assert.strictEqual(result.attempts, 2);
  });

  test("never calls the model for an empty fact sheet", async () => {
    let called = false;
    const callModel = async () => {
      called = true;
      return "{}";
    };

    const result = await generateSleepInsights({
      factSheet: {facts: [], insufficient: ["meanDuration"], windowNights: 7,
        nightsWithData: 0},
      callModel,
    });

    assert.strictEqual(called, false);
    assert.strictEqual(result.insights.length, 0);
  });

  test("a model error yields no insights rather than propagating", async () => {
    const callModel = async () => {
      throw new Error("upstream 503");
    };
    const result = await generateSleepInsights({factSheet: sheet, callModel});
    assert.strictEqual(result.insights.length, 0);
  });

  test("the model is handed the fact sheet and nothing else", async () => {
    let seen = null;
    const callModel = async (req) => {
      seen = req;
      return JSON.stringify({insights: [{kind: "duration",
        text: "You averaged 6h 52m.", basedOn: ["meanDuration"]}]});
    };

    await generateSleepInsights({factSheet: sheet, callModel});
    assert.deepStrictEqual(JSON.parse(seen.user), sheet);
    assert.match(seen.system, /must appear verbatim/);
  });
});

describe("the prompt states the rules it depends on", () => {
  test("forbids computing, causal claims and discussing gated metrics", () => {
    const prompt = systemPrompt();
    assert.match(prompt, /You do not compute/);
    assert.match(prompt, /Never claim a cause/);
    assert.match(prompt, /MUST NOT be discussed/);
  });
});
