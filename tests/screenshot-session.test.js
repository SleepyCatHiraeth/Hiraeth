const assert = require("node:assert/strict");
const fs = require("node:fs");

const service = fs.readFileSync("modules/services/Screenshot.qml", "utf8");
const tool = fs.readFileSync("modules/tools/ScreenshotTool.qml", "utf8");

const recognition = service.slice(service.indexOf("function _runRecognition"), service.indexOf("function ocrLangs"));
assert.ok(recognition.indexOf("recognitionPending = true") < recognition.indexOf("BackendService.call"));
assert.ok(recognition.indexOf("recognitionPending = false") > recognition.indexOf("BackendService.call"));
assert.ok(recognition.includes("root.releaseFrozenFrames()"));

const close = tool.slice(tool.indexOf("function close()"), tool.indexOf("function executeCapture"));
assert.ok(close.includes("if (!Screenshot.recognitionPending)"));

console.log("Screenshot session: OCR keeps frozen frames until recognition completes.");
