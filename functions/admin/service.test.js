const test = require("node:test");
const assert = require("node:assert/strict");
const {AdminService, AdminError} = require("./service");

/**
 * A fake Auth with the three calls the guards use.
 * @param {!Object<string, !Object>} users
 * @return {!Object}
 */
function fakeAuth(users) {
  const calls = [];
  return {
    calls,
    getUser: async (uid) => {
      if (!users[uid]) {
        const err = new Error("nope");
        err.code = "auth/user-not-found";
        throw err;
      }
      return Object.assign({uid, metadata: {}}, users[uid]);
    },
    updateUser: async (uid, patch) => calls.push(["updateUser", uid, patch]),
    revokeRefreshTokens: async (uid) => calls.push(["revoke", uid]),
  };
}

const ADMIN = {admin: {customClaims: {admin: true}}};
const adminAuth = {uid: "admin", token: {admin: true}};

/**
 * @param {!Object} auth
 * @return {!AdminService}
 */
function service(auth) {
  const svc = new AdminService({
    db: null, auth, FieldValue: {}, AggregateField: {},
    now: () => Date.parse("2026-09-25T12:00:00Z"),
  });
  // The Firestore side of recordEvent/audit is exercised by the emulator;
  // here it is a recorder.
  svc.recorded = [];
  svc.recordEvent = async (uid, event) => svc.recorded.push([uid, event.name]);
  svc._audit = async (actor, action, target) =>
    svc.recorded.push(["audit", actor, action, target]);
  return svc;
}

const rejects = (promise, code) => assert.rejects(promise, (err) =>
  err instanceof AdminError && err.code === code);

test("no auth, or no admin claim, is refused", async () => {
  const svc = service(fakeAuth(ADMIN));
  await rejects(svc.assertAdmin(null), "unauthenticated");
  await rejects(svc.assertAdmin({uid: "u", token: {}}), "permission-denied");
});

test("a claim the Auth record no longer backs is refused", async () => {
  // The token still says admin, but the claim was revoked server-side.
  const svc = service(fakeAuth({admin: {customClaims: {}}}));
  await rejects(svc.assertAdmin(adminAuth), "permission-denied");
});

test("a disabled admin is refused", async () => {
  const svc = service(fakeAuth(
      {admin: {customClaims: {admin: true}, disabled: true}}));
  await rejects(svc.assertAdmin(adminAuth), "permission-denied");
});

test("a real admin passes", async () => {
  const svc = service(fakeAuth(ADMIN));
  assert.equal(await svc.assertAdmin(adminAuth), "admin");
});

test("disabling revokes sessions, records it and audits it", async () => {
  const auth = fakeAuth(Object.assign({u1: {}}, ADMIN));
  const svc = service(auth);
  assert.deepEqual(await svc.setDisabled("admin", {uid: "u1", disabled: true}),
      {status: "disabled"});
  assert.deepEqual(auth.calls, [
    ["updateUser", "u1", {disabled: true}],
    ["revoke", "u1"],
  ]);
  assert.deepEqual(svc.recorded, [
    ["u1", "account_disabled"],
    ["audit", "admin", "account_disabled", "u1"],
  ]);
});

test("re-enabling does not revoke", async () => {
  const auth = fakeAuth(Object.assign({u1: {disabled: true}}, ADMIN));
  const svc = service(auth);
  await svc.setDisabled("admin", {uid: "u1", disabled: false});
  assert.deepEqual(auth.calls, [["updateUser", "u1", {disabled: false}]]);
});

test("an admin can't manage themselves or another admin", async () => {
  const svc = service(fakeAuth(Object.assign(
      {other: {customClaims: {admin: true}}}, ADMIN)));
  await rejects(svc.setDisabled("admin", {uid: "admin", disabled: true}),
      "failed-precondition");
  await rejects(svc.setDisabled("admin", {uid: "other", disabled: true}),
      "failed-precondition");
});

test("ids from the client are validated before use", async () => {
  const svc = service(fakeAuth(ADMIN));
  await rejects(svc.setDisabled("admin", {uid: "a/b", disabled: true}),
      "invalid-argument");
  await rejects(svc.userDetail("../x"), "invalid-argument");
});

test("delete needs the uid repeated, then runs the shared erasure",
    async () => {
      const svc = service(fakeAuth(Object.assign({u1: {}}, ADMIN)));
      const erased = [];
      const erase = async (uid) => erased.push(uid);
      await rejects(svc.deleteUser("admin", {uid: "u1"}, erase),
          "failed-precondition");
      assert.deepEqual(erased, []);
      assert.deepEqual(
          await svc.deleteUser("admin", {uid: "u1", confirmUid: "u1"}, erase),
          {status: "deleted"});
      assert.deepEqual(erased, ["u1"]);
    });

test("a missing account can't be deleted", async () => {
  const svc = service(fakeAuth(ADMIN));
  await rejects(svc.deleteUser("admin", {uid: "ghost", confirmUid: "ghost"},
      async () => undefined), "not-found");
});

test("out-of-order events never move activity backwards", () => {
  const svc = service(fakeAuth(ADMIN));
  svc.FieldValue = {increment: (n) => ({inc: n}), serverTimestamp: () => "ts"};
  const later = new Date("2026-09-25T12:00:00Z");
  const earlier = new Date("2026-09-24T12:00:00Z");
  const fields = svc._patchFields({lastActiveAt: later},
      {name: "workout_completed", props: {}}, earlier);
  assert.equal(fields.lastActiveAt, undefined);
  assert.deepEqual(fields.workoutsCompleted, {inc: 1});
  assert.equal(fields.lastWorkoutAt, earlier);
});

/**
 * A fake Firestore holding just the summaries ensureSummary touches.
 * @param {!Set<string>} existing Summary uids that already exist.
 * @param {boolean=} raceOnCreate Whether create() loses to another trigger.
 * @return {!Object}
 */
function fakeSummaryDb(existing, raceOnCreate = false) {
  const created = [];
  return {
    created,
    collection: (name) => ({
      doc: (uid) => ({
        get: async () => ({
          exists: name === "adminUsers" && existing.has(uid),
          data: () => (name === "users" ? {name: "Sam"} : undefined),
        }),
        create: async (doc) => {
          if (raceOnCreate) {
            const err = new Error("exists");
            err.code = 6;
            throw err;
          }
          created.push(doc);
        },
      }),
    }),
  };
}

test("seeding a summary records account_created at the Auth time", async () => {
  const svc = service(fakeAuth({u1: {
    email: "sam@example.com",
    metadata: {creationTime: "2026-09-20T08:00:00Z"},
  }}));
  svc.db = fakeSummaryDb(new Set());
  const at = [];
  svc.recordEvent = async (uid, event, opts) =>
    at.push([uid, event.name, opts]);
  assert.equal(await svc.ensureSummary("u1"), true);
  assert.equal(svc.db.created.length, 1);
  assert.deepEqual(at, [["u1", "account_created",
    {sourceId: "u1", at: new Date("2026-09-20T08:00:00Z")}]]);
});

test("an existing summary, or a lost create race, records nothing", async () => {
  for (const db of [fakeSummaryDb(new Set(["u1"])),
    fakeSummaryDb(new Set(), true)]) {
    const svc = service(fakeAuth({u1: {}}));
    svc.db = db;
    assert.equal(await svc.ensureSummary("u1"), true);
    assert.deepEqual(svc.recorded, []);
  }
});

test("a deleted account gets no summary and no event", async () => {
  const svc = service(fakeAuth({}));
  svc.db = fakeSummaryDb(new Set());
  assert.equal(await svc.ensureSummary("gone"), false);
  assert.deepEqual(svc.db.created, []);
  assert.deepEqual(svc.recorded, []);
});
