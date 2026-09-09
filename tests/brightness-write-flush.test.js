// Extracts the brightness writer's decision logic from Brightness.qml and
// replays it with fake timers, so the "did the last target reach the
// hardware" guarantee is checked without touching a monitor.
const assert = require("assert");
const fs = require("fs");

const src = fs.readFileSync(__dirname + "/../modules/services/Brightness.qml", "utf8");

// Guard against the source drifting away from what this test models.
for (const needle of [
    "property real lastSentValue: -1",
    "monitor.lastSentValue = monitor.brightness;",
    "if (monitor.lastSentValue !== monitor.brightness)",
    "property real lastUserWriteAt: 0"
]) {
    assert.ok(src.includes(needle), `Brightness.qml no longer contains: ${needle}`);
}

function makeMonitor() {
    const writes = [];
    const m = {
        brightness: 0,
        lastUserWriteValue: 0,
        lastUserWriteAt: 0,
        lastSentValue: -1,
        setTimerRunning: false,
        writes
    };
    m.syncBrightness = () => {
        m.lastUserWriteAt = Date.now();
        m.lastUserWriteValue = m.brightness;
        m.lastSentValue = m.brightness;
        writes.push(m.brightness);
    };
    m.setBrightness = value => {
        value = Math.max(0.01, Math.min(1, value));
        m.brightness = value;
        m.lastUserWriteAt = Date.now();
        m.lastUserWriteValue = value;
        if (!m.setTimerRunning) {
            m.syncBrightness();
            m.setTimerRunning = true;
        }
    };
    // stopTimer fires 200ms after the last activity.
    m.stopTimerFires = () => {
        if (m.lastSentValue !== m.brightness)
            m.syncBrightness();
        m.setTimerRunning = false;
    };
    return m;
}

// A press sequence where the periodic timer never ticks between the last
// setBrightness() and the stop deadline: the final value must still land.
let m = makeMonitor();
m.setBrightness(0.6);
m.setBrightness(0.7);
m.stopTimerFires();
assert.deepStrictEqual(m.writes, [0.6, 0.7], "final target was not flushed");
assert.strictEqual(m.brightness, m.lastSentValue);
console.log("  pass: the final target is written when the periodic timer misses it");

// A single press already written on the leading edge must not be written twice.
m = makeMonitor();
m.setBrightness(0.4);
m.stopTimerFires();
assert.deepStrictEqual(m.writes, [0.4], "leading-edge write was duplicated by the flush");
console.log("  pass: an already-written value is not sent again");

// lastUserWriteValue alone cannot detect an unsent target — this is the
// predicate the flush originally used, kept here so a regression to it fails.
m = makeMonitor();
m.setBrightness(0.6);
m.setBrightness(0.7);
assert.strictEqual(m.lastUserWriteValue, m.brightness,
    "lastUserWriteValue tracks the request, not the write; it cannot gate the flush");
console.log("  pass: lastUserWriteValue is proven unusable as the flush predicate");

console.log("Brightness write flush: all checks passed");
