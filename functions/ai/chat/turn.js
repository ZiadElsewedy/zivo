/**
 * `runAiTurn` — the Ask chat orchestrator: one model↔tool round-trip loop per
 * user turn, with enforced cost/iteration ceilings and usage logging. This is
 * the "Chat AI implementation" — the thing that runs when the user sends a
 * message.
 *
 * Kept free of `@anthropic-ai/sdk` and `firebase-admin` so it runs offline under
 * `node --test` — `store` (Firestore reads/writes) and the model call are both
 * injected seams; `functions/index.js` wires the real ones.
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

const {dayKeyFor, localNowFacts, isUsableOffset} = require("../dates");
const {tools} = require("../tools");
const {mutatingTools} = require("../mutations");
const {validateAdvice} = require("../validator");
const {AnthropicProvider} = require("../providers/anthropic_provider");
const {legacyAnthropicClient} = require("../providers/legacy_client");

const {GatewayError, assertDocumentId} = require("./errors");
const {
  MODEL,
  DEFAULT_CONVERSATION_TITLE,
  DEFAULT_CONFIG,
  DAILY_LIMIT_MESSAGE,
  ITERATION_LIMIT_MESSAGE,
  TOKEN_CEILING_MESSAGE,
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
const {TurnUsage, isOverDailyCap} = require("./usage");
const {buildSystemBlocks} = require("./context");
const {persistProposal} = require("./actions");

// The model sees read + mutating tools; the gateway routes by `tool.mutating`.
const allTools = tools.concat(mutatingTools);
const allToolsByName = new Map(allTools.map((t) => [t.name, t]));

/**
 * Runs one user turn of the Ask conversation: persists the user message,
 * enforces the per-day cap, loops the model↔tool round-trip (bounded by
 * `config.maxIterations` and `config.perTurnTokenCeiling`), persists the
 * assistant's reply, and logs usage.
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
 * @param {string=} args.responseStyle The user's saved reply-length
 *   preference ('concise'|'balanced'|'detailed'). Anything else (including
 *   omitted) is treated as 'balanced' — never trust client input directly.
 * @param {(function(): !Date)|undefined} args.now Injectable clock.
 * @param {(!Object|undefined)} args.clientClock The user's own clock,
 *   forwarded by the app: `{offsetMinutes, zoneLabel}`. Cloud Functions run in
 *   UTC while the app writes diet entries against the DEVICE's calendar date,
 *   so without this the server's "today" is a different day from the user's
 *   for anyone east or west of UTC. Untrusted input — validated in
 *   `../dates.js` and ignored when implausible.
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
  responseStyle,
  now,
  clientClock,
  config,
  clientTurnId,
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
      return {status: "replayed", assistantText: prior.content, usage: null};
    }
    // A user message exists but no answer yet: skip the re-append below and
    // let the model run proceed exactly once.
    priorUserMessage = prior != null;
  }

  if (!priorUserMessage) {
    await store.appendMessage(uid, conversationId, {
      role: "user",
      content: trimmed,
      createdAt: turnNow,
      clientTurnId,
    });
  }
  await store.touchConversation(uid, conversationId, {
    title: DEFAULT_CONVERSATION_TITLE,
    createdAt: turnNow,
    updatedAt: turnNow,
  });

  // The daily cap resets at the USER's midnight, not the server's — "it
  // resets tomorrow" should mean their tomorrow.
  const dayKey = dayKeyFor(turnNow, offsetMinutes);
  const totals = await store.getTodayUsageTotals(uid, dayKey);
  if (isOverDailyCap(totals, cfg)) {
    await store.appendMessage(uid, conversationId, {
      role: "assistant",
      content: DAILY_LIMIT_MESSAGE,
      createdAt: clock(),
    });
    return {status: "daily-limit", assistantText: DAILY_LIMIT_MESSAGE,
      usage: null};
  }

  const history = await store.getRecentMessages(
      uid, conversationId, cfg.historyWindow);
  const messages = history.map(toNormalizedMessage);
  messages.push({role: "user", content: trimmed});

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
  let iterations = 0;
  const toolCalls = [];
  let finalText = null;
  let refusal = false;
  let tokenCeilingHit = false;
  let proposedAction = null;
  // The most recent diet state+findings payload the model was handed this turn
  // (from get_today/get_diet), kept so the reply can be validated against the
  // very numbers it read (Phase 7). Null when the turn read no diet data.
  let dietContext = null;
  // Set when the model tries to propose while an unexpired pending action
  // already awaits the user — the new proposal is suppressed (no duplicate).
  let proposalBlocked = false;
  // Phases are emitted once as the loop crosses each real boundary.
  let workingEmitted = false;

  // The turn is committed to running (past validation and the daily cap).
  emitPhase("understanding");

  for (let i = 0; i < cfg.maxIterations; i++) {
    iterations = i + 1;
    const normalizedRequest = {
      model: activeModel,
      maxTokens: cfg.maxTokens,
      system: systemBlocks,
      tools: normalizedTools,
      messages,
    };
    const resp = await activeProvider.generate(normalizedRequest, wantsStream ?
      {onText: (text) => emit({type: "delta", text})} : undefined);

    usage.add(resp.usage);

    if (resp.stopReason === "refusal") {
      refusal = true;
      break;
    }

    if (resp.stopReason !== "tool_use") {
      finalText = extractText(resp.content);
      break;
    }

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
    for (const block of resp.content) {
      if (!block || block.type !== "tool_use") continue;
      const tool = allToolsByName.get(block.name);
      toolCalls.push({name: block.name, toolCallId: block.id});

      // Mutating tools never execute here. The first one whose input validates
      // becomes a proposal that ends the turn awaiting the user's Confirm;
      // invalid input is fed back as an error so the model can self-correct.
      if (tool && tool.mutating) {
        if (proposal) continue; // at most one proposal per turn
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
      if (!tool) {
        resultPayload = {error: `Unknown tool: ${block.name}`};
        isError = true;
      } else {
        try {
          resultPayload = await tool.execute(
              store, uid, block.input || {}, turnNow, offsetMinutes);
          // Keep the structured diet state+findings so the reply can be checked
          // against what the model actually read (Phase 7). The last one wins —
          // the reply is about the most recently loaded day.
          if (block.name === "get_today" || block.name === "get_diet") {
            dietContext = resultPayload;
          }
        } catch (err) {
          resultPayload = {error: err.message || "Tool execution failed."};
          isError = true;
        }
      }
      emitStep(block.name, isError ? "error" : "ok");
      const toolResult = {
        type: "tool_result",
        toolUseId: block.id,
        content: capToolResult(
            JSON.stringify(resultPayload), cfg.maxToolResultChars),
      };
      if (isError) toolResult.isError = true;
      toolResults.push(toolResult);
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
      });
      break;
    }

    messages.push({role: "user", content: toolResults});

    if (usage.total > cfg.perTurnTokenCeiling) {
      tokenCeilingHit = true;
      break;
    }
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
  } else if (proposalBlocked) {
    status = "proposal-blocked";
    assistantText = PENDING_ACTION_MESSAGE;
  } else if (refusal) {
    status = "refusal";
    assistantText = REFUSAL_MESSAGE;
  } else if (tokenCeilingHit) {
    status = "token-ceiling";
    assistantText = TOKEN_CEILING_MESSAGE;
  } else if (finalText !== null) {
    assistantText = finalText || FALLBACK_MESSAGE;
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
    status = "iteration-limit";
    assistantText = ITERATION_LIMIT_MESSAGE;
  }

  const finishedAt = clock();
  if (!alreadyAppended) {
    await store.appendMessage(uid, conversationId, {
      role: "assistant",
      content: assistantText,
      createdAt: finishedAt,
      clientTurnId,
    });
  }

  const usageDoc = {
    dayKey,
    tokensIn: usage.tokensIn,
    tokensOut: usage.tokensOut,
    cacheReadTokens: usage.cacheReadTokens,
    cacheWriteTokens: usage.cacheWriteTokens,
    costUsd: usage.costUsd(),
    tools: toolCalls,
    iterations,
    latencyMs: finishedAt.getTime() - turnNow.getTime(),
    model: activeModel,
    createdAt: finishedAt,
    schemaVersion: 2,
  };
  // Recorded so the validator's real-world hit rate (and any false positives)
  // are observable in production, not a black box.
  if (validation) usageDoc.validation = validation;
  await store.logUsage(uid, usageDoc);

  // The durable record is written; the turn is done. Carries the terminal
  // status so a streaming client can reconcile without waiting on Firestore —
  // and `replaced` when a streamed reply was superseded by validated text, so
  // the client can show the authoritative message rather than its draft.
  emit({
    type: "phase",
    phase: "done",
    status,
    replaced: validation ? !validation.ok : false,
  });

  return {
    status,
    assistantText,
    actionId: proposedAction ? proposedAction.actionId : null,
    validation,
    usage: usageDoc,
  };
}

module.exports = {runAiTurn};
