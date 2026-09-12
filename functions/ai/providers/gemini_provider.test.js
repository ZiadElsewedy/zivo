/**
 * Offline unit tests for `./gemini_provider.js`: NormalizedRequest → Gemini
 * translation, Gemini → NormalizedResponse normalization, tool/function-call
 * round-tripping, schema sanitization, streaming aggregation, and usage/stop-
 * reason mapping. No network — the `@google/genai` client is a plain fake.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {
  GeminiProvider,
  toGeminiRequest,
  toNormalizedResponse,
  sanitizeSchema,
} = require("./gemini_provider");

/**
 * A fake `GoogleGenAI`-shaped client. `generateContent` records its request
 * and resolves to `response`; `generateContentStream` yields `chunks`.
 * @param {{response: !Object, chunks: !Array<!Object>}} opts
 * @return {!Object}
 */
function fakeClient({response, chunks} = {}) {
  const calls = [];
  const client = {
    calls,
    models: {
      generateContent: async (req) => {
        calls.push(req);
        return response;
      },
    },
  };
  if (chunks) {
    client.models.generateContentStream = async (req) => {
      calls.push(req);
      return (async function* gen() {
        for (const chunk of chunks) yield chunk;
      })();
    };
  }
  return client;
}

/**
 * A minimal Gemini text response.
 * @param {string} text The reply text.
 * @param {{finishReason: string, usageMetadata: !Object}=} opts
 * @return {!Object}
 */
function textResponse(text, {finishReason = "STOP", usageMetadata} = {}) {
  return {
    candidates: [{content: {parts: [{text}]}, finishReason}],
    usageMetadata,
  };
}

// --- Request translation ---------------------------------------------------

test("toGeminiRequest maps maxTokens, system, and message roles", () => {
  const req = toGeminiRequest({
    model: "gemini-2.5-pro",
    maxTokens: 2048,
    system: [{text: "You are ZIVO.", cache: "ephemeral"}, {text: "Be concise."}],
    messages: [
      {role: "user", content: "hi"},
      {role: "assistant", content: "hello"},
    ],
  });

  assert.equal(req.model, "gemini-2.5-pro");
  assert.equal(req.config.maxOutputTokens, 2048);
  // System blocks are joined into one instruction; cache breakpoints dropped.
  assert.equal(req.config.systemInstruction, "You are ZIVO.\n\nBe concise.");
  // "assistant" becomes Gemini's "model" role; "user" stays.
  assert.deepEqual(req.contents, [
    {role: "user", parts: [{text: "hi"}]},
    {role: "model", parts: [{text: "hello"}]},
  ]);
});

test("toGeminiRequest translates tools to functionDeclarations and 'any' toolChoice to ANY", () => {
  const req = toGeminiRequest({
    model: "gemini-2.5-pro",
    maxTokens: 100,
    tools: [{
      name: "get_today",
      description: "Today's data.",
      inputSchema: {type: "object", properties: {date: {type: "string"}}},
    }],
    toolChoice: "any",
    messages: [{role: "user", content: "x"}],
  });

  assert.equal(req.config.tools.length, 1);
  const decl = req.config.tools[0].functionDeclarations[0];
  assert.equal(decl.name, "get_today");
  assert.equal(decl.description, "Today's data.");
  assert.deepEqual(decl.parameters, {
    type: "object",
    properties: {date: {type: "string"}},
  });
  assert.deepEqual(req.config.toolConfig, {functionCallingConfig: {mode: "ANY"}});
});

test("sanitizeSchema strips JSON-Schema keys Gemini rejects, recursively", () => {
  const cleaned = sanitizeSchema({
    $schema: "http://json-schema.org/draft-07/schema#",
    type: "object",
    additionalProperties: false,
    properties: {
      name: {type: "string", default: "x"},
      items: {
        type: "array",
        items: {type: "object", additionalProperties: true, properties: {}},
      },
    },
  });

  assert.equal(cleaned.$schema, undefined);
  assert.equal(cleaned.additionalProperties, undefined);
  assert.equal(cleaned.properties.name.default, undefined);
  assert.equal(cleaned.properties.name.type, "string");
  assert.equal(cleaned.properties.items.items.additionalProperties, undefined);
});

test("toGeminiRequest turns a tool_result into a functionResponse matched by call name", () => {
  // A prior Gemini assistant turn's functionCall (carrying its id), followed by
  // the tool_result the turn loop feeds back — the adapter must resolve the
  // response's function NAME from the call's id.
  const req = toGeminiRequest({
    model: "gemini-2.5-pro",
    maxTokens: 100,
    messages: [
      {role: "user", content: "what did I eat?"},
      {
        role: "assistant",
        content: [{
          type: "raw",
          raw: {functionCall: {id: "call-1", name: "get_today", args: {}}},
        }],
      },
      {
        role: "user",
        content: [{
          type: "tool_result",
          toolUseId: "call-1",
          content: JSON.stringify({kcal: 1800}),
        }],
      },
    ],
  });

  // The assistant functionCall round-trips through unchanged (Gemini-native).
  assert.deepEqual(req.contents[1], {
    role: "model",
    parts: [{functionCall: {id: "call-1", name: "get_today", args: {}}}],
  });
  // The tool_result becomes a functionResponse with the resolved name + parsed
  // payload.
  assert.deepEqual(req.contents[2], {
    role: "user",
    parts: [{
      functionResponse: {
        id: "call-1",
        name: "get_today",
        response: {kcal: 1800},
      },
    }],
  });
});

test("toGeminiRequest translates an Anthropic-native tool_use raw block", () => {
  // When a turn started on Claude and fell back to Gemini mid-loop, the
  // history carries Anthropic-native raw blocks — they must translate, not
  // pass through.
  const req = toGeminiRequest({
    model: "gemini-2.5-pro",
    maxTokens: 100,
    messages: [
      {
        role: "assistant",
        content: [
          {type: "raw", raw: {type: "text", text: "Let me check."}},
          {type: "raw", raw: {type: "tool_use", id: "toolu_9", name: "get_diet", input: {day: "today"}}},
          {type: "raw", raw: {type: "thinking", thinking: "secret"}},
        ],
      },
      {
        role: "user",
        content: [{type: "tool_result", toolUseId: "toolu_9", content: "{}"}],
      },
    ],
  });

  // text→{text}, tool_use→functionCall; the thinking block is dropped.
  assert.deepEqual(req.contents[0].parts, [
    {text: "Let me check."},
    {functionCall: {id: "toolu_9", name: "get_diet", args: {day: "today"}}},
  ]);
  assert.equal(req.contents[1].parts[0].functionResponse.name, "get_diet");
});

// --- Response normalization ------------------------------------------------

test("toNormalizedResponse maps a text answer to end + a text block", () => {
  const resp = toNormalizedResponse(textResponse("You ate 1800 kcal."));
  assert.equal(resp.stopReason, "end");
  assert.equal(resp.content.length, 1);
  assert.equal(resp.content[0].type, "text");
  assert.equal(resp.content[0].text, "You ate 1800 kcal.");
});

test("toNormalizedResponse maps a functionCall to a tool_use block and tool_use stop reason", () => {
  const resp = toNormalizedResponse({
    candidates: [{
      content: {parts: [{functionCall: {name: "get_today", args: {date: "2026-09-13"}}}]},
      finishReason: "STOP",
    }],
  });
  // Gemini reports STOP even for a tool turn — the parts decide.
  assert.equal(resp.stopReason, "tool_use");
  const block = resp.content[0];
  assert.equal(block.type, "tool_use");
  assert.equal(block.name, "get_today");
  assert.deepEqual(block.input, {date: "2026-09-13"});
  // A synthetic id is minted and mirrored into raw so it round-trips.
  assert.ok(block.id);
  assert.equal(block.raw.functionCall.id, block.id);
});

test("toNormalizedResponse maps finish reasons and prompt blocks", () => {
  assert.equal(toNormalizedResponse(textResponse("x", {finishReason: "MAX_TOKENS"})).stopReason, "max_tokens");
  assert.equal(toNormalizedResponse(textResponse("x", {finishReason: "SAFETY"})).stopReason, "refusal");
  assert.equal(toNormalizedResponse({promptFeedback: {blockReason: "SAFETY"}, candidates: []}).stopReason, "refusal");
});

test("toNormalizedResponse maps usage, subtracting cache and folding thoughts into output", () => {
  const resp = toNormalizedResponse(textResponse("x", {
    usageMetadata: {
      promptTokenCount: 1000,
      cachedContentTokenCount: 300,
      candidatesTokenCount: 50,
      thoughtsTokenCount: 20,
    },
  }));
  assert.equal(resp.usage.inputTokens, 700); // 1000 - 300 cached
  assert.equal(resp.usage.cacheReadTokens, 300);
  assert.equal(resp.usage.outputTokens, 70); // 50 + 20 thinking
  assert.equal(resp.usage.cacheWriteTokens, 0);
});

// --- generate (buffered + streaming) ---------------------------------------

test("generate (buffered) sends the translated request and normalizes the reply", async () => {
  const client = fakeClient({response: textResponse("hi there")});
  const provider = new GeminiProvider(client);

  const resp = await provider.generate({
    model: "gemini-2.5-pro",
    maxTokens: 128,
    messages: [{role: "user", content: "hi"}],
  });

  assert.equal(client.calls[0].model, "gemini-2.5-pro");
  assert.equal(resp.content[0].text, "hi there");
});

test("generate (streaming) emits text deltas and aggregates the final response", async () => {
  const chunks = [
    {candidates: [{content: {parts: [{text: "You ate "}]}}]},
    {candidates: [{content: {parts: [{text: "1800 kcal."}]}, finishReason: "STOP"}],
      usageMetadata: {promptTokenCount: 10, candidatesTokenCount: 4}},
  ];
  const provider = new GeminiProvider(fakeClient({chunks}));
  const deltas = [];

  const resp = await provider.generate(
      {model: "gemini-2.5-pro", maxTokens: 128, messages: [{role: "user", content: "?"}]},
      {onText: (t) => deltas.push(t)});

  assert.deepEqual(deltas, ["You ate ", "1800 kcal."]);
  assert.equal(resp.stopReason, "end");
  assert.equal(resp.content.map((b) => b.text).join(""), "You ate 1800 kcal.");
  assert.equal(resp.usage.outputTokens, 4);
});

test("generate propagates the client's error unchanged (classification is the router's job)", async () => {
  const err = new Error("Gemini 503");
  err.status = 503;
  const provider = new GeminiProvider({
    models: {generateContent: async () => {
      throw err;
    }},
  });
  await assert.rejects(
      () => provider.generate({maxTokens: 1, messages: [{role: "user", content: "x"}]}),
      (e) => e === err);
});
