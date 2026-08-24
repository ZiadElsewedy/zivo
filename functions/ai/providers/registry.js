/**
 * A `name → AiProvider instance` lookup, used by `../routing/router.js` to
 * resolve a capability's route into an actual provider without either side
 * hardcoding the other.
 */
class ProviderRegistry {
  /**
   * Creates an empty registry — register providers with `.register()`.
   */
  constructor() {
    /** @private @const {!Map<string, !Object>} */
    this._providers = new Map();
  }

  /**
   * @param {string} name
   * @param {!Object} provider An `AiProvider`-shaped instance.
   * @return {!ProviderRegistry} `this`, for chaining registrations.
   */
  register(name, provider) {
    this._providers.set(name, provider);
    return this;
  }

  /**
   * @param {string} name
   * @return {!Object} The registered provider.
   * @throws {Error} If nothing is registered under `name`.
   */
  get(name) {
    const provider = this._providers.get(name);
    if (!provider) throw new Error(`Unknown AI provider: ${name}`);
    return provider;
  }

  /**
   * @param {string} name
   * @return {boolean}
   */
  has(name) {
    return this._providers.has(name);
  }
}

module.exports = {ProviderRegistry};
