const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').join(__dirname, '../modules/services/WeatherService.qml'), 'utf8');
const root = {requestToken: 0, handleResponse: value => { root.response = value; }, handleError: () => { root.failed = true; }};
const weatherProcess = {running: false};
const deferred = [];
const context = {root, weatherProcess, Config: {weather: {location: 'Berlin'}},
    SuspendManager: {isSuspending: false}, Qt: {callLater: fn => deferred.push(fn)}, console,
    BackendService: {call: () => { throw Error('Weather must not block shared IPC'); }}};
for (const name of ['updateWeather', 'finishWeather']) {
    const start = source.indexOf('    function ' + name + '(');
    assert.notEqual(start, -1);
    const end = source.indexOf('\n    }', start) + 6;
    root[name] = vm.runInNewContext('(' + source.slice(start, end).trim() + ')', context);
}
root.updateWeather();
assert.equal(weatherProcess.running, true);
assert.equal(weatherProcess.command[3], 'weather.get');
assert.equal(JSON.parse(weatherProcess.command[4]).location, 'Berlin');
const first = weatherProcess.token;
context.Config.weather.location = 'Paris';
root.updateWeather();
assert.equal(weatherProcess.token, first); // One in-flight request.
weatherProcess.running = false;
root.finishWeather(first, 0, '{"old":true}');
assert.equal(root.response, undefined);
deferred.shift()();
assert.equal(JSON.parse(weatherProcess.command[4]).location, 'Paris');
root.finishWeather(weatherProcess.token, 0, '{"ok":true}');
assert.equal(root.response.ok, true);
root.finishWeather(weatherProcess.token, 1, '');
assert.equal(root.failed, true);
root.failed = false;
root.finishWeather(weatherProcess.token, 0, 'invalid JSON');
assert.equal(root.failed, true);
context.SuspendManager.isSuspending = true;
root.requestToken++;
root.finishWeather(weatherProcess.token, 0, '{}');
assert.equal(deferred.length, 0);
console.log('Weather isolation, coalescing, stale responses, failure and suspend checks pass.');
