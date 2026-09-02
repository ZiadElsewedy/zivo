/**
 * ZIVO — client-supplied identifier validation.
 *
 * WHY THIS EXISTS. Firestore's `.doc(x)` accepts a slash-bearing string and
 * resolves it as a deeper PATH, not as a literal id. So any handler that takes
 * an id from the client and hands it straight to `.doc()` lets the client pick
 * where the write lands. For Admin-SDK code — which bypasses the security
 * rules entirely — that means a client can steer server-trusted writes (and,
 * in `aiDeleteConversation`, a `recursiveDelete`) to a location the rules were
 * never consulted about.
 *
 * The blast radius was always confined to the caller's own `users/{uid}`
 * subtree, because Firestore paths have no parent traversal — there is no
 * "..". So this was never a cross-tenant hole. But "the client chooses where
 * rule-exempt writes go" is not a property to leave lying around, and the fix
 * is one regex.
 *
 * Kept dependency-free and in `shared/` rather than beside its first caller,
 * so the AI gateway and the auth/account callables validate ids the same way.
 */

/**
 * A single Firestore path SEGMENT. Deliberately stricter than Firestore's own
 * rules (which also permit `.`, unicode, and much more): every id the app
 * actually mints is UUID-ish or a slug, so the narrow set is free to enforce
 * and leaves no room for surprises. 128 chars is generous for that.
 */
const DOCUMENT_ID_RE = /^[A-Za-z0-9_-]{1,128}$/;

/**
 * Whether [value] is usable as a single Firestore document id.
 * @param {*} value
 * @return {boolean}
 */
const isDocumentId = (value) =>
  typeof value === "string" && DOCUMENT_ID_RE.test(value);

module.exports = {
  DOCUMENT_ID_RE,
  isDocumentId,
};
