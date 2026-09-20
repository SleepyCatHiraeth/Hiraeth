.pragma library

// Splits a reply into prose and fenced-code runs.
//
// This used to live inline as a Repeater's model expression, which meant it
// re-ran on every change to the message content -- and during streaming the
// content changed on every token, so the whole reply was re-segmented, every
// segment delegate was rebuilt, and each code segment created a fresh
// TextEdit and syntax highlighter. Streaming no longer renders through here at
// all; a finished reply is segmented once.
//
// Kept as a library so it can be tested without a running shell.

// Returns [{type: "text"|"code", content, language}]. An unterminated fence is
// deliberately left as prose: a reply can be cut off mid-block by a cancel or a
// dropped connection, and half a code block rendered as a code block looks like
// the highlighter broke rather than like the answer stopped.
function split(text) {
    const source = typeof text === "string" ? text : "";
    const fence = /```(\w*)\n([\s\S]*?)```/g;
    let parts = [];
    let lastIndex = 0;
    let match;

    while ((match = fence.exec(source)) !== null) {
        if (match.index > lastIndex) {
            parts.push({
                type: "text",
                content: source.substring(lastIndex, match.index),
                language: ""
            });
        }
        parts.push({
            type: "code",
            content: match[2].trim(),
            language: match[1] || "text"
        });
        lastIndex = fence.lastIndex;
    }

    if (lastIndex < source.length) {
        parts.push({
            type: "text",
            content: source.substring(lastIndex),
            language: ""
        });
    }

    return parts;
}
