/**
 * Bridges the pre-provider-abstraction `callModel`/`streamModel` injected
 * seams (still used by `../gateway.js`'s and `../workout_import.js`'s own
 * unit tests, and by any caller that hasn't been updated to inject a
 * `provider` directly) into the `{messages: {create, stream}}` client shape
 * `AnthropicProvider` expects — the same shape a real `Anthropic` SDK
 * instance exposes.
 *
 * `callModel(req)` already matches `messages.create(req)` exactly, so it
 * passes straight through. `streamModel(req, onText)` resolves directly to
 * the final message, whereas the real SDK's `messages.stream(req)` returns a
 * `MessageStream` object exposing `.on("text", cb)`/`.finalMessage()`; the
 * wrapper here fakes that shape so `AnthropicProvider.generate` can drive
 * both identically.
 */

/**
 * @param {function(!Object): !Promise<!Object>} callModel
 * @param {(function(!Object, function(string): void): !Promise<!Object>)=}
 *   streamModel
 * @return {!Object} An `AnthropicClient`-shaped object (see
 *   `./anthropic_provider.js`).
 */
function legacyAnthropicClient(callModel, streamModel) {
  return {
    messages: {
      create: (req) => callModel(req),
      stream: streamModel && ((req) => {
        let textHandler = null;
        return {
          on: (event, cb) => {
            if (event === "text") textHandler = cb;
          },
          finalMessage: () =>
            streamModel(req, (delta) => {
              if (textHandler) textHandler(delta);
            }),
        };
      }),
    },
  };
}

module.exports = {legacyAnthropicClient};
