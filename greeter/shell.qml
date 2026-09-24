//@ pragma UseQApplication

// AMBXST greeter for greetd. Runs under a dedicated Hyprland as the `greeter`
// user (see hyprland.lua). Without GREETD_SOCK it runs in mock mode inside the
// current session for previewing: Escape quits, password "fail" fails.
import QtQuick
import Quickshell

ShellRoot {
    // The largest screen carries the clock and login card.
    readonly property var primaryScreen: {
        var best = null;
        for (const s of Quickshell.screens) {
            if (!best || s.width * s.height > best.width * best.height)
                best = s;
        }
        return best;
    }

    Variants {
        model: Quickshell.screens

        Surface {
            required property var modelData
            screen: modelData
            primary: modelData === primaryScreen
        }
    }
}
