.pragma library

// Stack space: `along` runs parallel to the screen edge the notch is welded to,
// `across` measures inward from that edge. Every measurement in the AI notch is
// written once in those terms and mapped here, so the shape has one definition
// instead of one per edge.

var CornerTopLeft = 0;
var CornerTopRight = 1;
var CornerBottomLeft = 2;
var CornerBottomRight = 3;

function isVertical(edge) {
    return edge === "left" || edge === "right";
}

// Unit vector pointing at the bezel, in item coordinates (y grows down).
// This is the direction the notch travels as it hides.
function outward(edge) {
    switch (edge) {
    case "right":
        return {
            x: 1,
            y: 0
        };
    case "left":
        return {
            x: -1,
            y: 0
        };
    case "top":
        return {
            x: 0,
            y: -1
        };
    default:
        return {
            x: 0,
            y: 1
        };
    }
}

// Body radii: only the two corners facing away from the bezel are rounded.
// The pair against the bezel stay square so the body reads as welded to it.
function radii(edge, r) {
    switch (edge) {
    case "right":
        return {
            tl: r,
            tr: 0,
            bl: r,
            br: 0
        };
    case "left":
        return {
            tl: 0,
            tr: r,
            bl: 0,
            br: r
        };
    case "top":
        return {
            tl: 0,
            tr: 0,
            bl: r,
            br: r
        };
    default:
        return {
            tl: r,
            tr: r,
            bl: 0,
            br: 0
        };
    }
}

// The two inverse corners that flare the body back out to the bezel, as
// RoundCorner.CornerEnum values. `first` sits at the low end of the along axis,
// `second` at the high end.
function flareCorners(edge) {
    switch (edge) {
    case "right":
        return {
            first: CornerBottomRight,
            second: CornerTopRight
        };
    case "left":
        return {
            first: CornerBottomLeft,
            second: CornerTopLeft
        };
    case "top":
        return {
            first: CornerTopRight,
            second: CornerTopLeft
        };
    default:
        return {
            first: CornerBottomRight,
            second: CornerBottomLeft
        };
    }
}

// Canvas 2D transform mapping canonical space onto item coordinates.
// Canonical space is written for the right edge: `u` runs across from the far
// side (so the bezel lands at u == depth) and `v` runs along. Writing the
// silhouette four times would mean four copies of the corner-versus-flare
// clamping, and three of them would never be the one on screen when it broke.
function canvasTransform(edge, depth) {
    switch (edge) {
    case "right":
        return [1, 0, 0, 1, 0, 0];
    case "left":
        return [-1, 0, 0, 1, depth, 0];
    case "top":
        return [0, -1, 1, 0, 0, depth];
    default:
        return [0, 1, 1, 0, 0, 0];
    }
}
