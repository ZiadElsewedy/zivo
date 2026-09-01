/**
 * What this person burns, server-side — the mirror of
 * `lib/features/diet/domain/body_measures.dart` and
 * `lib/features/diet/domain/analysis/maintenance_calibration.dart`.
 *
 * The coach must reach the SAME maintenance figure the Diet screen shows.
 * Anything else and the app tells you your target is 300 over maintenance
 * while the coach congratulates you for hitting it — the exact drift the diet
 * rebuild exists to end. `test/fixtures/energy_vectors.json` is what keeps the
 * two honest; both suites run it.
 *
 * Precedence, identical on both sides:
 *
 *   stated > measured > estimated
 *
 * A measurement of the actual person replaces a population equation outright.
 * It does NOT replace a figure the user stated themselves — overriding what
 * someone explicitly told the app would be the app contradicting them
 * silently. The disagreement is surfaced by the rules engine instead.
 *
 * Pure: no clock, no Firestore. Everything is passed in.
 */

/** Mirrors the Dart `kKcalPerKgBodyweight`. */
const KCAL_PER_KG_BODYWEIGHT = 7700;

/** Mirrors the Dart `kMinCalibrationDays`. */
const MIN_CALIBRATION_DAYS = 14;

/** Mirrors the Dart `kMinLoggedCoverage`. */
const MIN_LOGGED_COVERAGE = 2 / 3;

/** Mirrors the Dart `kMinLoggedDays`. */
const MIN_LOGGED_DAYS = 10;

/** Mirrors the Dart `activityFactor`. */
const ACTIVITY_FACTOR = {
  sedentary: 1.2,
  light: 1.375,
  moderate: 1.55,
  high: 1.725,
  athlete: 1.9,
};

/**
 * Basal metabolic rate, Mifflin-St Jeor. Mirrors the Dart
 * `basalMetabolicRate`.
 * @param {!Object} body `{weightKg, heightCm, age, sex}`.
 * @return {number}
 */
function basalMetabolicRate({weightKg, heightCm, age, sex}) {
  const base = 10 * weightKg + 6.25 * heightCm - 5 * age;
  return Math.round(sex === "male" ? base + 5 : base - 161);
}

/**
 * Measures maintenance from weigh-ins and logged intake, or returns null with
 * the reason. Mirrors the Dart `calibrateMaintenance`.
 *
 * @param {!Object} args
 * @param {!Array<{weightKg: number, loggedAtMs: number}>} args.weighIns
 * @param {!Array<{dayKey: string, kcal: number}>} args.intake Per-day totals;
 *   days with nothing logged are ABSENT, never zero.
 * @return {{measured: ?Object, gap: ?string}}
 */
function calibrateMaintenance({weighIns, intake}) {
  const entries = (weighIns || []).filter(
      (w) => w && Number.isFinite(w.weightKg) && Number.isFinite(w.loggedAtMs));
  if (entries.length < 2) return {measured: null, gap: "needsWeighIns"};

  const sorted = [...entries].sort((a, b) => a.loggedAtMs - b.loggedAtMs);
  const first = sorted[0];
  const last = sorted[sorted.length - 1];
  const from = startOfDay(first.loggedAtMs);
  const to = startOfDay(last.loggedAtMs);
  const days = Math.round((to - from) / 86400000);
  if (days < MIN_CALIBRATION_DAYS) {
    return {measured: null, gap: "needsLongerWindow"};
  }

  const fromKey = dayKeyOfMs(from);
  const toKey = dayKeyOfMs(to);
  const inWindow = (intake || []).filter(
      (d) => d && d.dayKey >= fromKey && d.dayKey <= toKey);
  if (inWindow.length < MIN_LOGGED_DAYS ||
      inWindow.length / days < MIN_LOGGED_COVERAGE) {
    return {measured: null, gap: "needsMoreLoggedDays"};
  }

  const averageIntake =
    inWindow.reduce((sum, d) => sum + (Number(d.kcal) || 0), 0) /
    inWindow.length;
  const weightChangeKg = last.weightKg - first.weightKg;
  // Gaining means some of what they ate went into storage, so true
  // maintenance is BELOW what they ate — hence the subtraction.
  const storedPerDay = weightChangeKg * KCAL_PER_KG_BODYWEIGHT / days;

  return {
    measured: {
      maintenanceKcal: Math.round(averageIntake - storedPerDay),
      averageIntakeKcal: Math.round(averageIntake),
      weightChangeKg: round1(weightChangeKg),
      days,
      loggedDays: inWindow.length,
    },
    gap: null,
  };
}

/**
 * The `energy` block `buildDietState` takes, or null when ZIVO doesn't know
 * enough about this person's body to say anything.
 *
 * @param {!Object} args
 * @param {?Object} args.profile `{heightCm, sex, activity,
 *   statedMaintenanceKcal}` or null.
 * @param {?number} args.weightKg The latest weigh-in.
 * @param {?number} args.age
 * @param {?number} args.measuredMaintenanceKcal From [calibrateMaintenance].
 * @return {?{maintenanceKcal: number, source: string}}
 */
function energyFor({profile, weightKg, age, measuredMaintenanceKcal}) {
  if (!profile) return null;
  const stated = Number.isFinite(profile.statedMaintenanceKcal) ?
    Math.round(profile.statedMaintenanceKcal) : null;
  if (stated !== null) {
    return {maintenanceKcal: stated, source: "stated"};
  }
  if (Number.isFinite(measuredMaintenanceKcal)) {
    return {
      maintenanceKcal: Math.round(measuredMaintenanceKcal),
      source: "measured",
    };
  }
  // The equation needs every term. A maintenance figure resting on a guessed
  // height is not a weaker answer, it's a wrong one.
  if (!Number.isFinite(weightKg) || !Number.isFinite(age) ||
      !Number.isFinite(profile.heightCm) ||
      !ACTIVITY_FACTOR[profile.activity] ||
      (profile.sex !== "male" && profile.sex !== "female")) {
    return null;
  }
  const bmr = basalMetabolicRate({
    weightKg,
    heightCm: profile.heightCm,
    age,
    sex: profile.sex,
  });
  return {
    maintenanceKcal: Math.round(bmr * ACTIVITY_FACTOR[profile.activity]),
    source: "estimated",
  };
}

/**
 * Whole years between a date of birth and now. Mirrors the Dart `ageFrom`.
 * @param {number} dobMs
 * @param {number} nowMs
 * @return {number}
 */
function ageFrom(dobMs, nowMs) {
  const dob = new Date(dobMs);
  const now = new Date(nowMs);
  let age = now.getUTCFullYear() - dob.getUTCFullYear();
  const hadBirthday = now.getUTCMonth() > dob.getUTCMonth() ||
    (now.getUTCMonth() === dob.getUTCMonth() &&
      now.getUTCDate() >= dob.getUTCDate());
  if (!hadBirthday) age -= 1;
  return age;
}

/**
 * @param {number} ms
 * @return {number} Midnight UTC of that day, in ms.
 */
function startOfDay(ms) {
  const d = new Date(ms);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
}

/**
 * @param {number} ms
 * @return {string} 'yyyy-MM-dd'.
 */
function dayKeyOfMs(ms) {
  const d = new Date(ms);
  const pad = (n, w) => String(n).padStart(w, "0");
  return `${pad(d.getUTCFullYear(), 4)}-${pad(d.getUTCMonth() + 1, 2)}-` +
    `${pad(d.getUTCDate(), 2)}`;
}

/**
 * @param {number} v
 * @return {number}
 */
function round1(v) {
  return Math.round(v * 10) / 10;
}

module.exports = {
  basalMetabolicRate,
  calibrateMaintenance,
  energyFor,
  ageFrom,
  KCAL_PER_KG_BODYWEIGHT,
  MIN_CALIBRATION_DAYS,
  MIN_LOGGED_COVERAGE,
  MIN_LOGGED_DAYS,
  ACTIVITY_FACTOR,
};
