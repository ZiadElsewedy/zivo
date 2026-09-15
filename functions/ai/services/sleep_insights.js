/**
 * The sleep AI layer: interpretation, and nothing else.
 *
 * ZIVO computes every sleep figure deterministically on the client
 * (`lib/features/sleep/domain/sleep_metrics.dart`) and this module receives
 * only the finished numbers. The model's job is to say them better — never to
 * say more of them, and never to compute one (docs/SLEEP_SYSTEM.md §15).
 *
 * The control that makes that safe is `groundedNumerals`: after generation,
 * every numeral in the output is checked against the fact sheet it came from.
 * A model cannot claim "you slept 34 minutes more than last week" past a
 * filter holding the real delta, however fluent the claim. Same posture as
 * ADR-003's confirm-gated writes — the model proposes, deterministic code
 * decides.
 *
 * Pure and injectable like the rest of `./ai/`: no SDK imports, so it runs
 * offline under `node --test`.
 */

/** Insight kinds the client can render. Mirrors `SleepInsightKind` in Dart. */
const KINDS = [
  "duration",
  "weekOverWeek",
  "consistency",
  "targetAdherence",
  "trend",
  "insufficientData",
];

/**
 * Every numeral the model is allowed to use, as strings.
 *
 * Includes each fact's value in the forms a sentence might legitimately
 * render it: the raw minutes, and the hours/minutes split, because "412
 * minutes" is properly written "6h 52m" and both halves have to be allowed
 * or the gate rejects correct prose.
 * @param {!Object} sheet
 * @return {!Set<string>}
 */
function allowedNumerals(sheet) {
  const allowed = new Set();
  const add = (n) => allowed.add(String(Math.abs(Math.round(n))));

  add(sheet.windowNights ?? 0);
  add(sheet.nightsWithData ?? 0);

  for (const fact of sheet.facts ?? []) {
    const value = Math.abs(Math.round(fact.value));
    add(value);
    add(fact.nights ?? 0);
    if (fact.unit === "minutes" || fact.unit === "minutesPerNight") {
      add(Math.floor(value / 60));
      add(value % 60);
    }
  }
  return allowed;
}

/**
 * **The numeral gate.** Whether every number in `text` came from `sheet`.
 *
 * Deliberately dumb: pull out every digit run and check each against the
 * allow-list. Words-as-numbers ("three nights") are outside its reach by
 * construction — an accepted limit, because the failure mode being defended
 * against is a fabricated *figure*, and figures are written as digits.
 *
 * Mirrored on the client in `sleep_insight.dart`. Having it twice is
 * deliberate: this is the boundary, that one is the last thing between an
 * ungrounded number and a user's eyes, and a check this cheap is worth having
 * at both.
 * @param {string} text
 * @param {!Object} sheet
 * @return {boolean}
 */
function groundedNumerals(text, sheet) {
  const allowed = allowedNumerals(sheet);
  for (const match of String(text).matchAll(/\d+/g)) {
    const numeral = match[0];
    // A leading zero is a clock-time artefact ("07" in 07:15); compare on the
    // numeric value so `07` matches an allowed `7`.
    const normalized = String(parseInt(numeral, 10));
    if (!allowed.has(normalized) && !allowed.has(numeral)) return false;
  }
  return true;
}

/**
 * The system prompt. Every rule here exists because its absence produces a
 * specific, observed failure: invented figures, causal claims from
 * co-occurrence, and hedged versions of "not enough data" that read as
 * findings.
 * @return {string}
 */
function systemPrompt() {
  return [
    "You interpret sleep data for ZIVO, a training app. You do not compute.",
    "",
    "RULES — each is absolute:",
    "1. Every number you write must appear verbatim in the input facts.",
    "   You may re-express minutes as hours and minutes; you may not derive,",
    "   sum, average, or estimate anything.",
    "2. Metrics listed under `insufficient` MUST NOT be discussed, hinted at,",
    "   or hedged around. If asked to comment on one, say there are not",
    "   enough nights yet — plainly, as a fact, not as an apology.",
    "3. Never claim a cause. Two things moving together is not one causing",
    "   the other, and you cannot see anything else in this person's life.",
    "4. No medical claims, no diagnosis, no sleep-disorder speculation.",
    "5. Two or three short sentences. Plain, specific, second person.",
    "",
    "Return JSON only: {\"insights\":[{\"kind\":..,\"text\":..,\"basedOn\":[..]}]}",
    `Valid kinds: ${KINDS.join(", ")}.`,
    "`basedOn` lists the fact ids a sentence rests on. An insight with an",
    "empty `basedOn` will be discarded, so cite what you used.",
  ].join("\n");
}

/**
 * Parses and validates a model response.
 *
 * Anything unattributable or ungrounded is dropped rather than repaired: a
 * sentence we cannot trace is exactly what this pipeline exists to refuse, and
 * silently rewriting one would hide that it happened.
 * @param {string} raw
 * @param {!Object} sheet
 * @return {{insights: !Array<!Object>, rejected: number}}
 */
function validateResponse(raw, sheet) {
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (_) {
    return {insights: [], rejected: 0};
  }

  const candidates = Array.isArray(parsed?.insights) ? parsed.insights : [];
  const insights = [];
  let rejected = 0;

  for (const candidate of candidates) {
    const text = typeof candidate?.text === "string" ? candidate.text : "";
    const kind = KINDS.includes(candidate?.kind) ? candidate.kind : null;
    const basedOn = Array.isArray(candidate?.basedOn) ?
      candidate.basedOn.filter((id) => typeof id === "string") :
      [];

    if (!text || !kind || basedOn.length === 0) {
      rejected++;
      continue;
    }
    // Citing a metric that failed its gate is the same offence as inventing a
    // number: it claims knowledge the data does not contain.
    if (basedOn.some((id) => (sheet.insufficient ?? []).includes(id))) {
      rejected++;
      continue;
    }
    if (!groundedNumerals(text, sheet)) {
      rejected++;
      continue;
    }
    insights.push({kind, text, basedOn, nights: sheet.nightsWithData ?? 0});
  }

  return {insights: insights.slice(0, 3), rejected};
}

/**
 * Generates insights for one fact sheet.
 *
 * One retry, then nothing. Returning an empty list is the correct outcome, not
 * a failure to handle: the client always has its deterministic tier
 * (`deterministicInsights` in Dart) to fall back on, so an empty result here
 * degrades the wording and never the truthfulness. Loosening the gate to fill
 * the screen would invert that.
 * @param {{factSheet: !Object, callModel: function(!Object): !Promise<string>,
 *   maxAttempts: (number|undefined)}} args
 * @return {!Promise<{insights: !Array<!Object>, attempts: number,
 *   rejected: number}>}
 */
async function generateSleepInsights({factSheet, callModel, maxAttempts = 2}) {
  if (!factSheet || (factSheet.facts ?? []).length === 0) {
    return {insights: [], attempts: 0, rejected: 0};
  }

  let rejected = 0;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    let raw;
    try {
      raw = await callModel({
        system: systemPrompt(),
        // The model sees the fact sheet and nothing else — no raw sessions,
        // no history, nothing it could compute a new number from.
        user: JSON.stringify(factSheet),
      });
    } catch (_) {
      return {insights: [], attempts: attempt, rejected};
    }

    const result = validateResponse(raw, factSheet);
    rejected += result.rejected;
    if (result.insights.length > 0) {
      return {insights: result.insights, attempts: attempt, rejected};
    }
  }

  return {insights: [], attempts: maxAttempts, rejected};
}

module.exports = {
  KINDS,
  allowedNumerals,
  groundedNumerals,
  systemPrompt,
  validateResponse,
  generateSleepInsights,
};
