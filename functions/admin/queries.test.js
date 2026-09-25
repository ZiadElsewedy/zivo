const test = require("node:test");
const assert = require("node:assert/strict");
const {
  DAY_MS,
  MAX_PAGE_SIZE,
  parseUserQuery,
  toUserRow,
  toUserDetail,
  toEvent,
  localDayStart,
} = require("./queries");

const NOW = Date.parse("2026-09-25T12:00:00Z");

test("defaults to every user, most recently active first", () => {
  const q = parseUserQuery({}, NOW);
  assert.equal(q.segment, "all");
  assert.equal(q.orderField, "lastActiveAt");
  assert.equal(q.range, null);
  assert.equal(q.filter, null);
});

test("segments map to one bounded range on the sort field", () => {
  const active = parseUserQuery({segment: "active"}, NOW);
  assert.deepEqual(active.range, {field: "lastActiveAt", op: ">=",
    value: new Date(NOW - 7 * DAY_MS)});
  const inactive = parseUserQuery({segment: "inactive"}, NOW);
  assert.equal(inactive.range.op, "<");
  const fresh = parseUserQuery({segment: "new"}, NOW);
  assert.equal(fresh.orderField, "createdAt");
  assert.equal(fresh.range.field, "createdAt");
});

test("only whitelisted filters with valid values survive", () => {
  assert.deepEqual(
      parseUserQuery({filter: {field: "hasWorkoutPlan", value: false}}, NOW)
          .filter, {field: "hasWorkoutPlan", value: false});
  assert.equal(
      parseUserQuery({filter: {field: "emailLower", value: "a"}}, NOW).filter,
      null);
  assert.equal(
      parseUserQuery({filter: {field: "status", value: "banned"}}, NOW).filter,
      null);
});

test("page size is clamped and cursors must be ids", () => {
  assert.equal(parseUserQuery({pageSize: 1000}, NOW).pageSize, MAX_PAGE_SIZE);
  assert.equal(parseUserQuery({cursor: "a/b"}, NOW).cursor, null);
  assert.equal(parseUserQuery({cursor: "abc_1"}, NOW).cursor, "abc_1");
});

test("the row never carries the searchable email or anything unlisted", () => {
  const row = toUserRow("u1", {
    displayName: "Ziad", emailMasked: "zi**@gmail.com",
    emailLower: "ziad@gmail.com", nameLower: "ziad",
    status: "active", workoutsCompleted: 3, aiTokensIn: 10, aiTokensOut: 5,
    createdAt: new Date(NOW), secret: "x",
  });
  assert.equal(row.emailLower, undefined);
  assert.equal(row.secret, undefined);
  assert.equal(row.emailMasked, "zi**@gmail.com");
  assert.equal(row.aiTokens, 15);
  assert.equal(row.createdAt, new Date(NOW).toISOString());
});

test("detail feature counts only pass well-formed keys", () => {
  const d = toUserDetail("u1", {usage: {"ai_chat": 4, "Bad Key": 1}});
  assert.deepEqual(d.features, {ai_chat: 4});
});

test("event props are whitelisted by type and size", () => {
  const e = toEvent("e1", {uid: "u", name: "ai_request", at: new Date(NOW),
    props: {tokensIn: 5, feature: "chat", nested: {a: 1},
      long: "x".repeat(100)}});
  assert.deepEqual(e.props, {tokensIn: 5, feature: "chat"});
});

test("local day starts follow the caller's offset", () => {
  // 12:00Z is 15:00 in Cairo (+180) — its day started at 21:00Z the day
  // before.
  assert.equal(localDayStart(NOW, 180).toISOString(),
      "2026-09-24T21:00:00.000Z");
  assert.equal(localDayStart(NOW, 0, 1).toISOString(),
      "2026-09-24T00:00:00.000Z");
  assert.equal(localDayStart(NOW, 99999).toISOString(),
      "2026-09-25T00:00:00.000Z");
});
