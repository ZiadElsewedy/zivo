/**
 * Offline tests for `./training_calendar.js` — calendar adherence derived
 * from sessions, kept apart from workout progression.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {trainingCalendar, qualifiesAsTrainingDay} =
  require("./training_calendar");

test("a day without a session is inactive — nothing is invented for it",
    () => {
      // Sep 21 Push, Sep 22 nothing, Sep 23 Pull, Sep 24 Legs (today).
      const c = trainingCalendar({
        sessionsByDay: {"2026-09-21": 1, "2026-09-23": 1, "2026-09-24": 1},
        from: "2026-08-28",
        today: "2026-09-24",
      });
      assert.equal(c.from, "2026-09-21", "clamped to when history began");
      assert.equal(c.activeDays, 3);
      assert.equal(c.inactiveDays, 1);
      assert.deepEqual(c.inactiveDates, ["2026-09-22"]);
      assert.equal(c.trainingSessions, 3, "one per real session, no filler");
      assert.equal(c.trainedToday, true);
      assert.equal(c.daysSinceLastTraining, 0);
    });

test("today is not inactive until it is over", () => {
  const c = trainingCalendar({
    sessionsByDay: {"2026-09-21": 1},
    from: "2026-09-01",
    today: "2026-09-23",
  });
  assert.deepEqual(c.inactiveDates, ["2026-09-22"]);
  assert.equal(c.daysJudged, 2);
  assert.equal(c.trainedToday, false);
  assert.equal(c.daysSinceLastTraining, 2);
});

test("two sessions on one day are one active day and two sessions", () => {
  const c = trainingCalendar({
    sessionsByDay: {"2026-09-21": 2},
    from: "2026-09-21",
    today: "2026-09-21",
  });
  assert.equal(c.activeDays, 1);
  assert.equal(c.trainingSessions, 2);
  assert.equal(c.trainingDaysPerWeek, 7);
});

test("no training history yields no calendar", () => {
  assert.equal(trainingCalendar({sessionsByDay: {}, from: "2026-09-01",
    today: "2026-09-10"}), null);
});

test("a session counts only with a completed working set " +
    "(mirrors qualifiesForStreak)", () => {
  const set = (outcome, type = "working") => ({outcome, type});
  const s = (status, sets) => ({status, exercises: [{sets}]});
  assert.equal(qualifiesAsTrainingDay(s("completed", [set("completed")])),
      true);
  assert.equal(qualifiesAsTrainingDay(s("active", [set("completed")])), true);
  assert.equal(qualifiesAsTrainingDay(
      s("completed", [set("completed", "warmup")])), false);
  assert.equal(qualifiesAsTrainingDay(s("abandoned", [set("completed")])),
      false);
  assert.equal(qualifiesAsTrainingDay(s("voided", [set("completed")])), false);
});
