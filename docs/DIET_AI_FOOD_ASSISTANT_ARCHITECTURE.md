# AI food/diet interaction layer — architecture

> **Superseded in part (2026-09-24).** `suggest_meal_replacement` is now
> **`search_food_alternatives`**: the model proposes realistic candidates and the
> catalog prices them (the macro-share ranking below offered canned soup for
> molokhia); options are shown with `ask_choice` and the swap waits for the user's
> pick (the turn loop refuses `replace_meal_item` in the turn that offered them).
> `search_food_product` now tries the user's saved foods → Open Food Facts →
> Gemini web search. Current behaviour: `docs/STATE.md` and
> `functions/ai/chat/README.md`. Text below is the original design, kept for
> history.

> Started as a design doc written before any implementation; now also the build log, kept
> current as each phase landed — sections marked "as built" record where reality corrected
> the original sketch. Supersedes nothing; extends
> [ADR-001](DECISIONS/ADR-001-ai-assistant.md), [ADR-003](DECISIONS/ADR-003-ai-mutations-v2.md)
> and [ADR-007](DECISIONS/ADR-007-diet-onboarding-body-data-and-generation.md).
>
> **Status (2026-09-23): all five phases shipped or resolved as unnecessary.** Phase 1
> (a separate `userContext` doc) turned out not to be needed — §10. Phases 2–5 (external
> food search, context-aware generation, meal replacement, quantity-as-presets) all shipped;
> see the "Phased build order" section at the bottom for the one-line status of each.

## The one finding that reshapes the brief

The brief asks for: streaming tool-call visibility, structured UI instead of free-text
questions, a resolve→search→ask precedence for unknown foods, and a propose/confirm
pattern that never trusts a model-stated calorie figure.

**All four already exist and are load-bearing today**, in the Ask feature
(`lib/features/ai/`, `functions/ai/`), not the diet feature specifically:

- **Streaming tool visibility** — `AiTurnEvent` (`lib/features/ai/domain/ai_turn_event.dart`):
  `phase` (understanding/working/preparing_change/done), `step` (tool name + running/ok/error),
  `delta` (reply text), carried over `httpsCallable('aiChat').stream(...)`
  (`firebase_ai_repository.dart:258`).
- **Structured choice/input instead of chat questions** — `ask_choice` and `request_input`
  (`functions/ai/tools/elicitations.js`), rendered by `choice_chips.dart` /
  `input_request_card.dart`, answered as the next ordinary turn
  (`AskController.answerChoice`/`submitInput`). The system prompt already states the exact
  rule the brief asks for, verbatim: *"Read before you ask... ask at most one question per
  turn... call ask_choice with 2–5 concrete options rather than guessing or listing the
  options as plain text"* (`functions/ai/chat/prompt/sections/elicitation.js`).
- **Resolve → ask, never guess** — `resolve_food` / `calculate_meal_nutrition`
  (`functions/ai/tools/read.js:939-1097`) return `resolved` / `ambiguous` / `notFound`;
  `ambiguous` is explicitly routed to `ask_choice` by the tool's own description.
- **Never trust the model's number** — `log_food.verify()` (`functions/ai/tools/mutations.js:555`)
  re-resolves every item against the real catalog server-side and throws back to the model on
  anything unresolved. The model supplies food + amount; ZIVO supplies the number. This is
  the enforcement point, and it's already correct.

So this doc is **not** a green-field agent architecture. It's four concrete, additive gaps
in an existing, working propose→confirm loop:

| Brief's problem | What's missing | What already handles it |
|---|---|---|
| 1. Context-aware generation | No location/food-culture field anywhere in the app (confirmed: zero `country` hits in `lib/features/`) | `PlanPreferences.cuisine` (free text) partially covers it; the generation pipeline, schema-forced tool call, and pricing are unchanged |
| 2. Meal replacement | No replacement tool or mutation exists (`suggest_meal_replacement`/`replace_meal_item` don't exist) | The propose→confirm mutation pattern (`log_food`, `mark_meal_eaten`) is the template to copy |
| 3. Structured choices for missing info | Works for catalog ambiguity; **`notFound` today means "ask the user to type in the nutrition facts by hand"** — there's no product search, so an unknown branded food (`"BreadWay toast"`) can't be found, only hand-entered | `ask_choice`/`request_input` render whatever candidates a tool returns — no UI work needed, only a new tool |
| Quantity as preset buttons, not "how many grams" | Elicitation guidance defaults to `request_input` (a numeric field) for any missing value — no preference for discrete presets | `ask_choice` already supports this shape; it's a prompt-guidance gap, not a plumbing gap |

The rest of this doc designs those four gaps, reusing the existing seams everywhere reuse
is possible.

## Target architecture

### 1–2. Tool contracts + input/output schemas (new tools only)

**Decision (2026-09-23): the backing provider is Gemini's Google Search grounding**, not a
third-party product API. See "Phase 2 — detailed design" below for the full integration —
this subsection states the tool contract only.

**`search_food_product`** — read tool, `functions/ai/tools/food_search_product.js` (new
file, same shape as `resolve_food`).

```
name: "search_food_product"
description: "Search the web for a branded/packaged food or product NOT in ZIVO's catalog
  (resolve_food returned notFound). Returns candidate products with nutrition as REPORTED
  BY THE SEARCH — never treat these as ZIVO catalog data, and never invent values if this
  also finds nothing. Use only after resolve_food fails; never call this for a generic food
  resolve_food can already answer."
inputSchema: { query: string (required), brand?: string }
returns:
  { outcome: "found", candidates: [{ id, name, brand, per100g:{kcal,proteinG,carbsG,fatG},
      servingSize?, sourceUrls: [string] }] (max 5) }
  | { outcome: "notFound", query, note: "Offer to save it as a custom food instead
      (create_custom_food) — don't guess its nutrition." }
  | { outcome: "unavailable", query, note: "Search isn't working right now — offer a
      hand-entered custom food instead." }
```

The tool is provider-agnostic **to the model** — it only ever sees `search_food_product`.
Internally it is a Gemini-only implementation behind a small adapter, detailed below, so a
second/replacement backing search provider is one adapter change, never a tool-contract or
prompt change.

**`suggest_meal_replacement`** — read tool, `functions/ai/tools/read.js` (new export).
**As built (2026-09-23), differs from the sketch below**: a `FoodItem` (`food_item.dart`)
has no `id` of its own, unlike a `Meal` — so `itemId` doesn't exist to ask for. The real
handle is `{mealId, itemIndex, itemName}`: position within that meal's items, plus the name
as a staleness check, both read straight from `get_today`/`get_diet`'s `planItems` (which
gained an `index` field on each item for exactly this). No `planId`/`dayId` either — every
other plan-touching tool (`mark_meal_eaten`) already resolves against the ACTIVE plan +
an optional `date`, and this follows the same convention rather than inventing a new one.

```
name: "suggest_meal_replacement"
description: "Given one item in the user's active plan they want out, return
  nutritionally comparable alternatives — same macro role (protein/carb/fat source),
  ranked by how alike their calories' composition is. Does not modify the plan; call
  replace_meal_item with the user's pick to actually change it."
inputSchema: { mealId, itemIndex, itemName (all required — itemIndex/itemName from
  get_today/get_diet's planItems), reason?: string, avoid?: string[], allergies?: string[],
  day?: 'yyyy-MM-dd' }
returns:
  { outcome: "found", original: {name, calories, proteinG, carbsG, fatG, macroRole},
      alternatives: [{foodId, name, per100g, macroRole, similarityNote}] (up to 5) }
  | { outcome: "noNutritionData", note }   // the item has no macros to rank against
  | { outcome: "noAlternatives", note }    // nothing survived the avoid/allergy filter
  | { outcome: "notFound", note }          // no active plan, or a stale reference
```

`avoid`/`allergies` are tool **inputs**, not something the tool reads from a stored
preference — there is no persisted `PlanPreferences` anywhere server-side (it has always
been a per-generation, in-memory-only input; confirmed by grep before building this). The
model passes what it already knows from the conversation; the prompt says so explicitly
(§"Phase 4" below) so this isn't a silent safety gap.

Ranking is **pure and deterministic**, `functions/nutrition/meal_replacement.js` — dominant
macro-role classification by share of calories (Atwater 4/4/9, the same factors
`food_db.js`'s `KCAL_PER_GRAM` already uses), then same-role catalog + custom foods ranked
by macro-share Euclidean distance. **No Dart mirror yet** — see that file's own doc comment
for why (only the AI tool path exists; a future in-app "Replace" button would need one).

**`replace_meal_item`** — mutation, `functions/ai/tools/mutations.js` (new export), same
propose→confirm→execute shape as `log_food`, identifying the item the same
`{mealId, itemIndex, itemName}` way.

```
name: "replace_meal_item"
mutating: true
description: "Propose swapping one item in the active plan for an alternative — does not
  save until confirmed. Use after suggest_meal_replacement and the user has picked one
  (or after resolve_food, for a food not among its alternatives)."
inputSchema: { mealId, itemIndex, itemName, foodId (from suggest_meal_replacement or
  resolve_food, required), quantity, unit, date?: 'yyyy-MM-dd' }
verify(): re-locates the item against the REAL active plan (mirrors mark_meal_eaten's
  "a string is exactly what a model can invent" discipline) AND resolves+prices the
  replacement through the same catalog path log_food uses — two independent proofs, since
  neither half of this proposal (which item, what it becomes) can be trusted from the
  model alone.
confirm-time write (functions/ai/chat/actions.js): re-checks the SAME two things again —
  mirrors mark_meal_eaten's requireMealInPlan exactly, for the same reason (a pending
  action can sit up to an hour; the write is the last moment the reference can be
  proven) — then a narrow `store.savePlanDays(uid, planId, days)` overwrites just the
  `days` field of the ALREADY-active plan doc. Deliberately not `DietRepository.savePlan`
  (client) or a save through the same machinery server-side: saving an active plan there
  means "this plan is now active, archive whatever was" — correct for creating/replacing a
  whole plan, wrong for tweaking one item of the plan that's already active. Firestore has
  no per-element array update, so the whole mutated `days` array is the smallest possible
  write that doesn't touch the plan's other fields.
```

`read_user_context` is **not a tool** — see §10; it's a plain server-side fetch folded into
the generation prompt, because it's cheap, deterministic, and always needed, unlike the
above three which are conditionally invoked mid-conversation.

### 3. Structured UI interaction schema

Unchanged shape, two additive fields:

- `AiChoiceOption` (`lib/features/ai/domain/ai_choice_request.dart`) gains an optional
  `subtitle` (e.g. `"247 kcal / 100g"`) and optional `sourceTag` (`catalog` | `external`),
  rendered as a second line + small badge in `choice_chips.dart`. Backward compatible —
  every existing caller omits both and renders exactly as today.
- No new interaction type. A quantity-as-presets prompt ("1 tortilla / 2 / 3 / 4 / Custom")
  is an ordinary `ask_choice` call where `"Custom"` is a normal option; picking it is handled
  entirely in the prompt layer (§6), not new UI: the model's next turn calls `request_input`
  for the exact amount. This keeps the two existing interaction types doing everything the
  brief's mockups need.

### 4. Streaming event schema

Unchanged shape, one additive, optional field: `AiStepEvent.detail: String?` — a short
model-independent summary (`"3 matches"`, `"not found"`) that specific tool executions may
set. Everything else about `step` events (name-only, no args/results by default) stays as
designed — deliberately, so a search's raw payload never leaks into the stream, only a
count. Populate it for `search_food_product` and `resolve_food`'s `ambiguous`/`notFound`
outcomes only; every other tool leaves it null and renders exactly as today.

### 5. Conversation/tool-call state representation

No new concept. `replace_meal_item` becomes another `AiPendingAction` variant
(`ai_pending_action.dart`) alongside `log_food`/`mark_meal_eaten`, rendered by whatever
already renders a pending mutation card. `search_food_product` and
`suggest_meal_replacement` are plain read-tool steps — they produce an `ask_choice`
message, not a pending action, same as `resolve_food`'s ambiguous outcome does today.

### 6. Answer / call tool / ask question / show UI — decision procedure

This is prompt guidance, not new plumbing. **As built**: not one `food_resolution.js` as
first sketched, but three focused sibling sections next to `elicitation.js` — `food_search.js`
(Phase 2), `meal_replacement.js` (Phase 4), `quantity.js` (Phase 5) — one per capability
rather than one growing file, matching how every other concern here already gets its own
section (`mutations.js`, `elicitation.js`, `safety.js`, …). Stated as an explicit order so
the model isn't inferring it turn-to-turn:

1. **Answer directly** only if every needed fact is already in this turn's tool results or
   `read_user_context` — never re-ask for country, allergies, or targets those already carry.
2. **`resolve_food`** first, always, for any food/log/replace intent. `resolved` → proceed.
   `ambiguous` → `ask_choice` over the internal candidates (unchanged, existing rule).
3. **`notFound`** → `search_food_product` (new step) **before** offering hand-entry.
   Found → `ask_choice` over candidates (with `subtitle`/`sourceTag`). Still not found →
   fall back to today's behavior, offer a hand-entered custom food via `request_input`.
4. **Quantity missing** ✅ shipped 2026-09-23 (`sections/quantity.js`): if the resolved
   food's `measures` include a discrete unit (`piece`, `slice`, `cup`...), prefer
   `ask_choice` with 3–4 common counts + `"Custom"` over a bare numeric `request_input`.
   Otherwise (loose/weighed foods) go straight to `request_input` with a gram field —
   asking "how many grams of soup" as preset buttons would be worse UX than the field it
   replaces.
5. **Never** call `search_food_product` when `resolve_food` already returned `resolved` —
   matches the brief's "don't call tools unnecessarily" rule and costs nothing new to state,
   since it's the same "read before you ask" discipline the prompt already enforces for
   other tools.

### 7. Food/product search

Internal catalog (`food_db.js`) is unchanged — still no fuzzy matching, still
ambiguous-by-energy-gap, still zero external calls. `search_food_product` is purely
additive and only reachable after an internal `notFound`. A result from it is **never**
priced by the model — its own `per100g` figures pass through as-is (§11), same trust
posture as an internal catalog row.

### 8. Nutrition source-of-truth resolution

Precedence, made explicit for the first time as a single ordered list (this belongs next to
the "Gotchas" section of `lib/features/diet/FEATURE.md` once implemented):

1. **Internal catalog** (`usdaFdc` / `userCustom`) — always tried first, always wins if it
   matches.
2. **A confirmed search result, saved as an ordinary custom food** — once the user picks a
   candidate, the model calls the new `create_custom_food` mutation (propose→confirm→execute,
   same as every other write) with that candidate's own reported figures. On confirm it is
   written to the user's real `customFoods` collection — indistinguishable from a food the
   user typed in by hand via the app's own "My foods" form, and visible there too. **No new
   `NutritionSource` value, no separate cache**: the moment it's confirmed, it graduates to
   exactly the same standing as any other custom food, and the *second* mention of "BreadWay
   toast" resolves instantly through the existing `CompositeFoodResolver`, offline, with no
   repeat search — because it's now just one of the user's own foods.
3. **User-hand-entered custom food** — the same `create_custom_food` mutation, called with
   figures the user typed rather than ones a search found. Today's `notFound` fallback
   (ask, offer a custom food) currently has no tool to actually act on that offer — this
   closes that pre-existing gap too, not just the new search path.
4. **Model's own estimate** — never used for a logged or replaced item. Reserved
   exclusively for `diet_import.js` (a document a human wrote, priced as-is) and the
   unresolved tail of `diet_generate.js` (marked `estimated`, per existing behavior) — both
   already documented exceptions in `diet/FEATURE.md`, unchanged by this design.

### 9. Meal replacement mechanics

**Shipped 2026-09-23.** Two-step, mirroring `log_food`'s propose→confirm split:
`suggest_meal_replacement` (read, ranks alternatives, nothing saved) → `replace_meal_item`
(mutation, confirm-gated, verified server-side twice — see §1–2's "as built" note). Ranking
considers the *item's role* (its dominant macro share, classified by Atwater kcal
contribution — `classifyMacroRole` in `functions/nutrition/meal_replacement.js`), not just
matching calories — swapping eggs (protein) for a candy bar (carb, same calories) would be a
calorie-matched but nutritionally wrong suggestion. `avoid`/`allergies` (passed by the model,
not read from a stored preference — see §1–2) filter candidates before ranking, not after,
so an excluded food never even reaches the choice list.

**"Also expose it outside chat" — deferred, not shipped.** The original sketch here proposed
a plain "Replace" button in `diet_plan_edit_page.dart`/`meal_detail_page.dart` reusing the
same ranking function directly. That needs a Dart port of `classifyMacroRole`/
`rankAlternatives` with golden vectors (the same rigor `coaching/rules.dart`/`diet/state.js`
already have) — real work, and out of scope for what the brief actually asked for: the
conversational "I don't want eggs" path. `functions/nutrition/meal_replacement.js`'s own doc
comment flags this as the natural next step once (if) a direct in-app entry point is wanted;
the ranking logic is already isolated in one pure module specifically so that port, when it
happens, is additive rather than a rewrite.

### 10. Diet generation + culture/location

**As built (2026-09-23), simpler than first sketched.** The original sketch below proposed
a new persisted `userContext/current` doc + a full repository CRUD/stream surface (mirroring
`BodyProfile`'s stream-controller wiring) so location would survive across generations
independently of any one wizard run. Building it turned up a stronger, already-established
precedent that made that surface unnecessary: `PlanPreferences` (`plan_preferences.dart`)
already carries exactly this kind of "only the user can supply this, asked fresh each
generation" data (`cuisine` is the direct sibling), the wizard's own doc comment already
notes generation-context fields are deliberately asked as free text + voice per generation
(ADR-016) rather than persisted profile settings, and `body_profile_page.dart` is explicitly
scoped to *only* BMR-equation inputs (its own doc comment: "This screen buys one thing") —
adding location there would have been the same boundary violation the original sketch was
trying to avoid by keeping it out of `BodyProfile`. So: **`country` is a new sibling field to
`cuisine` on `PlanPreferences`**, captured by a small optional voice/text field in the Diet
Builder wizard's existing "How you eat" step (`diet_builder_page.dart`'s `_EatStep`,
`diet_builder_controller.dart`), and sent as its own top-level `country` key in
`toPayload()` — no new Firestore collection, no new repository methods, no new settings
page. `cuisine` (a cooking style) and `country` (where they actually are) are kept distinct
rather than merged, since they can disagree (an Egyptian living in Germany still shops
German grocery aisles) — `diet_generate.js`'s prompt is told to prefer the more specific
`cuisine` when the two conflict.

**No agentic loop for generation.** `diet_generate.js` stays a single forced-tool-call (plus
its existing second disambiguation call) — the brief allows the model to "use a search/tool
if it needs external information," but for generation specifically, `country` travels with
the rest of `PlanPreferences` through the exact same `buildRequest()`/prompt path `cuisine`
already used, no new fetch and no new server-side lookup. Turning generation into a
multi-turn tool loop would be the "huge generic agent framework" the brief explicitly says
to avoid, for a case where the inputs are already known and cheap to fetch directly.
`search_food_product` stays a **conversational** tool only (used when logging/replacing
one food the model doesn't recognize), not part of the generation pipeline — a generated
plan's items are still priced through `resolve.js` exactly as today; regional accuracy comes
from steering *what* the model proposes (via country/cuisine in the prompt), not from
searching for each proposed item externally.

### 11. Preventing hallucinated nutrition values

One rule, three enforcement points:

- `log_food.verify()` — unchanged, already re-resolves everything server-side.
- `replace_meal_item.verify()` — same re-resolution, new call site.
- `search_food_product` — the tool itself never fills in a missing macro; a candidate
  missing calories is dropped from the results, not padded with a guess (mirrors
  `resolveFood`'s existing "absent macros are a floor, not zero" discipline in
  `plausibility.dart`, applied to search instead of cross-checking).

Net effect: the model can *name* a food and an amount, in any of these three flows, but a
calorie/macro number reaching Firestore always traces to the catalog, a confirmed external
source, or the user's own hand-entry — never a number the model typed.

### 12. Flutter frontend consumption

No new consumption model — `AskController` already maps `step` tool names to copy
("Reading today's diet…") for the phase/step stream; two entries added
(`search_food_product` → "Searching for that product…", `suggest_meal_replacement` →
"Finding alternatives…"). `replace_meal_item` gets no entry — like every mutating tool it
proposes rather than executes, so it emits no `step` event (`preparing_change` already covers
it). `choice_chips.dart` renders the new optional `subtitle` when present, unchanged
otherwise (no `sourceTag` shipped — §3's original sketch, not built; the subtitle line alone
turned out to be enough). `input_request_card.dart` is untouched. The plain "Replace" button
in the meal detail page (§9) is deferred, not built.

## What this design deliberately does not do

- **No new streaming transport.** `httpsCallable(...).stream()` stays; its known reliability
  caveats (documented in `docs/STATE.md`, "Ask coach — Gemini as a second provider") are
  orthogonal to this feature and not this design's problem to fix.
- **No new provider abstraction.** Both providers already do native function-calling
  through `NormalizedRequest`/`NormalizedResponse`; three more tool declarations is all
  either provider needs.
- **No agentic loop, anywhere.** Every new tool is one more entry in the existing
  single-turn "model calls a tool, gets a result, decides next step" loop the Ask feature
  already runs. Generation stays single-shot (§10).
- **No new nutrition pricing logic.** `resolve.js`/`food_db.js`/`nutrition_calculator.dart`
  are unchanged; external search and replacement both terminate in the same
  `resolveAndCompute`/`nutritionFor` pipeline everything else already uses.

## Phase 2 — detailed design (Google Search grounding via Gemini)

Decided: the external search provider is **Gemini's Google Search grounding tool**
(`@google/genai` v2.18, already a `functions/package.json` dependency), reached through a
*dedicated, isolated model call* — not by adding `googleSearch` to the tools the main chat
turn already has. This matters for two independent reasons:

1. **Provider independence.** The main "chat" capability route is Anthropic-primary /
   Gemini-fallback (`functions/ai/routing/router.js`'s `CAPABILITY_ROUTES.chat`). Google
   Search grounding is a Gemini-only capability; if `search_food_product`'s execution
   depended on whichever provider happened to be driving the outer conversation, the feature
   would silently stop working whenever a turn ran on Anthropic (the common case). So the
   tool makes its own call to a **new, Gemini-only capability route**, independent of which
   provider is answering the user.
2. **API constraint.** Gemini does not support mixing the `googleSearch` grounding tool with
   custom `functionDeclarations` tools in the same `generateContent` call. Giving the *outer*
   chat model access to grounding directly (as one more tool alongside `resolve_food` etc.)
   would require stripping every other tool from that call — not viable. A dedicated,
   tools-free grounding call sidesteps this entirely.

### Exact integration points

**`functions/ai/routing/router.js`** — one new capability, Gemini-only (no Anthropic
fallback exists for it, so router failure paths behave exactly like today's
`workout_import`/`diet_import` single-route capabilities):

```js
food_search: [{provider: "gemini", model: "gemini-flash-latest"}],
```

**`functions/ai/providers/provider.js`** — `NormalizedRequest` gains one optional field:

```
grounding?: {googleSearch: true}   // Gemini-only; Anthropic adapter never receives it,
                                   // since food_search has no Anthropic route.
```

**`functions/ai/providers/gemini_provider.js`** — `toGeminiRequest` sets
`config.tools = [{googleSearch: {}}]` when `normalizedRequest.grounding?.googleSearch` is
true, and skips `functionDeclarations` entirely for that call (a grounded search call never
also carries function-calling tools — see constraint #2 above). Grounding metadata
(`groundingChunks` with `web.uri`/`web.title` — the citations) rides through untouched on
`NormalizedResponse.raw`, the same escape hatch every other Gemini-specific field already
uses; nothing generic needs to know about it.

**`functions/index.js`** — `buildProviderRegistry` is unchanged (the same `genai` client
already constructed for the `chat`/fallback route serves `food_search` too — one client, two
capabilities). One new line where `runAiTurn` is called:
`foodSearchProvider: providerForCapability(registry, "food_search")`.

**`functions/ai/chat/turn.js`** — `tool.execute(...)` gains one more parameter, a `deps` bag,
threaded through but ignored by every tool that doesn't need it (JS drops unused trailing
args — every existing tool's 3-arg `execute(store, uid, input)` is unaffected):

```js
tool.execute(store, uid, block.input || {}, turnNow, offsetMinutes,
    {chatProvider: provider, foodSearchProvider});
```

`chatProvider` is the *same* provider object already resolved for the turn (Anthropic-first)
— reused, not re-resolved, for the tool's second ("extraction") call. `foodSearchProvider`
is the new Gemini-only one. Both are optional; a deployment without a bound Gemini key
simply has `search_food_product` degrade to `outcome: "unavailable"` (see Failure/fallback).

### The tool's two-call design

`search_food_product.execute()` makes **two** model calls, mirroring the exact idiom
`diet_generate.js`'s `chooseFoods` second call already uses in this codebase (a forced
single-tool-call to turn free text into a schema) — no new pattern, just applied to search
instead of disambiguation:

1. **Ground** (`deps.foodSearchProvider`, `grounding: {googleSearch: true}`, no
   `tools`/`toolChoice`): one prompt asking the model to find the named product via search
   and state, in plain text, what it found and each candidate's per-100g nutrition **as
   reported by its sources**, citing them. Free-form text out, plus grounding citations on
   `response.raw`.
2. **Extract** (`deps.chatProvider`, `toolChoice: "any"`, one schema tool
   `emit_food_candidates`): the grounded text (+ a compact citation list) goes in as a user
   message; the model is forced to emit a `candidates` array in ZIVO's own schema. This step
   is deliberately **not** Gemini-specific — it's ordinary structured extraction, so it
   inherits Anthropic-primary/Gemini-fallback for free, and it never has search access itself
   (nothing here can re-invent a number the grounded text didn't state — the extraction
   prompt says so explicitly: "Only include a candidate whose calories AND all three macros
   were actually stated in the text above; drop anything else rather than filling it in").

The tool returns step 2's structured output directly. Both calls appear in the existing
`AiTurnEvent` stream as ordinary `step` events for `search_food_product` (start/ok/error) —
**no new event kind**; the two-call detail is entirely internal to one tool's `execute()` and
invisible to the outer turn loop, exactly as `calculate_meal_nutrition` internally calling
`nutritionFor` per item is invisible today.

### Normalized candidate schema

```
{
  id: string,          // stable within this tool result; NOT a persisted id
  name: string,
  brand: string | null,
  per100g: {kcal: number, proteinG: number, carbsG: number, fatG: number},
  servingSize: string | null,   // e.g. "1 slice (28 g)", as stated, never invented
  sourceUrls: string[],         // the grounding citations for this candidate, max 3
}
```

`id` is call-scoped (not a Firestore id) — a candidate only becomes a durable, priceable
food when the user picks one and the model calls `create_custom_food` with that candidate's
own figures (§8's precedence list). There is deliberately no server-side cache keyed by `id`
across turns: caching would let the model reference a candidate account by number without
carrying its actual figures forward, reopening exactly the "trust the model's memory of a
number" hole `NUMBERS` (the system prompt's load-bearing section) exists to close. Passing
the full remembered figures back into `create_custom_food` keeps the same discipline
`log_food` already has — the tool call itself carries the number, nothing is trusted from
context alone.

### Rendering: `ask_choice` gains an optional per-option `subtitle`

`search_food_product`'s own tool description tells the model to present results via
`ask_choice` (§6.3 below), one option per candidate. `AiChoiceOption` needs a second line for
"247 kcal / 100g" — the smallest additive change to the existing elicitation contract:

- `functions/ai/tools/elicitations.js` `normalizeOption`: an object option may carry an
  optional `subtitle` (≤ 60 chars, same `requireText`-style bound as `label`). A bare-string
  option (existing shape) is unaffected.
- `lib/features/ai/domain/ai_choice_request.dart` `AiChoiceOption`: optional `subtitle` field.
- `firebase_ai_repository.dart`'s shared `_optionsFrom` (the one helper both choice-parsing
  call sites already use): parses `subtitle` when present.
- `choice_chips.dart`'s `_OptionChip`: renders `subtitle` as a dimmer second line when
  non-null; chips without one render exactly as today (every existing caller is unaffected).

No `sourceTag`/provenance badge in this pass — the subtitle line ("247 kcal / 100g") is
enough signal, and a source-domain badge can be added later without another schema change if
it turns out to matter.

### Closing the loop: `create_custom_food`

Without this, `search_food_product` is a dead end — a found candidate has no `foodId`
`log_food` can accept (it isn't in the catalog; that's *why* the search ran). This is not
scope creep into Phase 4's meal-replacement machinery; it's the mechanics of Phase 2's own
flow ("user selects one → verification → calculate and log") from the brief. It also happens
to fix a **pre-existing dead end**: today, `resolve_food`'s `notFound` guidance already says
"offer to log it as a custom food," but no tool exists for the model to act on that offer —
only the app's own UI can create one. This one mutation fixes both.

`functions/ai/tools/mutations.js` (new export), propose→confirm→execute exactly like every
other mutating tool:

```
name: "create_custom_food"
mutating: true
kind: "create_custom_food"
description: "Save a food not in ZIVO's catalog as the user's own custom food — from a
  search_food_product candidate the user picked, or figures the user stated themselves.
  Does not save until confirmed. Pass the figures EXACTLY as they came from
  search_food_product or from the user — never adjust or round them yourself."
inputSchema: {
  name: string (required),
  kcalPer100g, proteinPer100g, carbsPer100g, fatPer100g: number (required),
  preparation?: "raw"|"cooked"|"dry",
}
validate(): bounds-checks name length and that all four numbers are finite and >= 0 —
  the same shape discipline every other mutation's validate() already has.
fields()/summarize()/result(): "Save <name> as a custom food · <kcal> kcal/100g", following
  logClause's existing pattern.
```

- **`functions/ai/chat/actions.js`** `applyProposedAction`: one new `case
  "create_custom_food"`, calling `store.saveCustomFood(uid, {id: action.actionId, ...v})` —
  the doc id derives from `actionId` exactly like `log_food`'s entries do, so a double-confirm
  overwrites rather than duplicates.
- **`functions/ai/shared/store.js`**: new `saveCustomFood(uid, data)`, a plain
  `.doc(id).set({...}, {merge:true})` mirroring `FirestoreDietRepository.saveCustomFood`'s
  exact field shape (`name`, `kcalPer100g`, `proteinPer100g`, `carbsPer100g`, `fatPer100g`,
  `preparation`, `portions: []`, `schemaVersion: 1`, `createdAt`) field-for-field, so a food
  the coach saved is indistinguishable in Firestore — and in the app's own "My foods" list —
  from one the user typed in by hand.
- No Dart-side change needed here at all: `CustomFood`/`FirestoreDietRepository` already
  read this shape; the app's Diet UI shows it the moment it's written, same as any other
  custom food.

### Precedence rule addition (extends §6)

New `functions/ai/chat/prompt/sections/food_search.js`, composed into `SYSTEM_PROMPT` right
after `ELICITATION` in `functions/ai/chat/prompt/system_prompt.js`:

> When `resolve_food` returns `notFound`, call `search_food_product` before offering a
> hand-entered custom food — don't skip straight to asking the user to type in numbers
> themselves. Present `found` results with `ask_choice`, one option per candidate, each
> option's `subtitle` as its kcal/100g. A result you get back is what the web says, not what
> ZIVO's catalog says — never say "this has X calories" as a fact the way you would for a
> resolved catalog food; say "search found X" and let the user confirm. Once they pick one
> (or state figures themselves), call `create_custom_food` with those exact figures — never
> your own rounding or estimate — then `log_food` with the new food. If
> `search_food_product` also returns `notFound` or `unavailable`, fall back to asking the
> user for the figures directly and offer `create_custom_food` for those.

The existing `MUTATIONS` section's tool list sentence gains one more clause naming
`create_custom_food`, additively (no existing substring assertion in
`functions/ai/gateway.test.js`/`mutations_gateway.test.js` matches that full sentence, so
this is safe — verified against both files before editing).

### Failure / fallback behavior

| Failure | Behavior |
|---|---|
| No Gemini key bound (`GEMINI_API_KEY` unset in a deployment) | `router.generate` throws "No registered AI provider for capability: food_search" inside the tool's own try/catch (not the turn loop's) → tool returns `{outcome: "unavailable", ...}`, a normal (non-error) tool result the model reacts to per the prompt rule above. The turn does not fail. |
| Gemini grounding call fails (5xx/429/timeout/blocked prompt) | Same `unavailable` outcome — caught inside the tool, never propagated as a turn-ending error. `isProviderFailure` classification is irrelevant here since there is no fallback route to try; the tool treats any failure of the one route the same way. |
| Grounding succeeds but finds nothing usable | Step 1's text says so; step 2 (extraction) is still called but is instructed to return `candidates: []` rather than inventing one — tool maps an empty array to `outcome: "notFound"`. |
| Extraction call (step 2) fails | Caught the same way → `unavailable` (a search that can't be turned into structured data is, from the model's perspective, indistinguishable from one that found nothing usable — same fallback instruction applies). |
| A candidate is missing a macro in the grounded text | Dropped from the array entirely in step 2 (the extraction prompt's explicit instruction, §"two-call design" above) — never padded with a guess. If that empties the array, `notFound`. |
| User picks a candidate, then changes their mind before confirming `create_custom_food` | Ordinary `cancelAction` — nothing was ever written; identical to cancelling any other proposal. |

### Required Gemini API / SDK changes

None beyond what `@google/genai` v2.18 already supports — `tools: [{googleSearch: {}}]` is a
standard `generateContent` config on current Gemini models (`gemini-flash-latest`, the same
rolling alias the `chat`/fallback route already uses successfully, per
`routing/router.js`'s own comment). No new dependency, no new secret (`GEMINI_API_KEY` is
already bound in `aiChat`'s `onCall` config). The only *behavioral* change to the existing
Gemini adapter is `toGeminiRequest`'s new grounding branch, which is additive and gated
entirely behind the new `grounding` field — every existing call (chat, the manual
Gemini-select route) is byte-for-byte unaffected since it never sets that field.

## Phased build order

1. ~~Data foundation (`userContext/current` doc)~~ — **turned out unnecessary.** §10's "As
   built" note explains why: `country` shipped as a sibling field on the existing
   `PlanPreferences` instead, so there was no separate data-foundation phase to build first.
2. **External food search** ✅ shipped 2026-09-23 (detailed design above) —
   `search_food_product` tool (Gemini Google Search grounding, behind an adapter) +
   `create_custom_food` mutation to close the loop + `FOOD SEARCH` prompt section +
   `AiChoiceOption.subtitle` rendering.
3. **Context-aware generation** ✅ shipped 2026-09-23 (§10's "As built" note) — `country` on
   `PlanPreferences`, captured in the Diet Builder wizard's "How you eat" step, sent to
   `diet_generate.js` alongside `cuisine`.
4. **Meal replacement** ✅ shipped 2026-09-23 (§9's "as built" note) —
   `suggest_meal_replacement` + `replace_meal_item` + `functions/nutrition/meal_replacement.js`
   (the ranking engine) + `MEAL REPLACEMENT` prompt section. The plain UI "Replace" entry
   point outside chat is deliberately deferred — see §9.
5. **Quantity-as-presets polish** ✅ shipped 2026-09-23 — exactly §6.4 as sketched, and
   nothing more: a new `QUANTITY` prompt section (`chat/prompt/sections/quantity.js`), no
   code changes anywhere else. `resolve_food`'s existing `measures` field and `ask_choice`'s
   existing `subtitle` (from Phase 2) already carried everything this needed.

Each phase ships independently and is individually testable against the existing
`test/diet/` and `functions/ai/tools/*.test.js` suites' patterns — no phase depends on a
later one existing first.
