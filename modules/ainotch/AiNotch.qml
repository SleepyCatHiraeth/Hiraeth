import QtQuick
import QtQuick.Effects
import qs.modules.components
import qs.modules.corners
import qs.modules.theme
import qs.config
import "NotchEdge.js" as NotchEdge

// The AI notch silhouette: a body welded to one screen edge, with inverse
// corners at each end flaring back out to that edge so it reads as part of the
// bezel rather than a floating panel. Purely visual — size and position are the
// caller's business, which keeps this reusable for both the resting notch and
// the expanded assistant panel.
Item {
    id: root

    // Which screen edge the notch is welded to.
    property string edge: "right"

    // Size of the inverse flare at each end. 0 draws a plain rounded body,
    // which is what the frame-wrapped assistant panel wants.
    property int flareSize: 0

    // Radius of the two body corners facing away from the bezel.
    property int bodyRadius: 0

    // Border stroke follows the theme, like the top notch's does.
    property bool borderEnabled: true

    // Surface variant. "transparent" is what the frame-wrapped assistant panel
    // needs so the screen frame draws its own background behind it.
    property string surfaceVariant: "bg"

    readonly property bool isVertical: NotchEdge.isVertical(edge)
    readonly property var bodyRadii: NotchEdge.radii(edge, bodyRadius)
    readonly property var flares: NotchEdge.flareCorners(edge)

    // Depth is across the shape (bezel to inner face), length runs along it.
    readonly property int depth: isVertical ? width : height
    readonly property int length: isVertical ? height : width

    // Clamped the way CodeNotch's SideNotchShape clamps: the corner is claimed
    // first out of half the depth, and the flare takes what is left. Clamping
    // the flare first collapses the corner to zero exactly when the shape folds
    // to its resting pill.
    readonly property int clampedCorner: Math.max(0, Math.min(bodyRadius, depth / 2))
    readonly property int clampedFlare: Math.max(0, Math.min(flareSize, length / 2, depth - clampedCorner))

    // Everything the caller puts in lands in the body, between the flares.
    default property alias content: contentArea.data
    readonly property alias body: contentArea

    StyledRect {
        id: notchBackground
        variant: root.surfaceVariant
        anchors.fill: parent
        enabled: false
        enableBorder: false
        animateRadius: false

        topLeftRadius: root.bodyRadii.tl
        topRightRadius: root.bodyRadii.tr
        bottomLeftRadius: root.bodyRadii.bl
        bottomRightRadius: root.bodyRadii.br

        layer.enabled: root.clampedFlare > 0
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: notchMask
            maskThresholdMin: 0.5
            maskThresholdMax: 1.0
            maskSpreadAtMin: 1.0
        }
    }

    // Carves the flares out of the background: two corner wedges against the
    // bezel and a body rect spanning the full depth between them.
    Item {
        id: notchMask
        visible: false
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: true

        Item {
            id: flareLow
            width: root.clampedFlare
            height: root.clampedFlare
            x: root.isVertical ? (root.edge === "right" ? parent.width - width : 0) : 0
            y: root.isVertical ? 0 : (root.edge === "bottom" ? parent.height - height : 0)

            RoundCorner {
                anchors.fill: parent
                corner: root.flares.first
                size: Math.max(parent.width, 1)
                color: "white"
            }
        }

        Rectangle {
            id: bodyMask
            color: "white"
            x: root.isVertical ? 0 : flareLow.width
            y: root.isVertical ? flareLow.height : 0
            width: root.isVertical ? parent.width : parent.width - 2 * root.clampedFlare
            height: root.isVertical ? parent.height - 2 * root.clampedFlare : parent.height

            topLeftRadius: root.bodyRadii.tl
            topRightRadius: root.bodyRadii.tr
            bottomLeftRadius: root.bodyRadii.bl
            bottomRightRadius: root.bodyRadii.br
        }

        Item {
            id: flareHigh
            width: root.clampedFlare
            height: root.clampedFlare
            x: root.isVertical ? flareLow.x : parent.width - width
            y: root.isVertical ? parent.height - height : flareLow.y

            RoundCorner {
                anchors.fill: parent
                corner: root.flares.second
                size: Math.max(parent.width, 1)
                color: "white"
            }
        }
    }

    // The body region, between the flares. Children go here rather than into
    // the full item so they never land under a flare.
    Item {
        id: contentArea
        x: bodyMask.x
        y: bodyMask.y
        width: bodyMask.width
        height: bodyMask.height
    }

    // One continuous stroke around the silhouette, matching the top notch's
    // outline canvas. Written once in canonical right-edge space and mapped
    // onto the actual edge, so there is only ever one copy of the geometry.
    Canvas {
        id: outlineCanvas
        anchors.fill: parent
        z: 5000
        antialiasing: true

        readonly property var borderData: Config.theme.srBg.border || ["transparent", 0]
        readonly property int borderWidth: borderData[1]
        readonly property color borderColor: Config.resolveColor(borderData[0])

        visible: root.borderEnabled && borderWidth > 0

        onPaint: {
            const ctx = getContext("2d");
            ctx.resetTransform();
            ctx.clearRect(0, 0, width, height);
            if (!visible || borderWidth <= 0)
                return;

            const depth = root.depth;
            const length = root.length;
            const offset = borderWidth / 2;
            const curl = root.clampedFlare;
            const r = Math.max(0, Math.min(root.clampedCorner, (length - 2 * curl) / 2));

            const m = NotchEdge.canvasTransform(root.edge, depth);
            ctx.setTransform(m[0], m[1], m[2], m[3], m[4], m[5]);

            ctx.strokeStyle = borderColor;
            ctx.lineWidth = borderWidth;
            ctx.lineJoin = "round";
            ctx.lineCap = "round";

            ctx.beginPath();
            ctx.moveTo(depth - offset, offset);
            if (curl > offset) {
                // Flare inward off the bezel onto the body's leading edge.
                ctx.arc(depth - curl, offset, curl - offset, 0, Math.PI / 2, false);
            } else {
                ctx.lineTo(depth - curl, curl);
            }
            ctx.lineTo(offset + r, curl);
            if (r > offset)
                ctx.arcTo(offset, curl, offset, curl + r, r - offset);
            ctx.lineTo(offset, length - curl - r);
            if (r > offset)
                ctx.arcTo(offset, length - curl, offset + r, length - curl, r - offset);
            ctx.lineTo(depth - curl, length - curl);
            if (curl > offset) {
                // And back out to the bezel at the far end.
                ctx.arc(depth - curl, length - offset, curl - offset, 3 * Math.PI / 2, 2 * Math.PI, false);
            } else {
                ctx.lineTo(depth - curl, length);
            }
            ctx.stroke();
        }

        onBorderColorChanged: requestPaint()
        onBorderWidthChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        Connections {
            target: root
            function onEdgeChanged() {
                outlineCanvas.requestPaint();
            }
            function onClampedFlareChanged() {
                outlineCanvas.requestPaint();
            }
            function onClampedCornerChanged() {
                outlineCanvas.requestPaint();
            }
        }

    }
}
