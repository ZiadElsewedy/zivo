// Security-rules tests for firestore.rules, run against the Firestore emulator.
//
// Run with:  firebase emulators:exec --only firestore --project demo-zivo "npm test"
// (from the repo root). The emulator loads no auth; contexts below supply the
// auth token that the rules gate on.
//
// Covers PLAN §10/§20/§28: deny-by-default, per-user ownership isolation,
// per-collection field validation, and the Functions-only emailOtps lockout —
// for all seven persisted collections plus the user profile doc.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { before, after, beforeEach, describe, it } from 'node:test';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, Timestamp } from 'firebase/firestore';

const here = dirname(fileURLToPath(import.meta.url));
const rules = readFileSync(join(here, '..', 'firestore.rules'), 'utf8');

const OWNER = 'owner-uid';
const OTHER = 'other-uid';
const ts = () => Timestamp.fromDate(new Date('2026-01-01T00:00:00Z'));

// Valid payloads that satisfy each collection's field validation.
const valid = {
  tasks: { title: 'T', done: false, priority: false, schemaVersion: 1 },
  expenses: { amountMinor: 100, currency: 'EGP', category: 'food', spentAt: ts(), schemaVersion: 1 },
  schedule: { title: 'E', start: ts(), schemaVersion: 1 },
  notes: { body: 'B', updatedAt: ts(), schemaVersion: 1 },
  workouts: { title: 'W', performedAt: ts(), exercises: [], schemaVersion: 1 },
  moments: { caption: 'M', takenAt: ts(), schemaVersion: 1 },
  universityItems: { title: 'U', type: 'assignment', done: false, schemaVersion: 1 },
};

// Each violates exactly one validation clause of its collection's write rule.
const invalid = {
  tasks: { title: 'T', done: false, priority: false }, // missing schemaVersion
  expenses: { amountMinor: -5, currency: 'EGP', category: 'food', spentAt: ts(), schemaVersion: 1 }, // amount < 0
  schedule: { title: 123, start: ts(), schemaVersion: 1 }, // title not a string
  notes: { body: 'B', updatedAt: 'not-a-timestamp', schemaVersion: 1 }, // updatedAt not a timestamp
  workouts: { title: 'W', performedAt: ts(), exercises: 'nope', schemaVersion: 1 }, // exercises not a list
  moments: { caption: 'M', takenAt: ts() }, // missing schemaVersion
  universityItems: { title: 'U', type: 'assignment', done: 'yes', schemaVersion: 1 }, // done not a bool
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
    await assertFails(setDoc(doc(anonDb(), collPath(OWNER, 'tasks')), valid.tasks));
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

describe('tasks update path (mirrors setDone)', () => {
  it('owner can flip done on an existing valid doc; non-owner cannot', async () => {
    await seed(collPath(OWNER, 'tasks'), valid.tasks);
    await assertSucceeds(updateDoc(doc(ownerDb(), collPath(OWNER, 'tasks')), { done: true }));
    await assertFails(updateDoc(doc(otherDb(), collPath(OWNER, 'tasks')), { done: true }));
  });
});
