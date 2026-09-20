// Runnable check for the motion vocabulary: `node tests/motion-tokens.test.js`.
//
// Durations and curves were written out at every call site — Config.animDuration
// and /2, /4, *2, plus hardcoded 200, 400 and 1000 ms — and `animDuration = 0`
// was the only way to turn motion off. It was never a real reduced-motion mode:
// the animations with a hardcoded duration ignored it, because their `running`
// did not consult it either.
//
// These checks are against the sources, since the values are QML bindings.

const fs = require("fs");
const path = require("path");

const base = path.join(__dirname, "..");
const read = f => fs.readFileSync(path.join(base, f), "utf8");

function assert(cond, msg) {
    if (!cond)
        throw new Error(msg);
    console.log("  ok  " + msg);
}

console.log("the singleton:");

const motion = read("modules/theme/Motion.qml");
assert(/pragma Singleton/.test(motion), "Motion is a singleton, like Styling and Colors");
assert(/readonly property int base: Config\.animDuration/.test(motion), "every duration still scales from the existing setting");
assert(/Config\.theme\.reducedMotion \|\| base <= 0/.test(motion), "both the new switch and a zero duration suppress motion");
assert(/readonly property bool enabled: !reduced/.test(motion), "there is one thing for a Behavior or a loop to gate on");

for (const token of ["micro", "fast", "normal", "enter", "exit", "ambient"])
    assert(new RegExp("property int " + token + ":").test(motion), "there is a named duration for " + token);

// Enter and exit sharing a curve is what makes a panel feel dragged rather
// than moving.
assert(/enterEasing: Easing\.OutBack/.test(motion) && /exitEasing: Easing\.OutQuad/.test(motion),
    "arrival and departure do not share an easing curve");

console.log("\nthe config key:");

// A defaults-only key merges to disk, reads back undefined, and silently keeps
// its ?? fallback forever — the adapter declares its properties explicitly.
assert(/"reducedMotion": false/.test(read("config/defaults/theme.js")), "reducedMotion has a default");
assert(/property bool reducedMotion: false/.test(read("config/Config.qml")), "reducedMotion is declared on the theme adapter too");

console.log("\nthe call sites:");

const surfaces = [
    "modules/sidebar/AssistantSidebar.qml",
    "modules/sidebar/AssistantIconButton.qml",
    "modules/sidebar/ModelSelectorPopup.qml",
    "modules/ainotch/AiNotchCollapsed.qml",
    "modules/ainotch/AiUsageCell.qml"
];

for (const file of surfaces) {
    const src = read(file);
    assert(!/Config\.animDuration/.test(src), file.split("/").pop() + " no longer reaches past the vocabulary for a duration");
}

// Every looping animation in these files must be stoppable, or reduced motion
// is a setting that leaves the moving parts moving.
for (const file of surfaces) {
    const src = read(file);
    const loops = src.split("\n").filter(l => /loops: Animation\.Infinite/.test(l)).length;
    if (loops === 0)
        continue;
    const gated = src.split("\n").filter(l => /running:.*Motion\.enabled/.test(l)).length;
    assert(gated >= 1, file.split("/").pop() + " gates its looping animation on the motion switch");
}

console.log("\nMotion tokens: all checks passed");
