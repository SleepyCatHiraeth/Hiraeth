const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {spawnSync} = require('node:child_process');
const base = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(base, file), 'utf8');
function method(source, name, context) {
    const start = source.match(new RegExp('^([ ]*)function ' + name + '\\(', 'm'));
    assert.ok(start, name);
    const end = source.indexOf('\n' + start[1] + '}', start.index);
    return vm.runInNewContext('(' + source.slice(start.index, end + start[1].length + 2).trim() + ')', context);
}
const usage = {};
vm.createContext(usage);
vm.runInContext(read('modules/services/UsageSnapshot.js').replace('.pragma library', ''), usage);
const now = 1700000000000;
const entry = {usedPercent: 50, windowMinutes: 300, updatedAt: now};
assert.equal(usage.stale(entry, now + 1199999, 10), false);
assert.equal(usage.stale(entry, now + 1200000, 10), true);
assert.equal(usage.stale({...entry, error: true}, now, 10), true);
assert.equal(usage.stale({...entry, resetsAt: new Date(now).toISOString()}, now, 10), true);
assert.equal(usage.reading({...entry, usedPercent: NaN}, now), null);
assert.equal(usage.reading({...entry, usedPercent: 150}, now).usedPercent, 100);
const legacy = {providers: {claude: {usedPercent: 20, windowMinutes: 300}}, updatedAt: now - 10000};
let merged = usage.select([legacy, {providers: {claude: entry, codex: entry}}], ['claude']);
assert.equal(merged.providers.claude.usedPercent, 50);
assert.equal(merged.providers.codex, undefined);
merged = usage.select([{providers: {claude: entry}}, {providers: {claude: {...entry, error: true, checkedAt: now + 1000}}}], ['claude']);
assert.equal(merged.providers.claude.error, true);
assert.equal(merged.providers.claude.updatedAt, now);

// Run the real refresh methods against one shared runtime owner slot.
let owner = null;
const PluginService = {runtimeValue: () => owner, setRuntimeValue: (id, key, value) => { owner = value; }};
const fallback = {enabled: true, StateService: {initialized: true}, stale: true, now: 0, nextAttempt: 0,
    usageProcess: {running: false}, providers: ['claude'], PluginService, pluginId: 'ai-overview-control', ownerKey: 'usageRefreshOwner',
    helperPath: '/example/helper', timeout: {restart() {}}, Date: {now: () => now}};
fallback.root = fallback;
const serviceSource = read('modules/services/AiUsage.qml');
const failure = {lastError: '', snapshot: {providers: {claude: entry}}, requestedProviders: ['claude'],
    refreshMinutes: 10, stateKey: 'test', StateService: {set() {}}, Date: {now: () => now + 1000}, console: {warn() {}}};
method(serviceSource, 'fail', failure)('offline');
assert.equal(failure.ownSnapshot.providers.claude.error, true);
assert.equal(failure.ownSnapshot.providers.claude.updatedAt, now);
method(serviceSource, 'fail', failure)('partial', false);
assert.equal(failure.ownSnapshot.providers.claude.error, undefined);
fallback.check = method(serviceSource, 'check', fallback);
fallback.release = method(serviceSource, 'release', fallback);
fallback.check();
assert.equal(owner.usageProcess, fallback.usageProcess);
assert.equal(fallback.usageProcess.running, true);
const pluginSource = fs.readFileSync(process.env.AIOC_MAIN || path.join(process.env.XDG_CONFIG_HOME || path.join(process.env.HOME, '.config'), 'ambxst/plugins/ai-overview-control/Main.qml'), 'utf8');
const plugin = {selectedProviders: ['claude'], visible: true, quotaNotificationsEnabled: true,
    usageProcess: {running: false}, pendingRefreshProviders: [], PluginService,
    pluginId: 'ai-overview-control', providerScript: '/example/helper', timeout: {restart() {}}};
plugin.root = plugin;
plugin.refresh = method(pluginSource, 'refresh', plugin);
plugin.refresh();
assert.equal(plugin.usageProcess.running, false);
assert.equal(plugin.pendingRefreshProviders[0], 'claude');
fallback.usageProcess.running = false;
fallback.release();
plugin.refresh();
assert.equal(plugin.usageProcess.running, true);
assert.equal(owner.usageProcess, plugin.usageProcess);
fallback.check();
assert.equal(fallback.usageProcess.running, false);

// Partial failures retain the original reading age; successful providers advance independently.
let published;
const publishing = {pluginId: 'ai-overview-control', refreshMinutes: 10, Date: {now: () => now + 5000},
    providerName: id => id, providers: [
        {provider: 'claude', error: 'offline', _usageCheckedAt: now + 5000},
        {provider: 'codex', usage: {primary: {usedPercent: 12, windowMinutes: 300}}, _usageCheckedAt: now + 5000}],
    PluginService: {runtimeValue: () => ({providers: {claude: entry}}),
        setRuntimeValue: (id, key, value) => { published = value; }, set() {}}};
method(pluginSource, 'publishUsageSnapshot', publishing)();
assert.equal(published.providers.claude.updatedAt, now);
assert.equal(published.providers.claude.error, true);
assert.equal(published.providers.codex.updatedAt, now + 5000);

// Execute the actual pre-validation migration against both legacy policies.
const migration = read('config/Config.qml').match(/if \(name === "ai" && typeof current.sidebarPinnedOnStartup[\s\S]*?\n            }/)[0];
for (const pin of [false, true]) {
    const current = {sidebarPinnedOnStartup: pin};
    vm.runInNewContext(migration, {name: 'ai', current});
    assert.equal(current.sidebarMergeIntoFrame, pin);
    assert.equal(current.sidebarReserveSpace, pin);
    current.sidebarMergeIntoFrame = !pin;
    vm.runInNewContext(migration, {name: 'ai', current});
    assert.equal(current.sidebarMergeIntoFrame, !pin);
}

const globalSource = read('modules/globals/GlobalStates.qml');
const state = {assistantScreens: [{name: 'DP-2'}], assistantScreenName: 'gone', assistantVisible: true,
    AxctlService: {focusedMonitor: {name: 'gone'}}};
const reconcile = method(globalSource, 'reconcileAssistantScreen', state);
reconcile();
assert.equal(state.assistantScreenName, 'DP-2');
state.assistantScreens = [];
reconcile();
assert.equal(state.assistantVisible, false);

const collapsedSource = read('modules/ainotch/AiNotchCollapsed.qml');
const capacity = collapsedSource.match(/property int maxUsageCells: (.+)/)[1];
for (const [height, expected] of [[24, 0], [140, 2], [300, 3]])
    assert.equal(vm.runInNewContext(capacity, {height, cellHeight: 43}), expected);

const sidebarSource = read('modules/sidebar/AssistantSidebar.qml');
const queue = {attachmentReadProcess: {running: false}, attachmentQueue: [
    {path: '/first', mimeType: 'image/png', name: 'first', chatId: 'one'},
    {path: '/second', mimeType: 'image/jpeg', name: 'second', chatId: 'one'}]};
const next = method(sidebarSource, 'startNextAttachment', queue);
next(); next();
assert.equal(queue.attachmentReadProcess.filePath, '/first');
assert.equal(queue.attachmentQueue.length, 1);
queue.attachmentReadProcess.running = false;
next();
assert.equal(queue.attachmentReadProcess.filePath, '/second');
assert.equal(queue.attachmentReadProcess.mimeType, 'image/jpeg');

// Exercise the actual static clipboard script with a harmless hostile argument.
const clipboardCommand = sidebarSource.match(/command: (\["bash", "-c", "set -o pipefail;[\s\S]*?\])/)[1];
const mimeType = 'image/png$(printf injected)" with spaces';
const args = vm.runInNewContext(clipboardCommand, {mimeType, mainChatArea: {maxAttachmentBytes: 8 * 1024 * 1024}, String});
// Bounded like a file attachment: an oversize paste must be refused before it
// has been buffered and base64'd in full.
assert.ok(/head -c "\$2"/.test(args[2]), 'the clipboard read is bounded');
assert.equal(args[5], '8388611');
const result = spawnSync(args[0], ['-c', 'wl-paste() { printf "%s" "$2"; }; ' + args[2], ...args.slice(3)], {encoding: 'utf8'});
assert.equal(result.status, 0, result.stderr);
assert.equal(Buffer.from(result.stdout.trim(), 'base64').toString(), mimeType);
// The attachment read is bounded and takes its filename as a positional
// argument, so a file named with shell metacharacters is read, not run.
const attachmentCommand = sidebarSource.match(/command: (\["\/usr\/bin\/bash", "-c",[\s\S]*?\])/)[1];
const hostileName = '/tmp/$(printf pwned) "; id; #.png';
const attachArgs = vm.runInNewContext(attachmentCommand, {
    mainChatArea: {maxAttachmentBytes: 8 * 1024 * 1024},
    filePath: hostileName,
    String
});
assert.ok(attachArgs.includes(hostileName), 'the path is passed as its own argument');
assert.ok(/head -c "\$1"/.test(attachArgs[2]), 'the read is bounded by head');
assert.equal(attachArgs[4], '8388611', 'the bound is three bytes past the limit: base64 works in three-byte groups, so one byte over encodes to the same length');
{
    const limit = 8 * 1024 * 1024;
    const encoded = n => Math.ceil(n / 3) * 4;
    assert.ok(encoded(Number(attachArgs[4])) > encoded(limit), 'a file over the limit encodes longer than one at it');
}

{
    const probe = '/tmp/ambxst-attach-probe $(printf pwned).png';
    fs.writeFileSync(probe, 'hello');
    const probeArgs = vm.runInNewContext(attachmentCommand, {
        mainChatArea: {maxAttachmentBytes: 8 * 1024 * 1024},
        filePath: probe,
        String
    });
    const run = spawnSync(probeArgs[0], probeArgs.slice(1), {encoding: 'utf8'});
    fs.unlinkSync(probe);
    assert.equal(run.status, 0, run.stderr);
    assert.equal(Buffer.from(run.stdout.trim(), 'base64').toString(), 'hello');
}

assert.ok(!sidebarSource.includes('Qt.createQmlObject'));
assert.ok(!read('modules/sidebar/CodeBlock.qml').includes('Qt.createQmlObject'));
console.log('SideNotch: freshness, validation, refresh exclusion, monitor recovery, capacity, attachment queue and clipboard safety pass.');
