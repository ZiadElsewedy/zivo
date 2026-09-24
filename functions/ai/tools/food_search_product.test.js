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
  isConsistent,
  matchesAll,
} = require("./food_search_product");

const searchFoodProduct = foodSearchToolsByName.get("search_food_product");

/** @const {!Object} A zeroed `NormalizedUsage` — irrelevant to these tests. */
const NO_USAGE = {
  inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0,
};

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
    usage: NO_USAGE,
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
      {
        type: "tool_use", id: "t1", name: "emit_food_candidates",
        input: {candidates},
      },
    ],
    usage: NO_USAGE,
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

test("nothing wired and nothing saved is notFound, with an ask-for-the-label " +
    "note", async () => {
  const result = await searchFoodProduct.execute(
      {}, "u1", {query: "BreadWay toast"}, new Date(), 0, undefined);
  assert.equal(result.outcome, "notFound");
  assert.match(result.note, /nutrition label/);
  assert.match(result.note, /Never estimate/);
});

test("a found, fully-specified candidate is returned — with no URLs for the " +
    "model to show", async () => {
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
  assert.equal(c.sourceUrls, undefined);

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
    kcalPer100g: 98,
    proteinPer100g: 10,
    carbsPer100g: 10,
    fatPer100g: 2,
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

/**
 * A fake `fetch` answering the product-database lookup with `products`.
 * @param {!Array<!Object>} products
 * @return {!Function}
 */
function fakeFetch(products) {
  const f = async (url) => {
    f.urls.push(url);
    return {ok: true, json: async () => ({products})};
  };
  f.urls = [];
  return f;
}

/**
 * An Open Food Facts-shaped product row.
 * @param {string} name
 * @param {string} brands
 * @param {!Array<number>} figures kcal, protein, carbs, fat per 100 g.
 * @return {!Object}
 */
function offProduct(name, brands, [kcal, p, c, f]) {
  return {
    product_name: name,
    brands,
    serving_size: "1 wrap (90 g)",
    nutriments: {
      "energy-kcal_100g": kcal, "proteins_100g": p,
      "carbohydrates_100g": c, "fat_100g": f,
    },
  };
}

test("a product the user already saved is found first, with its foodId",
    async () => {
      const store = {listCustomFoods: async () => [{
        id: "bw1", name: "BreadWay Tortilla", kcalPer100g: 289,
        proteinPer100g: 6.7, carbsPer100g: 55.6, fatPer100g: 6.7,
      }]};
      const fetch = fakeFetch([]);
      const result = await searchFoodProduct.execute(
          store, "u1", {query: "breadway tortilla"}, new Date(), 0, {fetch});
      assert.equal(result.outcome, "found");
      assert.equal(result.candidates[0].foodId, "custom:bw1");
      assert.equal(result.candidates[0].alreadySaved, true);
      assert.equal(fetch.urls.length, 0, "no external search needed");
    });

test("the product-label database is searched before the web, and only the " +
    "named product with consistent figures comes back", async () => {
  const fetch = fakeFetch([
    offProduct("Flour Tortilla", "Breadway", [289, 6.7, 55.6, 6.7]),
    // Same brand, impossible label: 40 g fat can't be 282 kcal.
    offProduct("Wholewheat Tortilla", "Breadway", [282, 8, 52.2, 40]),
    // A different brand is not the product asked for.
    offProduct("Flour Tortilla", "Other Bakery", [300, 8, 50, 7]),
  ]);
  const foodSearchProvider = fakeProvider(groundResponse("unused"));
  const chatProvider = fakeProvider(extractResponse([]));
  const result = await searchFoodProduct.execute(
      {}, "u1", {query: "tortilla", brand: "BreadWay"}, new Date(), 0,
      {fetch, foodSearchProvider, chatProvider});
  assert.equal(result.outcome, "found");
  assert.deepEqual(result.candidates.map((c) => [c.brand, c.name]),
      [["Breadway", "Flour Tortilla"]]);
  assert.deepEqual(result.candidates[0].per100g,
      {kcal: 289, proteinG: 6.7, carbsG: 55.6, fatG: 6.7});
  assert.match(fetch.urls[0], /search_terms=BreadWay%20tortilla/);
  assert.equal(foodSearchProvider.calls.length, 0, "web search not needed");
});

test("the database finding nothing falls through to the web search",
    async () => {
      const fetch = fakeFetch([]);
      const foodSearchProvider = fakeProvider(groundResponse("findings"));
      const chatProvider = fakeProvider(extractResponse([]));
      const result = await searchFoodProduct.execute(
          {}, "u1", {query: "zzqx snack"}, new Date(), 0,
          {fetch, foodSearchProvider, chatProvider});
      assert.equal(foodSearchProvider.calls.length, 1);
      assert.equal(result.outcome, "notFound");
    });

test("a database outage is not an error — the web search still runs",
    async () => {
      const fetch = async () => {
        throw new Error("ECONNRESET");
      };
      const foodSearchProvider = fakeProvider(groundResponse("findings"));
      const chatProvider = fakeProvider(extractResponse([]));
      const result = await searchFoodProduct.execute(
          {}, "u1", {query: "zzqx snack"}, new Date(), 0,
          {fetch, foodSearchProvider, chatProvider});
      assert.equal(foodSearchProvider.calls.length, 1);
      assert.equal(result.outcome, "notFound");
    });

test("per-serving label figures are converted to per 100 g by arithmetic",
    () => {
      const [c] = normalizeCandidates([{
        name: "Flour Tortilla", brand: "Breadway",
        perServing: {kcal: 260, proteinG: 6, carbsG: 50, fatG: 6},
        servingGrams: 90,
      }], []);
      assert.deepEqual(c.per100g,
          {kcal: 289, proteinG: 6.7, carbsG: 55.6, fatG: 6.7});
    });

test("per-serving figures without the serving's weight are dropped", () => {
  assert.equal(normalizeCandidates([{
    name: "Flour Tortilla",
    perServing: {kcal: 260, proteinG: 6, carbsG: 50, fatG: 6},
  }], []).length, 0);
});

test("web results for another brand are dropped when a brand was named",
    async () => {
      const foodSearchProvider = fakeProvider(groundResponse("findings"));
      const chatProvider = fakeProvider(extractResponse([
        {name: "Flour Tortilla", brand: "Other", kcalPer100g: 300,
          proteinPer100g: 8, carbsPer100g: 50, fatPer100g: 7},
      ]));
      const result = await searchFoodProduct.execute(
          {}, "u1", {query: "tortilla", brand: "BreadWay"}, new Date(), 0,
          {foodSearchProvider, chatProvider});
      assert.equal(result.outcome, "notFound");
    });

test("isConsistent rejects labels whose energy contradicts their macros", () => {
  assert.ok(isConsistent({kcal: 289, proteinG: 6.7, carbsG: 55.6, fatG: 6.7}));
  assert.ok(!isConsistent({kcal: 282, proteinG: 8, carbsG: 52.2, fatG: 40}));
  assert.ok(!isConsistent({kcal: 100, proteinG: 150, carbsG: 0, fatG: 0}));
});

test("matchesAll matches brand words inside run-together names", () => {
  assert.ok(matchesAll(["breadway", "tortilla"],
      "Bran Tortilla Damfi Breadway Selections"));
  assert.ok(matchesAll(["breadway"], "Bread Way Toast"));
  assert.ok(!matchesAll(["breadway", "tortilla"], "Breadway Toast"));
});
