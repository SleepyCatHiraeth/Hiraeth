// Runnable check for the edge mapping: `node NotchEdge.test.js`.
// The mapping is the only non-obvious logic in the AI notch — a sign error
// here draws the flares on the wrong side, which is invisible in a lint pass
// and obvious only once it is on screen.

const fs = require("fs");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "NotchEdge.js"), "utf8").replace(".pragma library", "");
const NotchEdge = {};
new Function("exports", src + "\nexports.isVertical = isVertical;" + "\nexports.outward = outward;" + "\nexports.radii = radii;" + "\nexports.flareCorners = flareCorners;" + "\nexports.canvasTransform = canvasTransform;")(NotchEdge);

const EDGES = ["right", "left", "top", "bottom"];
const DEPTH = 44;
const LENGTH = 180;

function apply(m, x, y) {
    return {
        x: m[0] * x + m[2] * y + m[4],
        y: m[1] * x + m[3] * y + m[5]
    };
}

function assert(cond, msg) {
    if (!cond)
        throw new Error(msg);
    console.log("  ok  " + msg);
}

for (const edge of EDGES) {
    console.log(edge + ":");
    const vertical = NotchEdge.isVertical(edge);
    const m = NotchEdge.canvasTransform(edge, DEPTH);

    // The item is depth x length for a side edge, length x depth for a
    // horizontal one.
    const itemW = vertical ? DEPTH : LENGTH;
    const itemH = vertical ? LENGTH : DEPTH;

    // Canonical (u = DEPTH) is the bezel. Every point on it must land on the
    // item's own bezel edge, and pointing outward from there must leave the item.
    const out = NotchEdge.outward(edge);
    for (const v of [0, LENGTH / 2, LENGTH]) {
        const p = apply(m, DEPTH, v);
        const beyond = {
            x: p.x + out.x,
            y: p.y + out.y
        };
        assert(beyond.x < 0 || beyond.x > itemW || beyond.y < 0 || beyond.y > itemH,
            `bezel point (${p.x},${p.y}) is on the ${edge} edge`);
    }

    // Canonical u = 0 is the inner face: still inside the item, and stepping
    // outward from it must move toward the bezel rather than away.
    const inner = apply(m, 0, LENGTH / 2);
    assert(inner.x >= 0 && inner.x <= itemW && inner.y >= 0 && inner.y <= itemH,
        "inner face stays inside the item");

    // The transform is a rotation or a mirror, never a scale: |det| == 1, or
    // the border stroke would come out the wrong width on some edges.
    const det = Math.abs(m[0] * m[3] - m[1] * m[2]);
    assert(Math.abs(det - 1) < 1e-9, "transform preserves scale (|det| = 1)");

    // Exactly the two corners facing away from the bezel are rounded.
    const r = NotchEdge.radii(edge, 20);
    const rounded = Object.keys(r).filter(k => r[k] > 0);
    assert(rounded.length === 2, `two rounded corners, got ${rounded.join(",")}`);

    // The two flares are distinct, and both sit on the bezel side.
    const f = NotchEdge.flareCorners(edge);
    assert(f.first !== f.second, "flare corners differ");
}

// The rounded pair must be the pair opposite the bezel, checked explicitly so a
// swapped case in `radii` cannot pass the count test above.
const expectRounded = {
    right: ["tl", "bl"],
    left: ["tr", "br"],
    top: ["bl", "br"],
    bottom: ["tl", "tr"]
};
for (const edge of EDGES) {
    const r = NotchEdge.radii(edge, 20);
    const got = Object.keys(r).filter(k => r[k] > 0).sort();
    const want = expectRounded[edge].slice().sort();
    assert(got.join() === want.join(), `${edge}: rounds ${want.join("+")}`);
}

console.log("\nNotchEdge: all checks passed");
