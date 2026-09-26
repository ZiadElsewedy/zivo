#!/usr/bin/env node
/**
 * Grants or revokes the `admin` custom claim — the ONLY way an account
 * becomes a ZIVO admin (ADR-018). Deliberately not reachable from any app or
 * callable: role changes are an owner action with owner credentials.
 *
 *   node scripts/set-admin.js grant  someone@example.com
 *   node scripts/set-admin.js revoke someone@example.com
 *
 * Needs Application Default Credentials for project zivo-63f15
 * (`gcloud auth application-default login`). The admin must sign out and
 * back in afterwards so their ID token carries the new claim.
 */

const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");

const main = async () => {
  const [action, email] = process.argv.slice(2);
  if (!["grant", "revoke"].includes(action) || !email) {
    console.error("usage: set-admin.js grant|revoke <email>");
    process.exit(2);
  }
  initializeApp({projectId: process.env.GCLOUD_PROJECT || "zivo-63f15"});
  const auth = getAuth();
  const user = await auth.getUserByEmail(email);
  const claims = Object.assign({}, user.customClaims);
  if (action === "grant") claims.admin = true;
  else delete claims.admin;
  await auth.setCustomUserClaims(user.uid, claims);
  // A revoked admin must not keep a token that still says admin. (The
  // callables re-check the Auth record anyway; this also ends the session.)
  if (action === "revoke") await auth.revokeRefreshTokens(user.uid);
  console.log(`${action === "grant" ? "Granted" : "Revoked"} admin: ` +
    `${user.uid}`);
};

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
