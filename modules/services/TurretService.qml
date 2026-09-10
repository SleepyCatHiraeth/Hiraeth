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

    property int subHandle: -1

    signal failed(string message)

    // One entry point for the keybind: show the notch, then let the backend
    // decide whether this press starts listening, stops listening, or
    // interrupts a reply in progress.
    function activate() {
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
    }

    Component.onCompleted: {
        root.subHandle = BackendService.addSubscription(["assistant"], (service, data) => {
            if (service !== "assistant.state")
                return;
            Qt.callLater(() => root._apply(data));
        });
    }
}
