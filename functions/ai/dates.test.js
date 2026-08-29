/**
 * Offline tests for `./dates.js` — the timezone half of the AI gateway's
 * "what day is it" problem.
 *
 * The bug these exist to prevent: Cloud Functions run in UTC, but the app
 * writes `dietEntries.dayKey` from the DEVICE's calendar date. Without the
 * client's offset the server resolved a different "today" from the one on
 * screen for every user east or west of UTC — a UTC+3 user asking the coach
 * anything between local midnight and 03:00 got yesterday's diet entries and
 * yesterday's weekday plan slot, silently.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {
  dayKeyFor,
  isoWeekday,
  dayRangeMs,
  weekRangeMs,
  monthRangeMs,
  resolveDietDay,
  localNowFacts,
  isUsableOffset,
} = require("./dates");

// 00:30 on Sunday 30 August 2026 for a UTC+3 user — 21:30 the PREVIOUS day
// in UTC. Every assertion below turns on that gap.
const JUST_AFTER_LOCAL_MIDNIGHT = new Date("2026-08-29T21:30:00Z");
const CAIRO = 180;

test("dayKeyFor resolves the user's calendar day, not the server's", () => {
  assert.equal(dayKeyFor(JUST_AFTER_LOCAL_MIDNIGHT, CAIRO), "2026-08-30");
  // Same instant, a user four hours behind UTC: still the 29th for them.
  assert.equal(dayKeyFor(JUST_AFTER_LOCAL_MIDNIGHT, -240), "2026-08-29");
});

test("isoWeekday follows the user's day too (1=Mon..7=Sun)", () => {
  // 21:30Z on Saturday the 29th is already Sunday for a UTC+3 user.
  assert.equal(isoWeekday(JUST_AFTER_LOCAL_MIDNIGHT, CAIRO), 7);
  assert.equal(isoWeekday(JUST_AFTER_LOCAL_MIDNIGHT, -240), 6);
});

test("resolveDietDay picks the weekday slot the USER is living in", () => {
  const days = [
    {weekday: 6, label: "Saturday", meals: []},
    {weekday: 7, label: "Sunday", meals: []},
  ];
  assert.equal(
      resolveDietDay(days, JUST_AFTER_LOCAL_MIDNIGHT, CAIRO).label, "Sunday");
  assert.equal(
      resolveDietDay(days, JUST_AFTER_LOCAL_MIDNIGHT, -240).label, "Saturday");
});

test("day/week/month ranges start at the user's local midnight", () => {
  const day = dayRangeMs(JUST_AFTER_LOCAL_MIDNIGHT, CAIRO);
  assert.equal(new Date(day.fromMs).toISOString(), "2026-08-29T21:00:00.000Z");
  assert.equal(new Date(day.toMs).toISOString(), "2026-08-30T21:00:00.000Z");

  // Local Sunday 30 Aug → the week that began local Monday 24 Aug.
  const week = weekRangeMs(JUST_AFTER_LOCAL_MIDNIGHT, CAIRO);
  assert.equal(new Date(week.fromMs).toISOString(), "2026-08-23T21:00:00.000Z");
  assert.equal(new Date(week.toMs).toISOString(), "2026-08-30T21:00:00.000Z");

  const month = monthRangeMs(JUST_AFTER_LOCAL_MIDNIGHT, CAIRO);
  assert.equal(
      new Date(month.fromMs).toISOString(), "2026-07-31T21:00:00.000Z");
  assert.equal(new Date(month.toMs).toISOString(), "2026-08-31T21:00:00.000Z");
});

test("a whole day is exactly 24h of range, and ranges abut without gaps",
    () => {
      const day = dayRangeMs(JUST_AFTER_LOCAL_MIDNIGHT, CAIRO);
      assert.equal(day.toMs - day.fromMs, 24 * 60 * 60 * 1000);
      const week = weekRangeMs(JUST_AFTER_LOCAL_MIDNIGHT, CAIRO);
      assert.equal(week.toMs - week.fromMs, 7 * 24 * 60 * 60 * 1000);
      // The day the user is in sits inside the week they are in.
      assert.ok(day.fromMs >= week.fromMs && day.toMs <= week.toMs);
    });

test("an implausible or missing offset falls back to server-local", () => {
  // Never trust client input: a bad offset must degrade, not corrupt dates.
  for (const bad of [undefined, null, "180", NaN, 1e9, 15 * 60, -13 * 60, 1.5]) {
    assert.equal(isUsableOffset(bad), false, `${bad} should be rejected`);
    assert.equal(
        dayKeyFor(JUST_AFTER_LOCAL_MIDNIGHT, bad),
        dayKeyFor(JUST_AFTER_LOCAL_MIDNIGHT),
    );
  }
  // The real-world extremes are accepted.
  assert.equal(isUsableOffset(14 * 60), true);
  assert.equal(isUsableOffset(-12 * 60), true);
  assert.equal(isUsableOffset(0), true);
});

test("localNowFacts states the date the coach should quote", () => {
  const facts = localNowFacts(JUST_AFTER_LOCAL_MIDNIGHT, CAIRO, "EEST");
  assert.equal(facts.dayKey, "2026-08-30");
  assert.equal(facts.weekday, "Sunday");
  assert.equal(facts.longDate, "30 August 2026");
  assert.equal(facts.time, "00:30");
  assert.equal(facts.zone, "EEST (UTC+03:00)");
  assert.equal(facts.usedClientClock, true);
});

test("localNowFacts admits when it had no client clock", () => {
  // The gateway turns this into an explicit hedge in the prompt rather than
  // quietly presenting the server's day as the user's.
  const facts = localNowFacts(JUST_AFTER_LOCAL_MIDNIGHT, undefined, undefined);
  assert.equal(facts.usedClientClock, false);
  assert.equal(facts.zone, "UTC+00:00");
});

test("a half-hour offset zone resolves correctly", () => {
  // India is UTC+5:30 — offsets are not all whole hours.
  const t = new Date("2026-08-29T18:45:00Z"); // 00:15 on the 30th in Kolkata
  assert.equal(dayKeyFor(t, 330), "2026-08-30");
  assert.equal(localNowFacts(t, 330).time, "00:15");
  assert.equal(localNowFacts(t, 330).zone, "UTC+05:30");
});
