/**
 * The triggers that keep `users/{uid}/dietDays/{dayKey}` in step with the
 * three sources it is derived from (`day_record.js`):
 *
 *   foodLogs / dietEntries written → rebuild that day (and the old day too,
 *     if an edit moved a doc between days)
 *   dietPlans written → rebuild TODAY only, so today's snapshot follows the
 *     plan as it's edited while every past day stays frozen
 *
 * One writer for the record, whoever changed the sources — the app, Ask, an
 * older build, the backfill — so there is never a second implementation to
 * keep in agreement. Failures are logged, never thrown: a missed rebuild is
 * repaired by the next write to that day, and must not retry-storm.
 */

const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const {Timestamp} = require("firebase-admin/firestore");
const {dayKeyFor} = require("../ai/shared/dates");

const REGION = "us-central1";

/**
 * The days a write to a `foodLogs`/`dietEntries` doc touched, each with the
 * doc's `date` (the app's device-local midnight, which reveals the user's
 * offset). Pure.
 * @param {?Object} before The doc before the write, or null.
 * @param {?Object} after The doc after, or null.
 * @return {!Array<{dayKey: string, localMidnight: ?Date}>}
 */
function daysTouched(before, after) {
  const out = [];
  for (const d of [after, before]) {
    if (!d || typeof d.dayKey !== "string" ||
        !/^\d{4}-\d{2}-\d{2}$/.test(d.dayKey)) {
      continue;
    }
    if (out.some((o) => o.dayKey === d.dayKey)) continue;
    out.push({
      dayKey: d.dayKey,
      localMidnight: d.date instanceof Timestamp ? d.date.toDate() : null,
    });
  }
  return out;
}

/**
 * @param {{store: !Object, now: (function(): !Date|undefined)}} deps
 * @return {!Object<string, !Function>} The exports to deploy.
 */
function buildDietDayTriggers({store, now = () => new Date()}) {
  const data = (snap) => (snap && snap.exists ? snap.data() : null);

  const rebuildTouched = (label) => async (event) => {
    const uid = event.params.uid;
    for (const {dayKey, localMidnight} of daysTouched(
        data(event.data.before), data(event.data.after))) {
      try {
        const outcome = await store.rebuildDietDay(
            uid, dayKey, {now: now(), localMidnight});
        logger.debug(label, {dayKey, outcome});
      } catch (err) {
        logger.warn(`${label}: rebuild skipped`,
            {dayKey, errorMessage: err && err.message});
      }
    }
  };

  return {
    dietDayOnFoodLog: onDocumentWritten(
        {document: "users/{uid}/foodLogs/{entryId}", region: REGION},
        rebuildTouched("dietDayOnFoodLog")),

    dietDayOnDietEntry: onDocumentWritten(
        {document: "users/{uid}/dietEntries/{entryId}", region: REGION},
        rebuildTouched("dietDayOnDietEntry")),

    dietDayOnPlan: onDocumentWritten(
        {document: "users/{uid}/dietPlans/{planId}", region: REGION},
        async (event) => {
          const uid = event.params.uid;
          try {
            // "Today" in the user's own timezone, learned from their most
            // recent record; a user with no record has no day to refresh.
            const offset = await store.latestDietDayOffset(uid);
            if (offset === undefined) return;
            const dayKey = dayKeyFor(now(), offset === null ? 0 : offset);
            await store.rebuildDietDay(
                uid, dayKey, {now: now(), localMidnight: null});
          } catch (err) {
            logger.warn("dietDayOnPlan: rebuild skipped",
                {errorMessage: err && err.message});
          }
        }),
  };
}

module.exports = {buildDietDayTriggers, daysTouched};
