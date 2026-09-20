// Runnable check for tool-call streaming: `node tests/ai-tool-stream.test.js`.
//
// The approval card in the sidebar was unreachable: Ai.qml always requests a
// streamed response, and the stream consumer read only `content` and `error`,
// so nothing ever constructed a message carrying a functionCall. The three
// providers also disagree about how a call arrives — OpenAI fragments the
// arguments, Anthropic announces the call and streams its JSON separately,
// Gemini sends it whole — so each strategy normalizes to one shape and this
// file checks both halves against the real sources.

const fs = require("fs");
const path = require("path");

const base = path.join(__dirname, "..");
const read = f => fs.readFileSync(path.join(base, f), "utf8");

function assert(cond, msg) {
    if (!cond)
        throw new Error(msg);
    console.log("  ok  " + msg);
}

// Pulls a `function name(...) {...}` out of QML by brace matching.
function extract(src, name) {
    const sig = "function " + name + "(";
    const start = src.indexOf(sig);
    if (start === -1)
        throw new Error("no " + name + "()");
    let depth = 0;
    for (let i = src.indexOf("{", start); i < src.length; i++) {
        if (src[i] === "{")
            depth++;
        else if (src[i] === "}" && --depth === 0)
            return src.slice(start, i + 1);
    }
    throw new Error("unbalanced " + name + "()");
}

function callable(src, name, ctx) {
    return new Function("ctx", "with (ctx) { " + extract(src, name) + " return " + name + "; }")(ctx || {});
}

// ---------------------------------------------------------------------------
// Each provider normalizes to { index, id, name, argumentsFragment }
// ---------------------------------------------------------------------------

console.log("provider normalization:");

const openai = callable(read("modules/services/ai/strategies/OpenAiApiStrategy.qml"), "parseStreamChunk");
const gemini = callable(read("modules/services/ai/strategies/GeminiApiStrategy.qml"), "parseStreamChunk");
const anthropic = callable(read("modules/services/ai/strategies/AnthropicApiStrategy.qml"), "parseStreamChunk");

const openaiStart = openai('data: ' + JSON.stringify({
    choices: [{delta: {tool_calls: [{index: 0, id: "call_1", type: "function", function: {name: "list_directory", arguments: ""}}]}}]
}));
assert(openaiStart.toolCallDelta[0].name === "list_directory" && openaiStart.toolCallDelta[0].index === 0,
    "OpenAI announces the call name against a call index");

const openaiArgs = openai('data: ' + JSON.stringify({
    choices: [{delta: {tool_calls: [{index: 0, function: {arguments: '{"path":'}}]}}]
}));
assert(openaiArgs.toolCallDelta[0].argumentsFragment === '{"path":', "OpenAI argument fragments are passed through verbatim");
assert(openaiArgs.content === "", "a tool-call chunk carries no text content");

const geminiCall = gemini('data: ' + JSON.stringify({
    candidates: [{content: {parts: [{functionCall: {name: "disk_usage", args: {path: "/"}}}]}, finishReason: "STOP"}]
}));
assert(geminiCall.toolCallDelta[0].name === "disk_usage", "Gemini emits its call from a functionCall part");
assert(JSON.parse(geminiCall.toolCallDelta[0].argumentsFragment).path === "/", "Gemini sends the whole call as a single fragment");

const anthropicStart = anthropic('data: ' + JSON.stringify({
    type: "content_block_start", index: 1, content_block: {type: "tool_use", id: "toolu_1", name: "read_text_file"}
}));
assert(anthropicStart.toolCallDelta[0].name === "read_text_file" && anthropicStart.toolCallDelta[0].index === 1,
    "Anthropic announces the call on its content block index");

const anthropicArgs = anthropic('data: ' + JSON.stringify({
    type: "content_block_delta", index: 1, delta: {type: "input_json_delta", partial_json: '{"path":"/etc"}'}
}));
assert(anthropicArgs.toolCallDelta[0].argumentsFragment === '{"path":"/etc"}', "Anthropic streams its arguments as input_json_delta");
assert(anthropicArgs.toolCallDelta[0].index === 1, "the argument fragments carry the same index as the announcement");

// A text chunk must stay a text chunk in all three.
assert(openai('data: ' + JSON.stringify({choices: [{delta: {content: "hi"}}]})).content === "hi", "OpenAI text still streams as content");
assert(gemini('data: ' + JSON.stringify({candidates: [{content: {parts: [{text: "hi"}]}}]})).content === "hi", "Gemini text still streams as content");
assert(anthropic('data: ' + JSON.stringify({type: "content_block_delta", delta: {type: "text_delta", text: "hi"}})).content === "hi", "Anthropic text still streams as content");

// ---------------------------------------------------------------------------
// Accumulation and completion
// ---------------------------------------------------------------------------

console.log("accumulation:");

const aiSrc = read("modules/services/Ai.qml");

function accumulate(chunks) {
    const ctx = {toolCallParts: {}};
    const record = callable(aiSrc, "recordToolCallDelta", ctx);
    chunks.forEach(record);
    return ctx.toolCallParts;
}

const collect = callable(aiSrc, "collectToolCalls", {});

// The OpenAI shape end to end: name first, arguments in pieces.
const fragmented = accumulate([
    [{index: 0, id: "call_1", name: "list_directory", argumentsFragment: ""}],
    [{index: 0, argumentsFragment: '{"pa'}],
    [{index: 0, argumentsFragment: 'th":"/et'}],
    [{index: 0, argumentsFragment: 'c"}'}]
]);
const done = collect(fragmented);
assert(done.length === 1, "fragments with one index make one call");
assert(done[0].name === "list_directory" && done[0].args.path === "/etc", "the arguments are parsed once the stream has finished");

const two = collect(accumulate([
    [{index: 1, name: "disk_usage", argumentsFragment: '{"path":"/"}'}],
    [{index: 0, name: "list_directory", argumentsFragment: '{"path":"/tmp"}'}]
]));
assert(two.length === 2 && two[0].name === "list_directory", "calls come back in the order the provider numbered them, not arrival order");

assert(collect(accumulate([[{index: 0, name: "list_directory", argumentsFragment: '{"path": '}]])).length === 0,
    "a call whose arguments never parsed is dropped rather than guessed at");
assert(collect(accumulate([[{index: 0, argumentsFragment: '{"path":"/"}'}]])).length === 0,
    "arguments with no tool name are dropped");
assert(collect(accumulate([[{index: 0, name: "system_status", argumentsFragment: ""}]]))[0].args.path === undefined,
    "a call with no arguments is still a call");
assert(collect(accumulate([[{index: 0, name: "x", argumentsFragment: '["not","an","object"]'}]])).length === 0,
    "arguments that are not an object are refused");
assert(collect({}).length === 0 && collect(null).length === 0, "no proposal means no calls");

// ---------------------------------------------------------------------------
// The stream reaches the accumulator, and a completed call waits for approval
// ---------------------------------------------------------------------------

console.log("wiring:");

assert(/root\.recordToolCallDelta\(result\.toolCallDelta\)/.test(aiSrc), "the stream consumer feeds tool deltas to the accumulator");

const exitBody = aiSrc.slice(aiSrc.indexOf("id: curlProcess"));
assert(/collectToolCalls\(root\.toolCallParts\)/.test(exitBody), "the completed stream is checked for proposals");
assert(/functionPending: true/.test(exitBody), "a proposal is left pending rather than run");
assert(/ai\.tool_calls_ignored/.test(exitBody), "extra proposals are said out loud rather than dropped quietly");
assert(/toolCallParts = \(\{\}\)/.test(aiSrc), "the accumulator is reset between requests");

console.log("\nAI tool streaming: all checks passed");
