const assert = require("node:assert/strict");
const {test} = require("node:test");

const {
  upNextDay,
  rotationFrom,
  swapDayOrders,
  applyRotationChange,
} = require("./workout_rotation");

/** @return {!Array<!Object>} Push → Pull → Legs, Pull listed first. */
function days() {
  return [
    {id: "pull", label: "Pull", order: 1, exercises: [{name: "Row"}]},
    {id: "push", label: "Push", order: 0, exercises: [{name: "Bench"}]},
    {id: "legs", label: "Legs", order: 2, exercises: [{name: "Squat"}]},
  ];
}

const names = (list) => list.map((d) => d.label);

test("up next is the cursor's day; the rotation reads from it", () => {
  assert.equal(upNextDay(days(), 0).id, "push");
  assert.deepEqual(names(rotationFrom(days(), 1)), ["Pull", "Legs", "Push"]);
  // A stale cursor never reads as "nothing up next".
  assert.equal(upNextDay(days(), 9).id, "push");
});

test("SWAP: the two trade places, the cursor stays — Pull today, Push next, " +
    "nothing missed; exercises untouched", () => {
  const next = applyRotationChange({days: days(), cycleCursor: 0},
      {mode: "swap", dueDayId: "push", targetDayId: "pull"});
  assert.deepEqual(names(rotationFrom(next.days, next.cycleCursor)),
      ["Pull", "Push", "Legs"]);
  assert.deepEqual(next.days.map((d) => d.order), [0, 1, 2]);
  assert.deepEqual(next.days.find((d) => d.id === "push").exercises,
      [{name: "Bench"}]);
});

test("SKIP: the cursor moves onto the chosen day — Push drops out of this " +
    "round and the rotation continues after Pull", () => {
  const next = applyRotationChange({days: days(), cycleCursor: 0},
      {mode: "skip", dueDayId: "push", targetDayId: "pull"});
  assert.equal(upNextDay(next.days, next.cycleCursor).id, "pull");
  assert.deepEqual(names(rotationFrom(next.days, next.cycleCursor)),
      ["Pull", "Legs", "Push"]);
});

test("a change is refused when the day that was due has moved on", () => {
  assert.throws(() => applyRotationChange({days: days(), cycleCursor: 1},
      {mode: "swap", dueDayId: "push", targetDayId: "legs"}),
  /changed since/);
  assert.throws(() => applyRotationChange({days: days(), cycleCursor: 0},
      {mode: "skip", dueDayId: "push", targetDayId: "gone"}),
  /isn't in your split/);
  assert.equal(swapDayOrders(days(), "push", "push").length, 3);
});
