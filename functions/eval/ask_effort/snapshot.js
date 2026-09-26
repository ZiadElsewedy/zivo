/**
 * Snapshots ONE account's coaching data (diet, training, sleep, body,
 * expenses, settings) from production into `fixture/<name>.json` — read-only,
 * run once by the owner. The eval (`run.mjs`) loads it into the Firestore
 * EMULATOR, so every eval turn reads real data and nothing touches prod.
 *
 * Chat history, usage logs and auth records are NOT copied. The fixture is
 * gitignored (it's a real person's data).
 *
 *   node eval/ask_effort/snapshot.js --uid <uid> [--name owner]
 */

const fs = require("node:fs");
const path = require("node:path");
const admin = require("firebase-admin");

// What the Ask tools read. Everything else under users/{uid} stays behind.
const SKIP = new Set(["aiConversations", "aiUsage", "auth", "authEvents",
  "session", "quotas", "media", "moments"]);

/**
 * Firestore values → JSON, Timestamps tagged so the loader can restore them.
 * @param {*} v
 * @return {*}
 */
function encode(v) {
  if (v instanceof admin.firestore.Timestamp) return {__ts: v.toMillis()};
  if (Array.isArray(v)) return v.map(encode);
  if (v && typeof v === "object") {
    const out = {};
    for (const [k, x] of Object.entries(v)) out[k] = encode(x);
    return out;
  }
  return v;
}

/**
 * Every document under `ref`'s collections, recursively, keyed by path
 * relative to the user doc.
 * @param {!Object} ref A DocumentReference.
 * @param {string} base
 * @param {!Object} out
 */
async function dumpCollections(ref, base, out) {
  for (const col of await ref.listCollections()) {
    if (!base && SKIP.has(col.id)) continue;
    for (const doc of (await col.get()).docs) {
      const rel = `${base}${col.id}/${doc.id}`;
      out[rel] = encode(doc.data());
      await dumpCollections(doc.ref, `${rel}/`, out);
    }
  }
}

(async () => {
  const argv = process.argv.slice(2);
  const arg = (k) => {
    const i = argv.indexOf(k);
    return i >= 0 ? argv[i + 1] : undefined;
  };
  const uid = arg("--uid");
  const name = arg("--name") || "owner";
  if (!uid) throw new Error("--uid is required");
  admin.initializeApp({projectId: "zivo-63f15"});
  const userRef = admin.firestore().collection("users").doc(uid);
  const userDoc = await userRef.get();
  const docs = {};
  await dumpCollections(userRef, "", docs);
  const fixture = {
    uid,
    snapshotAt: Date.now(),
    user: userDoc.exists ? encode(userDoc.data()) : null,
    docs,
  };
  const file = path.join(__dirname, "fixture", `${name}.json`);
  fs.writeFileSync(file, JSON.stringify(fixture));
  const byCol = {};
  for (const p of Object.keys(docs)) {
    const c = p.split("/")[0];
    byCol[c] = (byCol[c] || 0) + 1;
  }
  console.log(`wrote ${file} (${Object.keys(docs).length} docs)`, byCol);
})().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
