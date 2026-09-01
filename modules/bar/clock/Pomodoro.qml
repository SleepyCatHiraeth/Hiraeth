pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    id: root
    implicitHeight: content.implicitHeight + 24
    width: 300
    required property string screenName

    readonly property bool isRunning: PomodoroService.isRunning
    readonly property bool isWorkSession: PomodoroService.isWorkSession
    readonly property bool alarmActive: PomodoroService.alarmActive
    readonly property int timeLeft: PomodoroService.timeLeft
    readonly property int totalTime: PomodoroService.totalTime
    readonly property real visualProgress: PomodoroService.visualProgress
    readonly property bool isResuming: PomodoroService.isResuming

    signal requestPopupOpen()

    Connections {
        target: PomodoroService
        function onRequestPopupOpen() {
            if (root.screenName === AxctlService.focusedMonitor?.name)
                root.requestPopupOpen();
        }
    }

    // --- UI Layout ---
    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        // Top Row: Small Configs
        RowLayout {
            Layout.fillWidth: true
            
            StyledRect {
                variant: "common"
                Layout.preferredHeight: 28
                Layout.preferredWidth: 110
                radius: Styling.radius(-4)
                
                Text {
                    anchors.centerIn: parent
                    text: root.isWorkSession ? "Work Session" : "Rest Session"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    font.weight: Font.Bold
                    color: mouseAreaToggle.containsMouse ? Styling.srItem("overprimary") : Colors.overBackground
                }
                
                MouseArea {
                    id: mouseAreaToggle
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !root.isRunning && !root.alarmActive
                    onClicked: PomodoroService.toggleSession()
                }
            }

            Item { Layout.fillWidth: true }

            // Reset
            StyledRect {
                variant: "common"
                implicitWidth: 28; implicitHeight: 28
                radius: Styling.radius(-4)
                Text {
                    anchors.centerIn: parent
                    text: Icons.arrowCounterClockwise
                    font.family: Icons.font; font.pixelSize: 14
                    color: Colors.overBackground
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: PomodoroService.resetTimer()
                }
            }
        }

        // Stack-like view for Timer Inputs
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            clip: true

            ColumnLayout {
                id: timerInputs
                anchors.centerIn: parent
                spacing: 4

                RowLayout {
                    spacing: 4
                    Layout.alignment: Qt.AlignHCenter
                    
                    TimerInput {
                        id: minIn
                        value: Math.floor(root.timeLeft / 60)
                        onValueUpdated: val => {
                            PomodoroService.setTime((val * 60) + (root.timeLeft % 60));
                        }
                    }
                    
                    Text {
                        text: ":"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(8)
                        font.weight: Font.Bold
                        color: root.alarmActive ? Styling.srItem("overprimary") : Colors.overBackground
                        Layout.topMargin: -6
                    }
                    
                    TimerInput {
                        id: secIn
                        value: root.timeLeft % 60
                        onValueUpdated: val => {
                            PomodoroService.setTime((Math.floor(root.timeLeft / 60) * 60) + val);
                        }
                    }
                }
            }

            // Inverse Progress Bar
            StyledRect {
                id: progressTrack
                variant: "common"
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                height: 4
                width: 180
                radius: 2
                opacity: root.isRunning || root.alarmActive || root.visualProgress < 1.0 ? 1.0 : 0.3
                
                Rectangle {
                    height: parent.height
                    width: root.visualProgress * parent.width
                    radius: progressTrack.radius
                    color: Styling.srItem("overprimary")
                }
            }
        }

        // Quick Adjust & Start
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ControlBtn {
                text: "-1m"
                onClicked: {
                    if (root.timeLeft >= 60)
                        PomodoroService.setTime(root.timeLeft - 60);
                }
            }

            StyledRect {
                id: playBtn
                variant: root.alarmActive ? "primary" : (root.isRunning ? "focus" : "common")
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: Styling.radius(0)
                
                Text {
                    anchors.centerIn: parent
                    text: root.alarmActive ? "STOP ALARM" : (root.isRunning ? "PAUSE" : (root.isResuming ? "RESUME" : "START " + (root.isWorkSession ? "WORK" : "REST")))
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(0)
                    font.weight: Font.Black
                    font.letterSpacing: 1
                    color: playBtn.item
                }
                
                MouseArea {
                    anchors.fill: parent
                    onClicked: PomodoroService.toggleTimer()
                }
            }

            ControlBtn {
                text: "+1m"
                onClicked: PomodoroService.setTime(root.timeLeft + 60)
            }
        }

        // Settings Row
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: 20

            // Auto Toggle
            RowLayout {
                spacing: 8
                Text {
                    text: "Auto"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    color: Colors.outline
                }
                Item {
                    Layout.preferredWidth: 36; Layout.preferredHeight: 20
                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: Config.system.pomodoro.autoStart ? Styling.srItem("overprimary") : Colors.surfaceBright
                        opacity: Config.system.pomodoro.autoStart ? 1.0 : 0.4
                        Rectangle {
                            x: Config.system.pomodoro.autoStart ? parent.width - 18 : 2
                            y: 2; width: 16; height: 16; radius: 8
                            color: Colors.background
                            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutQuart } }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: Config.system.pomodoro.autoStart = !Config.system.pomodoro.autoStart
                    }
                }
            }

            // Sync Spotify Toggle
            RowLayout {
                spacing: 8
                Text {
                    text: "Sync Spotify"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    color: Colors.outline
                }
                Item {
                    Layout.preferredWidth: 36; Layout.preferredHeight: 20
                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: Config.system.pomodoro.syncSpotify ? Styling.srItem("overprimary") : Colors.surfaceBright
                        opacity: Config.system.pomodoro.syncSpotify ? 1.0 : 0.4
                        Rectangle {
                            x: Config.system.pomodoro.syncSpotify ? parent.width - 18 : 2
                            y: 2; width: 16; height: 16; radius: 8
                            color: Colors.background
                            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutQuart } }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: Config.system.pomodoro.syncSpotify = !Config.system.pomodoro.syncSpotify
                    }
                }
            }
        }
    }

    // --- Sub-components ---
    component TimerInput: TextField {
        id: tIn
        property int value: 0
        signal valueUpdated(int newValue)
        
        text: value.toString().padStart(2, '0')
        onActiveFocusChanged: if (!activeFocus) text = value.toString().padStart(2, '0')
        
        font.family: Config.theme.monoFont
        font.pixelSize: Styling.fontSize(8)
        font.weight: Font.Bold
        color: root.alarmActive ? (Math.floor(Date.now() / 500) % 2 === 0 ? Styling.srItem("overprimary") : Colors.overBackground) : Colors.overBackground
        
        background: Item {}
        padding: 0; leftPadding: 0; rightPadding: 0
        horizontalAlignment: TextInput.AlignHCenter
        maximumLength: 2
        validator: IntValidator { bottom: 0; top: 99 }
        selectByMouse: true
        
        onTextEdited: {
            let v = parseInt(text);
            if (!isNaN(v)) {
                tIn.valueUpdated(v);
            }
        }
        
        onEditingFinished: {
            let v = parseInt(text) || 0;
            tIn.valueUpdated(v);
            text = v.toString().padStart(2, '0');
        }
        
        Layout.preferredWidth: 60
        
        Timer {
            interval: 500
            running: root.alarmActive
            repeat: true
            onTriggered: tIn.update()
        }
    }

    component ControlBtn: StyledRect {
        id: cBtn
        property string text: ""
        signal clicked()
        
        variant: "common"
        implicitWidth: 44; implicitHeight: 40
        radius: Styling.radius(-4)
        
        Text {
            anchors.centerIn: parent
            text: cBtn.text
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-1)
            color: mouseA.containsMouse ? Styling.srItem("overprimary") : Colors.overBackground
        }
        
        MouseArea {
            id: mouseA
            anchors.fill: parent
            hoverEnabled: true
            onClicked: cBtn.clicked()
        }
    }
}
