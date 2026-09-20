.pragma library

// The tools a cloud model may propose, and the only place a proposal becomes a
// command line.
//
// What this replaces: one tool, `run_shell_command`, whose approved payload ran
// as ["bash", "-c", args.command]. The approval gate around it was well built
// -- single use, refused while loading, refused for a wrong tool name -- but
// the payload was a model-produced string with full user authority behind one
// click, which is why the turret assistant was built beside this path instead
// of on it.
//
// Here a proposal names a tool and supplies typed arguments; this file decides
// the argv. There is no shell, so a metacharacter in a path is a character in a
// filename and nothing else, and `--` ends option parsing so a file called
// `-rf` cannot become a flag. A tool that is not in this list cannot run, and
// a tool in it can only ever run its own fixed program.

// Every entry: the JSON-schema fragment sent to the provider, plus `build`,
// which returns the argv or null when the arguments do not validate.
var TOOLS = [
    {
        name: "list_directory",
        description: "List the contents of a directory on the user's Linux system, with sizes and permissions.",
        parameters: {
            type: "object",
            properties: {
                path: {
                    type: "string",
                    description: "Absolute path, or a path starting with ~/ (e.g. '/etc', '~/Downloads')"
                }
            },
            required: ["path"]
        },
        build: function (args, homeDir) {
            var path = normalizePath(args && args.path, homeDir);
            return path === null ? null : ["ls", "-la", "--", path];
        }
    },
    {
        name: "read_text_file",
        description: "Read the beginning of a text file on the user's Linux system. Output is truncated to 64 KiB.",
        parameters: {
            type: "object",
            properties: {
                path: {
                    type: "string",
                    description: "Absolute path, or a path starting with ~/ (e.g. '/etc/os-release')"
                }
            },
            required: ["path"]
        },
        build: function (args, homeDir) {
            var path = normalizePath(args && args.path, homeDir);
            // Bounded on the reading side rather than trusting the file to be
            // small: `cat /dev/zero` is a filename like any other.
            return path === null ? null : ["head", "-c", "65536", "--", path];
        }
    },
    {
        name: "disk_usage",
        description: "Report free and used space for the filesystem holding a path on the user's Linux system.",
        parameters: {
            type: "object",
            properties: {
                path: {
                    type: "string",
                    description: "Absolute path, or a path starting with ~/ (e.g. '/', '~/')"
                }
            },
            required: ["path"]
        },
        build: function (args, homeDir) {
            var path = normalizePath(args && args.path, homeDir);
            return path === null ? null : ["df", "-h", "--", path];
        }
    }
];

// A path the model supplied. Absolute or `~`-relative only: a relative path has
// no meaning here, because there is no shell and therefore no working directory
// the user could reason about. A NUL or newline is rejected outright rather
// than escaped -- neither belongs in a path a model is asking permission for,
// and a multi-line "path" is the shape an injection attempt takes.
function normalizePath(raw, homeDir) {
    if (typeof raw !== "string")
        return null;

    var path = raw.trim();
    if (path === "")
        return null;
    if (path.indexOf("\0") !== -1 || path.indexOf("\n") !== -1 || path.indexOf("\r") !== -1)
        return null;

    if (path === "~" || path.indexOf("~/") === 0) {
        if (typeof homeDir !== "string" || homeDir === "")
            return null;
        path = path === "~" ? homeDir : homeDir + path.substring(1);
    }

    if (path.charAt(0) !== "/")
        return null;

    return path;
}

function find(name) {
    for (var i = 0; i < TOOLS.length; i++) {
        if (TOOLS[i].name === name)
            return TOOLS[i];
    }
    return null;
}

// The schema fragments, without the `build` functions -- providers are sent the
// contract, never the implementation.
function definitions() {
    return TOOLS.map(function (tool) {
        return {
            name: tool.name,
            description: tool.description,
            parameters: tool.parameters
        };
    });
}

// Resolves a proposal to the argv that would run. Returns {argv} on success and
// {error} otherwise, so a refusal can say which of the two it was: a tool that
// does not exist, or arguments that do not validate.
function resolve(call, homeDir) {
    if (!call || typeof call.name !== "string")
        return {error: "malformed"};

    var tool = find(call.name);
    if (!tool)
        return {error: "unknown_tool"};

    var argv = tool.build(call.args, homeDir);
    if (!argv)
        return {error: "bad_arguments"};

    return {argv: argv};
}

// What the approval card shows. The user approves the command line that will
// actually run, not the arguments it was derived from -- a card showing the
// proposal while something else executes is the failure this whole file exists
// to prevent.
function describe(call, homeDir) {
    var resolved = resolve(call, homeDir);
    if (resolved.error)
        return "";
    return resolved.argv.join(" ");
}
