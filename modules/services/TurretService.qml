pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.globals
import qs.modules.services

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
    // Which part failed: "microphone", "stt", "tts", "audio", "memory",
    // "provider", "timeout" or "config". The backend keeps one error state and
    // varies this instead, so the UI can point at the right setting.
    property string lastErrorKind: ""

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
    // Mirrors assistant.web_enabled. The settings panel states a security
    // property that depends on it, so it has to arrive with every state event
    // rather than being read once.
    property bool webEnabled: false
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
        // No notch to open any more: the AI notch on the right shows the
        // voice state, and it is always on screen. Push-to-talk deliberately
        // does NOT force the side panel open -- the notch animating through
        // listening and thinking is the feedback, and popping a full panel
        // over the user's work every time they hold a key is not.
        BackendService.call("assistant.toggle", {}, (result, error) => {
            if (error)
                root.failed(String(error));
        });
    }

    // Push-to-talk: the key came up.
    //
    // Hold to talk, release to send. A quick tap latches instead, leaving the
    // microphone open so the same key still works as a press-twice toggle --
    // the backend owns that rule, because it is the only side that knows when
    // listening actually began.
    function releaseKey() {
        BackendService.call("assistant.release", {}, () => {});
    }

    function cancel() {
        BackendService.call("assistant.cancel", {});
    }

    // Reports which local dependencies are actually present, so the UI can name
    // a missing piece instead of failing mid-turn.
    function check(callback) {
        BackendService.call("assistant.check", {}, callback);
    }

    // False until the first snapshot has been applied. The first event a
    // subscriber receives is the CURRENT state, not a transition to it, so
    // announcing it would chirp on every shell start that happened to catch a
    // pending memory or a turn in progress.
    property bool _seenFirstSnapshot: false

    function _apply(data) {
        if (!data)
            return;
        const incoming = data.seq === undefined ? root.seq + 1 : data.seq;
        // A sequence far BELOW ours is a new daemon, not a stale event: the
        // counter restarts at zero, and treating that as stale left the UI
        // frozen on pre-restart state until the new daemon caught up. Accept it
        // and resynchronise.
        const restarted = incoming + 1 < root.seq;
        if (restarted)
            root._seenFirstSnapshot = false;
        // Strictly newer. Equal sequence numbers were accepted, so a resent
        // snapshot could be treated as a fresh transition.
        else if (incoming <= root.seq && root._seenFirstSnapshot)
            return;
        // Events can be dropped when a subscriber queue fills (see
        // pkg/ipc/server.go), and the backend's sequence number is what reveals
        // it. A gap means the state we last saw is NOT the predecessor of this
        // one, so any cue derived from that pair would be invented.
        const contiguous = incoming === root.seq + 1;
        root.seq = incoming;
        const previousState = root.state;
        root.state = data.state || "idle";
        root.transcript = data.transcript || "";
        root.response = data.response || "";
        root.lastError = data.error || "";
        root.lastErrorKind = data.error_kind || "";
        root.enabled = data.enabled === true;
        root.memoryEnabled = data.memory_enabled === true;
        root.webEnabled = data.web_enabled === true;
        root.llmReachable = data.llm_reachable !== false;
        root.llmError = data.llm_error || "";
        root.embedError = data.embed_error || "";
        const pending = data.pending_memories || 0;
        const hadPending = root.pendingMemories;
        if (pending !== root.pendingMemories) {
            root.pendingMemories = pending;
            if (pending > 0)
                root.refreshReviewQueue();
            else
                root.reviewQueue = [];
        }

        if (root._seenFirstSnapshot && contiguous)
            _announce(previousState, hadPending, pending);
        root._seenFirstSnapshot = true;
    }

    // Sound follows state transitions, not states: a cue means "this just
    // happened". Only transitions the user would want to hear are announced --
    // the microphone opening above all, because that is the one the shell has a
    // duty to make audible.
    function _announce(previousState, hadPending, pending) {
        if (root.state === previousState) {
            // No state change; a memory arriving is still worth a cue.
            if (pending > hadPending)
                SoundService.play("turretReview");
            return;
        }

        switch (root.state) {
        case "listening":
            SoundService.play("turretListening");
            break;
        case "thinking":
            SoundService.play("turretThinking");
            break;
        case "error":
            SoundService.play("turretError");
            break;
        case "idle":
            // Only when a turn actually produced something: going idle from
            // idle, or after a cancel, is not an achievement.
            if (previousState === "speaking")
                SoundService.play("turretDone");
            break;
        }

        if (pending > hadPending)
            SoundService.play("turretReview");
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

    // The store's own history: what was remembered, confirmed, corrected,
    // superseded, refused or forgotten, and when. Contains no memory text.
    function memoryAudit(limit, callback) {
        BackendService.call("assistant.memory.audit", {limit: limit || 100}, (result, error) => {
            callback(error || !result ? [] : (result.entries || []));
        });
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
