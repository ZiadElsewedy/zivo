/**
 * `search_food_product` — the coach's way to find a branded/packaged food
 * `resolve_food` couldn't. Searches, in order, and stops at the first that
 * finds the product:
 *
 *   0. the user's OWN saved foods (they may have saved it before);
 *   1. Open Food Facts — a public database of scanned product LABELS, queried
 *      directly (`deps.fetch`), no model involved: brand + name must match
 *      the query, and figures must be internally consistent (energy vs
 *      macros) or the row is dropped;
 *   2. a Google-grounded web search (below) when the database has nothing.
 *
 * Whatever the path, a number reaching the model was STATED by a label or a
 * source — per 100 g, or per serving with the serving's weight, converted
 * here by plain arithmetic — never estimated. Nothing found → `notFound`, and
 * the coach asks the user for the label's figures.
 *
 * The web-search path (see `docs/DIET_AI_FOOD_ASSISTANT_ARCHITECTURE.md`,
 * "Phase 2 — detailed design"). The model only ever sees this one tool; Google
 * Search is an implementation detail hidden behind it, reached through Gemini's
 * search-grounding tool via a DEDICATED model call, never by adding grounding
 * to the outer chat turn's own tools (Gemini can't combine `googleSearch` with
 * function-calling tools in one call, and grounding is Gemini-only regardless
 * of which provider is driving the outer conversation).
 *
 * Two model calls, both hidden inside `execute()`:
 *   1. GROUND  — `deps.foodSearchProvider` (Gemini + `grounding.googleSearch`,
 *      no tools) asks the model to search and report what real sources say,
 *      in plain text with citations.
 *   2. EXTRACT — `deps.chatProvider` (the SAME provider already resolved for
 *      this turn — Anthropic-first) forces a single schema tool call to turn
 *      that text into ZIVO's own candidate shape. This step has no search
 *      access itself and is told to DROP a candidate rather than fill in a
 *      macro the grounded text didn't state — the one property this whole
 *      design exists to preserve: a number reaching the user always traces to
 *      something a source actually said, never a model fill-in.
 *
 * A confirmed candidate is not usable on its own — `log_food` only accepts a
 * catalog-resolvable food. The model closes the loop with `create_custom_food`
 * (`./mutations.js`), which is the actual trust boundary: whatever this tool
 * returns is provisional until the user picks one and it is written, byte for
 * byte, into their own `customFoods` collection.
 */

const {extractText} = require("../chat/messages");

/** @const {number} */
const MAX_CANDIDATES = 5;

const NOT_FOUND_NOTE =
  "Couldn't verify that exact product anywhere. Tell the user so plainly and " +
  "ask for the figures on its nutrition label (calories, protein, carbs, " +
  "fat — per 100 g, or per serving with the serving's weight); then offer " +
  "create_custom_food with exactly those. Never estimate its nutrition.";
const UNAVAILABLE_NOTE =
  "Search isn't working right now. Tell the user you couldn't look it up " +
  "and ask for the figures on its nutrition label instead — never estimate.";
/** @const {number} */
const GROUND_MAX_TOKENS = 1024;
/** @const {number} */
const EXTRACT_MAX_TOKENS = 1024;

const GROUND_SYSTEM_PROMPT =
  "You are searching the web on behalf of a nutrition app to identify a " +
  "branded or packaged food product the app's own catalog does not carry. " +
  "The product may be sold in Egypt or elsewhere in the Middle East — search " +
  "in English and Arabic, including the brand's own site, supermarket and " +
  "delivery listings, and product-label databases. Report only products " +
  "whose BRAND matches the one named. For up to 5 real matches report: the " +
  "exact product name, its brand, and its nutrition — calories, protein, " +
  "carbs, fat — EXACTLY as the label or source states it, either PER 100 " +
  "GRAMS or PER SERVING together with the serving's weight in grams. Say " +
  "which basis each figure is on. Never calculate, convert, round or " +
  "estimate a figure yourself; if a source doesn't state all four, say so " +
  "for that product rather than filling in the rest. Cite the source URL " +
  "for every product. If you find nothing plausible, say so directly.";

/**
 * @param {string} query
 * @param {?string} brand
 * @return {string}
 */
function groundPrompt(query, brand) {
  const named = brand ? `${query} (brand: ${brand})` : query;
  return `Find this product and its nutrition, per the rules above: "${named}"`;
}

const EXTRACT_SYSTEM_PROMPT =
  "You are given search findings about a food product (with source " +
  "citations) and must extract them into a strict structured shape. You have " +
  "NO search access yourself — extract ONLY what the text below actually " +
  "states. For each product, fill EITHER the per-100g fields (when the text " +
  "states per-100g figures) OR the perServing fields plus servingGrams (when " +
  "it states per-serving figures and the serving's weight in grams) — " +
  "whichever the text actually gives, never converting between them " +
  "yourself. Drop any product missing calories or any of protein, carbs, " +
  "fat on the basis it uses, rather than filling one in. If nothing " +
  "qualifies, call the tool with an empty candidates array. Never invent a " +
  "product, a brand, or a number that is not traceable to the text.";

const EMIT_FOOD_CANDIDATES_TOOL_NAME = "emit_food_candidates";

const EMIT_FOOD_CANDIDATES_TOOL = {
  name: EMIT_FOOD_CANDIDATES_TOOL_NAME,
  description:
    "Emit the structured product candidates extracted from the search " +
    "findings text, or an empty array if none qualify.",
  inputSchema: {
    type: "object",
    properties: {
      candidates: {
        type: "array",
        items: {
          type: "object",
          properties: {
            name: {type: "string"},
            brand: {type: "string"},
            kcalPer100g: {type: "number"},
            proteinPer100g: {type: "number"},
            carbsPer100g: {type: "number"},
            fatPer100g: {type: "number"},
            perServing: {
              type: "object",
              description: "only when the text states per-serving figures",
              properties: {
                kcal: {type: "number"},
                proteinG: {type: "number"},
                carbsG: {type: "number"},
                fatG: {type: "number"},
              },
            },
            servingGrams: {
              type: "number",
              description: "the serving's weight in grams, as stated",
            },
            servingSize: {
              type: "string",
              description: "as stated, e.g. '1 slice (28 g)' — omit if unstated",
            },
          },
          required: ["name"],
        },
      },
    },
    required: ["candidates"],
  },
};

/**
 * Up to 3 `web.uri` citations from a Gemini grounded response's
 * `groundingMetadata` — Gemini does not reliably attribute a citation to one
 * specific candidate among several, so every candidate this call returns
 * carries the same general source list rather than a fabricated per-candidate
 * mapping.
 * @param {?Object} raw The ground call's `NormalizedResponse.raw`.
 * @return {!Array<string>}
 */
function citationsFrom(raw) {
  const candidate = raw && raw.candidates && raw.candidates[0];
  const chunks = candidate && candidate.groundingMetadata &&
    candidate.groundingMetadata.groundingChunks;
  if (!Array.isArray(chunks)) return [];
  const urls = [];
  for (const chunk of chunks) {
    const uri = chunk && chunk.web && chunk.web.uri;
    if (typeof uri === "string" && uri && !urls.includes(uri)) urls.push(uri);
    if (urls.length >= 3) break;
  }
  return urls;
}

/**
 * A finite, non-negative number, or null.
 * @param {*} v
 * @return {?number}
 */
function num(v) {
  return typeof v === "number" && Number.isFinite(v) && v >= 0 ? v : null;
}

/** @const {number} Kcal the Atwater sum may differ from the stated energy. */
const ENERGY_TOLERANCE_KCAL = 40;
/** @const {number} …or this fraction of it, whichever is larger. */
const ENERGY_TOLERANCE_SHARE = 0.3;

/**
 * Whether stated per-100g figures hang together: energy should be about
 * 4·protein + 4·carbs + 9·fat. Label data has typos (a real BreadWay row in
 * Open Food Facts claims 40 g fat and 282 kcal — impossible), and a
 * self-contradicting label is not a figure to log. Generous tolerance:
 * fibre, polyols and rounding legitimately move it.
 * @param {{kcal: number, proteinG: number, carbsG: number, fatG: number}} p
 * @return {boolean}
 */
function isConsistent(p) {
  const atwater = 4 * p.proteinG + 4 * p.carbsG + 9 * p.fatG;
  if (p.proteinG > 100 || p.carbsG > 100 || p.fatG > 100) return false;
  const gap = Math.abs(atwater - p.kcal);
  return gap <= Math.max(ENERGY_TOLERANCE_KCAL,
      ENERGY_TOLERANCE_SHARE * Math.max(p.kcal, atwater));
}

/**
 * Rounds to one decimal.
 * @param {number} v
 * @return {number}
 */
function r1(v) {
  return Math.round(v * 10) / 10;
}

/**
 * Per-100g figures from a raw candidate: as stated, or converted from a
 * stated per-serving set and the serving's stated weight (plain arithmetic
 * on stated numbers — not an estimate). Null when neither basis is complete.
 * @param {!Object} raw
 * @return {?{per100g: !Object, basis: string}}
 */
function per100gFrom(raw) {
  const kcal = num(raw.kcalPer100g);
  const protein = num(raw.proteinPer100g);
  const carbs = num(raw.carbsPer100g);
  const fat = num(raw.fatPer100g);
  if (kcal != null && protein != null && carbs != null && fat != null) {
    return {
      per100g: {kcal, proteinG: protein, carbsG: carbs, fatG: fat},
      basis: "per100g",
    };
  }
  const serving = raw.perServing;
  const grams = num(raw.servingGrams);
  if (serving && typeof serving === "object" && grams && grams > 0) {
    const sk = num(serving.kcal);
    const sp = num(serving.proteinG);
    const sc = num(serving.carbsG);
    const sf = num(serving.fatG);
    if (sk != null && sp != null && sc != null && sf != null) {
      const f = 100 / grams;
      return {
        per100g: {
          kcal: Math.round(sk * f), proteinG: r1(sp * f),
          carbsG: r1(sc * f), fatG: r1(sf * f),
        },
        basis: "perServing",
      };
    }
  }
  return null;
}

/**
 * Normalizes the extraction call's raw tool input into candidates ZIVO can
 * show, dropping anything missing a required macro rather than defaulting it
 * to zero (a silent zero is as much an invented number as a guessed one), and
 * anything whose figures contradict themselves (`isConsistent`).
 * @param {*} rawCandidates
 * @param {!Array<string>} sourceUrls Shared citation list (see
 *   `citationsFrom`).
 * @return {!Array<Object>}
 */
function normalizeCandidates(rawCandidates, sourceUrls) {
  const list = Array.isArray(rawCandidates) ? rawCandidates : [];
  const out = [];
  for (const raw of list) {
    if (out.length >= MAX_CANDIDATES) break;
    if (!raw || typeof raw !== "object") continue;
    const name = typeof raw.name === "string" ? raw.name.trim() : "";
    const figures = per100gFrom(raw);
    if (!name || !figures || !isConsistent(figures.per100g)) continue;
    out.push({
      id: `cand-${out.length}`,
      name,
      brand: typeof raw.brand === "string" && raw.brand.trim() ?
        raw.brand.trim() : null,
      per100g: figures.per100g,
      servingSize: typeof raw.servingSize === "string" &&
        raw.servingSize.trim() ? raw.servingSize.trim() : null,
      sourceUrls,
    });
  }
  return out;
}

/** @const {string} Open Food Facts' product search endpoint. */
const OFF_SEARCH_URL = "https://world.openfoodfacts.org/cgi/search.pl";
/** @const {number} Longest the database lookup may take, in ms. */
const OFF_TIMEOUT_MS = 6000;
/** @const {string} Open Food Facts asks every client to identify itself. */
const OFF_USER_AGENT = "ZIVO/1.0 (nutrition lookup)";

/**
 * Lowercased words of `text` (Latin or Arabic letters and digits), ignoring
 * one-letter noise.
 * @param {string} text
 * @return {!Array<string>}
 */
function words(text) {
  return String(text || "").toLowerCase()
      .split(/[^\p{L}\p{N}]+/u)
      .filter((w) => w.length > 1);
}

/**
 * Whether every word of the query appears in `haystack` — as a word, or
 * inside the space-stripped text so "breadway" matches "Bread Way" and
 * "Damfi Breadway Selections". This is what makes a hit the PRODUCT asked
 * for rather than something that merely shares a word with it.
 * @param {!Array<string>} queryWords
 * @param {string} haystack
 * @return {boolean}
 */
function matchesAll(queryWords, haystack) {
  const hay = String(haystack || "").toLowerCase();
  const compact = hay.replace(/[^\p{L}\p{N}]+/gu, "");
  const hayWords = new Set(words(hay));
  return queryWords.every((w) => hayWords.has(w) || compact.includes(w));
}

/**
 * The user's own saved foods that match — a product they already saved is
 * the answer, before any external search.
 * @param {!Object} store
 * @param {string} uid
 * @param {!Array<string>} queryWords
 * @return {!Promise<!Array<Object>>}
 */
async function matchSavedFoods(store, uid, queryWords) {
  if (!store || typeof store.listCustomFoods !== "function") return [];
  let saved;
  try {
    saved = await store.listCustomFoods(uid);
  } catch (_err) {
    return [];
  }
  return (saved || [])
      .filter((cf) => cf && matchesAll(queryWords, cf.name))
      .slice(0, MAX_CANDIDATES)
      .map((cf, i) => ({
        id: `saved-${i}`,
        // Already the user's own food: log_food can use this foodId directly,
        // no create_custom_food needed.
        foodId: `custom:${cf.id}`,
        name: cf.name,
        brand: null,
        per100g: {
          kcal: Number(cf.kcalPer100g), proteinG: Number(cf.proteinPer100g),
          carbsG: Number(cf.carbsPer100g), fatG: Number(cf.fatPer100g),
        },
        servingSize: null,
        alreadySaved: true,
      }));
}

/**
 * Searches Open Food Facts for the product and returns label figures for the
 * rows whose name+brand match EVERY query word and whose figures are
 * complete and consistent. Any failure (network, timeout, bad JSON) is an
 * empty result — the tool then tries the web search — never a thrown error.
 * @param {function(string, !Object): !Promise<!Object>} fetchImpl
 * @param {!Array<string>} queryWords
 * @param {string} searchTerms
 * @return {!Promise<!Array<Object>>}
 */
async function searchProductDatabase(fetchImpl, queryWords, searchTerms) {
  const url = `${OFF_SEARCH_URL}?search_terms=${
    encodeURIComponent(searchTerms)}&search_simple=1&json=1&page_size=24` +
    "&fields=product_name,product_name_en,product_name_ar,brands," +
    "nutriments,serving_size,serving_quantity";
  let body;
  try {
    const res = await fetchImpl(url, {
      headers: {"User-Agent": OFF_USER_AGENT},
      signal: AbortSignal.timeout(OFF_TIMEOUT_MS),
    });
    if (!res || !res.ok) return [];
    body = await res.json();
  } catch (_err) {
    return [];
  }
  const products = body && Array.isArray(body.products) ? body.products : [];
  const out = [];
  for (const p of products) {
    if (out.length >= MAX_CANDIDATES) break;
    const name = [p.product_name, p.product_name_en, p.product_name_ar]
        .find((n) => typeof n === "string" && n.trim());
    if (!name) continue;
    const brand = typeof p.brands === "string" ? p.brands.split(",")[0].trim() : "";
    const hay = [p.product_name, p.product_name_en, p.product_name_ar, p.brands]
        .filter((v) => typeof v === "string").join(" ");
    if (!matchesAll(queryWords, hay)) continue;
    const n = p.nutriments || {};
    const per100g = {
      kcal: num(n["energy-kcal_100g"]),
      proteinG: num(n.proteins_100g),
      carbsG: num(n.carbohydrates_100g),
      fatG: num(n.fat_100g),
    };
    if (Object.values(per100g).some((v) => v == null)) continue;
    const rounded = {
      kcal: Math.round(per100g.kcal), proteinG: r1(per100g.proteinG),
      carbsG: r1(per100g.carbsG), fatG: r1(per100g.fatG),
    };
    if (!isConsistent(rounded)) continue;
    // The same product is often listed twice; keep the first.
    if (out.some((c) =>
      c.name === name.trim() && c.per100g.kcal === rounded.kcal)) {
      continue;
    }
    out.push({
      id: `cand-${out.length}`,
      name: name.trim(),
      brand: brand || null,
      per100g: rounded,
      servingSize: typeof p.serving_size === "string" && p.serving_size.trim() ?
        p.serving_size.trim() : null,
    });
  }
  return out;
}

const SEARCH_FOOD_PRODUCT_TOOL = {
  name: "search_food_product",
  // SEARCH class: finds figures, changes nothing.
  search: true,
  description:
    "Search for a branded/packaged product (\"BreadWay tortilla\") beyond " +
    "ZIVO's own food list: the user's saved foods, then product-label " +
    "databases, then the web. Use it after resolve_food didn't find that " +
    "exact product (a generic match like plain \"tortilla\" is NOT the " +
    "product). Returns the label figures per 100 g for matching products — " +
    "found, never estimated — or notFound. A found product is usable once " +
    "the user confirms it and you save it with create_custom_food (skip that " +
    "for one marked alreadySaved: log it by its foodId).",
  inputSchema: {
    type: "object",
    properties: {
      query: {type: "string", description: "the product to search for"},
      brand: {type: "string", description: "optional, narrows the search"},
    },
    required: ["query"],
  },
  /**
   * @param {!Object} store Unused — kept for the shared `execute` signature.
   * @param {string} uid Unused — kept for the shared `execute` signature.
   * @param {!Object} input
   * @param {!Date=} now Unused.
   * @param {number=} offsetMinutes Unused.
   * @param {{chatProvider: !Object, foodSearchProvider: !Object}=} deps
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input, now, offsetMinutes, deps) {
    const query = typeof input.query === "string" ? input.query.trim() : "";
    if (!query) {
      return {outcome: "notFound", query: "", note: "No product named to search for."};
    }
    const brand = typeof input.brand === "string" && input.brand.trim() ?
      input.brand.trim() : null;
    const searchTerms = brand && !matchesAll(words(brand), query) ?
      `${brand} ${query}` : query;
    const queryWords = words(searchTerms);

    // 0. The user's own saved foods.
    const saved = await matchSavedFoods(store, uid, queryWords);
    if (saved.length > 0) {
      return {outcome: "found", query, candidates: saved};
    }

    // 1. Product-label database (no model involved).
    if (deps && typeof deps.fetch === "function") {
      const labelled = await searchProductDatabase(
          deps.fetch, queryWords, searchTerms);
      if (labelled.length > 0) {
        return {outcome: "found", query, candidates: labelled};
      }
    }

    // 2. Web search (Gemini-grounded).
    if (!deps || !deps.foodSearchProvider || !deps.chatProvider) {
      return {
        outcome: "notFound",
        query,
        note: NOT_FOUND_NOTE,
      };
    }

    let groundResponse;
    try {
      groundResponse = await deps.foodSearchProvider.generate({
        maxTokens: GROUND_MAX_TOKENS,
        system: [{text: GROUND_SYSTEM_PROMPT}],
        grounding: {googleSearch: true},
        messages: [
          {role: "user", content: groundPrompt(query, brand)},
        ],
      });
    } catch (_err) {
      return {
        outcome: "unavailable",
        query,
        note: UNAVAILABLE_NOTE,
      };
    }

    const groundedText = extractText(groundResponse.content);
    if (!groundedText) {
      return {outcome: "notFound", query, note: NOT_FOUND_NOTE};
    }
    const sourceUrls = citationsFrom(groundResponse.raw);

    let extractResponse;
    try {
      extractResponse = await deps.chatProvider.generate({
        maxTokens: EXTRACT_MAX_TOKENS,
        system: [{text: EXTRACT_SYSTEM_PROMPT}],
        tools: [EMIT_FOOD_CANDIDATES_TOOL],
        toolChoice: "any",
        messages: [
          {
            role: "user",
            content: `Search findings for "${query}":\n\n${groundedText}` +
              (sourceUrls.length ?
                `\n\nSources:\n${sourceUrls.join("\n")}` : ""),
          },
        ],
      });
    } catch (_err) {
      return {outcome: "unavailable", query, note: UNAVAILABLE_NOTE};
    }

    const call = (extractResponse.content || []).find(
        (b) => b && b.type === "tool_use" &&
          b.name === EMIT_FOOD_CANDIDATES_TOOL_NAME);
    const candidates = normalizeCandidates(
        call && call.input && call.input.candidates, sourceUrls)
        // A brand was named: only that brand's products are THE product.
        .filter((c) => !brand ||
          matchesAll(words(brand), `${c.brand || ""} ${c.name}`));

    if (candidates.length === 0) {
      return {outcome: "notFound", query, note: NOT_FOUND_NOTE};
    }
    // Source URLs stay out of the model's payload: the user is never shown a
    // link or told where a figure came from — only that it was found.
    return {
      outcome: "found",
      query,
      candidates: candidates.map(({sourceUrls: _urls, ...c}) => c),
    };
  },
};

const foodSearchTools = [SEARCH_FOOD_PRODUCT_TOOL];
const foodSearchToolsByName = new Map(
    foodSearchTools.map((t) => [t.name, t]));

module.exports = {
  SEARCH_FOOD_PRODUCT_TOOL,
  EMIT_FOOD_CANDIDATES_TOOL,
  foodSearchTools,
  foodSearchToolsByName,
  // Exported for tests only.
  normalizeCandidates,
  isConsistent,
  matchesAll,
  searchProductDatabase,
  citationsFrom,
};
