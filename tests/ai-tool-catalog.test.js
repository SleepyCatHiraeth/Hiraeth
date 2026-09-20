// Runnable check for the AI tool allow-list: `node tests/ai-tool-catalog.test.js`.
//
// This is the boundary where a model-produced proposal becomes a command line.
// It replaced `run_shell_command`, whose approved payload ran as
// ["bash", "-c", args.command] -- one model-produced string with full user
// authority behind a single click. The properties asserted here are the reason
// that replacement is worth anything: no shell, a fixed program per tool,
// option parsing terminated before the model's argument, and a refusal for
// anything that does not resolve.

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const SRC = path.join(__dirname, "..", "modules", "services", "ai", "ToolCatalog.js");
const catalog = {};
vm.createContext(catalog);
vm.runInContext(fs.readFileSync(SRC, "utf8").replace(".pragma library", ""), catalog);

function assert(cond, msg) {
    if (!cond)
        throw new Error(msg);
    console.log("  ok  " + msg);
}

const HOME = "/home/someone";

// ---------------------------------------------------------------------------
// The contract sent to providers
// ---------------------------------------------------------------------------

console.log("advertised tools:");

const defs = catalog.definitions();
assert(defs.length === catalog.TOOLS.length, "every tool in the catalog is advertised");
assert(defs.every(d => d.name && d.description && d.parameters), "each definition carries a name, description and schema");
assert(defs.every(d => d.build === undefined), "the build function is never sent to a provider");
assert(!defs.some(d => /shell|bash|command/i.test(d.name)), "no tool offers the model a shell");

// ---------------------------------------------------------------------------
// Resolution
// ---------------------------------------------------------------------------

console.log("resolution:");

const ok = catalog.resolve({name: "list_directory", args: {path: "/etc"}}, HOME);
assert(Array.isArray(ok.argv) && ok.error === undefined, "a valid proposal resolves to an argv");
assert(ok.argv[0] === "ls", "the program is fixed by the tool, not by the model");
assert(ok.argv.includes("--"), "option parsing is terminated before the model's argument");
assert(ok.argv[ok.argv.length - 1] === "/etc", "the model's path is the final argument");

assert(catalog.resolve({name: "rm", args: {path: "/"}}, HOME).error === "unknown_tool", "a tool outside the catalog cannot run");
assert(catalog.resolve(null, HOME).error === "malformed", "a missing proposal cannot run");
assert(catalog.resolve({args: {path: "/etc"}}, HOME).error === "malformed", "a proposal with no tool name cannot run");
assert(catalog.resolve({name: "list_directory", args: {}}, HOME).error === "bad_arguments", "a missing argument is refused, not defaulted");

const bounded = catalog.resolve({name: "read_text_file", args: {path: "/dev/zero"}}, HOME);
assert(bounded.argv.includes("-c") && bounded.argv.includes("65536"), "a file read is bounded rather than trusting the file to be small");

// ---------------------------------------------------------------------------
// Paths
// ---------------------------------------------------------------------------

console.log("path validation:");

function pathOf(raw, home) {
    const r = catalog.resolve({name: "list_directory", args: {path: raw}}, home === undefined ? HOME : home);
    return r.error ? null : r.argv[r.argv.length - 1];
}

assert(pathOf("~/Downloads") === HOME + "/Downloads", "a ~/ path expands to the user's home");
assert(pathOf("~") === HOME, "a bare ~ expands to the user's home");
assert(pathOf("~/x", "") === null, "a ~ path is refused when there is no home to expand to");
assert(pathOf("  /etc  ") === "/etc", "surrounding whitespace is trimmed");

assert(pathOf("etc") === null, "a relative path is refused: there is no shell and so no working directory");
assert(pathOf("") === null, "an empty path is refused");
assert(pathOf("   ") === null, "a whitespace-only path is refused");
assert(pathOf(42) === null, "a non-string path is refused");
assert(pathOf("/etc\npasswd") === null, "a newline in a path is refused rather than escaped");
assert(pathOf("/etc\rpasswd") === null, "a carriage return inside a path is refused");
assert(pathOf("/etc\r") === "/etc", "a trailing carriage return is trimmed away like any other whitespace");
assert(pathOf("/etc\0passwd") === null, "a NUL in a path is refused");

// There is no shell, so these are filenames -- but they must stay the final
// argument and must never be split or re-read as anything else.
assert(pathOf("/tmp/a b; rm -rf ~") === "/tmp/a b; rm -rf ~", "shell metacharacters stay one literal filename");
assert(pathOf("/tmp/$(whoami)") === "/tmp/$(whoami)", "command substitution is a filename, not a substitution");
assert(pathOf("/tmp/`id`") === "/tmp/`id`", "backticks are a filename, not a substitution");

// ---------------------------------------------------------------------------
// What the approval card shows
// ---------------------------------------------------------------------------

console.log("approval display:");

assert(catalog.describe({name: "disk_usage", args: {path: "/"}}, HOME) === "df -h -- /",
    "the card shows the command line that will actually run");
assert(catalog.describe({name: "rm", args: {path: "/"}}, HOME) === "",
    "a proposal that cannot run has nothing to show, and so nothing to approve");

console.log("\nAI tool catalog: all checks passed");
