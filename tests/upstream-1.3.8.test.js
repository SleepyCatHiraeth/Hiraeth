// Run: node tests/upstream-1.3.8.test.js
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const read = file => fs.readFileSync(path.join(__dirname, '..', file), 'utf8');
function block(source, pattern) {
    const match = source.match(pattern);
    assert.ok(match, String(pattern));
    const end = source.indexOf('\n' + match[1] + '}', match.index);
    assert.ok(end > match.index);
    return source.slice(match.index, end + match[1].length + 2).trim();
}
function method(source, name, context) {
    return vm.runInNewContext('(' + block(source, new RegExp('^( *)function ' + name + '\\(', 'm')) + ')', context);
}

const catalog = {};
vm.createContext(catalog);
vm.runInContext(read('config/KeybindActions.js').replace(/^\.pragma library\s*/m, ''), catalog);
for (const [id, flags] of [['audio.mute-toggle', 'lr'], ['audio.volume-up', 'le'], ['brightness.up', 'le']])
    assert.equal(catalog.ACTION_CATALOG.find(action => action.id === id).flags, flags);
assert.equal(catalog.actionFromLegacy('togglefloating', '', '').id, 'window.toggle-float');

// Exercise the actual popup lifecycle and focus-loss handler. Prematurely
// clearing isOpen makes close() return without unregistering or hiding.
const popup = read('modules/components/BarPopup.qml');
const pending = [];
let registered = false;
const root = {
    isOpen: false, visible: false, focusActive: false, closeOnFocusLost: true,
    extraGrabWindows: [], closedExternally() {},
    popupOpacity: 0, popupScale: 0.9,
    closeTimer: {running: false, stop() {this.running = false;}, restart() {this.running = true;}},
    Qt: {callLater: callback => pending.push(callback)},
    Visibilities: {registerBarPopup() {registered = true;}, unregisterBarPopup() {registered = false;}}
};
root.root = root;
for (const name of ['open', 'close', 'toggle', 'refreshFocusGrab']) root[name] = method(popup, name, root);
const cleared = block(popup, /^( *)onCleared: \{/m).replace(/^onCleared:/, '');
root.open(); pending.splice(0).forEach(callback => callback());
assert.equal(registered, true);
root.extraGrabWindows = [{}];
vm.runInNewContext(cleared, root);
assert.equal(root.isOpen, true);
root.extraGrabWindows = [];
vm.runInNewContext(cleared, root);
assert.equal(root.isOpen, false);
assert.equal(registered, false);
assert.equal(root.closeTimer.running, true);
root.open(); pending.splice(0).forEach(callback => callback());
assert.equal(root.visible, true);
assert.equal(root.isOpen, true);
assert.equal(root.closeTimer.running, false);
assert.equal(registered, true);

// Hidden state changes defer delegate destruction and preserve unrelated
// plugin settings through StateService's reactive, backend-owned write.
const tray = read('modules/bar/systray/SysTray.qml');
const item = read('modules/bar/systray/SysTrayItem.qml');
assert.match(tray, /property alias activeChildMenu: root\.activeChildMenu/);
assert.match(item, /overflowPopupRef\.activeChildMenu = isOpen \? systrayPopup : null/);
assert.match(item, /readonly property string iconSource: root\.item\.icon/);
assert.match(tray, /component ChevronButton: AbstractButton/);
assert.match(tray, /activeFocusOnTab: true/);
assert.match(tray, /Accessible\.name: I18n\.t\("bar\.systray\.overflow"\)/);
for (const source of [tray, item, popup]) {
    assert.doesNotMatch(source, /enabled: Config\.animDuration > 0/);
    assert.match(source, /enabled: Motion\.enabled/);
}
const writes = [];
const state = {initialized: true, state: {'plugin.example.enabled': true},
    BackendService: {call: (method, value) => writes.push([method, value])}};
state.root = state;
const set = method(read('modules/services/StateService.qml'), 'set', state);
const previous = state.state;
const StateService = {
    _hidden: [],
    get systrayHidden() {return this._hidden;},
    set systrayHidden(value) {this._hidden = value; set('systrayHidden', value);}
};
const context = {StateService, Qt: {callLater: callback => pending.push(callback)}};
const hide = method(tray, 'hideItem', context);
const show = method(tray, 'showItem', context);
hide('example'); hide('example');
assert.equal(StateService.systrayHidden.length, 0);
pending.splice(0).forEach(callback => callback());
assert.equal(StateService.systrayHidden.join(), 'example');
assert.equal(writes.length, 1);
assert.notEqual(state.state, previous);
assert.equal(state.state['plugin.example.enabled'], true);
show('example'); pending.splice(0).forEach(callback => callback());
assert.equal(StateService.systrayHidden.length, 0);
assert.equal(writes[1][0], 'config.stateSet');
console.log('1.3.8 compatibility: catalog, popup lifecycle, systray ownership, state and motion passed');
