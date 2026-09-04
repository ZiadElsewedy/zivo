// Security-rules tests for firestore.rules, run against the Firestore emulator.
//
// Run with:  firebase emulators:exec --only firestore --project demo-zivo "npm test"
// (from the repo root). The emulator loads no auth; contexts below supply the
// auth token that the rules gate on.
//
// Covers PLAN §10/§20/§28: deny-by-default, per-user ownership isolation,
// per-collection field validation, and the Functions-only emailOtps lockout —
// for each persisted collection (across the expenses/workouts/moments/diet
// feature repositories, including the user's custom expense categories, plus
// the workout-plan template store and the
// workout-session execution-record store) plus the user profile doc, plus
// the AI conversation store (ADR-001): client-writable `aiConversations`,
// and server-only `messages`/`aiUsage`, plus the auth-activity stores
// (owner-writable `auth/account` summary; append-only `authEvents` log).

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { before, after, beforeEach, describe, it } from 'node:test';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, Timestamp, serverTimestamp,
} from 'firebase/firestore';

const here = dirname(fileURLToPath(import.meta.url));
const rules = readFileSync(join(here, '..', 'firestore.rules'), 'utf8');

const OWNER = 'owner-uid';
const OTHER = 'other-uid';
const ts = () => Timestamp.fromDate(new Date('2026-01-01T00:00:00Z'));

// Valid payloads that satisfy each collection's field validation.
const valid = {
  expenses: { amountMinor: 100, currency: 'EGP', category: 'food', spentAt: ts(), schemaVersion: 1 },
  workouts: { title: 'W', performedAt: ts(), exercises: [], schemaVersion: 1 },
  moments: { caption: 'M', takenAt: ts(), schemaVersion: 1 },
  dietPlans: { name: 'Cut', status: 'active', days: [], schemaVersion: 1 },
  dietEntries: { dayKey: '2026-01-01', date: ts(), mealId: 'm1', eaten: true, schemaVersion: 1 },
  workoutPlans: { name: 'PPL', status: 'active', source: 'manual', days: [], cycleCursor: 0, schemaVersion: 1 },
  workoutMeta: { activeSplitId: 'plan1' },
  workoutSessions: { dayLabel: 'Push', status: 'active', startedAt: ts(), exercises: [], schemaVersion: 1 },
  bodyWeightEntries: { weightKg: 82.5, loggedAt: ts(), schemaVersion: 1 },
  aiConversations: { title: 'Chat', schemaVersion: 1 },
  expenseCategories: { label: 'Subs', iconId: 'bills' },
};

// Each violates exactly one validation clause of its collection's write rule.
const invalid = {
  expenses: { amountMinor: -5, currency: 'EGP', category: 'food', spentAt: ts(), schemaVersion: 1 }, // amount < 0
  workouts: { title: 'W', performedAt: ts(), exercises: 'nope', schemaVersion: 1 }, // exercises not a list
  moments: { caption: 'M', takenAt: ts() }, // missing schemaVersion
  dietPlans: { name: 'Cut', status: 'active', days: 'nope', schemaVersion: 1 }, // days not a list
  dietEntries: { dayKey: '2026-01-01', date: ts(), mealId: 'm1', eaten: 'yes', schemaVersion: 1 }, // eaten not bool
  workoutPlans: { name: 'PPL', status: 'paused', source: 'manual', days: [], cycleCursor: 0, schemaVersion: 1 }, // status not in enum
  workoutMeta: { activeSplitId: 123 }, // activeSplitId neither string nor null
  workoutSessions: { dayLabel: 'Push', status: 'paused', startedAt: ts(), exercises: [], schemaVersion: 1 }, // status not in enum
  bodyWeightEntries: { weightKg: -1, loggedAt: ts(), schemaVersion: 1 }, // weight not > 0
  aiConversations: { title: 123, schemaVersion: 1 }, // title not a string
  // `emoji` was the pre-migration field name; a doc still shaped that way is
  // missing `iconId` and must be rejected.
  expenseCategories: { label: 'Subs', emoji: '🧾', hue: 'iris' }, // no iconId
};

const collections = Object.keys(valid);

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-zivo-rules',
    firestore: { rules },
  });
});
after(async () => { await testEnv.cleanup(); });
beforeEach(async () => { await testEnv.clearFirestore(); });

const ownerDb = () => testEnv.authenticatedContext(OWNER).firestore();
const otherDb = () => testEnv.authenticatedContext(OTHER).firestore();
const anonDb = () => testEnv.unauthenticatedContext().firestore();

// Seed a document bypassing rules, so read/ownership tests have something to read.
async function seed(path, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), path), data);
  });
}

const collPath = (uid, coll) => `users/${uid}/${coll}/doc1`;

describe('deny-by-default', () => {
  it('unauthenticated cannot read a user profile', async () => {
    await seed(`users/${OWNER}`, { name: 'Z', dateOfBirth: ts() });
    await assertFails(getDoc(doc(anonDb(), `users/${OWNER}`)));
  });

  it('unauthenticated cannot write feature data', async () => {
    await assertFails(setDoc(doc(anonDb(), collPath(OWNER, 'expenses')), valid.expenses));
  });

  it('authenticated user cannot touch an unknown top-level collection (catch-all)', async () => {
    await assertFails(setDoc(doc(ownerDb(), 'randomCollection/x'), { a: 1 }));
    await assertFails(getDoc(doc(ownerDb(), 'randomCollection/x')));
  });

  it('authenticated user cannot touch an unknown subcollection under their own user doc', async () => {
    await assertFails(setDoc(doc(ownerDb(), `users/${OWNER}/secrets/x`), { a: 1 }));
  });
});

describe('emailOtps is Functions-only (denied to all clients)', () => {
  it('owner cannot read or write their own OTP record', async () => {
    await seed(`emailOtps/${OWNER}`, { hash: 'x' });
    await assertFails(getDoc(doc(ownerDb(), `emailOtps/${OWNER}`)));
    await assertFails(setDoc(doc(ownerDb(), `emailOtps/${OWNER}`), { hash: 'y' }));
  });
});

describe('passwordResetOtps is Functions-only (denied to all clients)', () => {
  it('owner cannot read or write their own reset-code record', async () => {
    await seed(`passwordResetOtps/${OWNER}`, { hash: 'x' });
    await assertFails(getDoc(doc(ownerDb(), `passwordResetOtps/${OWNER}`)));
    await assertFails(setDoc(doc(ownerDb(), `passwordResetOtps/${OWNER}`), { hash: 'y' }));
  });
});

describe('users/{uid} profile ownership', () => {
  it('owner can read and write their own profile', async () => {
    const db = ownerDb();
    await assertSucceeds(setDoc(doc(db, `users/${OWNER}`), { name: 'Z', dateOfBirth: ts() }));
    await assertSucceeds(getDoc(doc(db, `users/${OWNER}`)));
  });

  it('a different signed-in user cannot read or write the profile', async () => {
    await seed(`users/${OWNER}`, { name: 'Z', dateOfBirth: ts() });
    await assertFails(getDoc(doc(otherDb(), `users/${OWNER}`)));
    await assertFails(setDoc(doc(otherDb(), `users/${OWNER}`), { name: 'hacked' }));
  });

  it('unauthenticated cannot write the profile', async () => {
    await assertFails(setDoc(doc(anonDb(), `users/${OWNER}`), { name: 'Z' }));
  });
});

for (const coll of collections) {
  describe(`users/{uid}/${coll} ownership + validation`, () => {
    it('owner can create a valid doc and read it back', async () => {
      const db = ownerDb();
      await assertSucceeds(setDoc(doc(db, collPath(OWNER, coll)), valid[coll]));
      await assertSucceeds(getDoc(doc(db, collPath(OWNER, coll))));
    });

    it('a different signed-in user cannot read or write it', async () => {
      await seed(collPath(OWNER, coll), valid[coll]);
      await assertFails(getDoc(doc(otherDb(), collPath(OWNER, coll))));
      await assertFails(setDoc(doc(otherDb(), collPath(OWNER, coll)), valid[coll]));
    });

    it('unauthenticated cannot write it', async () => {
      await assertFails(setDoc(doc(anonDb(), collPath(OWNER, coll)), valid[coll]));
    });

    it('owner cannot write a malformed doc (field validation)', async () => {
      await assertFails(setDoc(doc(ownerDb(), collPath(OWNER, coll)), invalid[coll]));
    });
  });
}

// The generic loop above exercises the string-id case; the pointer is also
// written with a null id to CLEAR it (when the last split is deleted), so
// cover that allowed path explicitly.
describe('workoutMeta active-split pointer allows a null id', () => {
  it('owner can write { activeSplitId: null } to clear the pointer', async () => {
    await assertSucceeds(
      setDoc(doc(ownerDb(), collPath(OWNER, 'workoutMeta')), { activeSplitId: null }),
    );
  });
});

describe('AI messages are Functions-only (owner may read, no client may write)', () => {
  const messagesPath = `users/${OWNER}/aiConversations/c1/messages/m1`;
  const message = { role: 'assistant', content: 'hi', createdAt: ts(), schemaVersion: 1 };

  it('owner can read a seeded message but cannot write one', async () => {
    await seed(messagesPath, message);
    await assertSucceeds(getDoc(doc(ownerDb(), messagesPath)));
    await assertFails(setDoc(doc(ownerDb(), messagesPath), message));
  });

  it('a different signed-in user cannot read it', async () => {
    await seed(messagesPath, message);
    await assertFails(getDoc(doc(otherDb(), messagesPath)));
  });
});

describe('AI pending actions are Functions-only (owner may read, no client may write)', () => {
  const pendingPath = `users/${OWNER}/aiConversations/c1/pendingActions/a1`;
  const action = {
    kind: 'create_task', tool: 'create_task', status: 'pending',
    summary: 'Add task', createdAt: ts(), expiresAt: ts(), schemaVersion: 1,
  };

  it('owner can read a seeded pending action but cannot write one', async () => {
    await seed(pendingPath, action);
    await assertSucceeds(getDoc(doc(ownerDb(), pendingPath)));
    await assertFails(setDoc(doc(ownerDb(), pendingPath), action));
  });

  it('a different signed-in user cannot read it', async () => {
    await seed(pendingPath, action);
    await assertFails(getDoc(doc(otherDb(), pendingPath)));
  });
});

describe('aiUsage is Functions-only (owner may read, no client may write)', () => {
  const usagePath = `users/${OWNER}/aiUsage/u1`;
  const usage = { tokensIn: 10, tokensOut: 20, schemaVersion: 1 };

  it('owner can read a seeded usage doc but cannot write one', async () => {
    await seed(usagePath, usage);
    await assertSucceeds(getDoc(doc(ownerDb(), usagePath)));
    await assertFails(setDoc(doc(ownerDb(), usagePath), usage));
  });

  it('a different signed-in user cannot read it', async () => {
    await seed(usagePath, usage);
    await assertFails(getDoc(doc(otherDb(), usagePath)));
  });
});

// Regression test for a real bug: `allow write` combined with field
// validation denies every delete, since `request.resource.data` is null on
// delete (see firestore.rules' comment on this collection).
describe('expenses delete path', () => {
  it('owner can delete their own expense; non-owner cannot', async () => {
    await seed(collPath(OWNER, 'expenses'), valid.expenses);
    await assertFails(deleteDoc(doc(otherDb(), collPath(OWNER, 'expenses'))));
    await assertSucceeds(deleteDoc(doc(ownerDb(), collPath(OWNER, 'expenses'))));
  });
});

describe('expenseCategories delete path', () => {
  it('owner can delete their own category; non-owner cannot', async () => {
    await seed(collPath(OWNER, 'expenseCategories'), valid.expenseCategories);
    await assertFails(deleteDoc(doc(otherDb(), collPath(OWNER, 'expenseCategories'))));
    await assertSucceeds(deleteDoc(doc(ownerDb(), collPath(OWNER, 'expenseCategories'))));
  });
});

describe('workouts delete path', () => {
  it('owner can delete their own workout; non-owner cannot', async () => {
    await seed(collPath(OWNER, 'workouts'), valid.workouts);
    await assertFails(deleteDoc(doc(otherDb(), collPath(OWNER, 'workouts'))));
    await assertSucceeds(deleteDoc(doc(ownerDb(), collPath(OWNER, 'workouts'))));
  });
});

// The user keeps a LIBRARY of plans, of which one is active. The rules cannot
// enforce "exactly one active" — that needs a read of sibling documents, which
// rules cannot do, and it is held by the repository's batched write instead.
// What the rules do hold is the shape of each document and the vocabulary its
// status comes from.
describe('dietPlans as a library', () => {
  const plan = (patch = {}) => ({
    name: 'Cut', status: 'active', days: [], schemaVersion: 1, ...patch,
  });
  const write = (id, data) =>
    setDoc(doc(ownerDb(), `users/${OWNER}/dietPlans/${id}`), data);

  it('accepts several plans side by side', async () => {
    await assertSucceeds(write('p1', plan({ updatedAt: ts() })));
    await assertSucceeds(
      write('p2', plan({ name: 'Bulk', status: 'archived', updatedAt: ts() })),
    );
    await assertSucceeds(
      write('p3', plan({ name: 'Draft', status: 'draft', updatedAt: ts() })),
    );
  });

  it('rejects a status outside the vocabulary', async () => {
    await assertFails(write('p4', plan({ status: 'following' })));
  });

  it("a different signed-in user cannot read or reshuffle someone's library", async () => {
    await seed(`users/${OWNER}/dietPlans/p1`, plan());
    await assertFails(getDoc(doc(otherDb(), `users/${OWNER}/dietPlans/p1`)));
    await assertFails(
      setDoc(doc(otherDb(), `users/${OWNER}/dietPlans/p1`), plan({ status: 'archived' })),
    );
  });
});

describe('dietPlans delete path', () => {
  it('owner can delete their own plan; non-owner cannot', async () => {
    await seed(collPath(OWNER, 'dietPlans'), valid.dietPlans);
    await assertFails(deleteDoc(doc(otherDb(), collPath(OWNER, 'dietPlans'))));
    await assertSucceeds(deleteDoc(doc(ownerDb(), collPath(OWNER, 'dietPlans'))));
  });
});

describe('workoutPlans delete path', () => {
  it('owner can delete their own plan; non-owner cannot', async () => {
    await seed(collPath(OWNER, 'workoutPlans'), valid.workoutPlans);
    await assertFails(deleteDoc(doc(otherDb(), collPath(OWNER, 'workoutPlans'))));
    await assertSucceeds(deleteDoc(doc(ownerDb(), collPath(OWNER, 'workoutPlans'))));
  });
});

describe('workoutSessions delete path', () => {
  it('owner can delete their own session; non-owner cannot', async () => {
    await seed(collPath(OWNER, 'workoutSessions'), valid.workoutSessions);
    await assertFails(deleteDoc(doc(otherDb(), collPath(OWNER, 'workoutSessions'))));
    await assertSucceeds(deleteDoc(doc(ownerDb(), collPath(OWNER, 'workoutSessions'))));
  });
});

describe('bodyWeightEntries delete path', () => {
  it('owner can delete their own weigh-in; non-owner cannot', async () => {
    await seed(collPath(OWNER, 'bodyWeightEntries'), valid.bodyWeightEntries);
    await assertFails(deleteDoc(doc(otherDb(), collPath(OWNER, 'bodyWeightEntries'))));
    await assertSucceeds(deleteDoc(doc(ownerDb(), collPath(OWNER, 'bodyWeightEntries'))));
  });
});

// --- Auth activity stores (account summary + append-only event log) ---------

describe('users/{uid}/auth account-metadata ownership + validation', () => {
  const authPath = `users/${OWNER}/auth/account`;
  const account = {
    schemaVersion: 1,
    registeredVia: 'password',
    lastSignInAt: serverTimestamp(),
    signInCount: 1,
  };

  it('owner can create and read their own summary doc', async () => {
    await assertSucceeds(setDoc(doc(ownerDb(), authPath), account));
    await assertSucceeds(getDoc(doc(ownerDb(), authPath)));
  });

  it('a different signed-in user cannot read or write it', async () => {
    await seed(authPath, { schemaVersion: 1, signInCount: 3 });
    await assertFails(getDoc(doc(otherDb(), authPath)));
    await assertFails(setDoc(doc(otherDb(), authPath), { schemaVersion: 1 }));
  });

  it('owner cannot write a malformed summary (field validation)', async () => {
    await assertFails(setDoc(doc(ownerDb(), authPath), { schemaVersion: 2 })); // bad schemaVersion
    await assertFails(setDoc(doc(ownerDb(), authPath), { schemaVersion: 1, signInCount: 'many' })); // not int
    await assertFails(setDoc(doc(ownerDb(), authPath), { schemaVersion: 1, registeredVia: 42 })); // not string
  });

  it('nobody (not even the owner) can delete the summary', async () => {
    await seed(authPath, { schemaVersion: 1 });
    await assertFails(deleteDoc(doc(ownerDb(), authPath)));
    await assertFails(deleteDoc(doc(otherDb(), authPath)));
  });
});

describe('users/{uid}/authEvents is an append-only audit log', () => {
  const event = () => ({
    schemaVersion: 1,
    type: 'signIn',
    provider: 'password',
    platform: 'ios',
    occurredAt: serverTimestamp(),
  });

  it('owner can append a well-formed event and read the log back', async () => {
    const db = ownerDb();
    await assertSucceeds(
      setDoc(doc(db, `users/${OWNER}/authEvents/e1`), event()),
    );
    await assertSucceeds(getDoc(doc(db, `users/${OWNER}/authEvents/e1`)));
  });

  it('a different signed-in user cannot read or append to it', async () => {
    await seed(`users/${OWNER}/authEvents/e1`, { schemaVersion: 1, type: 'signIn' });
    await assertFails(getDoc(doc(otherDb(), `users/${OWNER}/authEvents/e1`)));
    await assertFails(setDoc(doc(otherDb(), `users/${OWNER}/authEvents/e1`), event()));
  });

  it('append must carry a known type from the vocabulary', async () => {
    await assertFails(setDoc(doc(ownerDb(), `users/${OWNER}/authEvents/e2`), {
      ...event(),
      type: 'hax',
    }));
  });

  it('append must pin occurredAt to the server clock', async () => {
    // A client-chosen timestamp would let a hostile user forge history.
    await assertFails(setDoc(doc(ownerDb(), `users/${OWNER}/authEvents/e3`), {
      ...event(),
      occurredAt: ts(),
    }));
  });

  it('events cannot be updated or deleted once written', async () => {
    await seed(`users/${OWNER}/authEvents/e4`, {
      schemaVersion: 1, type: 'signIn', occurredAt: ts(),
    });
    await assertFails(updateDoc(doc(ownerDb(), `users/${OWNER}/authEvents/e4`), {
      type: 'accountCreated',
    }));
    await assertFails(deleteDoc(doc(ownerDb(), `users/${OWNER}/authEvents/e4`)));
  });
});

// The consumption log is what every "meals eaten" and "kcal left" figure in
// the app is computed from, so its shape is validated tightly. These cover the
// clauses added when the AI write path was hardened: a malformed entry is not
// a loud failure, it is a quietly wrong number on the Diet screen.
describe('dietEntries shape validation', () => {
  const entry = (patch = {}) => ({
    dayKey: '2026-01-01', date: ts(), mealId: 'm1', eaten: true,
    schemaVersion: 1, ...patch,
  });
  const write = (data, id = 'e1') =>
    setDoc(doc(ownerDb(), `users/${OWNER}/dietEntries/${id}`), data);

  it('accepts the shape the app actually writes', async () => {
    await assertSucceeds(write(entry({ createdAt: ts(), updatedAt: ts() })));
  });

  it('rejects a dayKey that is not a yyyy-MM-dd calendar date', async () => {
    await assertFails(write(entry({ dayKey: '2026-1-1' })));
    await assertFails(write(entry({ dayKey: 'today' })));
  });

  it('rejects an empty or oversized mealId', async () => {
    await assertFails(write(entry({ mealId: '' })));
    await assertFails(write(entry({ mealId: 'm'.repeat(201) })));
  });

  it('rejects a missing or non-timestamp date', async () => {
    await assertFails(write(entry({ date: '2026-01-01' })));
    const { date, ...noDate } = entry();
    await assertFails(write(noDate));
  });

  it('rejects unknown fields smuggled onto the entry', async () => {
    await assertFails(write(entry({ calories: 9999 })));
  });
});

// The user's objective. Everything the coach says is measured against this, so
// an unreadable target is worse than none at all — the app would end up
// coaching against a number nobody chose.
describe('dietTargets shape validation', () => {
  const targets = (patch = {}) => ({
    goal: 'fatLoss', calories: 2200, proteinG: 160, carbsG: 250, fatG: 73,
    source: 'calculated', schemaVersion: 1, ...patch,
  });
  const write = (data) =>
    setDoc(doc(ownerDb(), `users/${OWNER}/dietTargets/current`), data);

  it('accepts the shape the app writes', async () => {
    await assertSucceeds(write(targets({ updatedAt: ts() })));
  });

  it('accepts a target with no macro targets — blank means untracked', async () => {
    await assertSucceeds(
      write(targets({ proteinG: null, carbsG: null, fatG: null })),
    );
  });

  it('rejects an unknown goal', async () => {
    await assertFails(write(targets({ goal: 'shredded' })));
  });

  it('rejects a missing, zero or absurd calorie figure', async () => {
    const { calories, ...noCalories } = targets();
    await assertFails(write(noCalories));
    await assertFails(write(targets({ calories: 0 })));
    await assertFails(write(targets({ calories: 99999 })));
    await assertFails(write(targets({ calories: 2200.5 })));
  });

  it('rejects an unknown provenance', async () => {
    // A target has to say where it came from, from a fixed vocabulary — the
    // same rule food figures follow with `estimated`.
    await assertFails(write(targets({ source: 'vibes' })));
  });

  it('rejects unknown fields', async () => {
    await assertFails(write(targets({ secretMultiplier: 2 })));
  });

  it('a different signed-in user can neither read nor write them', async () => {
    await seed(`users/${OWNER}/dietTargets/current`, targets());
    await assertFails(
      getDoc(doc(otherDb(), `users/${OWNER}/dietTargets/current`)),
    );
    await assertFails(
      setDoc(doc(otherDb(), `users/${OWNER}/dietTargets/current`), targets()),
    );
  });

  it('the owner can delete their target', async () => {
    await seed(`users/${OWNER}/dietTargets/current`, targets());
    await assertSucceeds(
      deleteDoc(doc(ownerDb(), `users/${OWNER}/dietTargets/current`)),
    );
  });
});

// Body data underwrites every "this plan makes you gain" answer the app gives.
// A doc that stored two of its three required fields wouldn't fail loudly — it
// would produce a maintenance figure resting on a default nobody chose.
describe('bodyProfile shape validation', () => {
  const profile = (patch = {}) => ({
    heightCm: 178, sex: 'male', activity: 'moderate',
    statedMaintenanceKcal: null, schemaVersion: 1, ...patch,
  });
  const write = (data) =>
    setDoc(doc(ownerDb(), `users/${OWNER}/bodyProfile/current`), data);

  it('accepts the shape the app writes', async () => {
    await assertSucceeds(write(profile({ updatedAt: ts() })));
  });

  it('accepts a stated maintenance figure the user knows', async () => {
    await assertSucceeds(write(profile({ statedMaintenanceKcal: 2900 })));
  });

  it('rejects a profile missing any equation input', async () => {
    const { heightCm, ...noHeight } = profile();
    const { sex, ...noSex } = profile();
    const { activity, ...noActivity } = profile();
    await assertFails(write(noHeight));
    await assertFails(write(noSex));
    await assertFails(write(noActivity));
  });

  it('rejects an implausible height — a typo, not a person', async () => {
    await assertFails(write(profile({ heightCm: 1.78 })));
    await assertFails(write(profile({ heightCm: 300 })));
  });

  it('rejects unknown vocabularies', async () => {
    await assertFails(write(profile({ sex: 'unspecified' })));
    await assertFails(write(profile({ activity: 'olympian' })));
  });

  it('rejects an absurd stated maintenance figure', async () => {
    await assertFails(write(profile({ statedMaintenanceKcal: 100 })));
    await assertFails(write(profile({ statedMaintenanceKcal: 50000 })));
  });

  it('rejects unknown fields — no weight here, it lives in bodyWeights', async () => {
    await assertFails(write(profile({ weightKg: 82 })));
  });

  it('a different signed-in user can neither read nor write it', async () => {
    await seed(`users/${OWNER}/bodyProfile/current`, profile());
    await assertFails(
      getDoc(doc(otherDb(), `users/${OWNER}/bodyProfile/current`)),
    );
    await assertFails(
      setDoc(doc(otherDb(), `users/${OWNER}/bodyProfile/current`), profile()),
    );
  });

  it('the owner can delete their body data', async () => {
    await seed(`users/${OWNER}/bodyProfile/current`, profile());
    await assertSucceeds(
      deleteDoc(doc(ownerDb(), `users/${OWNER}/bodyProfile/current`)),
    );
  });
});

// The food log is the ledger every consumed/remaining figure is computed from,
// so a malformed entry doesn't fail loudly — it quietly makes the coach wrong.
describe('foodLogs shape validation', () => {
  const entry = (patch = {}) => ({
    dayKey: '2026-01-01', date: ts(), loggedAt: ts(),
    foodId: 'usda:171477', foodName: 'Chicken breast, roasted',
    quantity: 200, unit: 'g', grams: 200,
    kcal: 330, proteinG: 62, carbsG: 0, fatG: 7.2,
    source: 'usdaFdc', sourceRef: '171477', origin: 'logged',
    estimated: false, mealId: null, schemaVersion: 1, ...patch,
  });
  const write = (data, id = 'e1') =>
    setDoc(doc(ownerDb(), `users/${OWNER}/foodLogs/${id}`), data);

  it('accepts the shape the app writes', async () => {
    await assertSucceeds(write(entry()));
  });

  it('requires a food reference — a figure with nothing behind it is the '
    + 'exact thing this design forbids', async () => {
    await assertFails(write(entry({ foodId: '' })));
    const { foodId, ...noFood } = entry();
    await assertFails(write(noFood));
  });

  it('requires provenance from a fixed vocabulary', async () => {
    await assertFails(write(entry({ source: 'guessed' })));
    await assertFails(write(entry({ origin: 'probably' })));
    // The three real sources are all accepted.
    for (const source of ['usdaFdc', 'userCustom', 'dietPlan']) {
      await assertSucceeds(write(entry({ source }), `ok-${source}`));
    }
  });

  it('rejects negative or absurd nutrition', async () => {
    await assertFails(write(entry({ kcal: -1 })));
    await assertFails(write(entry({ kcal: 99999 })));
    await assertFails(write(entry({ proteinG: -5 })));
    await assertFails(write(entry({ kcal: 330.5 })));
  });

  it('rejects a malformed dayKey and unknown fields', async () => {
    await assertFails(write(entry({ dayKey: 'today' })));
    await assertFails(write(entry({ verified: true })));
  });

  it('a different signed-in user cannot read or write it', async () => {
    await seed(`users/${OWNER}/foodLogs/e9`, entry());
    await assertFails(getDoc(doc(otherDb(), `users/${OWNER}/foodLogs/e9`)));
    await assertFails(setDoc(doc(otherDb(), `users/${OWNER}/foodLogs/e9`), entry()));
  });
});

// A user's own foods: validated for shape and plausibility, never for
// "correctness" — it is not the app's place to tell someone their own recipe
// is wrong.
describe('customFoods shape validation', () => {
  const food = (patch = {}) => ({
    name: 'Koshari (mum)', kcalPer100g: 150, proteinPer100g: 5,
    carbsPer100g: 27, fatPer100g: 3, preparation: 'cooked',
    portions: [{ label: 'plate', grams: 350 }],
    schemaVersion: 1, createdAt: ts(), ...patch,
  });
  const write = (data, id = 'f1') =>
    setDoc(doc(ownerDb(), `users/${OWNER}/customFoods/${id}`), data);

  it('accepts a food the user defined', async () => {
    await assertSucceeds(write(food()));
  });

  it('requires a name and a per-100g energy figure', async () => {
    await assertFails(write(food({ name: '' })));
    const { kcalPer100g, ...noEnergy } = food();
    await assertFails(write(noEnergy));
  });

  it('rejects physically impossible composition', async () => {
    // Nothing is more than 100g of macro per 100g, and no food exceeds pure
    // fat's energy density.
    await assertFails(write(food({ proteinPer100g: 150 })));
    await assertFails(write(food({ kcalPer100g: 5000 })));
    await assertFails(write(food({ fatPer100g: -1 })));
  });

  it('rejects unknown fields', async () => {
    await assertFails(write(food({ verified: true })));
  });
});

// --- email verification as a BOUNDARY, not just a screen --------------------
//
// `resolveAuthState` sends an unverified password account to the OTP screen,
// but a screen is not a boundary — anything talking to the API directly used
// to skip it and write freely. These pin the server half of that policy.
//
// Note the tokens every OTHER test in this file uses carry no email claim at
// all, which is exactly the "provider withheld an address" case: those must
// keep working, and the fact that all 111 of them still pass is that
// assertion. Here we supply real email claims to exercise the other branches.
describe('email verification gates writes, never reads', () => {
  const unverifiedDb = () => testEnv
    .authenticatedContext(OWNER, { email: 'z@example.com', email_verified: false })
    .firestore();
  const verifiedDb = () => testEnv
    .authenticatedContext(OWNER, { email: 'z@example.com', email_verified: true })
    .firestore();

  it('an unverified address cannot write feature data', async () => {
    await assertFails(
      setDoc(doc(unverifiedDb(), collPath(OWNER, 'workouts')), valid.workouts),
    );
  });

  it('an unverified address cannot write the profile', async () => {
    await assertFails(
      setDoc(doc(unverifiedDb(), `users/${OWNER}`), { name: 'Z', dateOfBirth: ts() }),
    );
  });

  it('an unverified address CAN still read what it already has', async () => {
    // Losing write access is a gate; losing read access is data loss. A
    // stranded account must still be able to see and export its own data.
    await seed(collPath(OWNER, 'workouts'), valid.workouts);
    await seed(`users/${OWNER}`, { name: 'Z', dateOfBirth: ts() });
    await assertSucceeds(getDoc(doc(unverifiedDb(), collPath(OWNER, 'workouts'))));
    await assertSucceeds(getDoc(doc(unverifiedDb(), `users/${OWNER}`)));
  });

  it('a verified address writes normally', async () => {
    await assertSucceeds(
      setDoc(doc(verifiedDb(), collPath(OWNER, 'workouts')), valid.workouts),
    );
    await assertSucceeds(
      setDoc(doc(verifiedDb(), `users/${OWNER}`), { name: 'Z', dateOfBirth: ts() }),
    );
  });

  it('an unverified address may still record its own auth activity', async () => {
    // The deliberate exception: an unverified account still signs in, and
    // those sign-ins are the ones most worth having in the log. Gating the
    // audit trail on verification would blind it exactly where it matters.
    await assertSucceeds(setDoc(
      doc(unverifiedDb(), `users/${OWNER}/authEvents/e1`),
      { schemaVersion: 1, type: 'signIn', occurredAt: serverTimestamp() },
    ));
    await assertSucceeds(setDoc(
      doc(unverifiedDb(), `users/${OWNER}/auth/account`),
      { schemaVersion: 1, signInCount: 1 },
    ));
  });
});

// --- the profile document's own shape ---------------------------------------
describe('users/{uid} profile shape validation', () => {
  const write = (data) => setDoc(doc(ownerDb(), `users/${OWNER}`), data);

  it('accepts the shape the app actually writes', async () => {
    await assertSucceeds(write({
      name: 'Ziad', dateOfBirth: ts(), photoPath: 'media/a.jpg',
      bio: 'lifts things', updatedAt: serverTimestamp(),
    }));
  });

  it('accepts a profile with no photo or bio — both are optional', async () => {
    await assertSucceeds(write({
      name: 'Ziad', dateOfBirth: ts(), photoPath: null, bio: null,
    }));
  });

  it('requires a non-empty name and a real date of birth', async () => {
    await assertFails(write({ name: '', dateOfBirth: ts() }));
    await assertFails(write({ dateOfBirth: ts() }));
    await assertFails(write({ name: 'Ziad', dateOfBirth: '1999-01-01' }));
    await assertFails(write({ name: 'Ziad' }));
  });

  it('bounds the free-text fields', async () => {
    await assertFails(write({ name: 'x'.repeat(121), dateOfBirth: ts() }));
    await assertFails(write({ name: 'Z', dateOfBirth: ts(), bio: 'x'.repeat(501) }));
  });

  it('rejects unknown fields smuggled onto the profile', async () => {
    // This document is the only PII in the database and used to be guarded by
    // a bare `allow read, write`. Anything not in the vocabulary is refused.
    await assertFails(write({ name: 'Z', dateOfBirth: ts(), role: 'admin' }));
    await assertFails(write({ name: 'Z', dateOfBirth: ts(), blob: 'x'.repeat(2000) }));
  });

  it('nobody may delete the profile from a client', async () => {
    // Account deletion runs server-side (recursiveDelete, Admin SDK). A client
    // delete would strand every feature subcollection under a document that no
    // longer describes anyone.
    await seed(`users/${OWNER}`, { name: 'Z', dateOfBirth: ts() });
    await assertFails(deleteDoc(doc(ownerDb(), `users/${OWNER}`)));
  });
});

// --- the audit trail cannot be decorated or forged --------------------------
describe('auth summary: server-authored fields are not client-writable', () => {
  const acct = `users/${OWNER}/auth/account`;

  it('a client cannot stamp emailVerifiedAt on create', async () => {
    await assertFails(setDoc(doc(ownerDb(), acct), {
      schemaVersion: 1, signInCount: 1, emailVerifiedAt: ts(),
    }));
    await assertFails(setDoc(doc(ownerDb(), acct), {
      schemaVersion: 1, signInCount: 1, emailLastSentAt: ts(),
    }));
  });

  it('a client cannot change or remove emailVerifiedAt on update', async () => {
    // `hasOnly` alone cannot express this: on a merge, request.resource.data is
    // the RESULTING document, so the server-authored field has to be allowed
    // in the vocabulary. Immutability is stated separately.
    await seed(acct, { schemaVersion: 1, signInCount: 1, emailVerifiedAt: ts() });
    await assertFails(updateDoc(doc(ownerDb(), acct), {
      emailVerifiedAt: Timestamp.fromDate(new Date('2020-01-01T00:00:00Z')),
    }));
  });

  it('a client CAN advance its own sign-in bookkeeping alongside them', async () => {
    await seed(acct, { schemaVersion: 1, signInCount: 1, emailVerifiedAt: ts() });
    await assertSucceeds(updateDoc(doc(ownerDb(), acct), {
      signInCount: 2, lastSignInAt: serverTimestamp(),
    }));
  });

  it('rejects unknown fields and a negative sign-in count', async () => {
    await assertFails(setDoc(doc(ownerDb(), acct), {
      schemaVersion: 1, isAdmin: true,
    }));
    await assertFails(setDoc(doc(ownerDb(), acct), {
      schemaVersion: 1, signInCount: -1,
    }));
  });
});

describe('authEvents entries cannot carry arbitrary payload', () => {
  it('rejects unknown fields on an otherwise valid event', async () => {
    // An append-only log whose entries accept anything is an unbounded,
    // client-controlled write channel wearing an audit trail's clothes.
    await assertFails(setDoc(doc(ownerDb(), `users/${OWNER}/authEvents/e1`), {
      schemaVersion: 1, type: 'signIn', occurredAt: serverTimestamp(),
      payload: 'x'.repeat(5000),
    }));
  });
});

// --- the paid-endpoint quota counters ---------------------------------------
describe('quotas are Functions-only (owner may read, no client may write)', () => {
  const bucket = `users/${OWNER}/quotas/workoutImport`;

  it('owner can read their counter but cannot write one', async () => {
    // A client that could write its own counter could reset it — which is the
    // entire ceiling gone.
    await seed(bucket, { dayKey: '2026-09-02', used: 3 });
    await assertSucceeds(getDoc(doc(ownerDb(), bucket)));
    await assertFails(setDoc(doc(ownerDb(), bucket), { dayKey: '2026-09-02', used: 0 }));
    await assertFails(updateDoc(doc(ownerDb(), bucket), { used: 0 }));
    await assertFails(deleteDoc(doc(ownerDb(), bucket)));
  });

  it('a different signed-in user cannot read it', async () => {
    await seed(bucket, { dayKey: '2026-09-02', used: 3 });
    await assertFails(getDoc(doc(otherDb(), bucket)));
  });
});
