const test = require("node:test");
const assert = require("node:assert/strict");
const {
  TerminalState,
  terminalStateFor,
  isTransientToolError,
  replyLanguageFor,
  describeUnfinishedTurn,
  TOOL_PHRASES,
} = require("./outcome");
const {ITERATION_LIMIT_MESSAGE} = require("./config");
const {tools} = require("../tools/read");

test("every turn status maps to exactly one terminal state", () => {
  assert.equal(terminalStateFor("ok"), TerminalState.COMPLETED);
  assert.equal(terminalStateFor("validated-fallback"), TerminalState.COMPLETED);
  assert.equal(terminalStateFor("proposed"), TerminalState.NEEDS_USER_INPUT);
  assert.equal(terminalStateFor("awaiting-input"),
      TerminalState.NEEDS_USER_INPUT);
  assert.equal(terminalStateFor("iteration-limit"),
      TerminalState.MAX_STEPS_REACHED);
  assert.equal(terminalStateFor("token-ceiling"),
      TerminalState.MAX_STEPS_REACHED);
  assert.equal(terminalStateFor("tool-error"), TerminalState.TOOL_ERROR);
  assert.equal(terminalStateFor("cancelled"), TerminalState.CANCELLED);
});

test("only backend hiccups count as transient tool failures", () => {
  assert.ok(isTransientToolError({code: 14}));
  assert.ok(isTransientToolError({code: "unavailable"}));
  assert.ok(isTransientToolError({transient: true}));
  assert.ok(!isTransientToolError(new Error("Unknown exercise")));
  assert.ok(!isTransientToolError({code: "invalid-argument"}));
  assert.ok(!isTransientToolError(null));
});

test("reply language follows the user's script", () => {
  assert.equal(replyLanguageFor("مش عايز ملوخية في الدايت"), "ar");
  assert.equal(replyLanguageFor("what's my lunch?"), "en");
  assert.equal(replyLanguageFor(""), "en");
});

test("max-steps reply names what was done, deduped, in order", () => {
  const text = describeUnfinishedTurn({
    terminalState: TerminalState.MAX_STEPS_REACHED,
    activity: [
      {tool: "get_diet", status: "ok"},
      {tool: "get_diet", status: "ok"},
      {tool: "search_food_alternatives", status: "ok"},
      {tool: "resolve_food", status: "error"},
    ],
    lang: "en",
  });
  assert.match(text,
      /I checked your diet and looked for alternatives, but I didn't get/);
  assert.doesNotMatch(text, /looked up the food/);
});

test("max-steps reply with no activity is the plain limit message", () => {
  assert.equal(describeUnfinishedTurn({
    terminalState: TerminalState.MAX_STEPS_REACHED, activity: [], lang: "en",
  }), ITERATION_LIMIT_MESSAGE);
});

test("tool-error reply says what succeeded and what failed", () => {
  const text = describeUnfinishedTurn({
    terminalState: TerminalState.TOOL_ERROR,
    activity: [
      {tool: "get_diet", status: "ok"},
      {tool: "resolve_food", status: "error"},
    ],
    failedTool: "resolve_food",
    lang: "en",
  });
  assert.match(text, /^I checked your diet, but I couldn't get the food/);
});

test("tool-error reply for an unnamed tool never leaks its identifier", () => {
  const text = describeUnfinishedTurn({
    terminalState: TerminalState.TOOL_ERROR,
    activity: [],
    failedTool: "log_food",
    lang: "en",
  });
  assert.doesNotMatch(text, /log_food/);
  assert.match(text, /kept failing/);
});

test("every read tool has a phrase in both languages", () => {
  for (const tool of tools) {
    assert.ok(TOOL_PHRASES.en[tool.name], `en phrase for ${tool.name}`);
    assert.ok(TOOL_PHRASES.ar[tool.name], `ar phrase for ${tool.name}`);
  }
});
