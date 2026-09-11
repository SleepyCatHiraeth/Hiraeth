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
        case "starting":
            return Colors.warning;
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
        case "starting":
            return Icons.power;
        case "error":
            return Icons.alert;
        default:
            return Icons.robot;
        }
    }

    // What to tell the user when the backend gave a kind but no message.
    function errorHint(kind) {
        switch (kind) {
        case "microphone":
            return "Microphone problem";
        case "stt":
            return "Could not transcribe";
        case "tts":
            return "Could not speak";
        case "audio":
            return "Playback problem";
        case "memory":
            return "Memory problem";
        case "provider":
            return "Model server problem";
        case "timeout":
            return "Timed out";
        case "config":
            return "Setup problem";
        default:
            return "Error";
        }
    }

    function label(state, transcript, response, error, errorKind) {
        switch (state) {
        case "listening":
            return "Listening";
        case "transcribing":
            return "Transcribing";
        case "thinking":
            return transcript !== "" ? transcript : "Thinking";
        case "speaking":
            return response !== "" ? response : "Speaking";
        case "starting":
            return "Starting model server";
        case "cancelled":
            return "Cancelled";
        case "error":
            return error !== "" ? error : errorHint(errorKind);
        default:
            return transcript !== "" ? transcript : "Ready";
        }
    }

    // Whether this state should animate its indicator. Motion means "working";
    // a static indicator means "waiting for you".
    function animated(state) {
        return state === "listening" || state === "transcribing"
            || state === "thinking" || state === "speaking"
            || state === "starting";
    }
}
