import QtQuick
import QtMultimedia
import QtQuick.Effects
import qs.modules.theme
import qs.config

Item {
    id: root
    property string source: ""
    // Still frame for a video/gif source, extracted when the wallpaper was chosen.
    // Painted underneath the player so the surface is never blank while decoding.
    property string posterSource: ""
    property real radius: 0
    property bool tintEnabled: false

    readonly property bool isVideo: {
        var ext = source.toString().toLowerCase().split('?')[0].split('.').pop();
        return ["mp4", "webm", "mov", "avi", "mkv", "gif"].includes(ext);
    }

    property real pendingSeekMs: -1

    // Guard on `item`, not on `status`: when the loader deactivates on a wallpaper
    // switch the item is cleared while the status still reads Ready, and
    // dereferencing it there threw, which left the surface with no player at all
    // and painted it black.
    readonly property var player: videoPlayerLoader.item ? videoPlayerLoader.item.player : null
    readonly property real videoPosition: player ? player.position : 0

    function applyPendingSeek() {
        if (pendingSeekMs < 0 || !player)
            return;
        var status = player.mediaStatus;
        if (status >= MediaPlayer.LoadedMedia && status !== MediaPlayer.InvalidMedia) {
            player.setPosition(pendingSeekMs);
            pendingSeekMs = -1;
        }
    }

    // Whether this surface wants video on screen. `play()` issued while the media
    // is still loading is dropped by the backend, and a single fire-and-forget call
    // leaves the player parked in Stopped with a sink attached and nothing drawn --
    // which screen that hits is a race, so one monitor would play and the other stay
    // black. Hold the intent and re-issue until the player actually reports Playing.
    property bool wantPlaying: false
    readonly property bool playbackReady: player
        && player.mediaStatus >= MediaPlayer.LoadedMedia
        && player.mediaStatus !== MediaPlayer.InvalidMedia

    function ensurePlaying() {
        if (!wantPlaying || !playbackReady)
            return;
        if (player.playbackState !== MediaPlayer.PlayingState)
            player.play();
    }

    Timer {
        id: playRetry
        interval: 250
        repeat: true
        running: root.wantPlaying && root.isVideo
            && (!root.player || root.player.playbackState !== MediaPlayer.PlayingState)
        onTriggered: {
            root.applyPendingSeek();
            root.ensurePlaying();
        }
    }

    function videoPlayAt(ms) {
        if (!root.isVideo)
            return;
        pendingSeekMs = ms;
        wantPlaying = true;
        if (player) {
            ensurePlaying();
            applyPendingSeek();
        }
    }

    function videoSeek(ms) {
        if (player)
            player.setPosition(ms);
    }

    function videoPlay() {
        wantPlaying = true;
        ensurePlaying();
    }

    // Idle media objects cost real time to build and tear down, so they
    // only exist while the source is actually a video/gif.
    Loader {
        id: videoPlayerLoader
        active: root.isVideo
        sourceComponent: videoPlayerComponent
        onLoaded: {
            root.wantPlaying = true;
            root.ensurePlaying();
        }
    }

    Component {
        id: videoPlayerComponent

        Item {
            visible: false
            width: 0
            height: 0

            property alias player: videoPlayer

            MediaPlayer {
                id: videoPlayer
                loops: MediaPlayer.Infinite
                audioOutput: mutedAudio
                // Bind straight to `item`. Gating on `status` means the false branch
                // never reads `item`, so the binding registers no dependency on it:
                // once the output appears without a further status change the sink
                // stays null, the player decodes into nothing, and the surface that
                // lost the race renders blank.
                videoOutput: videoLoader.item
                source: root.source

                onMediaStatusChanged: {
                    applyPendingSeek();
                    root.ensurePlaying();
                }
            }

            AudioOutput {
                id: mutedAudio
                muted: true
                volume: 0
            }
        }
    }

    Component {
        id: videoOutputComponent

        VideoOutput {
            id: videoOut
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectCrop

            layer.enabled: root.tintEnabled
            layer.effect: ShaderEffect {
                property var paletteTexture: paletteTextureSource
                property real paletteSize: root.optimizedPalette.length
                property real texWidth: videoOut.width
                property real texHeight: videoOut.height

                vertexShader: "../widgets/dashboard/wallpapers/palette.vert.qsb"
                fragmentShader: "../widgets/dashboard/wallpapers/palette.frag.qsb"
            }
        }
    }

    // Subset of colors for optimization (approx 25 colors vs 98)
    // Copied from Wallpaper.qml to ensure consistency
    readonly property var optimizedPalette: [
        "background", "overBackground", "shadow",
        "surface", "surfaceBright", "surfaceDim",
        "surfaceContainer", "surfaceContainerHigh", "surfaceContainerHighest", "surfaceContainerLow", "surfaceContainerLowest",
        "primary", "secondary", "tertiary",
        "red", "lightRed",
        "green", "lightGreen",
        "blue", "lightBlue",
        "yellow", "lightYellow",
        "cyan", "lightCyan",
        "magenta", "lightMagenta"
    ]

    // Palette generation for the shader
    Item {
        id: paletteSourceItem
        visible: true
        width: root.optimizedPalette.length
        height: 1
        opacity: 0

        Row {
            anchors.fill: parent
            Repeater {
                model: root.optimizedPalette
                Rectangle {
                    width: 1
                    height: 1
                    color: Colors[modelData]
                }
            }
        }
    }

    ShaderEffectSource {
        id: paletteTextureSource
        sourceItem: paletteSourceItem
        hideSource: true
        visible: false
        smooth: false
        recursive: false
    }

    // Container for masking (rounded corners)
    Item {
        anchors.fill: parent
        layer.enabled: root.radius > 0
        layer.effect: MultiEffect {
            maskEnabled: true
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
            maskSource: ShaderEffectSource {
                sourceItem: Rectangle {
                    width: root.width
                    height: root.height
                    radius: root.radius
                }
            }
        }

        Image {
            mipmap: true
            id: rawImage
            anchors.fill: parent
            visible: true
            source: root.isVideo
                ? (root.posterSource ? "file://" + root.posterSource : "")
                : root.source
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true

            // Tint layer
            layer.enabled: root.tintEnabled
            layer.effect: ShaderEffect {
                property var paletteTexture: paletteTextureSource
                property real paletteSize: root.optimizedPalette.length
                property real texWidth: rawImage.width
                property real texHeight: rawImage.height

                vertexShader: "../widgets/dashboard/wallpapers/palette.vert.qsb"
                fragmentShader: "../widgets/dashboard/wallpapers/palette.frag.qsb"
            }
        }

        Loader {
            id: videoLoader
            anchors.fill: parent
            active: root.isVideo
            sourceComponent: videoOutputComponent

            // Reveal only once frames are actually flowing; until then the poster
            // below is what the user sees, instead of black.
            opacity: root.player && root.player.playbackState === MediaPlayer.PlayingState ? 1 : 0

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
