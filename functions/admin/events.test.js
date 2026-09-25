const test = require("node:test");
const assert = require("node:assert/strict");
const {
  AdminEvent,
  sessionEvents,
  appOpenEvents,
  aiEvents,
  workoutPlanEvents,
  dietPlanEvents,
  summaryPatch,
  eventId,
  maskEmail,
  searchKey,
} = require("./events");

const names = (events) => events.map((e) => e.name);
const at = new Date("2026-09-25T10:00:00Z");

test("a new session is a workout_started", () => {
  assert.deepEqual(names(sessionEvents(null, {status: "active"})),
      [AdminEvent.WORKOUT_STARTED]);
});

test("set-by-set updates with no status change produce nothing", () => {
  assert.deepEqual(
      sessionEvents({status: "active"}, {status: "active", exercises: [1]}),
      []);
});

test("completing a session is a workout_completed with its duration", () => {
  const start = new Date("2026-09-25T10:00:00Z");
  const end = new Date("2026-09-25T11:05:00Z");
  const events = sessionEvents({status: "active"}, {
    status: "completed", startedAt: start, completedAt: end,
    pausedAccumMs: 5 * 60000,
  });
  assert.deepEqual(events, [{
    name: AdminEvent.WORKOUT_COMPLETED, props: {durationMinutes: 60},
  }]);
});

test("a user-corrected duration wins over the measured one", () => {
  const [e] = sessionEvents({status: "active"}, {
    status: "completed", correctedDurationMinutes: 45,
  });
  assert.equal(e.props.durationMinutes, 45);
});

test("a session logged straight to completed is started + completed", () => {
  assert.deepEqual(names(sessionEvents(null, {status: "completed"})),
      [AdminEvent.WORKOUT_STARTED, AdminEvent.WORKOUT_COMPLETED]);
});

test("abandoning is a workout_abandoned", () => {
  assert.deepEqual(
      names(sessionEvents({status: "active"}, {status: "abandoned"})),
      [AdminEvent.WORKOUT_ABANDONED]);
});

test("voiding a completed session takes it back off the count", () => {
  const [e] = sessionEvents({status: "completed"}, {status: "voided"});
  assert.equal(e.name, AdminEvent.WORKOUT_VOIDED);
  assert.equal(summaryPatch(e, at).inc.workoutsCompleted, -1);
  assert.equal(summaryPatch(e, at).set.lastActiveAt, undefined);
});

test("a deleted session (account erasure) is not activity", () => {
  assert.deepEqual(sessionEvents({status: "completed"}, null), []);
});

test("app_opened only when a NEW device session is claimed", () => {
  const after = {sessionId: "s2", platform: "ios", appVersion: "1.2.0"};
  assert.deepEqual(appOpenEvents({sessionId: "s1"}, after), [{
    name: AdminEvent.APP_OPENED,
    props: {platform: "ios", appVersion: "1.2.0"},
  }]);
  assert.deepEqual(appOpenEvents({sessionId: "s2"}, after), []);
  assert.deepEqual(appOpenEvents(after, null), []);
});

test("ai_request copies counts, never content", () => {
  const [e] = aiEvents({
    feature: "chat", provider: "anthropic", status: "ok",
    tokensIn: 1200, tokensOut: 300, costUsd: 0.01,
    prompt: "private words", model: "x",
  });
  assert.deepEqual(e.props, {
    feature: "chat", provider: "anthropic", status: "ok",
    tokensIn: 1200, tokensOut: 300, costUsd: 0.01,
  });
});

test("ai_request adds its tokens and feature to the summary", () => {
  const [e] = aiEvents({feature: "diet_import", tokensIn: 10, tokensOut: 5,
    costUsd: 0.5});
  const {inc} = summaryPatch(e, at);
  assert.equal(inc.aiRequests, 1);
  assert.equal(inc.aiTokensIn, 10);
  assert.equal(inc.aiTokensOut, 5);
  assert.equal(inc.aiCostUsd, 0.5);
  assert.equal(inc["usage.ai_diet_import"], 1);
});

test("a plan marks the user as having one", () => {
  const [e] = workoutPlanEvents({source: "pdf", days: []});
  assert.deepEqual(e, {name: AdminEvent.WORKOUT_PLAN_CREATED,
    props: {source: "pdf"}});
  assert.equal(summaryPatch(e, at).set.hasWorkoutPlan, true);
});

test("an imported or generated diet is diet_imported; a manual one isn't",
    () => {
      assert.equal(dietPlanEvents({source: "generated"})[0].name,
          AdminEvent.DIET_IMPORTED);
      assert.equal(dietPlanEvents({source: "manual"})[0].name,
          AdminEvent.DIET_PLAN_CREATED);
      assert.equal(dietPlanEvents({})[0].name, AdminEvent.DIET_PLAN_CREATED);
    });

test("admin actions change status but are not the user being active", () => {
  const p = summaryPatch({name: AdminEvent.ACCOUNT_DISABLED, props: {}}, at);
  assert.equal(p.set.status, "disabled");
  assert.equal(p.set.lastActiveAt, undefined);
});

test("user events move lastActiveAt and record the last event", () => {
  const p = summaryPatch({name: AdminEvent.APP_OPENED,
    props: {platform: "android"}}, at);
  assert.equal(p.set.lastActiveAt, at);
  assert.deepEqual(p.set.lastEvent, {name: AdminEvent.APP_OPENED, at});
  assert.equal(p.set.platform, "android");
});

test("event ids are deterministic and path-safe", () => {
  assert.equal(eventId("app_opened", "u1", "a/b"), "app_opened_u1_a_b");
  assert.equal(eventId("x", "u", "s"), eventId("x", "u", "s"));
});

test("emails are masked", () => {
  assert.equal(maskEmail("ziad@gmail.com"), "zi**@gmail.com");
  assert.equal(maskEmail("a@b.co"), "a*@b.co");
  assert.equal(maskEmail(undefined), null);
});

test("search keys are trimmed and lower-cased", () => {
  assert.equal(searchKey("  Ziad "), "ziad");
  assert.equal(searchKey(""), null);
  assert.equal(searchKey(null), null);
});
