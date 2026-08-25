/**
 * Offline unit tests for `./anthropic_provider.js`: request translation
 * (`NormalizedRequest` → Anthropic wire shape) and response mapping
 * (Anthropic response → `NormalizedResponse`). The injected client is a
 * plain fake — no `@anthropic-ai/sdk`, no network.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {AnthropicProvider} = require("./anthropic_provider");

/**
 * A `{messages: {create}}` fake that records the request and resolves to
 * `response`.
 * @param {!Object} response
 * @return {!Object}
 */
function fakeClient(response) {
  const calls = [];
  return {
    calls,
    messages: {
      create: async (req) => {
        calls.push(req);
        return response;
      },
    },
  };
}

// --- request translation ----------------------------------------------

test("maxTokens and model pass through to the wire request", async () => {
  const client = fakeClient({stop_reason: "end_turn", content: [], usage: {}});
  const provider = new AnthropicProvider(client);

  await provider.generate({
    model: "claude-sonnet-5",
    maxTokens: 2048,
    messages: [{role: "user", content: "hi"}],
  });

  const req = client.calls[0];
  assert.equal(req.model, "claude-sonnet-5");
  assert.equal(req.max_tokens, 2048);
});

test("a system block with cache: 'ephemeral' becomes a cache_control breakpoint", async () => {
  const client = fakeClient({stop_reason: "end_turn", content: [], usage: {}});
  const provider = new AnthropicProvider(client);

  await provider.generate({
    model: "m",
    maxTokens: 10,
    system: [{text: "You are Ask.", cache: "ephemeral"}],
    messages: [{role: "user", content: "hi"}],
  });

  const req = client.calls[0];
  assert.ok(Array.isArray(req.system));
  assert.equal(req.system[0].text, "You are Ask.");
  assert.deepEqual(req.system[0].cache_control, {type: "ephemeral"});
});

test("a system block without cache carries no cache_control", async () => {
  const client = fakeClient({stop_reason: "end_turn", content: [], usage: {}});
  const provider = new AnthropicProvider(client);

  await provider.generate({
    model: "m",
    maxTokens: 10,
    system: [{text: "plain"}],
    messages: [{role: "user", content: "hi"}],
  });

  const req = client.calls[0];
  assert.equal(req.system[0].cache_control, undefined);
});

test("no system field is sent when the request has none", async () => {
  const client = fakeClient({stop_reason: "end_turn", content: [], usage: {}});
  const provider = new AnthropicProvider(client);

  await provider.generate({model: "m", maxTokens: 10, messages: [{role: "user", content: "hi"}]});

  assert.equal(client.calls[0].system, undefined);
});

test("tools translate name/description/inputSchema to input_schema, carrying strict when set", async () => {
  const client = fakeClient({stop_reason: "end_turn", content: [], usage: {}});
  const provider = new AnthropicProvider(client);

  await provider.generate({
    model: "m",
    maxTokens: 10,
    tools: [
      {name: "get_tasks", description: "reads tasks", inputSchema: {type: "object"}},
      {name: "propose_workout_split", description: "d", inputSchema: {type: "object"}, strict: true},
    ],
    messages: [{role: "user", content: "hi"}],
  });

  const req = client.calls[0];
  assert.deepEqual(req.tools[0], {
    name: "get_tasks", description: "reads tasks", input_schema: {type: "object"},
  });
  assert.equal(req.tools[1].strict, true);
  assert.deepEqual(req.tools[1].input_schema, {type: "object"});
});

test("no tools/tool_choice fields are sent when the request has none", async () => {
  const client = fakeClient({stop_reason: "end_turn", content: [], usage: {}});
  const provider = new AnthropicProvider(client);

  await provider.generate({model: "m", maxTokens: 10, messages: [{role: "user", content: "hi"}]});

  const req = client.calls[0];
  assert.equal(req.tools, undefined);
  assert.equal(req.tool_choice, undefined);
});

test("toolChoice 'any' becomes {type: 'any'}", async () => {
  const client = fakeClient({stop_reason: "end_turn", content: [], usage: {}});
  const provider = new AnthropicProvider(client);

  await provider.generate({
    model: "m",
    maxTokens: 10,
    toolChoice: "any",
    messages: [{role: "user", content: "hi"}],
  });

  assert.deepEqual(client.calls[0].tool_choice, {type: "any"});
});

test("a document part translates to a base64 document block", async () => {
  const client = fakeClient({stop_reason: "end_turn", content: [], usage: {}});
  const provider = new AnthropicProvider(client);

  await provider.generate({
    model: "m",
    maxTokens: 10,
    messages: [{
      role: "user",
      content: [
        {type: "document", mediaType: "application/pdf", dataBase64: "ZmFrZQ=="},
        {type: "text", text: "Extract it."},
      ],
    }],
  });

  const block = client.calls[0].messages[0].content[0];
  assert.equal(block.type, "document");
  assert.equal(block.source.type, "base64");
  assert.equal(block.source.media_type, "application/pdf");
  assert.equal(block.source.data, "ZmFrZQ==");
  assert.equal(client.calls[0].messages[0].content[1].text, "Extract it.");
});

test("an image part translates to a base64 image block", async () => {
  const client = fakeClient({stop_reason: "end_turn", content: [], usage: {}});
  const provider = new AnthropicProvider(client);

  await provider.generate({
    model: "m",
    maxTokens: 10,
    messages: [{
      role: "user",
      content: [
        {type: "image", mediaType: "image/jpeg", dataBase64: "aW1n"},
        {type: "text", text: "Extract it."},
      ],
    }],
  });

  const block = client.calls[0].messages[0].content[0];
  assert.equal(block.type, "image");
  assert.equal(block.source.type, "base64");
  assert.equal(block.source.media_type, "image/jpeg");
  assert.equal(block.source.data, "aW1n");
});

test("a tool_result part translates to tool_use_id/is_error", async () => {
  const client = fakeClient({stop_reason: "end_turn", content: [], usage: {}});
  const provider = new AnthropicProvider(client);

  await provider.generate({
    model: "m",
    maxTokens: 10,
    messages: [{
      role: "user",
      content: [{type: "tool_result", toolUseId: "call-1", content: "{}", isError: true}],
    }],
  });

  const block = client.calls[0].messages[0].content[0];
  assert.deepEqual(block, {
    type: "tool_result", tool_use_id: "call-1", content: "{}", is_error: true,
  });
});

test("a raw part passes through to the wire request unchanged", async () => {
  const client = fakeClient({stop_reason: "end_turn", content: [], usage: {}});
  const provider = new AnthropicProvider(client);
  const original = {type: "thinking", thinking: "reasoning", signature: "sig-abc"};

  await provider.generate({
    model: "m",
    maxTokens: 10,
    messages: [{role: "assistant", content: [{type: "raw", raw: original}]}],
  });

  assert.equal(client.calls[0].messages[0].content[0], original);
});

test("a plain string message content passes through unchanged (persisted history)", async () => {
  const client = fakeClient({stop_reason: "end_turn", content: [], usage: {}});
  const provider = new AnthropicProvider(client);

  await provider.generate({
    model: "m",
    maxTokens: 10,
    messages: [{role: "user", content: "plain text"}],
  });

  assert.deepEqual(client.calls[0].messages[0], {role: "user", content: "plain text"});
});

// --- response mapping ----------------------------------------------------

test("a text response maps stop reason 'end_turn' to 'end' and mirrors text", async () => {
  const client = fakeClient({
    stop_reason: "end_turn",
    content: [{type: "text", text: "hello"}],
    usage: {input_tokens: 5, output_tokens: 2},
  });
  const provider = new AnthropicProvider(client);

  const resp = await provider.generate({model: "m", maxTokens: 10, messages: [{role: "user", content: "hi"}]});

  assert.equal(resp.stopReason, "end");
  assert.equal(resp.content[0].type, "text");
  assert.equal(resp.content[0].text, "hello");
  assert.equal(resp.content[0].raw, resp.raw.content[0]);
});

test("a tool_use response mirrors id/name/input and maps stop reason 'tool_use'", async () => {
  const raw = {
    stop_reason: "tool_use",
    content: [{type: "tool_use", id: "call-1", name: "get_tasks", input: {a: 1}}],
    usage: {input_tokens: 1, output_tokens: 1},
  };
  const client = fakeClient(raw);
  const provider = new AnthropicProvider(client);

  const resp = await provider.generate({model: "m", maxTokens: 10, messages: [{role: "user", content: "hi"}]});

  assert.equal(resp.stopReason, "tool_use");
  const block = resp.content[0];
  assert.equal(block.type, "tool_use");
  assert.equal(block.id, "call-1");
  assert.equal(block.name, "get_tasks");
  assert.deepEqual(block.input, {a: 1});
  assert.equal(block.raw, raw.content[0]);
});

test("stop reasons 'refusal' and 'max_tokens' map straight through, others map to 'other'", async () => {
  const provider1 = new AnthropicProvider(fakeClient({stop_reason: "refusal", content: [], usage: {}}));
  const resp1 = await provider1.generate({model: "m", maxTokens: 10, messages: [{role: "user", content: "hi"}]});
  assert.equal(resp1.stopReason, "refusal");

  const provider2 = new AnthropicProvider(fakeClient({stop_reason: "max_tokens", content: [], usage: {}}));
  const resp2 = await provider2.generate({model: "m", maxTokens: 10, messages: [{role: "user", content: "hi"}]});
  assert.equal(resp2.stopReason, "max_tokens");

  const provider3 = new AnthropicProvider(fakeClient({stop_reason: "stop_sequence", content: [], usage: {}}));
  const resp3 = await provider3.generate({model: "m", maxTokens: 10, messages: [{role: "user", content: "hi"}]});
  assert.equal(resp3.stopReason, "end");

  const provider4 = new AnthropicProvider(fakeClient({stop_reason: "something_new", content: [], usage: {}}));
  const resp4 = await provider4.generate({model: "m", maxTokens: 10, messages: [{role: "user", content: "hi"}]});
  assert.equal(resp4.stopReason, "other");
});

test("usage fields are mirrored into camelCase, defaulting missing ones to 0", async () => {
  const client = fakeClient({
    stop_reason: "end_turn",
    content: [],
    usage: {
      input_tokens: 100, output_tokens: 10,
      cache_creation_input_tokens: 2000, cache_read_input_tokens: 4000,
    },
  });
  const provider = new AnthropicProvider(client);

  const resp = await provider.generate({model: "m", maxTokens: 10, messages: [{role: "user", content: "hi"}]});

  assert.deepEqual(resp.usage, {
    inputTokens: 100, outputTokens: 10, cacheReadTokens: 4000,
    cacheWriteTokens: 2000,
  });
});

test("usage defaults to all zeros when absent from the response", async () => {
  const client = fakeClient({stop_reason: "end_turn", content: []});
  const provider = new AnthropicProvider(client);

  const resp = await provider.generate(
      {model: "m", maxTokens: 10, messages: [{role: "user", content: "hi"}]});

  assert.deepEqual(resp.usage, {
    inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0,
  });
});

test("the full raw response is preserved on the normalized response", async () => {
  const raw = {stop_reason: "end_turn", content: [], usage: {}, id: "msg-1"};
  const provider = new AnthropicProvider(fakeClient(raw));

  const resp = await provider.generate({model: "m", maxTokens: 10, messages: [{role: "user", content: "hi"}]});

  assert.equal(resp.raw, raw);
});

// --- streaming -------------------------------------------------------------

/**
 * A fake client whose `messages.stream` mimics the real SDK's `MessageStream`:
 * `.on("text", cb)` registers a delta listener, `.finalMessage()` resolves to
 * the scripted final response after replaying `deltas` through it.
 * @param {!Array<string>} deltas
 * @param {!Object} finalResponse
 * @return {!Object}
 */
function fakeStreamingClient(deltas, finalResponse) {
  const calls = [];
  return {
    calls,
    messages: {
      stream: (req) => {
        calls.push(req);
        let textHandler = null;
        return {
          on: (event, cb) => {
            if (event === "text") textHandler = cb;
          },
          finalMessage: async () => {
            for (const delta of deltas) {
              if (textHandler) textHandler(delta);
            }
            return finalResponse;
          },
        };
      },
    },
  };
}

test("generate with onText streams deltas and resolves to the final normalized response", async () => {
  const client = fakeStreamingClient(
      ["Hel", "lo"],
      {stop_reason: "end_turn", content: [{type: "text", text: "Hello"}], usage: {input_tokens: 1, output_tokens: 1}},
  );
  const provider = new AnthropicProvider(client);
  const seen = [];

  const resp = await provider.generate(
      {model: "m", maxTokens: 10, messages: [{role: "user", content: "hi"}]},
      {onText: (text) => seen.push(text)},
  );

  assert.deepEqual(seen, ["Hel", "lo"]);
  assert.equal(resp.stopReason, "end");
  assert.equal(resp.content[0].text, "Hello");
  assert.equal(client.calls.length, 1);
});

test("generate without onText uses create, not the streaming path", async () => {
  const client = fakeStreamingClient([], {stop_reason: "end_turn", content: [], usage: {}});
  let createCalls = 0;
  client.messages.create = async (req) => {
    createCalls++;
    return {stop_reason: "end_turn", content: [], usage: {}};
  };

  const provider = new AnthropicProvider(client);
  await provider.generate({model: "m", maxTokens: 10, messages: [{role: "user", content: "hi"}]});

  assert.equal(createCalls, 1);
  assert.equal(client.calls.length, 0); // messages.stream was never invoked.
});
