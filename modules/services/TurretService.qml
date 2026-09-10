pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.globals

// Frontend mirror of the backend assistant service.
//
// This holds no logic of its own on purpose. The microphone, the model client,
// every worker process and the whole state machine live in the Go daemon; QML
// only reflects what the backend reports and forwards two intents back
// (activate, cancel). That split is what keeps a shell reload from orphaning a
// recording process, and keeps the model endpoint somewhere QML cannot point
// off-machine.
Singleton {
    id: root

    // Mirrors the backend state names verbatim; see pkg/svc/assistant.
    property string state: "idle"
    property string transcript: ""
    property string response: ""
    property string lastError: ""

    // Backend events can be dropped when a subscriber queue is full
    // (pkg/ipc/server.go's Push discards rather than blocks), so every event
    // carries the full state plus a sequence number. Out-of-order or stale
    // events are ignored rather than applied.
    property int seq: -1

    readonly property bool busy: state !== "idle" && state !== "error" && state !== "cancelled"
    readonly property bool capturing: state === "listening"

    // Memories awaiting the user's decision. Surfaced in the notch so a save
    // never happens silently and never needs hunting for in a settings page.
    // Model-server reachability. A stopped server is the most common reason the
    // assistant fails, and it is repairable, so it gets its own visible state
    // rather than surfacing as a generic error at turn time.
    property bool llmReachable: true
    property string llmError: ""
    property string embedError: ""

    property int pendingMemories: 0
    // Master switch. When false nothing polls, no database is open, no process
    // runs, and the notch stays hidden.
    property bool enabled: false
    property bool memoryEnabled: false
    property var reviewQueue: []

    property int subHandle: -1

    signal failed(string message)

    // One entry point for the keybind: show the notch, then let the backend
    // decide whether this press starts listening, stops listening, or
    // interrupts a reply in progress.
    function activate() {
        if (!root.enabled) {
            root.failed("The turret assistant is off. Turn it on in Settings.");
            return;
        }
        if (!GlobalStates.turretVisible)
            GlobalStates.toggleTurret();
        BackendService.call("assistant.toggle", {}, (result, error) => {
            if (error)
                root.failed(String(error));
        });
    }

    function cancel() {
        BackendService.call("assistant.cancel", {});
    }

    // Reports which local dependencies are actually present, so the UI can name
    // a missing piece instead of failing mid-turn.
    function check(callback) {
        BackendService.call("assistant.check", {}, callback);
    }

    function _apply(data) {
        if (!data)
            return;
        const incoming = data.seq === undefined ? root.seq + 1 : data.seq;
        if (incoming < root.seq)
            return;
        root.seq = incoming;
        root.state = data.state || "idle";
        root.transcript = data.transcript || "";
        root.response = data.response || "";
        root.lastError = data.error || "";
        root.enabled = data.enabled === true;
        root.memoryEnabled = data.memory_enabled === true;
        root.llmReachable = data.llm_reachable !== false;
        root.llmError = data.llm_error || "";
        root.embedError = data.embed_error || "";
        const pending = data.pending_memories || 0;
        if (pending !== root.pendingMemories) {
            root.pendingMemories = pending;
            if (pending > 0)
                root.refreshReviewQueue();
            else
                root.reviewQueue = [];
        }
    }

    function refreshReviewQueue() {
        BackendService.call("assistant.memory.pending", {}, (result, error) => {
            if (error || !result) {
                root.reviewQueue = [];
                return;
            }
            root.reviewQueue = result.items || [];
        });
    }

    function confirmMemory(id) {
        BackendService.call("assistant.memory.confirm", {id: id}, () => root.refreshReviewQueue());
    }

    function forgetMemory(id, callback) {
        BackendService.call("assistant.memory.forget", {id: id}, (result, error) => {
            root.refreshReviewQueue();
            if (callback)
                callback(result, error);
        });
    }

    function forgetAllMemories(callback) {
        BackendService.call("assistant.memory.forget", {all: true}, callback);
    }

    function listMemories(callback) {
        BackendService.call("assistant.memory.list", {}, callback);
    }

    function checkHealth(callback) {
        BackendService.call("assistant.health", {}, callback);
    }

    function repairServer(callback) {
        BackendService.call("assistant.health", {repair: true}, callback);
    }

    function stopServer(callback) {
        BackendService.call("assistant.health", {stop: true}, callback);
    }

    function memoryStats(callback) {
        BackendService.call("assistant.memory.stats", {}, callback);
    }

    function getConfig(callback) {
        BackendService.call("assistant.config", {}, callback);
    }

    function setConfig(patch, callback) {
        BackendService.call("assistant.set", patch, callback);
    }

    function listVoices(callback) {
        BackendService.call("assistant.voices", {}, callback);
    }

    function checkDeps(callback) {
        BackendService.call("assistant.check", {}, callback);
    }

    function testVoice(text) {
        BackendService.call("assistant.say", {text: text});
    }

    function correctMemory(id, content, callback) {
        BackendService.call("assistant.memory.correct", {id: id, content: content}, callback);
    }

    Component.onCompleted: {
        root.subHandle = BackendService.addSubscription(["assistant"], (service, data) => {
            if (service !== "assistant.state")
                return;
            Qt.callLater(() => root._apply(data));
        });
    }
}
