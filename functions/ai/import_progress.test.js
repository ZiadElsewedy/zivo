const test = require("node:test");
const assert = require("node:assert");

const {
  completeStringValues,
  scanWorkoutProgress,
  scanDietProgress,
} = require("./import_progress");

test("a value still being streamed is not counted until it closes", () => {
  const partial = "{\"planName\": \"PPL\", \"days\": [{\"slot\": \"A\", \"label\": \"Pu";
  // "Pu… has no closing quote yet — counting it would flash a half-written
  // day label ("Pu") on screen, which is the exact failure this guards.
  assert.deepEqual(scanWorkoutProgress(partial).days, []);
  assert.equal(scanWorkoutProgress(partial).planName, "PPL");
});

test("workout progress counts days and exercises independently", () => {
  const partial = "{\"planName\": \"Push Pull Legs\", \"days\": [" +
    "{\"slot\": \"A\", \"label\": \"Push\", \"exercises\": [" +
    "{\"name\": \"Bench Press\", \"sets\": 4}, {\"name\": \"Fly\", \"sets\": 3}]}, " +
    "{\"slot\": \"B\", \"label\": \"Pull\", \"exercises\": [{\"name\": \"Row\"";
  const p = scanWorkoutProgress(partial);
  assert.equal(p.planName, "Push Pull Legs");
  assert.deepEqual(p.days, ["Push", "Pull"]);
  assert.equal(p.exercises, 3);
});

test("planName never inflates the exercise count", () => {
  // `planName` and `name` are distinct keys; a substring match would count the
  // plan itself as an exercise and start every import at 1.
  const partial = "{\"planName\": \"Legs\", \"days\": []}";
  assert.equal(scanWorkoutProgress(partial).exercises, 0);
});

test("an escaped quote inside a label neither truncates nor desyncs", () => {
  const partial = "{\"days\": [{\"label\": \"Push (\\\"heavy\\\")\", " +
    "\"exercises\": [{\"name\": \"Bench\"}]}]}";
  const p = scanWorkoutProgress(partial);
  assert.deepEqual(p.days, ["Push (\"heavy\")"]);
  assert.equal(p.exercises, 1);
});

test("progress only ever grows as more of the stream arrives", () => {
  const full = "{\"planName\": \"PPL\", \"days\": [" +
    "{\"slot\": \"A\", \"label\": \"Push\", \"exercises\": [{\"name\": \"Bench\"}]}, " +
    "{\"slot\": \"B\", \"label\": \"Pull\", \"exercises\": [{\"name\": \"Row\"}]}]}";
  let lastDays = 0;
  let lastExercises = 0;
  for (let i = 1; i <= full.length; i++) {
    const p = scanWorkoutProgress(full.slice(0, i));
    assert.ok(p.days.length >= lastDays, `days went backwards at ${i}`);
    assert.ok(p.exercises >= lastExercises, `exercises went backwards at ${i}`);
    lastDays = p.days.length;
    lastExercises = p.exercises;
  }
  const done = scanWorkoutProgress(full);
  assert.deepEqual(done.days, ["Push", "Pull"]);
  assert.equal(done.exercises, 2);
});

test("diet progress reports day and meal labels together, newest last", () => {
  // The diet schema uses `label` for both days and meals, so they share one
  // ordered list by design — the caller shows the latest.
  const partial = "{\"planName\": \"Cut\", \"days\": [{\"weekday\": null, " +
    "\"label\": \"Every day\", \"meals\": [" +
    "{\"label\": \"Breakfast\", \"items\": [{\"name\": \"Oats\"}, {\"name\": \"Eggs\"}]}, " +
    "{\"label\": \"Lunch\", \"items\": [{\"name\": \"Ric";
  const p = scanDietProgress(partial);
  assert.equal(p.planName, "Cut");
  assert.deepEqual(p.labels, ["Every day", "Breakfast", "Lunch"]);
  assert.equal(p.items, 2, "the unterminated \"Ric is not counted yet");
});

test("empty, absent and non-string input scan to nothing rather than throwing", () => {
  for (const input of ["", undefined, null, 42, {}]) {
    assert.deepEqual(completeStringValues(input, "label"), []);
  }
  assert.deepEqual(scanWorkoutProgress("").days, []);
  assert.equal(scanWorkoutProgress(undefined).exercises, 0);
  assert.deepEqual(scanDietProgress("").labels, []);
});

test("a malformed escape falls back to the raw text instead of throwing", () => {
  const partial = "{\"days\": [{\"label\": \"Bad \\\\u00 escape\"}]}";
  assert.doesNotThrow(() => scanWorkoutProgress(partial));
});
