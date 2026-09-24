/**
 * `runAiTurn` — the Ask chat orchestrator: one model↔tool round-trip loop per
 * user turn, with enforced cost/iteration ceilings and usage logging. This is
 * the "Chat AI implementation" — the thing that runs when the user sends a
 * message.
 *
 * Kept free of `@anthropic-ai/sdk` and `firebase-admin` so it runs offline
 * under `node --test` — `store` (Firestore reads/writes) and the model call are
 * both injected seams; `functions/index.js` wires the real ones.
 *
 * It stays thin by delegating the concerns around it:
 *   config.js   — the ceilings and the canned messages
 *   context.js  — the system blocks the model is handed (prompt + date + style)
 *   messages.js — history normalization + tool-result shaping
 *   usage.js    — token accounting + cost + the daily cap
 *   actions.js  — persisting a proposal (writes go through the confirm flow)
 *   prompt/     — the system prompt itself
 *
 * Reads never mutate. Writes (ADR-003 V2) are two-phase and user-confirmed: a
 * mutating tool call only PROPOSES a change (persists a pending action and ends
 * the turn); the actual Firestore write happens only in `confirmAction`
 * (actions.js), after the user taps Confirm. Nothing here writes user data.
 */

const {dayKeyFor, localNowFacts, isUsableOffset} = require("../shared/dates");
const {tools} = require("../tools/read");
const {mutatingTools, mutatingToolsByName} = require("../tools/mutations");
const {elicitationTools} = require("../tools/elicitations");
const {foodSearchTools} = require("../tools/food_search_product");
const {validateAdvice} = require("./validator");
const {AnthropicProvider} = require("../providers/anthropic_provider");
const {legacyAnthropicClient} = require("../providers/legacy_client");

const {GatewayError, assertDocumentId} = require("./errors");
const {
  MODEL,
  DEFAULT_CONVERSATION_TITLE,
  DEFAULT_CONFIG,
  DAILY_LIMIT_MESSAGE,
  DAILY_LIMIT_MESSAGE_AR,
  FINAL_STEP_DIRECTIVE,
  REFUSAL_MESSAGE,
  FALLBACK_MESSAGE,
  PENDING_ACTION_MESSAGE,
} = require("./config");
const {
  extractText,
  stripEmptyThinking,
  toNormalizedMessage,
  capToolResult,
} = require("./messages");
const {
  TurnUsage,
  totalCostUsd,
  isOverDailyCap,
  approxTokensFromChars,
} = require("./usage");
const {AiFeature, USAGE_SCHEMA_VERSION} = require("../shared/usage_log");
const {buildSystemBlocks} = require("./context");
const {persistProposal, persistElicitation} = require("./actions");
const {
  bindOfferedOptions,
  cardFromOffer,
  resolveChoiceAnswer,
  selectionNote,
  withMoreOption,
} = require("./choices");
const {ContextLedger} = require("./context_ledger");
const {
  TerminalState,
  terminalStateFor,
  isTransientToolError,
  replyLanguageFor,
  describeUnfinishedTurn,
} = require("./outcome");

// Most activity entries persisted on one assistant message — the timeline the
// app draws above the reply. A turn can't run more than this many tools in
// practice (the step budget stops it first); the cap only guards the doc.
const MAX_PERSISTED_ACTIVITY = 16;

// The model sees read + mutating + elicitation tools. The gateway routes by
// `tool.mutating` (propose→confirm) and `tool.elicits` (pause and ask); a bare
// tool just executes and returns data.
const allTools = tools.concat(mutatingTools).concat(elicitationTools)
    .concat(foodSearchTools);
const allToolsByName = new Map(allTools.map((t) => [t.name, t]));
const {ASK_CHOICE} = require("../tools/elicitations");

/**
 * Whether a card built from `offer` gets ZIVO's own "Other options" chip —
 * only when the tool that made the offer can always find more
 * (`moreOptions`, e.g. food alternatives; never a skip-or-swap question).
 * @param {?{tool: string}} offer
 * @return {boolean}
 */
function offersMore(offer) {
  const t = offer ? allToolsByName.get(offer.tool) : null;
  return !!(t && t.moreOptions);
}

/**
 * Runs one user turn of the Ask conversation: persists the user message,
 * enforces the per-day cap, runs the BOUNDED agent loop, persists the
 * assistant's reply, and logs usage.
 *
 * The loop contract (see `outcome.js` for the terminal states):
 *
 *   model call (one agent step)
 *     ├─ no tool requested ........ final answer → COMPLETED
 *     ├─ write / question tool .... persist card → NEEDS_USER_INPUT
 *     └─ read tools ............... run each (one retry if transient)
 *          ├─ a tool keeps failing → TOOL_ERROR (no further model calls)
 *          ├─ caller went away ... → CANCELLED
 *          └─ results fed back → next step
 *   the last step (`maxAgentSteps`, or once the token budget is spent) is
 *   called with tools disabled, so it must answer; if it still can't →
 *   MAX_STEPS_REACHED. A provider failure (after the router's own retry and
 *   fallback) is thrown tagged PROVIDER_ERROR.
 *
 * A turn therefore makes at most `maxAgentSteps` model calls, whatever the
 * model asks for — there is no recursion and no unbounded retry anywhere.
 *
 * @param {!Object} args
 * @param {!Object} args.store The `FirestoreStore`-shaped read/write seam.
 * @param {(!Object)=} args.provider An `AiProvider`-shaped instance
 *   (`../providers/provider.js`) — `{generate(normalizedRequest, {onText})}`.
 *   This is the real seam production wiring (`functions/index.js`) injects.
 *   When absent, `callModel`/`streamModel` (below) are wrapped into an
 *   `AnthropicProvider` instead — the legacy seam this module's own tests
 *   (and any caller not yet updated) still use.
 * @param {string=} args.model Provider-native model id for this turn.
 *   Defaults to `MODEL`. Ignored when a route with its own model resolves
 *   `provider` (e.g. a router-backed provider from `functions/index.js`).
 * @param {function(!Object): !Promise<!Object>=} args.callModel Legacy seam:
 *   one Anthropic `messages.create` call. Ignored when `provider` is given.
 * @param {(function(!Object, function(string): void): !Promise<!Object>)=}
 *   args.streamModel Legacy streaming seam: given the same request plus an
 *   `onText(delta)` callback, streams the model and resolves to the final
 *   message (same shape `callModel` returns). Ignored when `provider` is
 *   given — pass `args.stream: true` instead to request streaming from it.
 * @param {boolean=} args.stream Requests streaming from `provider`. Only
 *   meaningful together with `provider`; with the legacy seam, streaming is
 *   requested by passing `streamModel` instead.
 * @param {(function(!Object): void)=} args.onEvent Optional sink for live turn
 *   events — `{type:'phase', phase}`, `{type:'step', tool, status}` and
 *   `{type:'delta', text}`. Phases and steps are derived from the loop's real
 *   state (never the model's reasoning): a step is emitted as each READ tool
 *   starts (`running`) and finishes (`ok`|`error`). Mutating tools emit none —
 *   they don't execute here, they become a proposal, which the
 *   `preparing_change` phase and the confirmation card already cover. Only the
 *   tool name crosses the wire, never its input or result. When absent,
 *   nothing is emitted and the turn is byte-identical to before.
 * @param {string} args.uid
 * @param {string} args.conversationId
 * @param {string} args.message
 * @param {(!Object|undefined)} args.choice A tapped answer to a question card,
 *   `{requestId, value}` (untrusted). Resolved against the STORED card
 *   (`choices.js`): the user message becomes that option's label, the card is
 *   marked answered, and — when the option is bound to a verified change —
 *   that change is proposed directly with no model call. An unknown, stale or
 *   already-answered choice is rejected before anything is written.
 * @param {string=} args.responseStyle The user's saved reply-length
 *   preference ('concise'|'balanced'|'detailed'). Anything else (including
 *   omitted) is treated as 'balanced' — never trust client input directly.
 * @param {(function(): !Date)|undefined} args.now Injectable clock.
 * @param {(!Object|undefined)} args.clientClock The user's own clock,
 *   forwarded by the app: `{offsetMinutes, zoneLabel}`. Cloud Functions run in
 *   UTC while the app writes diet entries against the DEVICE's calendar date,
 *   so without this the server's "today" is a different day from the user's
 *   for anyone east or west of UTC. Untrusted input — validated in
 *   `../shared/dates.js` and ignored when implausible.
 * @param {(!Object)=} args.foodSearchProvider An `AiProvider`-shaped instance
 *   routed to the Gemini-only `food_search` capability (see
 *   `../routing/router.js`), passed through to `search_food_product`'s
 *   `execute` as `deps.foodSearchProvider`. Absent (no Gemini key bound) makes
 *   the tool degrade to its `unavailable` outcome rather than failing the turn.
 * @param {(function(string, !Object): !Promise<!Object>)=} args.fetchImpl
 *   The HTTP client `search_food_product` uses for its product-label
 *   database lookup (production passes the global `fetch`). Absent — every
 *   offline test — skips that lookup, so tests never touch the network.
 * @param {(AbortSignal|undefined)} args.signal The caller's cancel signal
 *   (the callable's `response.signal`, which fires when the client closes the
 *   stream). Checked before every step and passed to the model call, so a
 *   turn nobody is waiting for stops spending — it ends CANCELLED without an
 *   assistant message, which leaves a retry of the same turn free to run.
 * @param {(!Object|undefined)} args.config Overrides for `DEFAULT_CONFIG`.
 * @param {(string|undefined)} args.clientTurnId Client-generated idempotency
 *   key for this turn. When supplied and a previous attempt of the SAME turn
 *   already wrote messages, the gateway serves idempotently: an already-
 *   answered turn replays its assistant text without re-running the model,
 *   and a partially-written turn never appends a second user message. This
 *   is what makes a client retry after a false failure safe.
 * @return {!Promise<{status: string, assistantText: string, usage: ?Object}>}
 */
async function runAiTurn({
  store,
  provider,
  model,
  callModel,
  streamModel,
  stream,
  onEvent,
  uid,
  conversationId,
  message,
  choice,
  responseStyle,
  now,
  clientClock,
  config,
  clientTurnId,
  foodSearchProvider,
  fetchImpl,
  signal,
}) {
  const activeProvider = provider ||
    new AnthropicProvider(legacyAnthropicClient(callModel, streamModel));
  const activeModel = model || MODEL;
  const wantsStream = provider ? stream === true : typeof streamModel === "function";
  // A no-op sink keeps the streaming path off the hot path when unused.
  const emit = typeof onEvent === "function" ? onEvent : () => {};
  const emitPhase = (phase) => emit({type: "phase", phase});
  // One event per read tool, so the client's rail can name the work instead of
  // sitting on a single "working" label for the whole tool loop. Only the tool
  // NAME and its outcome cross the wire — never the input or the result. The
  // human label is the client's job: it keeps the wording localizable (the app
  // ships en + ar) and lets copy change without a functions deploy.
  const emitStep = (name, status) => emit({type: "step", tool: name, status});
  const cfg = Object.assign({}, DEFAULT_CONFIG, config || {});
  const clock = now || (() => new Date());
  // The user's UTC offset in minutes, or undefined when the app didn't send a
  // usable one (older builds, or a nonsense value). Every date computation in
  // this turn — the day key, the tool ranges, the diet day resolution — runs
  // through it, so "today" means the user's today, not the server's.
  const rawOffset = clientClock && clientClock.offsetMinutes;
  const offsetMinutes = isUsableOffset(rawOffset) ? rawOffset : undefined;
  const zoneLabel = clientClock && clientClock.zoneLabel;

  assertDocumentId(conversationId, "conversationId");
  if (typeof message !== "string" || message.trim() === "") {
    throw new GatewayError("invalid-argument", "message is required.");
  }
  const trimmed = message.trim();
  if (trimmed.length > cfg.maxMessageChars) {
    throw new GatewayError(
        "invalid-argument", "That message is too long.");
  }

  const turnNow = clock();

  // Idempotency gate (chat turn dedup): a client retry that races a
  // slow-but-successful first attempt must never duplicate the turn.
  let priorUserMessage = false;
  if (clientTurnId) {
    const prior = await store.findMessageByClientTurnId(
        uid, conversationId, clientTurnId);
    if (prior && prior.role === "assistant") {
      // The turn already completed server-side — replay its answer instead
      // of generating (and appending) a second one.
      return {status: "replayed", terminalState: TerminalState.COMPLETED,
        assistantText: prior.content, usage: null};
    }
    // A user message exists but no answer yet: skip the re-append below and
    // let the model run proceed exactly once.
    priorUserMessage = prior != null;
  }

  // A tapped choice is resolved against the stored card BEFORE anything is
  // written, so a stale or forged answer leaves no trace. The persisted user
  // message is the option's own label — the answer is the structured pick,
  // not whatever text the client displayed.
  const picked = choice ? await resolveChoiceAnswer({
    store, uid, conversationId, choice, isRetry: priorUserMessage,
  }) : null;
  const userContent = picked ? picked.option.label : trimmed;

  if (!priorUserMessage) {
    const userMessage = {
      role: "user",
      content: userContent,
      createdAt: turnNow,
      clientTurnId,
    };
    if (picked) {
      userMessage.choice = {
        requestId: picked.requestId, value: picked.option.value,
      };
    }
    await store.appendMessage(uid, conversationId, userMessage);
  }
  if (picked) {
    await store.markChoiceAnswered(
        uid, conversationId, picked.requestId, picked.option.value);
  }
  await store.touchConversation(uid, conversationId, {
    title: DEFAULT_CONVERSATION_TITLE,
    createdAt: turnNow,
    updatedAt: turnNow,
  });

  // The daily cap resets at the USER's midnight, not the server's — "it
  // resets tomorrow" should mean their tomorrow.
  const dayKey = dayKeyFor(turnNow, offsetMinutes);

  // A tapped option that is BOUND to a verified change (a food swap priced by
  // search_food_alternatives) needs no model at all: the change it means was
  // fixed when the card was built. It goes through the same validate → verify
  // → propose path as a model's call — re-proven against the live plan, and
  // still confirm-gated — so nothing is guessed and nothing is written yet.
  // If the plan moved under the card, verification fails and the model takes
  // over below with the failure in hand.
  let bindingFailure = null;
  const boundTool = picked && picked.binding ?
    mutatingToolsByName.get(picked.binding.tool) : null;
  if (boundTool) {
    try {
      const validated = boundTool.validate(picked.binding.input || {});
      const patch = typeof boundTool.verify === "function" ?
        await boundTool.verify(
            {store, uid, validated, now: turnNow, offsetMinutes}) :
        null;
      const active = await store.getActivePendingAction(
          uid, conversationId, turnNow);
      const status = active ? "proposal-blocked" : "proposed";
      let proposed = null;
      if (active) {
        await store.appendMessage(uid, conversationId, {
          role: "assistant",
          content: PENDING_ACTION_MESSAGE,
          createdAt: clock(),
          clientTurnId,
        });
      } else {
        emitPhase("preparing_change");
        proposed = await persistProposal({
          store, uid, conversationId, tool: boundTool,
          validated: patch ? Object.assign({}, validated, patch) : validated,
          clock, ttlMs: cfg.pendingActionTtlMs,
          turn: {clientTurnId},
        });
      }
      const terminalState = terminalStateFor(status);
      emit({type: "phase", phase: "done", status, terminalState,
        replaced: false});
      return {
        status,
        terminalState,
        assistantText: proposed ? proposed.summary : PENDING_ACTION_MESSAGE,
        actionId: proposed ? proposed.actionId : null,
        requestId: null,
        validation: null,
        usage: null,
      };
    } catch (err) {
      bindingFailure = err && err.message ?
        err.message : "It couldn't be applied.";
    }
  }
  const totals = await store.getTodayUsageTotals(uid, dayKey);
  // Checked before ANY model call, so no provider — and no fallback between
  // providers — ever runs for a user who is over ZIVO's own allowance.
  if (isOverDailyCap(totals, cfg)) {
    const limitText = replyLanguageFor(trimmed) === "ar" ?
      DAILY_LIMIT_MESSAGE_AR : DAILY_LIMIT_MESSAGE;
    await store.appendMessage(uid, conversationId, {
      role: "assistant",
      content: limitText,
      createdAt: clock(),
      clientTurnId,
    });
    emit({type: "phase", phase: "done", status: "daily-limit",
      terminalState: TerminalState.DAILY_LIMIT, replaced: false});
    return {status: "daily-limit", terminalState: TerminalState.DAILY_LIMIT,
      assistantText: limitText, usage: null};
  }

  const history = await store.getRecentMessages(
      uid, conversationId, cfg.historyWindow);
  const messages = history.map(toNormalizedMessage);
  // What the previous turn already looked up, still fresh enough to reuse
  // (`context_ledger.js`). A plan the user just confirmed a change to breaks
  // the chain, so a follow-up never reasons over data it changed.
  const ledger = ContextLedger.fromHistory(history, {now: turnNow, dayKey});
  // History already holds this turn's user message on a retry; the model is
  // handed the fresh copy below either way (the existing behaviour).
  let userTurn = picked ? selectionNote(picked) : trimmed;
  if (bindingFailure) {
    userTurn += `\n[Proposing that change failed: ${bindingFailure} Re-read ` +
      "the plan and continue from the user's pick — don't offer the same " +
      "options again unless they're still valid.]";
  }
  // The carried results go AHEAD of the user's words, so the question is the
  // last thing the model reads. A failed binding means the plan moved: the
  // model is told to re-read, so nothing stale is offered to it.
  const earlier = bindingFailure ? "" : ledger.toPromptBlock(turnNow);
  messages.push({
    role: "user",
    content: earlier ? `${earlier}\n\n${userTurn}` : userTurn,
  });

  const normalizedTools = allTools.map((t) => ({
    name: t.name,
    description: t.description,
    inputSchema: t.inputSchema,
  }));

  // The tool schemas + system prompt are a fixed, deterministically-ordered
  // prefix re-sent on every model call in the turn. Render order is
  // tools → system → messages, so a single cache breakpoint on the system
  // block caches the tool schemas too — the whole static prefix reads back at
  // ~0.1x after the first call instead of full price. (ADR-003 Phase 3.5.)
  //
  // The style directive and the CONTEXT block (the user's local date/time) are
  // appended AFTER the cached prompt as uncached blocks — see context.js. That
  // keeps element 0 (SYSTEM_PROMPT, cache: 'ephemeral') identical every turn.
  const nowFacts = localNowFacts(turnNow, offsetMinutes, zoneLabel);
  const systemBlocks = buildSystemBlocks({responseStyle, facts: nowFacts});

  const usage = new TurnUsage();
  // The chat provider as the tools see it (`search_food_product`'s extraction
  // call): the same router-backed provider, but its tokens are folded into
  // THIS turn's usage — the turn's recorded cost is everything spent
  // answering, not just the loop's own calls.
  const toolChatProvider = {
    generate: async (request, opts) => {
      const r = await activeProvider.generate(request, opts);
      usage.add(r.usage, r.provider, r.model);
      return r;
    },
  };
  let iterations = 0;
  // The provider/model that actually answered, captured from the response the
  // router stamps. `activeModel` is the requested default; on an `Auto` turn
  // that fell back, these hold what really ran, so the usage log is truthful.
  let usedProvider = null;
  let usedModel = null;
  let usedModelKey = null;
  // Set when ANY call in the turn required the router to fall back
  // (`../routing/router.js`) — a turn spans several calls, and once the
  // active provider has proven unreliable this turn, later calls fall back
  // too, so these hold the FIRST fallback's requested model/reason.
  let fellBack = false;
  let requestedProvider = null;
  let requestedModel = null;
  let fallbackReason = null;
  // How many of the turn's model calls needed the other provider, and every
  // attempt that failed on the way — so usage separates "asked for Gemini"
  // from "Claude answered 4 of 5 steps because Gemini's quota was out".
  let fallbackCalls = 0;
  const failedAttempts = [];
  const toolCalls = [];
  // Total characters of tool-result JSON fed back to the model this turn, so
  // the usage log can report roughly how much of the input was tool output
  // (Phase 3 observability). Counted once as each result is produced — the
  // re-send on later iterations is real input cost but is already captured by
  // the provider's own input-token accounting, so counting it here too would
  // double-count what this figure is meant to isolate.
  let toolResultChars = 0;
  let finalText = null;
  let refusal = false;
  // Set once the turn's input+output passes `perTurnTokenCeiling`: the NEXT
  // step becomes the forced final one, and if even that can't answer the turn
  // ends `token-ceiling` (MAX_STEPS_REACHED) rather than `iteration-limit`.
  let tokenBudgetSpent = false;
  // The read tools the turn actually ran, in order, each with its final
  // outcome after any retry — the user-visible activity timeline. Persisted
  // on the assistant message, and the only source of the "here's what I
  // checked" text when the turn can't finish. Names only, never input/result.
  const activity = [];
  // Failures per tool name this turn; see `cfg.maxToolFailuresPerTool`.
  const toolFailures = new Map();
  let toolErrorHit = false;
  let failedTool = null;
  let cancelled = false;
  const isCancelled = () => !!(signal && signal.aborted);
  // SEARCH tools that OFFERED the user options this turn (more than one
  // candidate came back found). A mutation that declares `refusedAfterOffer`
  // for one of them is refused in the same turn: DISCOVER → the user CHOOSES
  // → MUTATE, never discover-and-mutate in one go.
  const offered = new Set();
  // The latest verified option set a search produced this turn
  // (`tool.choiceOffer`), which an ask_choice is pinned to and which becomes
  // the card itself if the model answers in prose instead of asking.
  let offer = null;
  let proposedAction = null;
  // Set when a valid elicitation (ask_choice) ended the turn — the persisted
  // question card the client renders, awaiting the user's answer.
  let elicitedRequest = null;
  // The most recent diet state+findings payload the model was handed this turn
  // (from get_today/get_diet), kept so the reply can be validated against the
  // very numbers it read (Phase 7). Null when the turn read no diet data.
  let dietContext = null;
  // A diet state carried from the previous turn is what a reply that reuses
  // it is checked against — the validator must see the numbers the model saw.
  const carriedDiet = ledger.latest(["get_today", "get_diet"]);
  if (carriedDiet) dietContext = carriedDiet.result;
  // An offer the previous turn verified, re-derived from its carried search
  // result — so "what were those options again?" can still show a bound card.
  // Never used for the prose safety net (that needs an offer made THIS turn).
  let carriedOffer = null;
  for (const e of ledger.entries) {
    const t = allToolsByName.get(e.tool);
    if (!t || typeof t.choiceOffer !== "function") continue;
    const parsed = ledger.latest([e.tool]);
    const options = parsed ? t.choiceOffer(parsed.result, parsed.input) : null;
    if (options && options.length >= 2) {
      carriedOffer = {tool: e.tool, options};
    }
  }
  // Text the model wrote in a step that then called a tool ("Let me check
  // your plan…"). It streamed to the screen, so it is part of the reply: the
  // persisted message keeps it, or the text the user watched being written
  // would shrink the moment the durable copy lands.
  const narration = [];
  // Whether any earlier step already streamed visible text — the next step's
  // text starts a new paragraph (see `onText` below).
  let streamedAny = false;
  // Set when the model tries to propose while an unexpired pending action
  // already awaits the user — the new proposal is suppressed (no duplicate).
  let proposalBlocked = false;
  // Phases are emitted once as the loop crosses each real boundary.
  let workingEmitted = false;

  // The turn is committed to running (past validation and the daily cap).
  emitPhase("understanding");

  // Records a failed tool call and decides whether the turn must stop: a
  // transient failure that survived its retry is fatal at once; any other
  // failure is fed back to the model, until the same tool fails
  // `maxToolFailuresPerTool` times.
  const noteToolFailure = (name, fatal) => {
    const count = (toolFailures.get(name) || 0) + 1;
    toolFailures.set(name, count);
    if (fatal || count >= cfg.maxToolFailuresPerTool) {
      toolErrorHit = true;
      failedTool = name;
    }
  };

  // What a card ending this turn carries, like a text reply would: the turn
  // id, what the model said before it, the lookups behind it, and the ledger.
  const turnCarry = (preface = narration.join("\n\n")) => ({
    clientTurnId,
    preface,
    activity: activity.slice(0, MAX_PERSISTED_ACTIVITY),
    context: ledger.toPersisted(),
  });

  for (let i = 0; i < cfg.maxAgentSteps; i++) {
    if (isCancelled()) {
      cancelled = true;
      break;
    }
    iterations = i + 1;
    // The last step the budget allows — or the first one after the token
    // budget ran out — must ANSWER: tools are disabled for it and the model
    // is told why, so the loop ends with the best answer the data it already
    // read supports instead of a blind cut-off.
    const finalStep = i === cfg.maxAgentSteps - 1 || tokenBudgetSpent;
    // Between tool rounds the model is reading what came back — the client
    // shows that as "Thinking…" (execution progress, never the model's
    // reasoning, which is not streamed).
    if (i > 0) emitPhase("thinking");
    const normalizedRequest = {
      model: activeModel,
      maxTokens: cfg.maxTokens,
      // An extra UNCACHED block after the cached prompt — element 0 is
      // untouched, so the cache still hits on the final step.
      system: finalStep ?
        systemBlocks.concat([{text: FINAL_STEP_DIRECTIVE}]) : systemBlocks,
      tools: normalizedTools,
      messages,
    };
    // `none`, not dropping `tools`: the tool list is part of the cached
    // prefix (and a history holding tool calls needs it declared).
    if (finalStep) normalizedRequest.toolChoice = "none";
    const genOpts = {};
    // Each step's text is its own paragraph, exactly as the persisted reply
    // joins them (`narration` + the final text, "\n\n" apart): a step's
    // leading whitespace is dropped and, when an earlier step already wrote
    // something, the paragraph break is sent first — so the words streamed
    // are the words saved, and nothing jumps when the saved copy lands.
    // Trailing whitespace is held back until more text follows it in the
    // same step (and dropped if none does) — the saved text is trimmed, so
    // this keeps the two identical to the character.
    const priorStreamed = streamedAny;
    let stepStreamed = false;
    let heldSpace = "";
    if (wantsStream) {
      genOpts.onText = (text) => {
        let t = String(text || "");
        if (!stepStreamed) {
          t = t.replace(/^\s+/, "");
          if (!t) return;
          if (priorStreamed) t = `\n\n${t}`;
          stepStreamed = true;
          streamedAny = true;
        }
        t = heldSpace + t;
        const tail = /\s+$/.exec(t);
        heldSpace = tail ? tail[0] : "";
        if (tail) t = t.slice(0, t.length - heldSpace.length);
        if (t) emit({type: "delta", text: t});
      };
    }
    if (signal) genOpts.signal = signal;
    // The router is about to re-run this step on the other provider after the
    // active one failed (and its one retry). The user sees the switch as it
    // happens; any text the failed attempt streamed is superseded — the
    // client drops it on this event. Model KEYS only, never provider text.
    genOpts.onFallback = (info) => {
      const entry = {kind: "fallback", from: info.from, to: info.to,
        reason: info.reason};
      if (!activity.some((a) => a.kind === "fallback" &&
          a.from === entry.from && a.to === entry.to)) {
        activity.push(entry);
      }
      // The failed attempt's text is superseded: the client truncates back
      // to where this step began, and the retry starts its paragraph afresh.
      stepStreamed = false;
      streamedAny = priorStreamed;
      heldSpace = "";
      emit({type: "fallback", from: info.from, to: info.to});
    };
    let resp;
    try {
      resp = await activeProvider.generate(normalizedRequest, genOpts);
    } catch (err) {
      // The caller closed the stream mid-call: the abort surfaces as an
      // error, but it's a cancellation, not a provider failure.
      if (isCancelled()) {
        cancelled = true;
        break;
      }
      // The router already retried / fell back (`../routing/router.js`);
      // what reaches here is terminal. Rethrown — the callable maps it to
      // "<provider> is unavailable" with Switch model / Retry — but tagged,
      // so the usage record says how the turn ended.
      if (err && typeof err === "object" && !err.terminalState) {
        err.terminalState = TerminalState.PROVIDER_ERROR;
      }
      throw err;
    }

    if (resp.provider) usedProvider = resp.provider;
    if (resp.model) usedModel = resp.model;
    if (resp.modelKey) usedModelKey = resp.modelKey;
    if (resp.fallbackOccurred) {
      fallbackCalls += 1;
      for (const a of resp.failedAttempts || []) failedAttempts.push(a);
    }
    if (resp.fallbackOccurred && !fellBack) {
      fellBack = true;
      requestedProvider = resp.requestedProvider;
      requestedModel = resp.requestedModel;
      fallbackReason = resp.fallbackReason;
    }
    usage.add(resp.usage, resp.provider, resp.model);

    if (resp.stopReason === "refusal") {
      refusal = true;
      break;
    }

    if (resp.stopReason !== "tool_use") {
      finalText = extractText(resp.content);
      break;
    }
    const stepText = extractText(resp.content);
    if (stepText) narration.push(stepText);

    // Tools were disabled for this step and the model asked for one anyway
    // (a provider that ignored `toolChoice`). Nothing more may run — the turn
    // ends MAX_STEPS_REACHED below.
    if (finalStep) break;

    // Round-trips the assistant turn verbatim (a signed `thinking` block's
    // signature included) by carrying each block's provider-native `raw`
    // through a `NormalizedRawPart` rather than reconstructing it from the
    // normalized convenience fields.
    messages.push({
      role: "assistant",
      content: stripEmptyThinking(resp.content).map((b) => ({type: "raw", raw: b.raw})),
    });

    const toolResults = [];
    let proposal = null;
    let elicitation = null;
    for (const block of resp.content) {
      if (!block || block.type !== "tool_use") continue;
      const tool = allToolsByName.get(block.name);
      toolCalls.push({name: block.name, toolCallId: block.id});

      // Mutating tools never execute here. The first one whose input validates
      // becomes a proposal that ends the turn awaiting the user's Confirm;
      // invalid input is fed back as an error so the model can self-correct.
      if (tool && tool.mutating) {
        // At most one turn-ender per turn — a proposal never coexists with
        // another proposal or with a question.
        if (proposal || elicitation) continue;
        if (tool.refusedAfterOffer && offered.has(tool.refusedAfterOffer)) {
          // Not a tool failure (nothing is broken) — the model skipped the
          // user's choice. Fed back so it shows the options instead.
          toolResults.push({
            type: "tool_result",
            toolUseId: block.id,
            content: JSON.stringify({error: "The user hasn't chosen yet. " +
              "Show the options you found with ask_choice and wait for " +
              "their pick — make this change only after they choose."}),
            isError: true,
          });
          continue;
        }
        try {
          const validated = tool.validate(block.input || {});
          // `validate` is pure and can only prove the SHAPE of the input — and
          // a well-shaped id is exactly what a model can invent. A tool may
          // also expose `verify`, which checks the input against the user's
          // real stored data and returns the facts the write should actually
          // use (see mark_meal_eaten in ../mutations.js). It runs BEFORE the
          // user is ever shown a card, so a made-up reference is fed back to
          // the model as a tool error to correct rather than reaching the
          // confirm button.
          const patch = typeof tool.verify === "function" ?
            await tool.verify(
                {store, uid, validated, now: turnNow, offsetMinutes}) :
            null;
          proposal = {
            tool,
            validated: patch ? Object.assign({}, validated, patch) : validated,
          };
        } catch (err) {
          toolResults.push({
            type: "tool_result",
            toolUseId: block.id,
            content: JSON.stringify({error: err.message || "Invalid input."}),
            isError: true,
          });
          noteToolFailure(block.name, false);
          if (toolErrorHit) break;
        }
        continue;
      }

      // Elicitation tools (ask_choice) never execute either: the first valid
      // one becomes the turn-ender that pauses for the user's answer. Like a
      // proposal — at most one per turn, and never alongside a proposal.
      // Invalid input is fed back as a tool error so the model self-corrects.
      if (tool && tool.elicits) {
        if (proposal || elicitation) continue;
        try {
          const spec = tool.validate(block.input || {});
          // A choice after a verified search offers only what was verified —
          // with the server's figures and the change each one means.
          let bound = {spec, bindings: null};
          let boundTo = null;
          if (tool === ASK_CHOICE) {
            if (offer) {
              bound = bindOfferedOptions(spec, offer);
              boundTo = offer;
            } else if (carriedOffer) {
              // A question that isn't about the carried options is just a
              // plain question — the carried offer only binds what it matches.
              try {
                bound = bindOfferedOptions(spec, carriedOffer);
                boundTo = carriedOffer;
              } catch (_) {
                bound = {spec, bindings: null};
              }
            }
            if (offersMore(boundTo)) {
              bound = withMoreOption(bound, replyLanguageFor(trimmed));
            }
          }
          elicitation = {tool, validated: bound.spec,
            bindings: bound.bindings};
        } catch (err) {
          toolResults.push({
            type: "tool_result",
            toolUseId: block.id,
            content: JSON.stringify({error: err.message || "Invalid input."}),
            isError: true,
          });
          noteToolFailure(block.name, false);
          if (toolErrorHit) break;
        }
        continue;
      }

      // A read tool is about to run — the turn is actively gathering data.
      if (!workingEmitted) {
        emitPhase("working");
        workingEmitted = true;
      }
      emitStep(block.name, "running");

      let resultPayload;
      let isError = false;
      // A failure that survived its retry(s) — the turn stops on it.
      let fatal = false;
      if (!tool) {
        resultPayload = {error: `Unknown tool: ${block.name}`};
        isError = true;
      } else {
        // Bounded retry: only a transient failure is re-run, at most
        // `cfg.toolRetries` times, inside this same step. A tool that
        // rejected its input would fail identically, so that goes straight
        // back to the model.
        for (let attempt = 0; ; attempt++) {
          try {
            resultPayload = await tool.execute(
                store, uid, block.input || {}, turnNow, offsetMinutes,
                {chatProvider: toolChatProvider, foodSearchProvider,
                  fetch: fetchImpl});
            // Keep the structured diet state+findings so the reply can be
            // checked against what the model actually read (Phase 7). The
            // last one wins — the reply is about the most recently loaded day.
            if (block.name === "get_today" || block.name === "get_diet") {
              dietContext = resultPayload;
            }
            if (tool.search && resultPayload &&
                Array.isArray(resultPayload.alternatives) &&
                resultPayload.alternatives.length > 1) {
              offered.add(block.name);
            }
            if (typeof tool.choiceOffer === "function") {
              const options =
                tool.choiceOffer(resultPayload, block.input || {});
              if (options && options.length >= 2) {
                offer = {tool: block.name, options};
              }
            }
            break;
          } catch (err) {
            const transient = isTransientToolError(err);
            if (transient && attempt < cfg.toolRetries && !isCancelled()) {
              continue;
            }
            resultPayload = {error: err.message || "Tool execution failed."};
            isError = true;
            fatal = transient;
            break;
          }
        }
      }
      emitStep(block.name, isError ? "error" : "ok");
      activity.push({tool: block.name, status: isError ? "error" : "ok"});
      if (isError) noteToolFailure(block.name, fatal);
      const toolResult = {
        type: "tool_result",
        toolUseId: block.id,
        content: capToolResult(
            JSON.stringify(resultPayload), cfg.maxToolResultChars),
      };
      if (isError) toolResult.isError = true;
      else {
        ledger.record(block.name, block.input || {}, toolResult.content,
            turnNow, dayKey);
      }
      toolResultChars += toolResult.content.length;
      toolResults.push(toolResult);
      // Stop running this step's remaining tools: the turn is ending.
      if (toolErrorHit || isCancelled()) break;
    }

    // A valid proposal ends the turn: persist a pending action + an
    // action_proposal message, and stop (no tool_result is fed back, so the
    // loop halts cleanly awaiting the user). But only ONE pending action may
    // await the user at a time (ADR-003) — if one already does, suppress this
    // one and steer the user back to the existing card, so a re-proposal (e.g.
    // the user typing "confirm" instead of tapping) can't create a second
    // action and a duplicate write on double-confirm.
    if (proposal) {
      const active = await store.getActivePendingAction(
          uid, conversationId, turnNow);
      if (active) {
        proposalBlocked = true;
        break;
      }
      emitPhase("preparing_change");
      proposedAction = await persistProposal({
        store,
        uid,
        conversationId,
        tool: proposal.tool,
        validated: proposal.validated,
        clock,
        ttlMs: cfg.pendingActionTtlMs,
        turn: turnCarry(),
      });
      break;
    }

    // A valid question (ask_choice) ends the turn the same clean way: persist
    // the card and stop, awaiting the user's answer. No pending action / write
    // path — a question resolves by being answered, which returns as the next
    // turn. (No "already pending" gate: a question is inert, so a second one
    // simply supersedes the first.)
    if (elicitation) {
      emitPhase("awaiting_input");
      elicitedRequest = await persistElicitation({
        store,
        uid,
        conversationId,
        tool: elicitation.tool,
        validated: elicitation.validated,
        bindings: elicitation.bindings,
        clock,
        turn: turnCarry(),
      });
      break;
    }

    // A tool kept failing: stop here rather than hand the model another
    // chance to call it. No further model call is made.
    if (toolErrorHit) break;
    if (isCancelled()) {
      cancelled = true;
      break;
    }

    messages.push({role: "user", content: toolResults});

    if (usage.total > cfg.perTurnTokenCeiling) tokenBudgetSpent = true;
  }

  // The safety net: the turn verified options but the model answered in prose
  // (typically listing them as bullets) instead of asking. The card is built
  // from the verified offer itself, so options are never shown as text the
  // user has to retype — and never promised without being shown.
  if (offer && finalText && !elicitedRequest && !proposedAction &&
      !refusal && !cancelled && !toolErrorHit) {
    const lang = replyLanguageFor(trimmed);
    const built = cardFromOffer(offer, finalText, lang);
    const card = offersMore(offer) ? withMoreOption(built, lang) : built;
    emitPhase("awaiting_input");
    elicitedRequest = await persistElicitation({
      store, uid, conversationId, tool: ASK_CHOICE,
      validated: card.spec, bindings: card.bindings, clock,
      turn: turnCarry(),
    });
  }

  let status = "ok";
  let assistantText;
  // Set when the reply was checked against the diet state (Phase 7): whether it
  // passed, and — when it didn't — the deterministic text that replaced it.
  // Logged for observability; the client still just renders `assistantText`.
  let validation = null;
  // A proposal already appended its own action_proposal message; don't append
  // a second assistant message for the same turn.
  let alreadyAppended = false;
  if (proposedAction) {
    status = "proposed";
    assistantText = proposedAction.summary;
    alreadyAppended = true;
  } else if (elicitedRequest) {
    // The question card is the turn's output; it was already appended by
    // persistElicitation, and the prompt text is the durable fallback line.
    status = "awaiting-input";
    assistantText = elicitedRequest.prompt;
    alreadyAppended = true;
  } else if (proposalBlocked) {
    status = "proposal-blocked";
    assistantText = PENDING_ACTION_MESSAGE;
  } else if (refusal) {
    status = "refusal";
    assistantText = REFUSAL_MESSAGE;
  } else if (cancelled) {
    status = "cancelled";
    assistantText = null;
  } else if (toolErrorHit) {
    status = "tool-error";
  } else if (finalText !== null) {
    // Everything the model wrote this turn, in order — what the user watched
    // stream in. Validated as one: a figure in a lead-in counts too.
    const said = narration.concat(finalText ? [finalText] : []);
    assistantText = said.length ? said.join("\n\n") : FALLBACK_MESSAGE;
    // Validate the reply against the diet numbers it was handed. A reply that
    // states a calorie figure the state can't account for, or that recommends
    // eating below the safety floor, is replaced with deterministic text —
    // the findings the rules engine already produced, which is why rejecting
    // is safe: there is always a correct answer to fall back to.
    if (dietContext) {
      const result = validateAdvice(assistantText, dietContext);
      validation = {
        ok: result.ok,
        safe: result.safe,
        codes: result.violations.map((v) => v.code),
      };
      if (!result.ok) {
        assistantText = result.replacement;
        status = result.safe ? "validated-fallback" : "safety-intercept";
      }
    }
  } else {
    // The budget ran out without an answer (the forced final step still
    // asked for a tool, or the loop never got that far).
    status = tokenBudgetSpent ? "token-ceiling" : "iteration-limit";
  }
  const terminalState = terminalStateFor(status);
  // A turn that stopped without an answer says what it actually did — what it
  // checked, what failed, what to try next — built from the loop's own record,
  // in the language the user wrote in. Never a vague "needed more digging".
  if (terminalState === TerminalState.MAX_STEPS_REACHED ||
      terminalState === TerminalState.TOOL_ERROR) {
    // Kept after whatever the model already said (it streamed), so the
    // explanation extends the reply instead of replacing it.
    assistantText = narration.concat([describeUnfinishedTurn({
      terminalState,
      activity,
      failedTool,
      lang: replyLanguageFor(trimmed),
    })]).join("\n\n");
  }

  const finishedAt = clock();
  // A cancelled turn persists no reply: nobody is waiting for it, and an
  // assistant message under this clientTurnId would make the client's retry
  // replay "stopped" instead of actually answering.
  if (!alreadyAppended && !cancelled) {
    const reply = {
      role: "assistant",
      content: assistantText,
      createdAt: finishedAt,
      clientTurnId,
    };
    if (activity.length) {
      reply.activity = activity.slice(0, MAX_PERSISTED_ACTIVITY);
    }
    // The next turn's head start. Not after a refusal or a failed tool — a
    // follow-up there should look again.
    const context = status === "ok" || status === "validated-fallback" ?
      ledger.toPersisted() : null;
    if (context) reply.context = context;
    await store.appendMessage(uid, conversationId, reply);
  }

  const usageDoc = {
    feature: AiFeature.CHAT,
    status: "ok",
    dayKey,
    // `tokensIn` is the total input volume (uncached + cache read + cache
    // write) the daily cap and the client usage summary read; the three slices
    // below make the cache's effect legible and let Claude vs Gemini be
    // compared on the input they paid full price for (schema v3, Phase 3).
    tokensIn: usage.tokensIn,
    uncachedTokensIn: usage.uncachedTokensIn,
    cacheReadTokens: usage.cacheReadTokens,
    cacheWriteTokens: usage.cacheWriteTokens,
    tokensOut: usage.tokensOut,
    // Roughly how much of the input was tool-result JSON (own estimate, not the
    // provider's tokenizer) — the lever the context-engineering pass moves, so
    // it needs to be measurable, not inferred. See `approxTokensFromChars`.
    toolResultTokens: approxTokensFromChars(toolResultChars),
    // The context ledger's effect, measurable: how many earlier lookups this
    // turn was handed instead of re-running, and what they cost in input.
    contextCarried: ledger.carriedCount,
    contextCarriedTokens: bindingFailure ? 0 :
      approxTokensFromChars(earlier.length),
    // Priced at the provider that actually answered (Gemini on a fallback
    // turn), not always Anthropic. Null (legacy seam) prices at the default.
    costUsd: totalCostUsd(usage, usedProvider),
    calls: iterations,
    tools: toolCalls,
    iterations,
    // How the bounded loop ended (`outcome.js`) — the closed set a dashboard
    // can count, alongside the finer-grained `status`.
    terminalState,
    latencyMs: finishedAt.getTime() - turnNow.getTime(),
    model: usedModel || activeModel,
    createdAt: finishedAt,
    schemaVersion: USAGE_SCHEMA_VERSION,
  };
  if (usedModelKey) usageDoc.modelKey = usedModelKey;
  // The provider that answered (e.g. 'anthropic' | 'gemini'), when the router
  // reported it — so a fallback is visible in usage, not silent.
  if (usedProvider) usageDoc.provider = usedProvider;
  if (fellBack) {
    usageDoc.fallbackOccurred = true;
    usageDoc.fallbackReason = fallbackReason;
    usageDoc.requestedProvider = requestedProvider;
    usageDoc.requestedModel = requestedModel;
    usageDoc.fallbackCount = fallbackCalls;
    usageDoc.failedAttempts = failedAttempts.slice(0, MAX_PERSISTED_ACTIVITY);
  }
  // The turn's idempotency key, so a client can pair this usage record with the
  // assistant MESSAGE it produced (both carry the same clientTurnId) — that's
  // what the per-message "turn details" view queries on. Absent on turn-less
  // writes, exactly as on the messages themselves.
  if (clientTurnId) usageDoc.clientTurnId = clientTurnId;
  // Recorded so the validator's real-world hit rate (and any false positives)
  // are observable in production, not a black box.
  if (validation) usageDoc.validation = validation;
  if (failedTool) usageDoc.failedTool = failedTool;
  if (cancelled) usageDoc.status = "cancelled";
  await store.logUsage(uid, usageDoc);

  // The durable record is written; the turn is done. Carries the terminal
  // status so a streaming client can reconcile without waiting on Firestore —
  // and `replaced` when a streamed reply was superseded by validated text, so
  // the client can show the authoritative message rather than its draft.
  emit({
    type: "phase",
    phase: "done",
    status,
    terminalState,
    replaced: validation ? !validation.ok : false,
  });

  return {
    status,
    terminalState,
    assistantText,
    actionId: proposedAction ? proposedAction.actionId : null,
    requestId: elicitedRequest ? elicitedRequest.requestId : null,
    validation,
    usage: usageDoc,
  };
}

module.exports = {runAiTurn};
