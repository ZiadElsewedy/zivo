/**
 * The chat subsystem's error type + id guard.
 *
 * `GatewayError` is re-exported from `gateway.js`, so it stays importable as
 * `require("../gateway").GatewayError` by `workout_import.js`, `diet_import.js`
 * and `diet_generate.js` — moving it here changes no call site. Its `code` is a
 * gRPC-style string (e.g. "invalid-argument") the `onCall` handler maps to an
 * `HttpsError`.
 */

const {isDocumentId} = require("../../shared/ids");

/**
 * An error `runAiTurn`/`confirmAction`/`cancelAction` throw for problems the
 * caller (the `aiChat` `onCall` handler) should surface as an `HttpsError` with
 * a matching gRPC-style `code` (e.g. `"invalid-argument"`).
 */
class GatewayError extends Error {
  /**
   * @param {string} code
   * @param {string} message
   */
  constructor(code, message) {
    super(message);
    this.name = "GatewayError";
    this.code = code;
  }
}

/**
 * Asserts [value] is usable as a single Firestore document id, so a
 * client-supplied id can never be read as a deeper path by `.doc()`. See
 * ../../shared/ids.js for why that matters on the Admin-SDK side.
 * @param {*} value
 * @param {string} field Field name for the error message.
 * @return {string} The validated id.
 */
function assertDocumentId(value, field) {
  if (!isDocumentId(value)) {
    throw new GatewayError("invalid-argument", `${field} is required.`);
  }
  return value;
}

module.exports = {GatewayError, assertDocumentId};
