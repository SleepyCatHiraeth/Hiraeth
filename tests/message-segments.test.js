// Runnable check for reply segmentation: `node tests/message-segments.test.js`.
//
// This split a reply into prose and fenced code inline in a Repeater's model
// expression, so it re-ran on every content change — which during streaming
// meant once per token, for the whole reply. It is a library now, run once on
// a finished reply, and the cases below are the ones a streamed answer
// actually produces.

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const ctx = {};
vm.createContext(ctx);
vm.runInContext(
    fs.readFileSync(path.join(__dirname, "..", "modules", "sidebar", "MessageSegments.js"), "utf8").replace(".pragma library", ""),
    ctx);

function assert(cond, msg) {
    if (!cond)
        throw new Error(msg);
    console.log("  ok  " + msg);
}

const split = ctx.split;

console.log("segmentation:");

assert(split("").length === 0, "an empty reply has no segments");
assert(split(undefined).length === 0, "a missing reply has no segments");
assert(split(null).length === 0, "a null reply has no segments");

const plain = split("just prose");
assert(plain.length === 1 && plain[0].type === "text" && plain[0].content === "just prose", "prose alone is one text segment");

const fenced = split("before\n```js\nconst a = 1;\n```\nafter");
assert(fenced.length === 3, "prose around a fence makes three segments");
assert(fenced[0].type === "text" && fenced[0].content === "before\n", "the prose before the fence is kept");
assert(fenced[1].type === "code" && fenced[1].language === "js", "the fence's language is carried through");
assert(fenced[1].content === "const a = 1;", "the code is trimmed of the fence's own newlines");
assert(fenced[2].type === "text" && fenced[2].content === "\nafter", "the prose after the fence is kept");

const untagged = split("```\nplain code\n```");
assert(untagged[0].type === "code" && untagged[0].language === "text", "a fence with no language falls back to text");

const two = split("```sh\na\n```\nmiddle\n```py\nb\n```");
assert(two.filter(p => p.type === "code").length === 2, "two fences make two code segments");
assert(two.filter(p => p.type === "text").length === 1, "the prose between them is its own segment");

// A reply can stop mid-block: a cancel, a dropped connection, a token limit.
const truncated = split("here you go\n```py\nimport os");
assert(truncated.length === 1 && truncated[0].type === "text",
    "an unterminated fence stays prose rather than rendering as half a code block");

// The code must survive verbatim; it is the part people copy.
const tricky = split("```js\nconst s = \"```\";\n```");
assert(tricky.some(p => p.type === "code"), "a fence is still found when the code mentions backticks");

console.log("\nMessage segmentation: all checks passed");
