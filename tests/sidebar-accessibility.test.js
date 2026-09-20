// Runnable check for the assistant panel's keyboard and assistive-technology
// surface: `node tests/sidebar-accessibility.test.js`.
//
// The panel had six Accessible.name strings in nineteen hundred lines, all
// hardcoded English, and the per-message actions were shown on hover only — so
// copy, edit and retry could not be reached without a pointer at all. The
// conversation itself had no focus, no current item and no key handling.

const fs = require("fs");
const path = require("path");

const base = path.join(__dirname, "..");
const read = f => fs.readFileSync(path.join(base, f), "utf8");

function assert(cond, msg) {
    if (!cond)
        throw new Error(msg);
    console.log("  ok  " + msg);
}

const sidebar = read("modules/sidebar/AssistantSidebar.qml");
const iconButton = read("modules/sidebar/AssistantIconButton.qml");
const action = read("modules/sidebar/AssistantMessageAction.qml");

console.log("naming:");

// A hardcoded name is a name that is wrong in every locale but one.
const hardcoded = sidebar.match(/Accessible\.name: "[^"]*"/g) || [];
assert(hardcoded.length === 0, "no control is named with a hardcoded string");

for (const [src, name] of [[iconButton, "AssistantIconButton"], [action, "AssistantMessageAction"]]) {
    assert(/required property string label/.test(src), name + " requires a label");
    assert(/Accessible\.name: root\.label/.test(src), name + " names itself from that label");
    assert(/ToolTip\.text: root\.label/.test(src), name + "'s tooltip and accessible name cannot disagree");
}

console.log("\nreaching a message:");

assert(/ListView\.isCurrentItem/.test(sidebar), "the message actions follow the keyboard's current message");
assert(/bubbleArea\.containsMouse[\s\S]{0,200}ListView\.isCurrentItem/.test(sidebar),
    "they are no longer hover-only");
assert(/activeFocusOnTab: true/.test(action), "each action can be tabbed to once shown");

console.log("\nnavigating the conversation:");

const view = sidebar.slice(sidebar.indexOf("id: chatView"), sidebar.indexOf("delegate: Item"));
assert(/activeFocusOnTab: true/.test(view), "the conversation can be tabbed to");
assert(/keyNavigationEnabled: true/.test(view), "arrow keys move through it");
assert(/currentIndex: -1/.test(view), "nothing is selected until the keyboard arrives");
assert(/Keys\.onEscapePressed/.test(view), "Escape gives the selection up");
assert(/onActiveFocusChanged/.test(view), "losing focus clears the selection rather than leaving a stale one");
assert(/visible: chatView\.activeFocus/.test(sidebar),
    "the highlight is drawn only while the list holds the keyboard");
assert(/KeyNavigation\.backtab: chatView/.test(sidebar), "shift-tab from the composer reaches the conversation");

// Following the newest content and reading back through it are mutually
// exclusive; selecting a message must stop the chase.
assert(/onCurrentIndexChanged: if \(currentIndex >= 0\) followTail = false/.test(view),
    "selecting a message stops the view chasing the reply still arriving");

console.log("\nSidebar accessibility: all checks passed");
