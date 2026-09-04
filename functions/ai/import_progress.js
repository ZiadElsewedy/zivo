/**
 * Turns a structured-output import's **partially streamed tool input** into
 * progress a person can read.
 *
 * The PDF importers are one long, opaque model call: they emit no assistant
 * text (`toolChoice: "any"` forces a tool call), so there is nothing to stream
 * except the tool's own input JSON as it is written. That JSON *is* the work —
 * days and exercises, meals and items, appearing one at a time — so scanning it
 * gives progress tied to real extraction rather than a timer.
 *
 * The snapshot is mid-write and therefore **not parseable**: the last object is
 * usually truncated. So this scans for COMPLETE `"key": "value"` pairs and
 * ignores everything still being written. That is the whole trick, and the
 * reason this is a scanner rather than `JSON.parse`.
 *
 * Deliberately not a JSON parser: it never has to be correct about structure,
 * only about "how many of these have appeared so far", and a wrong answer
 * costs a slightly-stale progress line, never a failed import. The real result
 * always comes from the final, complete tool input.
 */

/**
 * Every complete string value for `key` in `json`, in order of appearance.
 *
 * Handles escaped quotes (`\\"`) inside the value so a day labelled
 * `Push ("heavy")` doesn't truncate the match or desync the scan. A value
 * still being streamed has no closing quote yet and so is skipped — which is
 * exactly what we want: it appears on the next snapshot, once it is real.
 *
 * @param {string} json The cumulative partial JSON.
 * @param {string} key The object key to collect, e.g. `label`.
 * @return {!Array<string>}
 */
function completeStringValues(json, key) {
  if (typeof json !== "string" || json === "") return [];
  const pattern = new RegExp(
      `"${key}"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"`, "g");
  const out = [];
  let match;
  while ((match = pattern.exec(json)) !== null) {
    out.push(unescapeJsonString(match[1]));
  }
  return out;
}

/**
 * Resolves the JSON string escapes the scanner may have captured. Falls back
 * to the raw text if the fragment isn't valid on its own — progress copy is
 * never worth throwing for.
 * @param {string} raw
 * @return {string}
 */
function unescapeJsonString(raw) {
  try {
    return JSON.parse(`"${raw}"`);
  } catch (_) {
    return raw;
  }
}

/**
 * Progress for a **workout** import: the plan's name, the day labels extracted
 * so far, and how many exercises have landed in total.
 *
 * `label` is unique to a day and `name` unique to an exercise in
 * `WORKOUT_IMPORT_SCHEMA` (the plan's own name is `planName`), so neither
 * count can be inflated by the other key.
 *
 * @param {string} partialJson
 * @return {{planName: (string|undefined), days: !Array<string>,
 *   exercises: number}}
 */
function scanWorkoutProgress(partialJson) {
  const days = completeStringValues(partialJson, "label");
  const exercises = completeStringValues(partialJson, "name").length;
  const planNames = completeStringValues(partialJson, "planName");
  return {
    planName: planNames.length ? planNames[0] : undefined,
    days,
    exercises,
  };
}

/**
 * Progress for a **diet** import.
 *
 * The diet schema reuses `label` for BOTH a day and a meal
 * (`days[].label` and `days[].meals[].label`), so — unlike the workout scan —
 * the two cannot be told apart by key alone without tracking nesting, which is
 * exactly the structural correctness this scanner refuses to attempt. So it
 * reports them together as `labels`, in the order the model wrote them, and
 * leaves the caller to show the **latest** one. That still reads honestly:
 * the newest label is whatever section is being extracted right now
 * ("Breakfast", "Training day"), which is the useful thing to say.
 *
 * `name` belongs only to a food item here (the plan's own name is `planName`),
 * so `items` is exact.
 *
 * @param {string} partialJson
 * @return {{planName: (string|undefined), labels: !Array<string>,
 *   items: number}}
 */
function scanDietProgress(partialJson) {
  const planNames = completeStringValues(partialJson, "planName");
  return {
    planName: planNames.length ? planNames[0] : undefined,
    labels: completeStringValues(partialJson, "label"),
    items: completeStringValues(partialJson, "name").length,
  };
}

module.exports = {
  completeStringValues,
  scanWorkoutProgress,
  scanDietProgress,
};
