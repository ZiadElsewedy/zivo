/**
 * LIVE TEXT — what a streaming turn sends to the screen, and the one rule
 * behind it: **the user never sees a reply start over.**
 *
 * The screen holds one growing text. It used to grow by appending every
 * model delta, which broke in two ways that both read as "the answer
 * restarted from the beginning":
 *
 *   1. RETRY — a transient provider failure after partial output is retried
 *      on the same provider (`../routing/router.js`). The retry streams the
 *      answer again from its first word, and those words were appended after
 *      the half answer already on screen.
 *   2. RESTATEMENT — a step writes a lead-in and calls a tool ("أيوه، بناءً
 *      على جدولك…"), and the next step opens its answer with the same words
 *      (Gemini does this readily). Both were streamed, and both were saved.
 *
 * This keeps a mirror of what the client shows — one segment per agent step,
 * joined by a blank line, exactly as `turn.js` joins the saved reply — and
 * when new text would duplicate a segment already on screen it HOLDS it back
 * (the client already shows those words) until the text either diverges or
 * finishes, then sends ONE `{type:'replace', text}` snapshot of the whole
 * reply. The client keeps the prefix it shares with the snapshot, so a retry
 * that reproduces the same words continues seamlessly and one that doesn't
 * rewinds only to where it differs. A restated lead-in is dropped from the
 * screen and (`restatedPrevious`) from the saved reply, so the two stay
 * identical.
 *
 * `replace` is only sent to a client that says it understands it (`aiChat`'s
 * `streamReplace`); for any other the stream is the plain append it always
 * was — an old app keeps its old behaviour rather than getting a snapshot it
 * would ignore.
 *
 * Also owns the delta shaping `turn.js` used to do inline: a step's leading
 * whitespace is dropped, a later step opens with the paragraph break, and
 * trailing whitespace is held back until more text follows it — so the words
 * streamed are the words saved (which are trimmed).
 *
 * Pure: no I/O; `emit` is `turn.js`'s event sink.
 */

/**
 * How many opening characters a step must share with the previous step's
 * text (or all of it, if that is shorter) to count as restating it. Long
 * enough that two different paragraphs don't match by chance.
 * @const {number}
 */
const RESTATE_MIN_CHARS = 16;

/**
 * @param {string} a
 * @param {string} b
 * @return {number} The length of the prefix `a` and `b` share.
 */
function commonPrefixLength(a, b) {
  const n = Math.min(a.length, b.length);
  let i = 0;
  while (i < n && a.charCodeAt(i) === b.charCodeAt(i)) i++;
  return i;
}

/**
 * Whether `next` opens by restating `prev` — the rule both the live stream
 * and a buffered turn apply, so a restated lead-in is dropped either way.
 * @param {?string} prev An earlier step's text.
 * @param {?string} next The following step's text.
 * @return {boolean}
 */
function restates(prev, next) {
  if (!prev || !next) return false;
  return commonPrefixLength(prev, next) >=
    Math.min(RESTATE_MIN_CHARS, prev.length);
}

/** The streamed reply of one turn, mirrored. */
class LiveText {
  /**
   * @param {function(!Object): void} emit The turn's event sink.
   * @param {{replace: boolean}=} opts `replace`: the client applies
   *   `{type:'replace'}` snapshots. Without it, text is only ever appended.
   */
  constructor(emit, opts = {}) {
    this._emit = emit;
    this._replace = opts.replace === true;
    /** Earlier steps' text as the client shows it. @type {!Array<string>} */
    this._prev = [];
    this._resetStep();
  }

  /** @private */
  _resetStep() {
    // This step's text as the client shows it.
    this._shown = "";
    this._resetAttempt();
    /**
     * What this step's text may be reproducing, held back while it does:
     * `{kind: 'restate'|'retry', ghost: string}`.
     * @type {?{kind: string, ghost: string}}
     */
    this._hold = null;
    this._restated = false;
  }

  /** @private */
  _resetAttempt() {
    // This attempt's text so far, shaped (no leading or trailing space).
    this._text = "";
    this._started = false;
    this._heldSpace = "";
  }

  /** The whole reply as the client should show it now. @return {string} */
  get text() {
    return this._prev.concat(this._shown ? [this._shown] : []).join("\n\n");
  }

  /**
   * Whether the step that just ended restated the one before it — its text
   * was dropped from the screen, so `turn.js` drops it from the saved reply.
   * @return {boolean}
   */
  get restatedPrevious() {
    return this._restated;
  }

  /** A new agent step is about to call the model. */
  beginStep() {
    if (this._shown) this._prev.push(this._shown);
    this._resetStep();
    if (this._replace && this._prev.length > 0) {
      this._hold = {kind: "restate", ghost: this._prev[this._prev.length - 1]};
    }
  }

  /**
   * A text delta from the model, for the current attempt of this step.
   * @param {string} raw
   */
  push(raw) {
    let t = String(raw || "");
    if (!this._started) {
      t = t.replace(/^\s+/, "");
      if (!t) return;
      this._started = true;
    }
    t = this._heldSpace + t;
    const tail = /\s+$/.exec(t);
    this._heldSpace = tail ? tail[0] : "";
    if (tail) t = t.slice(0, t.length - this._heldSpace.length);
    if (!t) return;
    this._text += t;
    this._sync(false);
  }

  /**
   * The router is re-running this step after a transient failure: the text
   * the failed attempt streamed is superseded by whatever the retry writes.
   */
  retry() {
    // An app that can't take a snapshot keeps the plain append.
    if (!this._replace) return;
    this._resetAttempt();
    // Already holding back a restatement of the previous step (nothing of
    // this step on screen yet): the retry is measured against the same text.
    if (this._hold && this._hold.kind === "restate" && !this._shown) return;
    this._hold = this._shown ? {kind: "retry", ghost: this._shown} : null;
  }

  /**
   * The router moved this step to another model (the cross-provider
   * fallback, off today): the client drops the step's text on the
   * `fallback` event itself; a snapshot makes that exact.
   */
  fallback() {
    this._shown = "";
    this._resetAttempt();
    this._hold = null;
    if (this._replace) this._emit({type: "replace", text: this.text});
  }

  /** The step's model call returned: settle anything still held back. */
  endStep() {
    this._sync(true);
  }

  /**
   * Brings the client up to date with this attempt's text.
   * @param {boolean} final The step is over — nothing more is coming.
   * @private
   */
  _sync(final) {
    const hold = this._hold;
    if (hold) {
      const text = this._text;
      const reproducing = hold.ghost.startsWith(text) &&
        text.length < hold.ghost.length;
      if (hold.kind === "restate") {
        if (reproducing && !final) return;
        this._hold = null;
        if (restates(hold.ghost, text)) {
          // The step is saying again what the previous one said: that text
          // leaves the screen (and the saved reply); this one takes its place.
          this._prev.pop();
          this._restated = true;
          this._shown = text;
          this._emit({type: "replace", text: this.text});
          return;
        }
        // A new paragraph after all — falls through to a plain append.
      } else {
        if (reproducing && !final) return;
        this._hold = null;
        if (text !== this._shown) {
          this._shown = text;
          this._emit({type: "replace", text: this.text});
        }
        return;
      }
    }
    if (this._text.length <= this._shown.length) return;
    let delta = this._text.slice(this._shown.length);
    if (!this._shown && this._prev.length > 0) delta = `\n\n${delta}`;
    this._shown = this._text;
    this._emit({type: "delta", text: delta});
  }
}

module.exports = {LiveText, restates, commonPrefixLength, RESTATE_MIN_CHARS};
