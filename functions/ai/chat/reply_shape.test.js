/**
 * Offline tests for `./reply_shape.js` — the per-message length decision —
 * and its place in the system blocks (`./context.js`).
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {
  ReplyShape, replyShapeFor, replyShapeDirective,
} = require("./reply_shape");
const {buildSystemBlocks} = require("./context");
const {SYSTEM_PROMPT} = require("./prompt/system_prompt");

const FACTS = {weekday: "Saturday", longDate: "September 26, 2026",
  dayKey: "2026-09-26", time: "09:00", zone: "UTC+03:00",
  usedClientClock: true};

test("a request for a call is a DECISION — English, Egyptian Arabic, Arabizi",
    () => {
      for (const m of [
        "Should I go to the gym today?",
        "can I eat pizza tonight?",
        "is it ok to skip leg day?",
        "أروح الجيم النهارده؟",
        "ينفع آكل بيتزا؟",
        "أمشي على الدايت النهارده ولا لأ؟",
        "اتمرن ولا اريح؟",
        "aroo7 el gym enharda?",
      ]) {
        assert.equal(replyShapeFor(m), ReplyShape.DECISION, m);
      }
    });

test("an explicit ask for depth is DETAIL", () => {
  for (const m of ["explain my progress", "why is my bench stuck?",
    "break down my week", "اشرحلي الدايت بالتفصيل", "وليه كده؟"]) {
    assert.equal(replyShapeFor(m), ReplyShape.DETAIL, m);
  }
});

test("both at once, and the everyday default", () => {
  assert.equal(replyShapeFor("should I train today? explain why"),
      ReplyShape.DECISION_DETAIL);
  for (const m of ["hi", "how much protein is left?", "اتمرنت النهارده",
    "عليه كام سعرة؟", "how can I improve my squat?", ""]) {
    assert.equal(replyShapeFor(m), ReplyShape.DEFAULT, m);
  }
});

test("the default shape adds no block; a decision or detail adds one " +
    "uncached block after the cached prompt and before CONTEXT", () => {
  assert.equal(
      buildSystemBlocks({facts: FACTS, replyShape: ReplyShape.DEFAULT}).length,
      2);
  for (const shape of [ReplyShape.DECISION, ReplyShape.DETAIL,
    ReplyShape.DECISION_DETAIL]) {
    const blocks = buildSystemBlocks({facts: FACTS, replyShape: shape,
      responseStyle: "concise"});
    assert.equal(blocks.length, 4);
    assert.equal(blocks[0].text, SYSTEM_PROMPT);
    assert.equal(blocks[0].cache, "ephemeral");
    assert.match(blocks[1].text, /short/i); // the saved preference first
    assert.equal(blocks[2].text, replyShapeDirective(shape));
    assert.equal(blocks[2].cache, undefined);
    assert.match(blocks[3].text, /^CONTEXT /);
  }
});

test("the decision directive puts the verdict first and forbids deciding " +
    "without the data", () => {
  const d = replyShapeDirective(ReplyShape.DECISION);
  assert.match(d, /Line 1 is the decision/);
  assert.match(d, /can't make the call and what's missing/);
});
