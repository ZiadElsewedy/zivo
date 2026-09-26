/**
 * Offline tests for `./live_text.js` — what a streaming turn puts on screen.
 * A tiny client mirror applies the events the way the app does (`delta`
 * appends, `replace` swaps the whole text) and every assertion reads what
 * the USER would see after each event.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {LiveText, restates} = require("./live_text");

const OPENING = "أيوه، بناءً على";

/**
 * @param {{replace: boolean}=} opts
 * @return {{live: !LiveText, screen: function(): string,
 *   frames: !Array<string>, events: !Array<!Object>}}
 */
function harness(opts = {replace: true}) {
  let text = "";
  const frames = [];
  const events = [];
  const live = new LiveText((e) => {
    events.push(e);
    if (e.type === "delta") text += e.text;
    if (e.type === "replace") text = e.text;
    frames.push(text);
  }, opts);
  return {live, screen: () => text, frames, events};
}

/**
 * @param {string} s
 * @param {string} needle
 * @return {number}
 */
function count(s, needle) {
  return s.split(needle).length - 1;
}

test("normal streaming appends token by token, shaped like the saved text",
    () => {
      const h = harness();
      h.live.beginStep();
      for (const t of ["  ", OPENING, " جدولك", "، اتمرن", " النهارده.  "]) {
        h.live.push(t);
      }
      h.live.endStep();
      assert.equal(h.screen(), `${OPENING} جدولك، اتمرن النهارده.`);
      assert.ok(h.events.every((e) => e.type === "delta"));
      // Every frame extends the one before it — nothing ever rewinds.
      for (let i = 1; i < h.frames.length; i++) {
        assert.ok(h.frames[i].startsWith(h.frames[i - 1]));
      }
    });

test("a later step opens its own paragraph", () => {
  const h = harness();
  h.live.beginStep();
  h.live.push("Let me check your plan.");
  h.live.endStep();
  h.live.beginStep();
  h.live.push("Pull is up next.");
  h.live.endStep();
  assert.equal(h.screen(), "Let me check your plan.\n\nPull is up next.");
  assert.equal(h.live.restatedPrevious, false);
});

test("REGRESSION: a provider retry after partial output never shows the " +
    "reply starting over", () => {
  const h = harness();
  h.live.beginStep();
  // 1. The stream opens…
  h.live.push(OPENING);
  // 2. …more chunks arrive…
  h.live.push(" جدولك وحالتك");
  // 3. …the first attempt fails and the router retries…
  h.live.retry();
  // 4. …and the second attempt starts from the beginning.
  for (const t of [OPENING, " جدولك وحالتك", "، اتمرن النهارده."]) {
    h.live.push(t);
  }
  h.live.endStep();
  // 5. At no moment did the screen hold the opening twice.
  for (const frame of h.frames) {
    assert.equal(count(frame, OPENING), 1, `duplicated: ${frame}`);
  }
  assert.equal(h.screen(), `${OPENING} جدولك وحالتك، اتمرن النهارده.`);
  // The retry reproduced the words already shown, so the screen never
  // rewound: it only ever grew.
  for (let i = 1; i < h.frames.length; i++) {
    assert.ok(h.frames[i].startsWith(h.frames[i - 1]));
  }
});

test("a retry that words it differently replaces the superseded text once",
    () => {
      const h = harness();
      h.live.beginStep();
      h.live.push(`${OPENING} جدولك`);
      h.live.retry();
      h.live.push(`${OPENING} اللي اتمرنته`);
      h.live.push(" امبارح، ريّح النهارده.");
      h.live.endStep();
      assert.equal(h.screen(), `${OPENING} اللي اتمرنته امبارح، ريّح النهارده.`);
      assert.equal(h.events.filter((e) => e.type === "replace").length, 1);
      for (const frame of h.frames) assert.equal(count(frame, OPENING), 1);
    });

test("a retry that writes less than was shown trims the screen to it", () => {
  const h = harness();
  h.live.beginStep();
  h.live.push("Yes — train today. You slept well and");
  h.live.retry();
  h.live.push("Yes — train today.");
  h.live.endStep();
  assert.equal(h.screen(), "Yes — train today.");
});

test("a retry keeps the earlier steps' text", () => {
  const h = harness();
  h.live.beginStep();
  h.live.push("Let me check your schedule.");
  h.live.endStep();
  h.live.beginStep();
  h.live.push("Pull is up");
  h.live.retry();
  h.live.push("Pull is up next — go.");
  h.live.endStep();
  assert.equal(h.screen(), "Let me check your schedule.\n\nPull is up next — go.");
});

test("REGRESSION: a step that restates the previous lead-in replaces it " +
    "instead of writing it twice", () => {
  const h = harness();
  h.live.beginStep();
  h.live.push(`${OPENING} جدولك،`);
  h.live.endStep();
  h.live.beginStep();
  h.live.push(`${OPENING} جدولك، `);
  h.live.push("اتمرن Pull النهارده.");
  h.live.endStep();
  assert.equal(h.live.restatedPrevious, true);
  assert.equal(h.screen(), `${OPENING} جدولك، اتمرن Pull النهارده.`);
  for (const frame of h.frames) assert.equal(count(frame, OPENING), 1);
});

test("a step that merely starts similarly is a new paragraph", () => {
  const h = harness();
  h.live.beginStep();
  h.live.push("Let me check your plan.");
  h.live.endStep();
  h.live.beginStep();
  h.live.push("Let me be");
  h.live.push(" honest: rest today.");
  h.live.endStep();
  assert.equal(h.live.restatedPrevious, false);
  assert.equal(h.screen(),
      "Let me check your plan.\n\nLet me be honest: rest today.");
});

test("an old client (no replace support) gets plain appends, as before", () => {
  const h = harness({replace: false});
  h.live.beginStep();
  h.live.push("Hi ");
  h.live.retry();
  h.live.push("Hi there");
  h.live.endStep();
  assert.ok(h.events.every((e) => e.type === "delta"));
});

test("restates: the rule the buffered path shares", () => {
  assert.equal(restates("Let me check your plan.", "Let me check your plan. " +
    "Pull is next."), true);
  assert.equal(restates("حاضر.", "حاضر. هشوف"), true);
  assert.equal(restates("Let me check your plan.", "Pull is next."), false);
  assert.equal(restates(undefined, "x"), false);
});
