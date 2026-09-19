pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.services
import qs.modules.globals
import "ai"
import "ai/strategies"

Singleton {
    id: root

    // ============================================
    // PROPERTIES
    // ============================================

    property string chatDir: Quickshell.env("HOME") + "/.local/share/ambxst/chats"
    property string tmpDir: "/tmp/ambxst-ai"

    property list<AiModel> models: []

    property AiModel currentModel: models.length > 0 ? models[0] : null
    property bool persistenceReady: false
    property string savedModelId: ""
    property bool isRestored: false

    onCurrentModelChanged: {
        if (persistenceReady && currentModel && isRestored) {
            StateService.set("lastAiModel", currentModel.model);
        }
        updateStrategy();
    }

    function restoreModel() {
        const lastModelId = StateService.get("lastAiModel", "gemini-2.0-flash");
        savedModelId = lastModelId;
        tryRestore();
        persistenceReady = true;
    }

    function tryRestore() {
        if (isRestored || models.length === 0)
            return;

        let found = false;

        for (let i = 0; i < models.length; i++) {
            if (models[i].model === savedModelId) {
                currentModel = models[i];
                found = true;
                break;
            }
        }

        if (!found && savedModelId) {
            for (let i = 0; i < models.length; i++) {
                if (models[i].model.endsWith(savedModelId) || models[i].model.endsWith("/" + savedModelId)) {
                    currentModel = models[i];
                    found = true;
                    break;
                }
            }
        }

        if (found)
            isRestored = true;
    }

    property bool _restored: false
    Connections {
        target: StateService
        function onInitializedChanged() {
            root._restore();
        }
    }
    Connections {
        target: KeyStore
        function onKeysChanged() {
            fetchAvailableModels();
        }
    }

    Component.onCompleted: root._restore()

    function _restore() {
        if (StateService.initialized && !root._restored) {
            root._restored = true;
            restoreModel();
        }
    }

    // The sidebar can be opened before StateService reports initialised, in
    // which case _restore has not run and persistenceReady is still false --
    // so a selection made in that window was silently dropped. Opening the
    // panel is late enough that state is available in practice; this is the
    // backstop for the case where the signal was missed entirely.
    function ensureRestored() {
        root._restore();
        if (!root.persistenceReady && StateService.initialized)
            restoreModel();
    }

    // Lazy init: trigger fetchAvailableModels/reloadHistory/createNewChat
    // when AI sidebar is opened for the first time.
    property bool _aiInitialized: false
    function _ensureInit() {
        if (_aiInitialized) return;
        _aiInitialized = true;
        // Order matters: registering the turret first would leave
        // models.length === 1, and the fetch below is guarded on the list being
        // empty -- which silently skipped discovery of every cloud model.
        ensureRestored();
        if (models.length === 0)
            fetchAvailableModels();
        registerTurretModel();
        reloadHistory();
        createNewChat();
    }

    // The turret's reply streams in over the assistant state broadcast, which
    // TurretService already mirrors. Nothing new is transported here: partial
    // text lands in `response` exactly as it does for a spoken turn, and this
    // copies it into the streaming message the chat is already rendering.
    Connections {
        target: TurretService
        enabled: root.turretActive

        function onResponseChanged() {
            const owner = root.activeRequest;
            if (!owner)
                return;
            const target = root.streamTargetIndex(owner, root.currentChatId, root.currentChat);
            if (target < 0)
                return;
            let chat = Array.from(root.currentChat);
            chat[target] = Object.assign({}, chat[target], {
                content: TurretService.response
            });
            root.currentChat = chat;
        }

        // The turn ends when the backend leaves its busy states. `busy` is
        // false for idle, error and cancelled, which are exactly the three
        // ways a turn can stop -- so this needs no state-name list of its own
        // that could drift from the backend's.
        function onBusyChanged() {
            if (TurretService.busy)
                return;
            const owner = root.activeRequest;
            if (!owner)
                return;

            if (TurretService.lastError) {
                root.failRequest(owner.seq, TurretService.lastError);
                return;
            }

            const target = root.streamTargetIndex(owner, root.currentChatId, root.currentChat);
            root.activeRequest = null;
            root.isLoading = false;
            // An empty reply is a failed turn, not an answer. Leaving the
            // blank bubble in place would look like the assistant chose to
            // say nothing.
            if (target >= 0 && !root.currentChat[target].content) {
                let chat = Array.from(root.currentChat);
                chat.splice(target, 1);
                root.currentChat = chat;
            }
        }
    }

    // A spoken turn lands in the same conversation as a typed one. Without
    // this the panel would show only what was typed, and the voice would be a
    // second, invisible conversation happening beside it.
    Connections {
        target: TurretService
        enabled: root.turretActive

        function onTranscriptChanged() {
            const text = TurretService.transcript;
            if (!text)
                return;
            // Only for a turn this panel did not start: a typed turn already
            // pushed its user message, and the backend echoes the prompt back
            // as the transcript.
            if (root.activeRequest)
                return;

            let chat = Array.from(root.currentChat);
            chat.push({
                role: "user",
                content: text
            });
            chat.push({
                role: "assistant",
                content: "",
                model: root.currentModel ? root.currentModel.name : "Turret (local)"
            });
            root.currentChat = chat;

            root.requestSeq += 1;
            root.activeRequest = root.requestOwner(root.requestSeq, root.currentChatId, chat.length - 1, null, root.currentModel);
            root.isLoading = true;
        }
    }

    // Trigger lazy init when AI sidebar is opened
    Connections {
        target: GlobalStates
        function onAssistantVisibleChanged() {
            if (GlobalStates.assistantVisible)
                root._ensureInit();
        }
    }

    // ============================================
    // STRATEGIES
    // ============================================

    property OpenAiApiStrategy openaiStrategy: OpenAiApiStrategy {}
    property GeminiApiStrategy geminiStrategy: GeminiApiStrategy {}
    property AnthropicApiStrategy anthropicStrategy: AnthropicApiStrategy {}
    property MistralApiStrategy mistralStrategy: MistralApiStrategy {}
    property GroqApiStrategy groqStrategy: GroqApiStrategy {}
    property OllamaApiStrategy ollamaStrategy: OllamaApiStrategy {}
    property MiniMaxApiStrategy minimaxStrategy: MiniMaxApiStrategy {}

    property ApiStrategy currentStrategy: openaiStrategy

    function getStrategyForProvider(providerName) {
        switch (providerName) {
        case "openai": return openaiStrategy;
        case "gemini": return geminiStrategy;
        case "anthropic": return anthropicStrategy;
        case "mistral": return mistralStrategy;
        case "groq": return groqStrategy;
        case "ollama": return ollamaStrategy;
        case "minimax": return minimaxStrategy;
        case "custom": return openaiStrategy; // custom endpoints use OpenAI-compatible format by default
        default: return openaiStrategy;
        }
    }

    function updateStrategy() {
        if (currentModel)
            currentStrategy = getStrategyForProvider(currentModel.provider);
        else
            currentStrategy = openaiStrategy;
    }

    // ============================================
    // STATE
    // ============================================

    property bool isLoading: false
    property string lastError: ""
    property string responseBuffer: ""

    // Current Chat
    property var currentChat: []
    property string currentChatId: ""

    // Chat History List (files)
    property var chatHistory: []

    FileView {
        id: chatFileView
        printErrors: false
    }

    FileView {
        id: bodyFileView
        printErrors: false
    }

    // ============================================
    // REQUEST LIFECYCLE
    // ============================================

    // Exactly one request may be in flight. `activeRequest` is the snapshot of
    // who owns it: the chat it was issued from, the index of the assistant
    // message it streams into, and the strategy/model it was built with. Every
    // delayed callback (mkdir, callLater, curl, command execution) validates
    // against this snapshot instead of reading the live `currentChat` /
    // `currentChatId` / `currentStrategy`, which can change under it.
    property var activeRequest: null
    property int requestSeq: 0

    // The helpers below are pure JS with no QML dependencies; they are
    // extracted and unit-tested by tests/ai-request-lifecycle.test.js. Keep
    // them free of QML identifiers and of braces inside string literals.

    function requestOwner(seq, chatId, index, strategy, model) {
        return {
            seq: seq,
            chatId: chatId,
            index: index,
            strategy: strategy,
            model: model
        };
    }

    // A delayed callback may only act if it still owns the in-flight request.
    function isRequestCurrent(owner, seq) {
        return !!owner && owner.seq === seq;
    }

    // The owned message index, or -1 once the conversation moved on.
    function ownedIndex(owner, chatId, chat) {
        if (!owner || !chat)
            return -1;
        if (owner.chatId !== chatId)
            return -1;
        if (owner.index < 0 || owner.index >= chat.length)
            return -1;
        return owner.index;
    }

    // Index of the placeholder a stream may write into. Appends after it (a
    // system message, a function result) leave it valid; truncation, a chat
    // switch, or a different message landing on the index invalidate it.
    function streamTargetIndex(owner, chatId, chat) {
        const i = ownedIndex(owner, chatId, chat);
        if (i < 0)
            return -1;
        const msg = chat[i];
        return msg && msg.role === "assistant" ? i : -1;
    }

    // Index of the function-call message a command execution belongs to.
    function functionCallIndex(owner, chatId, chat) {
        const i = ownedIndex(owner, chatId, chat);
        if (i < 0)
            return -1;
        const msg = chat[i];
        return msg && msg.functionCall ? i : -1;
    }

    // What sendMessage() should do with an input: nothing ("empty"), run it as
    // a slash command ("command"), refuse it because a request owns the
    // conversation ("busy"), or send it ("send").
    function classifySend(text, attachments, busy) {
        const trimmed = typeof text === "string" ? text.trim() : "";
        const hasAttachments = !!attachments && attachments.length > 0;
        if (trimmed === "" && !hasAttachments)
            return "empty";
        if (trimmed.startsWith("/"))
            return "command";
        return busy ? "busy" : "send";
    }

    // Commands that rewrite the conversation cannot run while a request owns
    // it; append-only ones stay available.
    function commandConflictsWithRequest(command, busy) {
        if (!busy)
            return false;
        return command === "/new" || command === "/model";
    }

    // Ends the request `seq` owns. A stale callback is ignored.
    function failRequest(seq, message) {
        if (!isRequestCurrent(activeRequest, seq))
            return false;
        activeRequest = null;
        isLoading = false;
        lastError = message;
        return true;
    }

    // ============================================
    // TOOLS
    // ============================================

    // Returns true when the regeneration was started.
    function regenerateResponse(index) {
        if (isLoading)
            return false;
        if (index < 0 || index >= currentChat.length)
            return false;

        let newChat = currentChat.slice(0, index);
        currentChat = newChat;

        lastError = "";
        return makeRequest();
    }

    function updateMessage(index, newContent) {
        if (isLoading)
            return false;
        if (index < 0 || index >= currentChat.length)
            return;

        let newChat = Array.from(currentChat);
        let msg = newChat[index];
        msg.content = newContent;
        newChat[index] = msg;

        currentChat = newChat;
        saveCurrentChat();
    }

    // `run_shell_command` hands one model-produced string full user authority:
    // an approved call runs as ["bash", "-c", args.command]. It is therefore
    // OFF unless explicitly enabled, and `Config.ai.tool` -- which already
    // existed, defaulted to "none", and was never read -- is the switch.
    //
    // With no tools advertised the model is never offered the capability at
    // all, which is stronger than relying on the approval dialog to catch every
    // case. The turret assistant deliberately does not use this path.
    readonly property bool toolsEnabled: (Config.ai.tool ?? "none") !== "none"
    readonly property var systemTools: toolsEnabled ? shellTools : []

    readonly property var shellTools: [
        {
            name: "run_shell_command",
            description: "Execute a shell command on the user's system (Linux). Use this to list files, control the system, or run utilities. Output will be returned.",
            parameters: {
                type: "object",
                properties: {
                    command: {
                        type: "string",
                        description: "The shell command to run (e.g. 'ls -la', 'ip addr')"
                    }
                },
                required: ["command"]
            }
        }
    ]

    // ============================================
    // CHAT MANAGEMENT
    // ============================================

    // Deleting the chat a request is streaming into would strand it; deleting
    // any other chat stays available. Returns true when the delete was started.
    function deleteChat(id) {
        if (isLoading && id === currentChatId)
            return false;

        if (id === currentChatId)
            createNewChat();

        let filename = chatDir + "/" + id + ".json";
        deleteChatProcess.command = ["rm", filename];
        deleteChatProcess.running = true;
        return true;
    }

    // ============================================
    // LOGIC
    // ============================================

    // Switching the model swaps `currentStrategy`, so it is refused while a
    // request is in flight. Returns true when the model was switched.
    function setModel(modelName) {
        if (isLoading)
            return false;

        for (let i = 0; i < models.length; i++) {
            if (models[i].name === modelName) {
                currentModel = models[i];
                // Persist here rather than relying on onCurrentModelChanged.
                // That handler only writes once `isRestored` is true, and
                // `isRestored` only became true when a previously saved model
                // was found -- so on a profile that had never saved one, the
                // selection could never be written and the picker reset on
                // every reload. An explicit choice is always worth saving.
                root.savedModelId = models[i].model;
                root.isRestored = true;
                if (root.persistenceReady)
                    StateService.set("lastAiModel", models[i].model);
                return true;
            }
        }
        return false;
    }

    function getApiKey(model) {
        if (!model || !model.requires_key)
            return "";

        // Try KeyStore first
        let ksKey = KeyStore.getKey(model.provider);
        if (ksKey)
            return ksKey;

        return "";
    }

    // Runs a slash command. Returns "none" when the text is not a command we
    // own, "handled" when it ran, and "rejected" when it would rewrite a
    // conversation the in-flight request owns.
    function runCommand(text) {
        let cmd = text.trim();
        if (!cmd.startsWith("/"))
            return "none";

        let parts = cmd.split(" ");
        let command = parts[0].toLowerCase();
        let args = parts.slice(1).join(" ");

        if (commandConflictsWithRequest(command, isLoading))
            return "rejected";

        switch (command) {
        case "/new":
            createNewChat();
            return "handled";
        case "/model":
            if (args) {
                let found = false;
                for (let i = 0; i < models.length; i++) {
                    if (models[i].name.toLowerCase().includes(args.toLowerCase()) || models[i].model.toLowerCase() === args.toLowerCase()) {
                        found = setModel(models[i].name);
                        break;
                    }
                }
                if (!found) {
                    pushSystemMessage("Model '" + args + "' not found.");
                } else {
                    pushSystemMessage("Switched to model: " + currentModel.name);
                }
            } else {
                modelSelectionRequested();
            }
            return "handled";
        case "/help":
            pushSystemMessage("🤖 **Assistant Commands**\n\n" + "**`/new`**\n" + "Starts a fresh conversation context.\n\n" + "**`/model [name]`**\n" + "Switches the active AI model.\n" + "• **List models:** Type `/model` without arguments.\n" + "• **Switch:** Type `/model gemini` or `/model mistral`.\n\n" + "**`/help`**\n" + "Shows this help message.\n\n" + "💡 **Tips:**\n" + "• **Edit:** Click the pen icon on any message to modify it.\n" + "• **Regenerate:** Click the refresh icon to get a new response.\n" + "• **Copy:** Use the copy button to grab code or text.");
            return "handled";
        }

        return "none";
    }

    // Kept for callers that only need to know whether the text was consumed.
    function processCommand(text) {
        return runCommand(text) === "handled";
    }

    // Append-only, so it can never move the message an in-flight request
    // streams into. `chatId` is optional: a delayed caller that passes the chat
    // it was started from gets its message dropped instead of landing in
    // whatever chat happens to be current now.
    function pushSystemMessage(text, chatId) {
        if (chatId !== undefined && chatId !== currentChatId)
            return false;

        let newChat = Array.from(currentChat);
        newChat.push({
            role: "system",
            content: text
        });
        currentChat = newChat;
        return true;
    }

    // Function Call Handling
    // The approval itself stays explicit: only a message that actually carries
    // an unresolved function call can be approved, and only once.
    function approveCommand(index) {
        if (isLoading)
            return false;
        if (index < 0 || index >= currentChat.length)
            return false;

        let msg = currentChat[index];
        if (!msg || !msg.functionCall || msg.functionPending === false)
            return false;
        if (msg.functionCall.name !== "run_shell_command")
            return false;
        // Defence in depth: a proposal made while tools were enabled must not
        // remain executable after they are turned off.
        if (!toolsEnabled) {
            pushSystemMessage("Command execution is disabled. Enable it in Settings → AI if you want this.");
            return false;
        }

        let newChat = Array.from(currentChat);
        newChat[index].functionPending = false;
        newChat[index].functionApproved = true;
        currentChat = newChat;
        saveCurrentChat();

        let args = msg.functionCall.args;
        // The follow-up request is part of this turn, so the command execution
        // holds the busy state until it either issues that request or is
        // dropped for having lost its conversation.
        requestSeq += 1;
        isLoading = true;
        commandExecutionProc.owner = requestOwner(requestSeq, currentChatId, index, null, null);
        commandExecutionProc.command = ["bash", "-c", args.command];
        commandExecutionProc.running = true;
        return true;
    }

    function rejectCommand(index) {
        if (isLoading)
            return false;
        if (index < 0 || index >= currentChat.length)
            return false;

        let msg = currentChat[index];
        if (!msg || !msg.functionCall || msg.functionPending === false)
            return false;

        let newChat = Array.from(currentChat);
        newChat[index].functionPending = false;
        newChat[index].functionApproved = false;

        newChat.push({
            role: "function",
            name: msg.functionCall.name,
            content: "User rejected the command execution."
        });

        currentChat = newChat;
        saveCurrentChat();
        return makeRequest();
    }

    // Returns true when the input was accepted — sent, or run as a command.
    // False means nothing was consumed and the caller should keep the draft:
    // empty input, a request already in flight, or a command that conflicts
    // with it.
    function sendMessage(text, attachments) {
        const kind = classifySend(text, attachments, isLoading);
        if (kind === "empty")
            return false;

        if (kind === "command") {
            const outcome = runCommand(text);
            if (outcome === "handled")
                return true;
            if (outcome === "rejected")
                return false;
            // Not a command we own — falls through and is sent as plain text.
            if (isLoading)
                return false;
        } else if (kind === "busy") {
            return false;
        }

        lastError = "";
        let userMsg = {
            role: "user",
            content: text
        };
        if (attachments && attachments.length > 0)
            userMsg.attachments = attachments;
        let newChat = Array.from(currentChat);
        newChat.push(userMsg);
        currentChat = newChat;
        saveCurrentChat();
        makeRequest();
        return true;
    }

    // Issues the single in-flight request against a snapshot of the current
    // chat, message index, strategy and model. Returns true when it started.
    function makeRequest() {
        if (activeRequest)
            return false;

        let model = currentModel;
        if (!model) {
            lastError = "No AI model available.";
            isLoading = false;
            return false;
        }

        // The turret answers over IPC, and keeps its own conversation history
        // in the daemon -- so only the newest user message is sent, not the
        // whole chat. Replaying the log here would double every exchange.
        if (model.provider === turretProvider) {
            let prompt = "";
            for (let i = currentChat.length - 1; i >= 0; i--) {
                if (currentChat[i].role === "user") {
                    prompt = currentChat[i].content;
                    break;
                }
            }
            if (!prompt) {
                lastError = "Nothing to ask.";
                isLoading = false;
                return false;
            }

            let turretChat = Array.from(currentChat);
            turretChat.push({
                role: "assistant",
                content: "",
                model: model.name
            });
            currentChat = turretChat;

            requestSeq += 1;
            activeRequest = requestOwner(requestSeq, currentChatId, turretChat.length - 1, null, model);
            isLoading = true;
            responseBuffer = "";

            const seq = requestSeq;
            BackendService.call("assistant.ask", {
                text: prompt,
                speak: Config.ai?.turretSpeak ?? false
            }, (result, error) => {
                // A refusal (assistant off, busy, remote endpoint) arrives as
                // the callback's second argument and must clear the spinner.
                // The streamed reply itself does not come back here at all --
                // it arrives on the TurretService subscription.
                if (error)
                    root.failRequest(seq, String(error));
            });
            return true;
        }

        let apiKey = getApiKey(model);
        if (!apiKey && model.requires_key) {
            lastError = "API Key missing for " + model.name + ". Add it in Settings or set " + (model.key_id || "the environment variable") + ".";
            isLoading = false;

            let errChat = Array.from(currentChat);
            errChat.push({
                role: "assistant",
                content: "Error: " + lastError
            });
            currentChat = errChat;
            return false;
        }

        let strategy = getStrategyForProvider(model.provider);

        // Determine endpoint — Gemini streaming uses a different endpoint
        let endpoint;
        let isGemini = model.provider === "gemini";
        if (isGemini && geminiStrategy._getStreamEndpoint) {
            endpoint = geminiStrategy._getStreamEndpoint(model, apiKey);
        } else {
            endpoint = strategy.getEndpoint(model, apiKey);
        }

        let headers = strategy.getHeaders(apiKey);

        // Build messages array
        let messages = [];
        if (Config.ai.systemPrompt) {
            messages.push({
                role: "system",
                content: Config.ai.systemPrompt
            });
        }

        for (let i = 0; i < currentChat.length; i++) {
            let msg = currentChat[i];
            let apiMsg = {
                role: msg.role,
                content: msg.content
            };
            if (msg.attachments)
                apiMsg.attachments = msg.attachments;
            if (msg.functionCall)
                apiMsg.functionCall = msg.functionCall;
            if (msg.geminiParts)
                apiMsg.geminiParts = msg.geminiParts;
            if (msg.name)
                apiMsg.name = msg.name;
            messages.push(apiMsg);
        }

        // Build body — always use streaming
        let body = strategy.getStreamBody(messages, model, systemTools);

        // Reset streaming buffer
        responseBuffer = "";

        // Add placeholder assistant message for streaming
        let streamChat = Array.from(currentChat);
        streamChat.push({
            role: "assistant",
            content: "",
            model: model.name
        });
        currentChat = streamChat;

        requestSeq += 1;
        activeRequest = requestOwner(requestSeq, currentChatId, streamChat.length - 1, strategy, model);
        isLoading = true;

        writeTempBody(JSON.stringify(body), headers, endpoint, requestSeq);
        return true;
    }

    function writeTempBody(jsonBody, headers, endpoint, seq) {
        requestProcess.command = ["/usr/bin/mkdir", "-p", tmpDir];
        requestProcess.step = "mkdir";
        requestProcess.payload = {
            body: jsonBody,
            headers: headers,
            endpoint: endpoint,
            seq: seq
        };
        requestProcess.running = true;
    }

    function executeRequest(payload) {
        if (!isRequestCurrent(activeRequest, payload.seq))
            return;

        let bodyPath = tmpDir + "/body.json";
        bodyFileView.path = bodyPath;
        bodyFileView.setText(payload.body);
        Qt.callLater(() => runCurl(payload));
    }

    function runCurl(payload) {
        if (!isRequestCurrent(activeRequest, payload.seq))
            return;

        let owner = activeRequest;
        let bodyPath = tmpDir + "/body.json";

        // Check for custom curl template — of the model this request was built
        // with, not whatever is selected by the time curl actually runs.
        let customCurl = "";
        if (owner.model && owner.model.customCurlTemplate) {
            customCurl = owner.model.customCurlTemplate;
        } else if (owner.model && KeyStore.getCustomCurl(owner.model.provider)) {
            customCurl = KeyStore.getCustomCurl(owner.model.provider);
        }

        if (customCurl) {
            // The key goes through the environment, never into the command
            // string.
            //
            // Substituting it into the text handed to `bash -c` put it in the
            // process's own argv, where any process owned by this user can read
            // it out of /proc/<pid>/cmdline, and made a key containing shell
            // metacharacters into command execution. That is the same defect
            // fixed for model discovery on 2026-09-10, still present on this
            // path. The template is the user's own, so it stays a shell command
            // -- that is the feature -- but the secret in it does not have to be
            // literal.
            const curlCmd = customCurl
                .replace("{{BODY_PATH}}", bodyPath)
                .replace("{{ENDPOINT}}", payload.endpoint)
                .replace("{{API_KEY}}", "$AMBXST_API_KEY");
            curlProcess.environment = ({
                "AMBXST_API_KEY": getApiKey(owner.model)
            });
            curlProcess.command = ["/usr/bin/bash", "-c", curlCmd];
        } else {
            // Headers go through `curl -K -`, never argv.
            //
            // They carry the API key -- `Authorization: Bearer ...`, or a
            // provider-specific key header -- and argv is readable from
            // /proc/<pid>/cmdline by any process this user owns. Model
            // discovery was moved onto this exact pattern on 2026-09-10 and the
            // request path, which runs far more often, was left behind.
            //
            // curl reads its options from stdin and treats EOF as "the config
            // is complete", which is why onStarted closes it.
            curlProcess.environment = ({});
            const quoted = (v) => '"' + String(v).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
            let cfg = "url = " + quoted(payload.endpoint) + "\n"
                + "request = POST\n"
                + "data = " + quoted("@" + bodyPath) + "\n";
            for (const header of payload.headers)
                cfg += "header = " + quoted(header) + "\n";
            curlProcess.pendingCurlConfig = cfg;
            curlProcess.command = ["curl", "-s", "--no-buffer", "-N",
                "--connect-timeout", "15", "--max-time", "300", "-K", "-"];
        }

        curlProcess.running = true;
    }

    // ============================================
    // PROCESSES
    // ============================================

    Process {
        id: requestProcess
        property string step: ""
        property var payload: ({})

        onExited: exitCode => {
            if (exitCode === 0 && step === "mkdir") {
                root.executeRequest(payload);
            } else if (exitCode !== 0) {
                root.failRequest(payload.seq, "Failed to create temp directory");
            }
        }
    }

    Process {
        id: curlProcess

        // curl -K - reads its options from stdin; closing stdin is what tells
        // it the config is complete and the request may proceed. Empty for the
        // custom-template branch, which builds its own command line.
        property string pendingCurlConfig: ""
        stdinEnabled: true
        onStarted: {
            if (pendingCurlConfig !== "") {
                write(pendingCurlConfig);
                pendingCurlConfig = "";
            }
            stdinEnabled = false;
        }

        // Use SplitParser for streaming — emits onRead per line
        stdout: SplitParser {
            onRead: data => {
                let owner = root.activeRequest;
                if (!owner || !owner.strategy)
                    return;

                // Parse with the strategy this request was built with, not the
                // one the model selector happens to point at now.
                let result = owner.strategy.parseStreamChunk(data);

                if (result.error) {
                    root.lastError = result.error;
                    return;
                }

                if (result.content) {
                    root.responseBuffer += result.content;
                    // Write into the message this request owns, not simply the
                    // last one in whatever chat is current.
                    let target = root.streamTargetIndex(owner, root.currentChatId, root.currentChat);
                    if (target < 0)
                        return;

                    let newChat = Array.from(root.currentChat);
                    newChat[target].content = root.responseBuffer;
                    root.currentChat = newChat;
                }

                // Note: done is handled in onExited
            }
        }

        stderr: StdioCollector {
            id: curlStderr
        }

        onExited: exitCode => {
            let owner = root.activeRequest;
            let target = root.streamTargetIndex(owner, root.currentChatId, root.currentChat);
            root.activeRequest = null;
            root.isLoading = false;

            if (exitCode === 0) {
                if (target >= 0) {
                    // No streaming data received — might be non-streaming response or error
                    if (!root.currentChat[target].content) {
                        let newChat = Array.from(root.currentChat);
                        newChat[target].content = root.responseBuffer !== "" ? root.responseBuffer : "No response received from the API.";
                        root.currentChat = newChat;
                    }

                    root.saveCurrentChat();
                }
            } else {
                root.lastError = "Network Request Failed: " + curlStderr.text;

                // Update the placeholder message with error
                if (target >= 0) {
                    let errChat = Array.from(root.currentChat);
                    errChat[target].content = "Error: " + root.lastError;
                    root.currentChat = errChat;
                }
            }

            root.responseBuffer = "";
        }
    }

    Process {
        id: commandExecutionProc
        property var owner: null

        stdout: StdioCollector {
            id: cmdStdout
        }
        stderr: StdioCollector {
            id: cmdStderr
        }

        onExited: exitCode => {
            let pending = commandExecutionProc.owner;
            commandExecutionProc.owner = null;

            let target = root.functionCallIndex(pending, root.currentChatId, root.currentChat);
            if (target < 0) {
                // The conversation this command belonged to is gone; drop the
                // output rather than appending it to an unrelated chat.
                root.isLoading = false;
                return;
            }

            let output = cmdStdout.text + "\n" + cmdStderr.text;
            if (output.trim() === "")
                output = "Command executed successfully (no output).";

            let newChat = Array.from(root.currentChat);
            newChat.push({
                role: "function",
                name: root.currentChat[target].functionCall.name,
                content: output
            });

            root.currentChat = newChat;
            root.saveCurrentChat();
            // makeRequest() takes over the busy state, or clears it on failure.
            root.makeRequest();
        }
    }

    // ============================================
    // CHAT STORAGE
    // ============================================

    // Both of these replace the conversation wholesale, so they are refused
    // while a request owns it. Each returns true when it was accepted.
    function createNewChat() {
        if (isLoading)
            return false;

        currentChat = [];
        currentChatId = Date.now().toString();
        chatModelChanged();
        return true;
    }

    function saveCurrentChat() {
        if (currentChat.length === 0)
            return;
        // The turret's own history is memory-only by design -- history.go says
        // "Nothing here is written to disk, ever." Routing its turns through
        // this chat must not quietly start writing local voice conversations
        // to ~/.local/share/ambxst/chats.
        if (turretActive)
            return;

        let filename = chatDir + "/" + currentChatId + ".json";
        let data = JSON.stringify(currentChat, null, 2);

        saveChatProcess.filePath = filename;
        saveChatProcess.data = data;
        saveChatProcess.command = ["/usr/bin/mkdir", "-p", chatDir];
        saveChatProcess.running = true;
    }

    function reloadHistory() {
        listHistoryProcess.command = ["ambxst", "chatlist", chatDir];
        listHistoryProcess.running = true;
    }

    function loadChat(id) {
        if (isLoading)
            return false;

        let filename = chatDir + "/" + id + ".json";
        loadChatProcess.targetId = id;
        loadChatProcess.command = ["cat", filename];
        loadChatProcess.running = true;
        return true;
    }

    Process {
        id: saveChatProcess
        property string filePath: ""
        property string data: ""
        onExited: exitCode => {
            if (exitCode === 0) {
                if (filePath.length > 0)
                    chatFileView.path = filePath;
                if (data.length > 0)
                    chatFileView.setText(data);
                reloadHistory();
            } else {
                console.warn("Failed to create chat directory");
            }
        }
    }

    Process {
        id: deleteChatProcess
        onExited: reloadHistory()
    }

    Process {
        id: listHistoryProcess
        stdout: StdioCollector {
            id: listHistoryStdout
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                let lines = listHistoryStdout.text.trim().split("\n");
                let history = [];
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i];
                    if (line === "")
                        continue;
                    let parts = line.split("|");
                    if (parts.length >= 2) {
                        history.push({
                            id: parts[0],
                            title: parts.slice(1).join("|"),
                            path: chatDir + "/" + parts[0] + ".json"
                        });
                    }
                }
                root.chatHistory = history;
                root.historyModelChanged();
            }
        }
    }

    Process {
        id: loadChatProcess
        property string targetId: ""
        stdout: StdioCollector {
            id: loadChatStdout
        }
        onExited: exitCode => {
            // A request may have started while `cat` was running; swapping the
            // conversation under it now would strand its stream.
            if (root.isLoading)
                return;

            if (exitCode === 0) {
                try {
                    root.currentChat = JSON.parse(loadChatStdout.text);
                    root.currentChatId = targetId;
                    root.chatModelChanged();
                } catch (e) {
                    console.log("Error loading chat: " + e);
                }
            }
        }
    }

    // ============================================
    // DYNAMIC MODEL FETCHING
    // ============================================

    property bool fetchingModels: false
    property int pendingFetches: 0

    function fetchAvailableModels() {
        fetchingModels = false; // Force refresh
        if (fetchingModels)
            return;

        fetchingModels = true;
        pendingFetches = 0;

        // Gemini
        let geminiKey = KeyStore.getKey("gemini");
        if (geminiKey) {
            pendingFetches++;
            startKeyedFetch(fetchProcessGemini, "https://generativelanguage.googleapis.com/v1beta/models", ["x-goog-api-key: " + geminiKey]);
        }

        // OpenAI
        let openaiKey = KeyStore.getKey("openai");
        if (openaiKey) {
            pendingFetches++;
            startKeyedFetch(fetchProcessOpenAI, "https://api.openai.com/v1/models", ["Authorization: Bearer " + openaiKey]);
        }

        // Anthropic
        let anthropicKey = KeyStore.getKey("anthropic");
        if (anthropicKey) {
            pendingFetches++;
            startKeyedFetch(fetchProcessAnthropic, "https://api.anthropic.com/v1/models", ["x-api-key: " + anthropicKey, "anthropic-version: 2023-06-01"]);
        }

        // Mistral
        let mistralKey = KeyStore.getKey("mistral");
        if (mistralKey) {
            pendingFetches++;
            startKeyedFetch(fetchProcessMistral, "https://api.mistral.ai/v1/models", ["Authorization: Bearer " + mistralKey]);
        }

        // Groq
        let groqKey = KeyStore.getKey("groq");
        if (groqKey) {
            pendingFetches++;
            startKeyedFetch(fetchProcessGroq, "https://api.groq.com/openai/v1/models", ["Authorization: Bearer " + groqKey]);
        }

        // Ollama (local)
        let ollamaEnabled = KeyStore.hasKey("ollama");
        if (ollamaEnabled) {
            pendingFetches++;
            fetchProcessOllama.command = ["curl", "-sS", "--connect-timeout", "5", "--max-time", "15", "http://127.0.0.1:11434/api/tags"];
            fetchProcessOllama.running = true;
        }

        // MiniMax
        let minimaxKey = KeyStore.getKey("minimax");
        if (minimaxKey) {
            pendingFetches++;
            fetchProcessMiniMax.command = ["true"];
            fetchProcessMiniMax.running = true;
        }

        if (pendingFetches === 0) {
            fetchingModels = false;
        }
    }

    Process {
        id: fetchProcessGemini
        // curl -K - reads its options from stdin; closing stdin is what
        // tells it the config is complete and the request may proceed.
        property string pendingCurlConfig: ""
        onStarted: {
            if (pendingCurlConfig !== "") {
                write(pendingCurlConfig);
                pendingCurlConfig = "";
            }
            stdinEnabled = false;
        }
        stdout: StdioCollector {
            id: fetchGeminiOut
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                try {
                    let data = JSON.parse(fetchGeminiOut.text);
                    if (data.models) {
                        let newModels = [];
                        for (let i = 0; i < data.models.length; i++) {
                            let item = data.models[i];
                            let id = item.name.replace("models/", "");
                            if (id.includes("gemini") || id.includes("flash") || id.includes("pro")) {
                                let m = aiModelFactory.createObject(root, {
                                    name: item.displayName || id,
                                    icon: Qt.resolvedUrl("../../../assets/aiproviders/google.svg"),
                                    description: item.description || "Google Gemini Model",
                                    endpoint: "https://generativelanguage.googleapis.com/v1beta",
                                    model: id,
                                    provider: "gemini",
                                    requires_key: true,
                                    key_id: "GEMINI_API_KEY"
                                });
                                if (m) newModels.push(m);
                            }
                        }
                        mergeModels(newModels);
                    }
                } catch (e) {
                    console.log("Gemini fetch error: " + e);
                }
            }
            checkFetchCompletion();
        }
    }

    Process {
        id: fetchProcessOpenAI
        // curl -K - reads its options from stdin; closing stdin is what
        // tells it the config is complete and the request may proceed.
        property string pendingCurlConfig: ""
        onStarted: {
            if (pendingCurlConfig !== "") {
                write(pendingCurlConfig);
                pendingCurlConfig = "";
            }
            stdinEnabled = false;
        }
        stdout: StdioCollector {
            id: fetchOpenAIOut
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                try {
                    let data = JSON.parse(fetchOpenAIOut.text);
                    if (data.data) {
                        let newModels = [];
                        let allowed = ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-4", "o1", "o1-mini", "o1-preview", "o3-mini"];
                        for (let i = 0; i < data.data.length; i++) {
                            let item = data.data[i];
                            let id = item.id;
                            let isAllowed = false;
                            for (let j = 0; j < allowed.length; j++) {
                                if (id === allowed[j] || id.startsWith(allowed[j] + "-")) {
                                    isAllowed = true;
                                    break;
                                }
                            }
                            if (isAllowed) {
                                let m = aiModelFactory.createObject(root, {
                                    name: id,
                                    icon: Qt.resolvedUrl("../../../assets/aiproviders/openai.svg"),
                                    description: "OpenAI Model",
                                    endpoint: "https://api.openai.com",
                                    model: id,
                                    provider: "openai",
                                    requires_key: true,
                                    key_id: "OPENAI_API_KEY"
                                });
                                if (m) newModels.push(m);
                            }
                        }
                        mergeModels(newModels);
                    }
                } catch (e) {
                    console.log("OpenAI fetch error: " + e);
                }
            }
            checkFetchCompletion();
        }
    }

    Process {
        id: fetchProcessMistral
        // curl -K - reads its options from stdin; closing stdin is what
        // tells it the config is complete and the request may proceed.
        property string pendingCurlConfig: ""
        onStarted: {
            if (pendingCurlConfig !== "") {
                write(pendingCurlConfig);
                pendingCurlConfig = "";
            }
            stdinEnabled = false;
        }
        stdout: StdioCollector {
            id: fetchMistralOut
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                try {
                    let data = JSON.parse(fetchMistralOut.text);
                    if (data.data) {
                        let newModels = [];
                        for (let i = 0; i < data.data.length; i++) {
                            let item = data.data[i];
                            let id = item.id;
                            let m = aiModelFactory.createObject(root, {
                                name: id,
                                icon: Qt.resolvedUrl("../../../assets/aiproviders/mistral.svg"),
                                description: "Mistral Model",
                                endpoint: "https://api.mistral.ai/v1",
                                model: id,
                                provider: "mistral",
                                requires_key: true,
                                key_id: "MISTRAL_API_KEY"
                            });
                            if (m) newModels.push(m);
                        }
                        mergeModels(newModels);
                    }
                } catch (e) {
                    console.log("Mistral fetch error: " + e);
                }
            }
            checkFetchCompletion();
        }
    }

    Process {
        id: fetchProcessGroq
        // curl -K - reads its options from stdin; closing stdin is what
        // tells it the config is complete and the request may proceed.
        property string pendingCurlConfig: ""
        onStarted: {
            if (pendingCurlConfig !== "") {
                write(pendingCurlConfig);
                pendingCurlConfig = "";
            }
            stdinEnabled = false;
        }
        stdout: StdioCollector {
            id: fetchGroqOut
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                try {
                    let data = JSON.parse(fetchGroqOut.text);
                    if (data.data) {
                        let newModels = [];
                        for (let i = 0; i < data.data.length; i++) {
                            let item = data.data[i];
                            let id = item.id;
                            let m = aiModelFactory.createObject(root, {
                                name: id,
                                icon: Qt.resolvedUrl("../../../assets/aiproviders/groq.svg"),
                                description: "Groq Model",
                                endpoint: "https://api.groq.com/openai/v1",
                                model: id,
                                provider: "groq",
                                requires_key: true,
                                key_id: "GROQ_API_KEY"
                            });
                            if (m) newModels.push(m);
                        }
                        mergeModels(newModels);
                    }
                } catch (e) {
                    console.log("Groq fetch error: " + e);
                }
            }
            checkFetchCompletion();
        }
    }

    Process {
        id: fetchProcessAnthropic
        // curl -K - reads its options from stdin; closing stdin is what
        // tells it the config is complete and the request may proceed.
        property string pendingCurlConfig: ""
        onStarted: {
            if (pendingCurlConfig !== "") {
                write(pendingCurlConfig);
                pendingCurlConfig = "";
            }
            stdinEnabled = false;
        }
        stdout: StdioCollector {
            id: fetchAnthropicOut
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                try {
                    let data = JSON.parse(fetchAnthropicOut.text);
                    if (data.data) {
                        let newModels = [];
                        for (let i = 0; i < data.data.length; i++) {
                            let item = data.data[i];
                            let id = item.id;
                            let m = aiModelFactory.createObject(root, {
                                name: item.display_name || id,
                                icon: Qt.resolvedUrl("../../../assets/aiproviders/anthropic.svg"),
                                description: item.description || "Anthropic Model",
                                endpoint: "https://api.anthropic.com/v1/messages",
                                model: id,
                                provider: "anthropic",
                                requires_key: true,
                                key_id: "ANTHROPIC_API_KEY"
                            });
                            if (m) newModels.push(m);
                        }
                        mergeModels(newModels);
                    }
                } catch (e) {
                    console.log("Anthropic fetch error: " + e);
                }
            }
            checkFetchCompletion();
        }
    }

    Process {
        id: fetchProcessOllama
        stdout: StdioCollector {
            id: fetchOllamaOut
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                try {
                    let data = JSON.parse(fetchOllamaOut.text);
                    if (data.models) {
                        let newModels = [];
                        for (let i = 0; i < data.models.length; i++) {
                            let item = data.models[i];
                            let m = aiModelFactory.createObject(root, {
                                name: item.name,
                                icon: Qt.resolvedUrl("../../../assets/aiproviders/ollama.svg"),
                                description: "Local Ollama Model",
                                endpoint: "http://127.0.0.1:11434",
                                model: item.name,
                                provider: "ollama",
                                requires_key: false
                            });
                            if (m) newModels.push(m);
                        }
                        mergeModels(newModels);
                    }
                } catch (e) {
                    console.log("Ollama fetch error: " + e);
                }
            }
            checkFetchCompletion();
        }
    }

    Process {
        id: fetchProcessMiniMax
        onExited: exitCode => {
            if (exitCode === 0) {
                let newModels = [];
                
                let models = [
                    { name: "MiniMax-M2.7", model: "MiniMax-M2.7", description: "Latest model with recursive self-improvement, SOTA coding capabilities", endpoint: "https://api.minimax.io" },
                    { name: "MiniMax-M2.7-highspeed", model: "MiniMax-M2.7-highspeed", description: "Same performance as M2.7, faster inference (~100 tps)", endpoint: "https://api.minimax.io" },
                    { name: "MiniMax-M2.5", model: "MiniMax-M2.5", description: "Peak performance, ultimate value, master the complex", endpoint: "https://api.minimax.io" },
                    { name: "MiniMax-M2.5-highspeed", model: "MiniMax-M2.5-highspeed", description: "Same performance as M2.5, faster inference (~100 tps)", endpoint: "https://api.minimax.io" },
                    { name: "MiniMax-M2.1", model: "MiniMax-M2.1", description: "Powerful multi-language programming, enhanced reasoning", endpoint: "https://api.minimax.io" },
                    { name: "MiniMax-M2.1-highspeed", model: "MiniMax-M2.1-highspeed", description: "Same performance as M2.1, faster inference (~100 tps)", endpoint: "https://api.minimax.io" },
                    { name: "MiniMax-M2", model: "MiniMax-M2", description: "Agentic capabilities, advanced reasoning, 200k context", endpoint: "https://api.minimax.io" },
                    { name: "M2-her", model: "M2-her", description: "Role-playing, multi-turn conversations, emotional expression", endpoint: "https://api.minimax.io" }
                ];
                
                for (let i = 0; i < models.length; i++) {
                    let item = models[i];
                    let m = aiModelFactory.createObject(root, {
                        name: item.name,
                        icon: Qt.resolvedUrl("../../../assets/aiproviders/minimax.svg"),
                        description: item.description,
                        endpoint: item.endpoint,
                        model: item.model,
                        provider: "minimax",
                        requires_key: true,
                        key_id: "MINIMAX_API_KEY"
                    });
                    if (m) newModels.push(m);
                }
                
                mergeModels(newModels);
            }
            checkFetchCompletion();
        }
    }



    // Model discovery used to build `["bash", "-c", "curl ... " + apiKey]` for
    // every provider. Two problems in one line, six times over: an API key is
    // user-entered text going through a shell, so a key containing $(...) or a
    // quote is command execution; and the key lands in argv, readable from
    // /proc by any process of this user.
    //
    // curl's `-K -` reads its options from stdin, so the URL and the auth
    // header never touch argv or a shell. The key exists only in this process's
    // memory and the pipe.
    function startKeyedFetch(proc, url, headers) {
        proc.command = ["curl", "-sS", "--connect-timeout", "10", "--max-time", "30", "-K", "-"];
        proc.stdinEnabled = true;
        proc.pendingCurlConfig = (() => {
            let cfg = 'url = "' + url + '"\n';
            for (let i = 0; i < headers.length; i++)
                cfg += 'header = "' + headers[i].replace(/"/g, '\\"') + '"\n';
            return cfg;
        })();
        proc.running = true;
    }

    function checkFetchCompletion() {
        pendingFetches--;
        if (pendingFetches <= 0) {
            fetchingModels = false;
            pendingFetches = 0;

            tryRestore();

            // Once every fetch has landed, the model list is as complete as it
            // is going to get, so restore is settled either way. Leaving
            // isRestored false here was half of the reset-on-reload defect:
            // a saved id that matched nothing kept persistence switched off
            // for the whole session.
            if (!currentModel && models.length > 0)
                currentModel = models[0];
            isRestored = true;
        }
    }

    // The local turret assistant, as one more entry in the model picker.
    //
    // It needs no key and no endpoint of its own: the Go daemon owns the
    // endpoint and enforces that it stays on loopback, so putting a URL here
    // would be a second source of truth that could disagree with it. The
    // `turret` provider is the signal to makeRequest() to go over IPC instead
    // of curl -- there is deliberately no ApiStrategy for it, because the
    // strategies are an HTTP contract (endpoint, headers, body, parse) and
    // none of those apply.
    readonly property string turretProvider: "turret"

    function registerTurretModel() {
        for (let i = 0; i < models.length; i++) {
            if (models[i].provider === turretProvider)
                return;
        }
        let m = aiModelFactory.createObject(root, {
            name: "Turret (local)",
            description: "Runs on this machine. Own memory and voice, nothing leaves the device.",
            endpoint: "",
            model: "turret",
            provider: turretProvider,
            requires_key: false
        });
        if (m)
            mergeModels([m]);
    }

    readonly property bool turretActive: currentModel && currentModel.provider === turretProvider

    function mergeModels(newModels) {
        let updatedList = [];
        for (let i = 0; i < models.length; i++)
            updatedList.push(models[i]);

        for (let i = 0; i < newModels.length; i++) {
            let m = newModels[i];
            let isDuplicate = false;
            for (let j = 0; j < updatedList.length; j++) {
                if (updatedList[j].model === m.model) {
                    isDuplicate = true;
                    break;
                }
            }
            if (!isDuplicate)
                updatedList.push(m);
        }

        models = updatedList;

        if (!isRestored)
            tryRestore();
    }

    // Signals
    signal chatModelChanged
    signal historyModelChanged
    signal modelSelectionRequested

    Component {
        id: aiModelFactory
        AiModel {}
    }
}
