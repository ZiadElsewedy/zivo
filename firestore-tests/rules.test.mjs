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
  dietEntries: { dayKey: '2026-01-01', mealId: 'm1', eaten: true, schemaVersion: 1 },
  workoutPlans: { name: 'PPL', status: 'active', source: 'manual', days: [], cycleCursor: 0, schemaVersion: 1 },
  workoutMeta: { activeSplitId: 'plan1' },
  workoutSessions: { dayLabel: 'Push', status: 'active', startedAt: ts(), exercises: [], schemaVersion: 1 },
  bodyWeightEntries: { weightKg: 82.5, loggedAt: ts(), schemaVersion: 1 },
  aiConversations: { title: 'Chat', schemaVersion: 1 },
  expenseCategories: { label: 'Subs', iconId: 'bills', hue: 'iris' },
};

// Each violates exactly one validation clause of its collection's write rule.
const invalid = {
  expenses: { amountMinor: -5, currency: 'EGP', category: 'food', spentAt: ts(), schemaVersion: 1 }, // amount < 0
  workouts: { title: 'W', performedAt: ts(), exercises: 'nope', schemaVersion: 1 }, // exercises not a list
  moments: { caption: 'M', takenAt: ts() }, // missing schemaVersion
  dietPlans: { name: 'Cut', status: 'active', days: 'nope', schemaVersion: 1 }, // days not a list
  dietEntries: { dayKey: '2026-01-01', mealId: 'm1', eaten: 'yes', schemaVersion: 1 }, // eaten not bool
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

