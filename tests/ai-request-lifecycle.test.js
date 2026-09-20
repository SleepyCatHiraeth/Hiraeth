// Runnable check for the AI request lifecycle: `node tests/ai-request-lifecycle.test.js`.
//
// One AI request may be in flight, and it is owned by the chat, message index
// and strategy it was issued from. The ownership decisions live in pure helpers
// in `modules/services/Ai.qml`; this file extracts those exact functions out of
// the QML source and runs them, so it cannot drift into a second copy of the
// implementation. The gates that must stay in place (refusing a send, model
// switch or chat change while a request owns the conversation) are checked
// against the source itself, since they read live QML state.

const fs = require("fs");
const path = require("path");

const AI_QML = path.join(__dirname, "..", "modules", "services", "Ai.qml");
const src = fs.readFileSync(AI_QML, "utf8");

// ---------------------------------------------------------------------------
// Extraction
// ---------------------------------------------------------------------------

// Pulls `function name(...) { ... }` out of the QML source by brace matching.
// The helpers are deliberately kept free of braces inside string literals so
// this stays honest; anything else here fails loudly rather than silently
// testing nothing.
function extractFunction(name) {
    const signature = "function " + name + "(";
    const start = src.indexOf(signature);
    if (start === -1)
        throw new Error("Ai.qml no longer defines " + name + "()");
    if (src.indexOf(signature, start + 1) !== -1)
        throw new Error("Ai.qml defines " + name + "() more than once");

    let depth = 0;
    for (let i = src.indexOf("{", start); i < src.length; i++) {
        if (src[i] === "{")
            depth++;
        else if (src[i] === "}") {
            depth--;
            if (depth === 0)
                return src.slice(start, i + 1);
        }
    }
    throw new Error("unbalanced braces in " + name + "()");
}

const PURE = ["requestOwner", "isRequestCurrent", "ownedIndex", "streamTargetIndex", "functionCallIndex", "classifySend", "commandConflictsWithRequest"];

const body = PURE.map(extractFunction).join("\n\n");
const Ai = new Function(body + "\nreturn {" + PURE.map(n => n + ": " + n).join(", ") + "};")();

function assert(cond, msg) {
    if (!cond)
        throw new Error(msg);
    console.log("  ok  " + msg);
}

// ---------------------------------------------------------------------------
// Ownership of the streamed message
// ---------------------------------------------------------------------------

console.log("stream ownership:");

const strategy = {
    id: "gemini"
};
const model = {
    name: "gemini-2.0-flash"
};

// A request issued from chat A: the user turn is index 1, the placeholder it
// streams into is index 2.
function chatA() {
    return [{
        role: "system",
        content: "prompt"
    }, {
        role: "user",
        content: "hello"
    }, {
        role: "assistant",
        content: ""
    }];
}

const owner = Ai.requestOwner(7, "chat-a", 2, strategy, model);

assert(owner.seq === 7 && owner.chatId === "chat-a" && owner.index === 2, "owner records seq, chat and message index");
assert(owner.strategy === strategy && owner.model === model, "owner pins the strategy and model the request was built with");

assert(Ai.streamTargetIndex(owner, "chat-a", chatA()) === 2, "a chunk writes into the message the request owns");

// Appends are the one mutation that must stay safe: a system message or a
// function result lands after the placeholder and cannot move it.
const appended = chatA();
appended.push({
    role: "system",
    content: "Clipboard read failed."
});
assert(Ai.streamTargetIndex(owner, "chat-a", appended) === 2, "an appended system message does not move the stream target");

// Everything that replaces or shortens the conversation must drop the chunk
// instead of writing into whatever now sits at the end of the chat.
assert(Ai.streamTargetIndex(owner, "chat-b", chatA()) === -1, "a chat switch drops the chunk");
assert(Ai.streamTargetIndex(owner, "chat-a", chatA().slice(0, 2)) === -1, "a truncated chat (regenerate) drops the chunk");
assert(Ai.streamTargetIndex(owner, "chat-a", []) === -1, "a new empty chat drops the chunk");

const reloaded = chatA();
reloaded[2] = {
    role: "user",
    content: "different conversation"
};
assert(Ai.streamTargetIndex(owner, "chat-a", reloaded) === -1, "a non-assistant message on the owned index drops the chunk");

assert(Ai.streamTargetIndex(null, "chat-a", chatA()) === -1, "no in-flight request means nothing to write to");
assert(Ai.ownedIndex(Ai.requestOwner(7, "chat-a", -1, strategy, model), "chat-a", chatA()) === -1, "an unset index is never owned");

// ---------------------------------------------------------------------------
// Ownership of a delayed callback
// ---------------------------------------------------------------------------

console.log("delayed callbacks:");

assert(Ai.isRequestCurrent(owner, 7) === true, "the callback of the live request runs");
assert(Ai.isRequestCurrent(owner, 6) === false, "a callback from a superseded request is ignored");
assert(Ai.isRequestCurrent(null, 7) === false, "a callback that outlived its request is ignored");
assert(Ai.isRequestCurrent(owner, undefined) === false, "a callback with no request identity is ignored");

// The command-execution process appends its output next to the function call
// it was approved for, so it validates that exact message, not just the index.
const withCall = chatA();
withCall[2] = {
    role: "assistant",
    content: "",
    functionCall: {
        name: "run_shell_command",
        args: {
            command: "ls"
        }
    }
};
const cmdOwner = Ai.requestOwner(8, "chat-a", 2, null, null);
assert(Ai.functionCallIndex(cmdOwner, "chat-a", withCall) === 2, "command output goes back to its own function call");
assert(Ai.functionCallIndex(cmdOwner, "chat-a", chatA()) === -1, "command output is dropped when the function call is gone");
assert(Ai.functionCallIndex(cmdOwner, "chat-b", withCall) === -1, "command output is dropped after a chat switch");

// ---------------------------------------------------------------------------
// Send acceptance
// ---------------------------------------------------------------------------

console.log("send acceptance:");

const IDLE = false;
const BUSY = true;

assert(Ai.classifySend("", undefined, IDLE) === "empty", "empty input is not accepted");
assert(Ai.classifySend("   \n ", undefined, IDLE) === "empty", "whitespace-only input is not accepted");
assert(Ai.classifySend(undefined, undefined, IDLE) === "empty", "missing input is not accepted");
assert(Ai.classifySend("", [{
    path: "/tmp/a.png"
}], IDLE) === "send", "an attachment alone is sendable");
assert(Ai.classifySend("hello", undefined, IDLE) === "send", "text is sendable while idle");
assert(Ai.classifySend("hello", undefined, BUSY) === "busy", "text is refused while a request is in flight");
assert(Ai.classifySend("", [{
    path: "/tmp/a.png"
}], BUSY) === "busy", "an attachment is refused while a request is in flight");
assert(Ai.classifySend("  /help  ", undefined, BUSY) === "command", "a command is still recognized while busy");

// A refused send must report false so the sidebar can keep the draft; the
// command gate decides which commands survive a request in flight.
assert(Ai.commandConflictsWithRequest("/new", IDLE) === false, "/new runs while idle");
assert(Ai.commandConflictsWithRequest("/model", IDLE) === false, "/model runs while idle");
assert(Ai.commandConflictsWithRequest("/new", BUSY) === true, "/new is refused while a request is in flight");
assert(Ai.commandConflictsWithRequest("/model", BUSY) === true, "/model is refused while a request is in flight");
assert(Ai.commandConflictsWithRequest("/help", BUSY) === false, "/help stays available: it only appends");

// ---------------------------------------------------------------------------
// Gates that read live QML state
// ---------------------------------------------------------------------------

console.log("source gates:");

function requireIn(name, needle, msg) {
    assert(extractFunction(name).includes(needle), msg);
}

for (const fn of ["regenerateResponse", "setModel", "createNewChat", "loadChat", "approveCommand", "rejectCommand"])
    requireIn(fn, "if (isLoading)", fn + "() refuses to change the conversation while a request is in flight");

requireIn("deleteChat", "if (isLoading && id === currentChatId)", "deleteChat() refuses to delete the chat a request is streaming into");
requireIn("sendMessage", "return false", "sendMessage() reports a refusal to its caller");
requireIn("sendMessage", "return true", "sendMessage() reports acceptance to its caller");
requireIn("runCommand", "commandConflictsWithRequest(command, isLoading)", "runCommand() applies the command gate");
requireIn("makeRequest", "if (activeRequest)", "makeRequest() refuses to start a second in-flight request");
requireIn("executeRequest", "isRequestCurrent(activeRequest, payload.seq)", "executeRequest() checks it still owns the request");
requireIn("runCurl", "isRequestCurrent(activeRequest, payload.seq)", "runCurl() checks it still owns the request");
requireIn("runCurl", "owner.model", "runCurl() uses the model the request was built with");
requireIn("pushSystemMessage", "chatId !== currentChatId", "pushSystemMessage() can drop a message aimed at a chat that is gone");

// A request that never starts must say why. The user turn is already in the
// conversation by then, so a refusal that only sets `lastError` leaves a
// question with no answer and no reason -- `lastError` has no reader in the
// sidebar. Every refusal therefore routes through failWithoutRequest(), and
// makeRequest() is checked to own no refusal state of its own.
requireIn("failWithoutRequest", "pushSystemMessage(message)", "failWithoutRequest() puts the reason in the conversation");
requireIn("failWithoutRequest", "isLoading = false", "failWithoutRequest() clears the busy state");
requireIn("failWithoutRequest", "lastError = message", "failWithoutRequest() still records the error for any other reader");

const makeRequestBody = extractFunction("makeRequest");
assert(!/isLoading = false/.test(makeRequestBody), "makeRequest() clears the busy state only through failWithoutRequest()");
assert(!/lastError = /.test(makeRequestBody), "makeRequest() sets lastError only through failWithoutRequest()");
assert((makeRequestBody.match(/failWithoutRequest\(/g) || []).length === 3, "every makeRequest() refusal that follows a user turn is reported");
assert(!/role: "assistant",\n\s+content: "Error: "/.test(src), "an error is never rendered as something the assistant said");

// The stream must never read the mutable current strategy: the model selector
// can point somewhere else by the time a chunk arrives.
assert(!/root\.currentStrategy/.test(src), "no callback parses a chunk with the live currentStrategy");
assert(src.includes("owner.strategy.parseStreamChunk"), "the stream parses with the strategy captured at request time");
assert(src.includes("root.streamTargetIndex(owner, root.currentChatId, root.currentChat)"), "the stream writes through the ownership check");
assert(!/newChat\[newChat\.length - 1\]\.content = root\.responseBuffer/.test(src), "the stream no longer writes into the last message of whatever chat is current");

// ---------------------------------------------------------------------------
// Request failure reporting
// ---------------------------------------------------------------------------

console.log("failure reporting:");

// A clean curl exit used to be taken as a successful turn. It is not: with
// plain `-s`, an HTTP 401 or 429 exits 0 with an error document on stdout, and
// the handler wrote "no response received" over it.
assert(/"--fail-with-body"/.test(src), "curl fails the request on an HTTP error status");
assert(/"-sS"/.test(src) && !/"curl", "-s",/.test(src), "curl still reports its own diagnostics on stderr");
assert(/"-K", "-"/.test(src), "headers still go through stdin, never argv");

const exitBody = src.slice(src.indexOf("id: curlProcess"));
assert(/exitCode !== 0 \|\| root\.streamError !== ""/.test(exitBody), "a parser error counts as a failure even at exit code 0");
assert(/role: "system"/.test(exitBody), "a failed request is reported as a notice, not as something the assistant said");

// describeRequestFailure() picks the most useful of three sources. Run the real
// one against a stub context rather than restating its order here.
function reasonWith(state) {
    const ctx = Object.assign({
        streamError: "",
        rawTail: "",
        I18n: {t: key => key + ": %1"}
    }, state);
    const make = new Function("ctx", "with (ctx) { " + extractFunction("describeRequestFailure") + " return describeRequestFailure; }");
    return make(ctx);
}

assert(reasonWith({streamError: "quota exceeded"})(22, "curl: (22) 429") === "ai.request_failed: quota exceeded",
    "the provider's own parsed error is preferred over curl's");
assert(reasonWith({rawTail: '{"error":"model not found"}\n'})(22, "curl: (22) 404") === 'ai.request_failed: {"error":"model not found"}',
    "the provider's error body is preferred over curl's exit message");
assert(reasonWith({})(6, "curl: (6) Could not resolve host") === "ai.network_failed: curl: (6) Could not resolve host",
    "a transport failure falls back to curl's diagnostic");
assert(reasonWith({})(7, "   ") === "ai.network_failed: curl exit 7",
    "a silent failure still names the exit code rather than reporting nothing");

// ---------------------------------------------------------------------------
// Cancellation
// ---------------------------------------------------------------------------

console.log("cancellation:");

const cancelBody = extractFunction("cancelRequest");
assert(/if \(!owner\)\s*\n\s*return false;/.test(cancelBody), "cancelRequest() reports that there was nothing to stop");
assert(/TurretService\.cancel\(\)/.test(cancelBody), "a turret turn is cancelled by the daemon that owns its processes");
assert(/curlProcess\.running = false/.test(cancelBody), "a cloud request kills its own curl");
assert(/cancelling = true/.test(cancelBody), "the stop is flagged so the exit handler does not report it as a failure");
assert(/activeRequest = null/.test(cancelBody) && /isLoading = false/.test(cancelBody), "cancelRequest() releases the request and the busy state");
assert(/root\.cancelling/.test(exitBody), "the exit handler honours a user-requested stop");

// finishCancelled() decides what is left behind. Run the real one.
function cancelledChat(chat, target) {
    const ctx = {
        currentChat: chat,
        responseBuffer: "buffered",
        streamError: "parser said no",
        rawTail: "raw",
        I18n: {t: key => key},
        saveCurrentChat: () => {}
    };
    const make = new Function("ctx", "with (ctx) { " + extractFunction("finishCancelled") + " return finishCancelled; }");
    make(ctx)(target);
    return ctx;
}

const partial = cancelledChat([{role: "user", content: "hi"}, {role: "assistant", content: "half an ans"}], 1);
assert(partial.currentChat.length === 3, "a partially streamed reply is kept and the stop is noted after it");
assert(partial.currentChat[1].content === "half an ans" && partial.currentChat[1].interrupted === true, "the kept reply is marked interrupted rather than rewritten");
assert(partial.currentChat[2].role === "system" && partial.currentChat[2].content === "ai.stopped", "the stop is reported as a notice");

const empty = cancelledChat([{role: "user", content: "hi"}, {role: "assistant", content: ""}], 1);
assert(empty.currentChat.length === 2, "an empty placeholder is removed rather than left as a blank bubble");
assert(empty.currentChat[1].role === "system", "only the stop notice remains after the user turn");

assert(partial.responseBuffer === "" && partial.streamError === "" && partial.rawTail === "", "cancelling clears the request-scoped buffers");

const noTarget = cancelledChat([{role: "user", content: "hi"}], -1);
assert(noTarget.currentChat.length === 2, "a stop with no owned message still says it stopped");

console.log("\nAi request lifecycle: all checks passed");
