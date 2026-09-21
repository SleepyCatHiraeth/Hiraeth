const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const read = file => fs.readFileSync(path.join(__dirname, '..', file), 'utf8');
const defaults = vm.runInNewContext(read('config/defaults/ai.js') + '; data');
assert.equal(defaults.notchTransparentPill, true);
assert.match(read('config/Config.qml'), /property bool notchTransparentPill: true/);
const globals = read('modules/globals/GlobalStates.qml');
assert.match(globals, /"ai": \[[^\]]*"notchTransparentPill"/);
const controls = read('modules/widgets/dashboard/controls/ShellPanel.qml');
assert.match(controls, /label: "Transparent Pill"[\s\S]*?markShellChanged\(\);\s*Config.ai.notchTransparentPill = value/);
const collapsed = read('modules/ainotch/AiNotchCollapsed.qml');
assert.match(collapsed, /visible: root.transparentPill/);
const expression = collapsed.match(/readonly property rect glassInset: ([\s\S]*?)\n    readonly property real glassRadius/)[1];
for (const enabled of [false, true]) {
    const rect = vm.runInNewContext(expression, {
        transparentPill: enabled,
        statsBubble: { x: 9, y: 20, width: 30, height: 100 },
        Qt: { rect: (...values) => values }
    });
    assert.deepEqual(rect, enabled ? [9, 20, 30, 100] : [0, 0, 0, 0]);
}
console.log('Pill toggle: defaults, persistence, settings and both mask states pass');
