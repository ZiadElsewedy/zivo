/**
 * ZIVO — shared per-user daily quota core.
 *
 * The pure decision logic behind every *paid* endpoint's abuse ceiling. Kept
 * free of any `firebase-admin` import so it stays unit-testable under plain
 * `node --test` (mirroring ../auth/otp.js) — the callables in ../index.js wrap
 * a Firestore transaction around `decideConsume` and translate the returned
 * decision into an `HttpsError`.
 *
 * WHY THIS EXISTS. `aiChat` already had a ceiling (gateway.js's
 * `perDayMaxTurns`/`perDayTokenCeiling`, derived from the `aiUsage` log). The
 * other model-backed callables — plan imports, diet generation, transcription
 * — had only a *size* cap on their input and no cap at all on how often they
 * could be called. A single signed-in account could loop 14 MB whole-PDF
 * extractions at 180s apiece, and the only thing bounding the bill was the
 * attacker's patience. This module is that bound.
 *
 * Design notes:
 *   • One counter document per (user, bucket), holding a rolling calendar-day
 *     window. Reads and writes are O(1) — unlike deriving a total by scanning
 *     a usage collection, which costs a read per prior call and gets more
 *     expensive exactly as an abuser makes it more necessary.
 *   • The window is keyed by a `dayKey` STRING, not a timestamp, so it rolls
 *     over at the *user's* midnight (the caller passes the key it already
 *     computes from the device offset — see ../ai/dates.js) rather than UTC's.
 *   • `cost` is caller-supplied so one bucket can price calls differently
 *     (a 14 MB PDF is not one transcription) without this module knowing
 *     anything about what it is metering.
 *   • Counters are advisory, not billing: they are reset by a new day and are
 *     not reconciled against the provider's actual spend. They exist to turn
 *     an unbounded loop into a bounded one, which is the whole job.
 *
 * All timestamps are epoch-millisecond NUMBERS, like ../auth/otp.js, so the
 * module stays dependency-free and trivially testable.
 */

/** Sensible default; ../index.js passes explicit per-bucket limits. */
const DEFAULT_LIMIT = 20;

/**
 * Decides whether one call may proceed against a per-user, per-day bucket.
 *
 * Purely, from the existing counter document and the caller's day key. The
 * returned `next` is the document to persist ONLY when `allowed` is true — a
 * refused call must not advance the counter, or a client hammering a blocked
 * endpoint would push its own reset further away with every rejected attempt.
 *
 * @param {{existing: ?Object, dayKey: string, nowMs: number,
 *   limit: (number|undefined), cost: (number|undefined)}} args
 * @return {{allowed: boolean, used: number, limit: number,
 *   remaining: number, next: (!Object|undefined)}}
 */
const decideConsume = ({
  existing, dayKey, nowMs, limit = DEFAULT_LIMIT, cost = 1,
}) => {
  // A counter from an earlier day is not "used up" — it's irrelevant. Treat a
  // mismatched (or missing) dayKey as a fresh window rather than clearing the
  // document, so the rollover needs no scheduled cleanup job.
  const sameDay = !!existing && existing.dayKey === dayKey;
  const used = sameDay && typeof existing.used === "number" ?
    existing.used : 0;

  if (used + cost > limit) {
    return {allowed: false, used, limit, remaining: Math.max(0, limit - used)};
  }

  const nextUsed = used + cost;
  return {
    allowed: true,
    used: nextUsed,
    limit,
    remaining: limit - nextUsed,
    next: {
      dayKey,
      used: nextUsed,
      // Purely diagnostic — answers "when did this account last spend here?"
      // without needing the (deliberately absent) per-call log.
      lastCallAt: nowMs,
      updatedAt: nowMs,
    },
  };
};

module.exports = {
  DEFAULT_LIMIT,
  decideConsume,
};
