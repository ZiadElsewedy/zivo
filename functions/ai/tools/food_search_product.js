/**
 * `search_food_product` — the coach's way to find a branded/packaged food
 * `resolve_food` couldn't (see `docs/DIET_AI_FOOD_ASSISTANT_ARCHITECTURE.md`,
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
/** @const {number} */
const GROUND_MAX_TOKENS = 1024;
/** @const {number} */
const EXTRACT_MAX_TOKENS = 1024;

const GROUND_SYSTEM_PROMPT =
  "You are searching the web on behalf of a nutrition app to identify a " +
  "branded or packaged food product the app's own catalog does not carry. " +
  "For the named product, find up to 5 real, plausible matches. For each " +
  "one, report: its exact product name, its brand, and its nutrition PER " +
  "100 GRAMS (calories, protein, carbs, fat) EXACTLY as your sources state " +
  "it — never calculate, convert, round, or estimate a figure yourself. If a " +
  "source does not state all four of those per-100g values for a product, " +
  "say so for that product plainly rather than filling in the rest. Cite the " +
  "source URL for every product you report. If you find nothing plausible, " +
  "say so directly.";

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
  "states. Only include a candidate whose calories AND all three macros " +
  "(protein, carbs, fat) per 100g were explicitly stated in the text — drop " +
  "any candidate missing even one of those four numbers rather than filling " +
  "it in or estimating it. If nothing in the text qualifies, call the tool " +
  "with an empty candidates array. Never invent a product, a brand, or a " +
  "number that is not traceable to the text.";

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
            servingSize: {
              type: "string",
              description: "as stated, e.g. '1 slice (28 g)' — omit if unstated",
            },
          },
          required: [
            "name", "kcalPer100g", "proteinPer100g", "carbsPer100g", "fatPer100g",
          ],
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

/**
 * Normalizes the extraction call's raw tool input into candidates ZIVO can
 * show, dropping anything missing a required macro rather than defaulting it
 * to zero (a silent zero is as much an invented number as a guessed one).
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
    const kcal = num(raw.kcalPer100g);
    const protein = num(raw.proteinPer100g);
    const carbs = num(raw.carbsPer100g);
    const fat = num(raw.fatPer100g);
    if (!name || kcal == null || protein == null || carbs == null ||
        fat == null) {
      continue;
    }
    out.push({
      id: `cand-${out.length}`,
      name,
      brand: typeof raw.brand === "string" && raw.brand.trim() ?
        raw.brand.trim() : null,
      per100g: {kcal, proteinG: protein, carbsG: carbs, fatG: fat},
      servingSize: typeof raw.servingSize === "string" &&
        raw.servingSize.trim() ? raw.servingSize.trim() : null,
      sourceUrls,
    });
  }
  return out;
}

const SEARCH_FOOD_PRODUCT_TOOL = {
  name: "search_food_product",
  description:
    "Search the web for a branded/packaged food or product NOT in ZIVO's " +
    "catalog (resolve_food already returned notFound for it). Returns " +
    "candidate products with nutrition AS REPORTED BY THE SEARCH — this is " +
    "not ZIVO catalog data, so present it to the user as a search result to " +
    "confirm, never as a stated fact. Use only after resolve_food fails; " +
    "never call this for a food resolve_food can already answer. A picked " +
    "candidate isn't usable until you save it with create_custom_food.",
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

    if (!deps || !deps.foodSearchProvider || !deps.chatProvider) {
      return {
        outcome: "unavailable",
        query,
        note: "Search isn't available right now — offer a hand-entered " +
          "custom food instead.",
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
        note: "Search isn't working right now — offer a hand-entered custom " +
          "food instead.",
      };
    }

    const groundedText = extractText(groundResponse.content);
    if (!groundedText) {
      return {
        outcome: "notFound",
        query,
        note: "Search found nothing usable. Offer to save it as a custom " +
          "food instead (create_custom_food) — don't guess its nutrition.",
      };
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
      return {
        outcome: "unavailable",
        query,
        note: "Search isn't working right now — offer a hand-entered custom " +
          "food instead.",
      };
    }

    const call = (extractResponse.content || []).find(
        (b) => b && b.type === "tool_use" &&
          b.name === EMIT_FOOD_CANDIDATES_TOOL_NAME);
    const candidates = normalizeCandidates(
        call && call.input && call.input.candidates, sourceUrls);

    if (candidates.length === 0) {
      return {
        outcome: "notFound",
        query,
        note: "Search found nothing with reliable nutrition. Offer to save " +
          "it as a custom food instead (create_custom_food) — don't guess " +
          "its nutrition.",
      };
    }
    return {outcome: "found", query, candidates};
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
  citationsFrom,
};
