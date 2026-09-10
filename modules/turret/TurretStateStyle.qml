pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.theme

// Visual identity per assistant state, in one place.
//
// The first version distinguished states only by a word, which meant the notch
// looked identical whether it was listening, thinking or failing. Colour and
// glyph carry the state at a glance; the label is the detail, not the signal.
Singleton {
    id: root

    // accent(state) -> the colour that identifies this state.
    function accent(state) {
        switch (state) {
        case "listening":
            return Colors.criticalRed;      // capture is live: the loudest colour we have
        case "transcribing":
        case "thinking":
            return Styling.srItem("overprimary");
        case "speaking":
            return Colors.primary;
        case "error":
            return Colors.criticalText;
        case "cancelled":
            return Colors.overSurfaceVariant;
        default:
            return Colors.overSurfaceVariant;
        }
    }

    function glyph(state) {
        switch (state) {
        case "listening":
            return Icons.mic;
        case "transcribing":
            return Icons.waveform;
        case "thinking":
            return Icons.robot;
        case "speaking":
            return Icons.speakerHigh;
        case "error":
            return Icons.alert;
        default:
            return Icons.robot;
        }
    }

    function label(state, transcript, response, error) {
        switch (state) {
        case "listening":
            return "Listening";
        case "transcribing":
            return "Transcribing";
        case "thinking":
            return transcript !== "" ? transcript : "Thinking";
        case "speaking":
            return response !== "" ? response : "Speaking";
        case "cancelled":
            return "Cancelled";
        case "error":
            return error !== "" ? error : "Error";
        default:
            return transcript !== "" ? transcript : "Ready";
        }
    }

    // Whether this state should animate its indicator. Motion means "working";
    // a static indicator means "waiting for you".
    function animated(state) {
        return state === "listening" || state === "transcribing"
            || state === "thinking" || state === "speaking";
    }
}
