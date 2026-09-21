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

// ---------------------------------------------------------------------------
// Getting the keyboard back
// ---------------------------------------------------------------------------
//
// Reported from use: type, click a message, click the composer -- and typing
// was dead until the panel was closed and reopened. The sidebar's root
// MouseArea sets `wantsFocus` on press but sits below everything, so a press
// the text field consumes never reaches it; the surface was left on
// keyboardFocus None while the field held Qt focus no keystroke could reach.

console.log("\nregaining focus:");

const input = sidebar.slice(sidebar.indexOf("id: inputField"), sidebar.indexOf("onTextChanged"));
assert(/onActiveFocusChanged/.test(input), "the composer reacts to taking focus");
assert(/root\.wantsFocus = true/.test(input), "and asserts the panel wants the keyboard");
assert(/root\.restoreInputFocus\(\)/.test(input),
    "and re-asserts the Wayland surface, which Quickshell only re-pushes when the binding changes");

// The pill is wider than its field; clicking the padding used to do nothing.
const composer = sidebar.slice(sidebar.indexOf("id: inputStyledRect"), sidebar.indexOf("DropArea"));
assert(/MouseArea/.test(composer) && /inputField\.forceActiveFocus\(\)/.test(composer),
    "the whole composer surface is a click target for its field");

// ---------------------------------------------------------------------------
// The list must not move under the pointer
// ---------------------------------------------------------------------------
//
// Also reported: messages twitched up and down on hover. The action row is
// 24px and the role label about 11, so revealing it grew the delegate the
// cursor was over and shifted everything below it.

console.log("\nstable rows:");

assert(/Layout\.preferredHeight: 24/.test(sidebar), "the role line reserves the action row's height");
assert(!/opacity: bubbleArea\.containsMouse[\s\S]{0,300}visible: opacity > 0\.01/.test(sidebar),
    "the action row is never taken out of the layout to hide it");
assert(/enabled: opacity > 0\.01/.test(sidebar), "a fully transparent action is not a click target");

// The glass terminal has a fixed composer. Transcript layout must reserve its
// entire footprint, including the model selector, rather than drawing behind it.
assert(/anchors.bottomMargin: inputContainer.height \+ inputContainer.anchors.bottomMargin/.test(sidebar),
    "transcript viewport ends above the composer and model selector");
const modelButton = sidebar.slice(sidebar.indexOf("id: modelButton"));
assert(/Accessible.name: I18n.t\("ai.cmd_switch_model"\)/.test(modelButton),
    "model selector is a named keyboard-accessible button");
assert(!/isWelcome/.test(modelButton), "model selector stays available in populated conversations");
assert(/root.visualFocus/.test(iconButton) && /border.width: root.visualFocus/.test(iconButton),
    "header and composer buttons expose visible keyboard focus");

console.log("\nSidebar accessibility: all checks passed");

// The hidden mask source must still paint the glass opening into its texture.
// A visible binding rendered the inset opaque despite correct geometry.
const frame = read("modules/frame/ScreenFrameContent.qml");
const glassMask = frame.slice(frame.indexOf("id: glassMask"));
assert(/opacity: root.sidebarMerged && root.sidebarGlassVisible/.test(glassMask)
    && !/visible:/.test(glassMask), "glass opening uses alpha inside the hidden frame mask");

const terminal = sidebar.slice(sidebar.indexOf("id: terminalSurface"), sidebar.indexOf("id: terminalContent"));
assert(/enableBorder: false/.test(terminal) && /border.width: 0/.test(terminal),
    "glass surface has no decorative edge highlight");
const send = sidebar.slice(sidebar.indexOf("glyph: Icons.paperPlane"), sidebar.indexOf("id: modelButton"));
assert(/visible: !Ai.isLoading\s/.test(send) && /inputField.text.trim\(\).length > 0/.test(send),
    "empty composer keeps Send in place but disables submission");
