/**
 * Unit tests for ./auth/activity.js — the server-side auth-metadata writer.
 * Run with: node --test auth/activity.test.js (from functions/).
 *
 * The module is a thin Firestore writer; these tests use a hand-rolled stub
 * that records every write and asserts the exact shapes that land in
 * users/{uid}/auth/account and users/{uid}/authEvents — the contract the
 * client reader (AccountAuthMetadata) depends on.
 */

const {test} = require("node:test");
const assert = require("node:assert/strict");

const {
  markEmailSent,
  markEmailVerified,
  markPasswordChanged,
  recordAuthEvent,
} = require("./activity");

/**
 * A minimal Firestore stub capturing collection/doc/set/add calls.
 * @return {{db: !Object, writes: {sets: !Array<!Object>,
 *     adds: !Array<!Object>}}} The stub db and captured writes.
 */
function stubDb() {
  const writes = {sets: [], adds: []};
  const db = {
    collection: (name) => ({
      doc: (id) => ({
        id,
        collection: (sub) => ({
          doc: (subId) => ({
            set: async (data, opts) => {
              writes.sets.push({path: `${name}/${id}/${sub}/${subId}`, data,
                opts});
            },
          }),
          add: async (data) => {
            writes.adds.push({path: `${name}/${id}/${sub}`, data});
          },
        }),
      }),
    }),
  };
  return {db, writes};
}

test("markEmailSent writes emailLastSentAt + an emailOtpSent event", async () => {
  const {db, writes} = stubDb();

  await markEmailSent(db, "u1");

  assert.equal(writes.sets.length, 1);
  const set = writes.sets[0];
  assert.equal(set.path, "users/u1/auth/account");
  assert.ok(set.opts.merge);
  assert.equal(set.data.schemaVersion, 1);
  assert.ok(set.data.emailLastSentAt instanceof Date);

  assert.equal(writes.adds.length, 1);
  const event = writes.adds[0];
  assert.equal(event.path, "users/u1/authEvents");
  assert.equal(event.data.type, "emailOtpSent");
  assert.equal(event.data.schemaVersion, 1);
  assert.ok(event.data.occurredAt instanceof Date);
  // Server-written events carry no provider/platform.
  assert.equal(event.data.provider, undefined);
});

test("markEmailVerified writes emailVerifiedAt + an emailVerified event",
    async () => {
      const {db, writes} = stubDb();

      await markEmailVerified(db, "u2");

      const set = writes.sets[0];
      assert.equal(set.path, "users/u2/auth/account");
      assert.ok(set.data.emailVerifiedAt instanceof Date);
      assert.equal(set.data.emailLastSentAt, undefined);

      const event = writes.adds[0];
      assert.equal(event.path, "users/u2/authEvents");
      assert.equal(event.data.type, "emailVerified");
    });

test("markPasswordChanged writes lastPasswordChangeAt + a passwordChanged event",
    async () => {
      const {db, writes} = stubDb();

      await markPasswordChanged(db, "u5");

      const set = writes.sets[0];
      assert.equal(set.path, "users/u5/auth/account");
      assert.ok(set.data.lastPasswordChangeAt instanceof Date);
      assert.equal(set.data.emailVerifiedAt, undefined);

      const event = writes.adds[0];
      assert.equal(event.path, "users/u5/authEvents");
      assert.equal(event.data.type, "passwordChanged");
      assert.equal(event.data.provider, "password");
    });

test("recordAuthEvent carries an optional provider", async () => {
  const {db, writes} = stubDb();

  await recordAuthEvent(db, "u3", "passwordChanged", {provider: "password"});

  const event = writes.adds[0];
  assert.equal(event.data.type, "passwordChanged");
  assert.equal(event.data.provider, "password");
});

test("recordAuthEvent omits provider when not given", async () => {
  const {db, writes} = stubDb();
  await recordAuthEvent(db, "u4", "signOut");
  assert.equal(writes.adds[0].data.provider, undefined);
});
