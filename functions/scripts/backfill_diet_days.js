#!/usr/bin/env node
/**
 * One-time backfill of `users/{uid}/dietDays/{dayKey}` — the daily diet record
 * (`diet/day_record.js`) — for every day that already has a meal tick or a
 * food log. Days written after the triggers deploy build themselves; this
 * covers the history before that.
 *
 *   node scripts/backfill_diet_days.js            # dry run: lists the days
 *   node scripts/backfill_diet_days.js --apply    # writes the records
 *   node scripts/backfill_diet_days.js --apply --uid <uid>
 *
 * It goes through the SAME `rebuildDietDay` the triggers use, so a backfilled
 * record is indistinguishable from a live one — except that a past day's plan
 * can only be read from the plan in force today, which the record says with
 * `plannedReconstructed: true`. Re-running is safe: an unchanged record is not
 * rewritten. Additive only — it never touches `dietPlans`, `dietEntries` or
 * `foodLogs`.
 *
 * Needs Application Default Credentials for project zivo-63f15
 * (`gcloud auth application-default login`). An owner action.
 */

const {initializeApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {FirestoreStore} = require("../ai/shared/store");

const main = async () => {
  const args = process.argv.slice(2);
  const apply = args.includes("--apply");
  const uidArg = args.includes("--uid") ? args[args.indexOf("--uid") + 1] : null;
  initializeApp({projectId: process.env.GCLOUD_PROJECT || "zivo-63f15"});
  const db = getFirestore();
  const store = new FirestoreStore(db);
  const now = new Date();

  const uids = uidArg ? [uidArg] :
    (await db.collection("users").listDocuments()).map((d) => d.id);
  const totals = {users: 0, days: 0, written: 0, unchanged: 0, none: 0};
  for (const uid of uids) {
    const user = db.collection("users").doc(uid);
    const [logs, entries] = await Promise.all([
      user.collection("foodLogs").select("dayKey", "date").get(),
      user.collection("dietEntries").select("dayKey", "date").get(),
    ]);
    // Each day once, with a doc the app wrote for it when there is one — its
    // `date` is the device's local midnight, which gives the user's offset.
    const days = new Map();
    for (const doc of [...entries.docs, ...logs.docs]) {
      const {dayKey, date} = doc.data();
      if (typeof dayKey !== "string") continue;
      const midnight = date instanceof Timestamp ? date.toDate() : null;
      if (!days.has(dayKey) || (midnight &&
          midnight.getUTCHours() + midnight.getUTCMinutes() !== 0)) {
        days.set(dayKey, midnight);
      }
    }
    if (days.size === 0) continue;
    totals.users++;
    for (const [dayKey, localMidnight] of [...days].sort()) {
      totals.days++;
      if (!apply) {
        console.log(`${uid.slice(0, 6)}… ${dayKey}`);
        continue;
      }
      const outcome =
        await store.rebuildDietDay(uid, dayKey, {now, localMidnight});
      totals[outcome] = (totals[outcome] || 0) + 1;
      console.log(`${uid.slice(0, 6)}… ${dayKey} ${outcome}`);
    }
  }
  console.log(apply ? "Applied:" : "Dry run (pass --apply to write):", totals);
};

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
