import QtQuick
import QtMultimedia

// Still, GIF or video wallpaper, cropped to fill. `ready` turns true once the
// first frame can be shown, so the intro never fades in an empty surface.
Item {
    id: root

    property url source: Theme.wallpaper
    property string kind: Theme.wallpaperKind
    readonly property bool ready: {
        if (kind === "image")
            return still.status === Image.Ready;
        if (kind === "gif")
            return gif.status === AnimatedImage.Ready;
        if (kind === "video")
            return player.playbackState === MediaPlayer.PlayingState && player.hasVideo;
        return true;
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    Image {
        id: still
        anchors.fill: parent
        visible: root.kind === "image"
        source: root.kind === "image" ? root.source : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        sourceSize.width: width
        sourceSize.height: height
    }

    AnimatedImage {
        id: gif
        anchors.fill: parent
        visible: root.kind === "gif"
        source: root.kind === "gif" ? root.source : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        playing: root.kind === "gif"
    }

    MediaPlayer {
        id: player
        source: root.kind === "video" ? root.source : ""
        loops: MediaPlayer.Infinite
        videoOutput: video
        audioOutput: AudioOutput {
            muted: true
            volume: 0
        }
        onSourceChanged: if (source.toString() !== "") play()
    }

    VideoOutput {
        id: video
        anchors.fill: parent
        visible: root.kind === "video"
        fillMode: VideoOutput.PreserveAspectCrop
    }
}
