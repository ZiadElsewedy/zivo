/**
 * Offline unit tests for `search_food_product` (`./food_search_product.js`).
 * Both model calls are scripted `AiProvider`-shaped fakes — no network, no
 * Gemini/Anthropic SDK — so this runs under plain `node --test`.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {
  foodSearchToolsByName,
  normalizeCandidates,
  citationsFrom,
} = require("./food_search_product");

const searchFoodProduct = foodSearchToolsByName.get("search_food_product");

/**
 * A fake `AiProvider` whose `generate` returns `response` (or throws
 * `response` if it's an Error), recording every call it received.
 * @param {(!Object|!Error)} response
 * @return {!Object}
 */
function fakeProvider(response) {
  const calls = [];
  return {
    calls,
    async generate(req) {
      calls.push(req);
      if (response instanceof Error) throw response;
      return response;
    },
  };
}

/**
 * A grounded ("ground" call) NormalizedResponse: some text plus one
 * grounding citation.
 * @param {string} text
 * @return {!Object}
 */
function groundResponse(text) {
  return {
    stopReason: "end",
    content: [{type: "text", text}],
    usage: {inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0},
    raw: {
      candidates: [{
        groundingMetadata: {
          groundingChunks: [{web: {uri: "https://example.com/breadway"}}],
        },
      }],
    },
  };
}

/**
 * An extraction-call NormalizedResponse carrying one `emit_food_candidates`
 * tool_use block.
 * @param {!Array<!Object>} candidates Raw candidate objects as the model
 *   would emit them.
 * @return {!Object}
 */
function extractResponse(candidates) {
  return {
    stopReason: "tool_use",
    content: [
      {type: "tool_use", id: "t1", name: "emit_food_candidates", input: {candidates}},
    ],
    usage: {inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0},
    raw: {},
  };
}

test("empty query returns notFound without calling either provider", async () => {
  const foodSearchProvider = fakeProvider(groundResponse("unused"));
  const chatProvider = fakeProvider(extractResponse([]));
  const result = await searchFoodProduct.execute(
      {}, "u1", {query: ""}, new Date(), 0, {foodSearchProvider, chatProvider});
  assert.equal(result.outcome, "notFound");
  assert.equal(foodSearchProvider.calls.length, 0);
  assert.equal(chatProvider.calls.length, 0);
});

test("missing deps returns unavailable without any call", async () => {
  const result = await searchFoodProduct.execute(
      {}, "u1", {query: "BreadWay toast"}, new Date(), 0, undefined);
  assert.equal(result.outcome, "unavailable");
});

test("a found, fully-specified candidate is returned with citations", async () => {
  const foodSearchProvider = fakeProvider(
      groundResponse("BreadWay Whole Wheat Toast: 247 kcal, 9g protein, " +
        "41g carbs, 3.5g fat per 100g, per breadway.com"));
  const chatProvider = fakeProvider(extractResponse([{
    name: "BreadWay Whole Wheat Toast",
    brand: "BreadWay",
    kcalPer100g: 247,
    proteinPer100g: 9,
    carbsPer100g: 41,
    fatPer100g: 3.5,
    servingSize: "1 slice (28 g)",
  }]));

  const result = await searchFoodProduct.execute(
      {}, "u1", {query: "BreadWay toast"}, new Date(), 0,
      {foodSearchProvider, chatProvider});

  assert.equal(result.outcome, "found");
  assert.equal(result.candidates.length, 1);
  const c = result.candidates[0];
  assert.equal(c.name, "BreadWay Whole Wheat Toast");
  assert.equal(c.brand, "BreadWay");
  assert.deepEqual(c.per100g, {kcal: 247, proteinG: 9, carbsG: 41, fatG: 3.5});
  assert.equal(c.servingSize, "1 slice (28 g)");
  assert.deepEqual(c.sourceUrls, ["https://example.com/breadway"]);

  // The ground call must never carry function-calling tools alongside
  // grounding (Gemini rejects the combination) — this tool must not regress
  // that constraint.
  assert.deepEqual(foodSearchProvider.calls[0].grounding, {googleSearch: true});
  assert.equal(foodSearchProvider.calls[0].tools, undefined);
  // The extraction call is the reused chat provider, forced to the one schema
  // tool, with no search access of its own.
  assert.equal(chatProvider.calls[0].toolChoice, "any");
  assert.equal(chatProvider.calls[0].tools[0].name, "emit_food_candidates");
  assert.equal(chatProvider.calls[0].grounding, undefined);
});

test("a candidate missing a macro is dropped, not defaulted to zero", async () => {
  const foodSearchProvider = fakeProvider(groundResponse("some findings"));
  const chatProvider = fakeProvider(extractResponse([
    {name: "Complete Food", kcalPer100g: 200, proteinPer100g: 5, carbsPer100g: 30, fatPer100g: 4},
    // Missing fatPer100g entirely — must be dropped, not treated as 0.
    {name: "Incomplete Food", kcalPer100g: 150, proteinPer100g: 3, carbsPer100g: 20},
  ]));

  const result = await searchFoodProduct.execute(
      {}, "u1", {query: "some food"}, new Date(), 0, {foodSearchProvider, chatProvider});

  assert.equal(result.outcome, "found");
  assert.equal(result.candidates.length, 1);
  assert.equal(result.candidates[0].name, "Complete Food");
});

test("no candidates qualify -> notFound with a create_custom_food hint", async () => {
  const foodSearchProvider = fakeProvider(groundResponse("nothing concrete"));
  const chatProvider = fakeProvider(extractResponse([]));

  const result = await searchFoodProduct.execute(
      {}, "u1", {query: "an obscure product"}, new Date(), 0,
      {foodSearchProvider, chatProvider});

  assert.equal(result.outcome, "notFound");
  assert.match(result.note, /create_custom_food/);
});

test("empty grounded text short-circuits before the extraction call", async () => {
  const foodSearchProvider = fakeProvider(groundResponse(""));
  const chatProvider = fakeProvider(extractResponse([]));

  const result = await searchFoodProduct.execute(
      {}, "u1", {query: "nothing found"}, new Date(), 0,
      {foodSearchProvider, chatProvider});

  assert.equal(result.outcome, "notFound");
  assert.equal(chatProvider.calls.length, 0);
});

test("the ground call failing degrades to unavailable, never a thrown error", async () => {
  const foodSearchProvider = fakeProvider(new Error("Gemini is down"));
  const chatProvider = fakeProvider(extractResponse([]));

  const result = await searchFoodProduct.execute(
      {}, "u1", {query: "BreadWay toast"}, new Date(), 0,
      {foodSearchProvider, chatProvider});

  assert.equal(result.outcome, "unavailable");
  assert.equal(chatProvider.calls.length, 0);
});

test("the extraction call failing also degrades to unavailable", async () => {
  const foodSearchProvider = fakeProvider(groundResponse("some findings"));
  const chatProvider = fakeProvider(new Error("provider failure"));

  const result = await searchFoodProduct.execute(
      {}, "u1", {query: "BreadWay toast"}, new Date(), 0,
      {foodSearchProvider, chatProvider});

  assert.equal(result.outcome, "unavailable");
});

test("normalizeCandidates caps at 5 and assigns stable sequential ids", () => {
  const raw = Array.from({length: 8}, (_, i) => ({
    name: `Food ${i}`,
    kcalPer100g: 100,
    proteinPer100g: 1,
    carbsPer100g: 1,
    fatPer100g: 1,
  }));
  const out = normalizeCandidates(raw, []);
  assert.equal(out.length, 5);
  assert.deepEqual(out.map((c) => c.id), ["cand-0", "cand-1", "cand-2", "cand-3", "cand-4"]);
});

test("citationsFrom reads up to 3 unique groundingChunk URLs", () => {
  const raw = {
    candidates: [{
      groundingMetadata: {
        groundingChunks: [
          {web: {uri: "https://a.example"}},
          {web: {uri: "https://a.example"}},
          {web: {uri: "https://b.example"}},
          {web: {uri: "https://c.example"}},
          {web: {uri: "https://d.example"}},
        ],
      },
    }],
  };
  assert.deepEqual(
      citationsFrom(raw),
      ["https://a.example", "https://b.example", "https://c.example"]);
});

test("citationsFrom tolerates a response with no grounding metadata", () => {
  assert.deepEqual(citationsFrom({}), []);
  assert.deepEqual(citationsFrom(null), []);
});
