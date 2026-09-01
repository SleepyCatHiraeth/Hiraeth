pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root

    signal requestPopupOpen()

    property bool isRunning: false
    property bool isWorkSession: true
    property bool alarmActive: false
    property int timeLeft: Config.system.pomodoro.workTime
    property int totalTime: Config.system.pomodoro.workTime
    property real visualProgress: 1.0

    readonly property bool isResuming: !isRunning && !alarmActive && timeLeft > 0
        && timeLeft < (isWorkSession ? Config.system.pomodoro.workTime : Config.system.pomodoro.restTime)
    readonly property var spotifyPlayer: {
        for (const player of MprisController.filteredPlayers) {
            if ((player?.dbusName ?? "").toLowerCase().includes("spotify"))
                return player;
        }
        return null;
    }

    IpcHandler {
        target: "pomodoro"
        function check() { root.requestPopupOpen(); }
        function stop() {
            root.stopAlarm();
            root.isRunning = false;
        }
    }

    Connections {
        target: Config.system.pomodoro
        function onSyncSpotifyChanged() { root.updateSpotify(); }
    }

    onIsRunningChanged: updateSpotify()
    onIsWorkSessionChanged: updateSpotify()
    onTimeLeftChanged: {
        if (!isRunning && !alarmActive)
            visualProgress = totalTime > 0 ? timeLeft / totalTime : 0;
    }

    function updateSpotify() {
        if (!Config.system.pomodoro.syncSpotify || !spotifyPlayer)
            return;
        if (isRunning && isWorkSession) {
            if (!spotifyPlayer.isPlaying && spotifyPlayer.canPlay)
                spotifyPlayer.play();
        } else if (spotifyPlayer.isPlaying && spotifyPlayer.canPause) {
            spotifyPlayer.pause();
        }
    }

    function setTime(value) {
        timeLeft = Math.max(0, value);
        if (!isRunning) {
            totalTime = timeLeft;
            if (isWorkSession)
                Config.system.pomodoro.workTime = timeLeft;
            else
                Config.system.pomodoro.restTime = timeLeft;
        }
    }

    function toggleSession() {
        if (isRunning || alarmActive)
            return;
        isWorkSession = !isWorkSession;
        timeLeft = isWorkSession ? Config.system.pomodoro.workTime : Config.system.pomodoro.restTime;
        totalTime = timeLeft;
    }

    function toggleTimer() {
        if (alarmActive) {
            stopAlarm();
            nextSession();
            return;
        }
        if (!isRunning && timeLeft === (isWorkSession ? Config.system.pomodoro.workTime : Config.system.pomodoro.restTime))
            totalTime = timeLeft;
        isRunning = !isRunning;
    }

    function resetTimer() {
        stopAlarm();
        isRunning = false;
        isWorkSession = true;
        timeLeft = Config.system.pomodoro.workTime;
        totalTime = timeLeft;
        visualProgress = 1.0;
    }

    function startAlarm() {
        const finishedSession = isWorkSession ? "Work" : "Rest";
        isRunning = false;
        alarmActive = true;
        visualProgress = 0;
        alarmSoundLoader.active = true;

        if (Config.system.pomodoro.autoStart)
            nextSession();

        Notifications.notifyInternal({
            summary: "Pomodoro",
            body: finishedSession + " session finished!",
            appName: "Pomodoro",
            urgency: "normal",
            expireTimeout: 60000,
            replaceKey: "pomodoro-" + finishedSession,
            actions: [
                { identifier: "check", text: "Check" },
                { identifier: "stop", text: "Stop" }
            ],
            actionHandlers: {
                "check": function () { root.requestPopupOpen(); },
                "stop": function () {
                    root.stopAlarm();
                    root.isRunning = false;
                }
            }
        });
    }

    function stopAlarm() {
        if (alarmSoundLoader.item)
            alarmSoundLoader.item.stop();
        alarmActive = false;
    }

    function nextSession() {
        isWorkSession = !isWorkSession;
        timeLeft = isWorkSession ? Config.system.pomodoro.workTime : Config.system.pomodoro.restTime;
        totalTime = timeLeft;
        visualProgress = 1.0;
        if (Config.system.pomodoro.autoStart)
            isRunning = true;
    }

    NumberAnimation {
        target: root
        property: "visualProgress"
        from: root.totalTime > 0 ? root.timeLeft / root.totalTime : 0
        to: 0
        duration: root.timeLeft * 1000
        running: root.isRunning && root.timeLeft > 0
    }

    Loader {
        id: alarmSoundLoader
        active: false
        source: Quickshell.shellDir + "/modules/bar/clock/PomodoroSound.qml"
        onLoaded: {
            item.alarmActive = Qt.binding(() => root.alarmActive);
            item.autoStart = Qt.binding(() => Config.system.pomodoro.autoStart);
            item.stopAlarmRequested.connect(root.stopAlarm);
            item.loops = Config.system.pomodoro.autoStart ? 2 : 255;
            if (root.alarmActive && (root.isWorkSession || !(Config.system.pomodoro.syncSpotify && root.spotifyPlayer)))
                item.play();
            else if (Config.system.pomodoro.autoStart && root.alarmActive)
                root.alarmActive = false;
        }
    }

    Timer {
        interval: 1000
        running: root.isRunning && root.timeLeft > 0
        repeat: true
        onTriggered: {
            if (--root.timeLeft === 0)
                root.startAlarm();
        }
    }
}
