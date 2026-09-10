pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

// Settings for the turret voice assistant.
//
// Every value here lives in the backend's own config file rather than an AMBXST
// Config domain, because the backend owns the assistant's lifecycle and must be
// able to read its settings without QML running. So this panel reads and writes
// over IPC (assistant.config / assistant.set) instead of binding to Config.
Item {
    id: root

    property int maxContentWidth: 520
    readonly property int contentWidth: Math.min(width, maxContentWidth)

    // Local mirror of the backend config. Written back field by field, so two
    // panels open at once cannot clobber each other's unrelated edits.
    property var cfg: ({})
    property var voices: []
    property var sources: []
    property var sinks: []

    // Prepend an explicit first choice so there is always a valid selection.
    // Without it, an unset device leaves currentIndex at -1 and the combo box
    // renders empty, which reads as broken rather than as "not chosen".
    readonly property var sourceChoices: [{name: "", description: "Auto-detect"}].concat(root.sources)
    readonly property var sinkChoices: [{name: "", description: "System default"}].concat(root.sinks)
    property var stats: ({})
    property bool loaded: false

    function reload() {
        TurretService.getConfig(result => {
            if (!root || !root.alive || !result)
                return;
            root.cfg = result;
            root.loaded = true;
        });
        TurretService.listVoices(result => {
            if (root && root.alive)
                root.voices = result || [];
        });
        TurretService.checkDeps(result => {
            if (!root || !root.alive || !result)
                return;
            root.sources = result.sources || [];
            root.sinks = result.sinks || [];
        });
        TurretService.memoryStats(result => {
            if (root && root.alive)
                root.stats = result || ({});
        });
    }

    function apply(key, value) {
        let patch = {};
        patch[key] = value;
        TurretService.setConfig(patch, result => {
            if (!root || !root.alive)
                return;
            if (result)
                root.cfg = result;
            root.reload();
        });
    }

    // The settings indexer loads every panel once to scrape its search entries,
    // then discards it. IPC replies arriving after that would run callbacks
    // against a destroyed object, so fetching is tied to being on screen and
    // every callback checks it is still alive first.
    property bool alive: true
    Component.onDestruction: alive = false

    onVisibleChanged: if (visible && !loaded) reload()
    Component.onCompleted: if (visible) reload()

    ScrollView {
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: root.contentWidth
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10

            PanelTitlebar {
                title: "Turret Assistant"
                showToggle: true
                toggleChecked: TurretService.enabled
                onToggleChanged: checked => root.apply("enabled", checked)
            }

            TurretSettingCard {
                Layout.fillWidth: true
                visible: !TurretService.enabled
                title: "Off"
                subtitle: "Nothing runs while this is off: no polling, no database, no models, no VRAM. It stays off after a reboot until you turn it back on."
                icon: Icons.power
                accent: Colors.overSurfaceVariant
            }

            // ---- Health ------------------------------------------------
            TurretSettingCard {
                Layout.fillWidth: true
                visible: TurretService.enabled
                title: TurretService.llmReachable ? "Model server running" : "Model server not running"
                subtitle: TurretService.llmReachable
                          ? "Local, on " + (root.cfg.endpoint ?? "")
                          : (TurretService.llmError !== "" ? TurretService.llmError
                                                           : "Speech and memory will not work until it starts.")
                icon: TurretService.llmReachable ? Icons.shieldCheck : Icons.alert
                accent: TurretService.llmReachable ? Colors.primary : Colors.criticalText

                Button {
                    visible: !TurretService.llmReachable
                    text: "Start server"
                    onClicked: TurretService.repairServer(() => { if (root && root.alive) root.reload(); })
                }

                // Explicit release of the ~650 MB the daemon holds plus any
                // resident model, rather than waiting for the idle TTL.
                Button {
                    visible: TurretService.llmReachable
                    text: "Stop & free memory"
                    onClicked: TurretService.stopServer(() => { if (root && root.alive) root.reload(); })
                }
            }

            // A local assistant that quietly became a remote one would be the
            // worst possible failure, so the guarantee is stated, not implied.
            TurretSettingCard {
                Layout.fillWidth: true
                visible: TurretService.enabled
                title: "Local only"
                subtitle: "The model endpoint is rejected unless it is loopback. Nothing is sent off this machine."
                icon: Icons.lock
                accent: Colors.primary
            }

            TurretSectionLabel { text: "Voice"; visible: TurretService.enabled }

            TurretSettingCard {
                Layout.fillWidth: true
                visible: TurretService.enabled
                title: "Speaking voice"
                subtitle: (root.cfg.tts_engine ?? "") + " · " + (root.cfg.tts_voice ?? "")
                icon: Icons.speakerHigh

                ComboBox {
                    Layout.preferredWidth: 210
                    model: root.voices
                    textRole: "label"
                    enabled: root.voices.length > 0
                    currentIndex: {
                        for (let i = 0; i < root.voices.length; i++) {
                            if (root.voices[i].voice === root.cfg.tts_voice)
                                return i;
                        }
                        return -1;
                    }
                    onActivated: index => {
                        const v = root.voices[index];
                        if (!v)
                            return;
                        // Engine and voice must change together: a Kokoro voice
                        // name means nothing to Piper, and the sample rates differ.
                        TurretService.setConfig({tts_engine: v.engine, tts_voice: v.voice},
                                                result => { if (root && root.alive && result) root.cfg = result; });
                    }
                }

                Button {
                    text: "Test"
                    enabled: TurretService.llmReachable || true
                    onClicked: TurretService.testVoice("Turret assistant online. This is the selected voice.")
                }
            }

            TurretSettingCard {
                Layout.fillWidth: true
                visible: TurretService.enabled
                title: "Speaking rate"
                subtitle: (speedSlider.minSpeed + speedSlider.value * (speedSlider.maxSpeed - speedSlider.minSpeed)).toFixed(2) + "x"
                icon: Icons.waveform

                // StyledSlider works in normalised 0..1 and exposes isDragging
                // rather than a pressed state, so speed is mapped onto that
                // range and committed when the drag ends -- not on every frame,
                // which would write the config file continuously.
                StyledSlider {
                    id: speedSlider
                    Layout.preferredWidth: 180
                    Layout.preferredHeight: 22
                    resizeParent: false
                    readonly property real minSpeed: 0.6
                    readonly property real maxSpeed: 1.6
                    value: ((root.cfg.speed ?? 1.0) - minSpeed) / (maxSpeed - minSpeed)
                    onIsDraggingChanged: {
                        if (isDragging)
                            return;
                        const next = minSpeed + value * (maxSpeed - minSpeed);
                        root.apply("speed", Math.round(next * 100) / 100);
                    }
                }
            }

            TurretSectionLabel { text: "Speech recognition"; visible: TurretService.enabled }

            TurretSettingCard {
                Layout.fillWidth: true
                visible: TurretService.enabled
                title: "Microphone"
                subtitle: root.cfg.capture_target === "" ? "Auto-detected" : (root.cfg.capture_target ?? "")
                icon: Icons.mic

                ComboBox {
                    Layout.preferredWidth: 210
                    model: root.sourceChoices
                    textRole: "description"
                    currentIndex: {
                        for (let i = 0; i < root.sourceChoices.length; i++) {
                            if (root.sourceChoices[i].name === (root.cfg.capture_target ?? ""))
                                return i;
                        }
                        return 0;
                    }
                    onActivated: index => {
                        const src = root.sourceChoices[index];
                        if (src) root.apply("capture_target", src.name);
                    }
                }
            }

            TurretSettingCard {
                Layout.fillWidth: true
                visible: TurretService.enabled
                title: "Speaker"
                subtitle: root.cfg.playback_target === "" ? "System default" : (root.cfg.playback_target ?? "")
                icon: Icons.speakerHigh

                ComboBox {
                    Layout.preferredWidth: 210
                    model: root.sinkChoices
                    textRole: "description"
                    currentIndex: {
                        for (let i = 0; i < root.sinkChoices.length; i++) {
                            if (root.sinkChoices[i].name === (root.cfg.playback_target ?? ""))
                                return i;
                        }
                        return 0;
                    }
                    onActivated: index => {
                        const snk = root.sinkChoices[index];
                        if (snk) root.apply("playback_target", snk.name);
                    }
                }
            }

            TurretSettingCard {
                Layout.fillWidth: true
                visible: TurretService.enabled
                title: "Known words"
                subtitle: "Names the transcriber should expect. Without these it guesses unfamiliar words phonetically."
                icon: Icons.notepad
                tall: true

                TextField {
                    Layout.fillWidth: true
                    text: root.cfg.stt_vocab ?? ""
                    placeholderText: "comma,separated,words"
                    onEditingFinished: if (text !== root.cfg.stt_vocab) root.apply("stt_vocab", text)
                }
            }

            TurretSectionLabel { text: "Memory"; visible: TurretService.enabled }

            TurretSettingCard {
                Layout.fillWidth: true
                visible: TurretService.enabled
                title: "Remember things"
                subtitle: TurretService.memoryEnabled
                          ? "Durable memories always ask before they are kept."
                          : "Off. Nothing durable is written."
                icon: Icons.robot

                Switch {
                    checked: TurretService.memoryEnabled
                    onToggled: root.apply("memory_enabled", checked)
                }
            }

            TurretSettingCard {
                Layout.fillWidth: true
                visible: TurretService.enabled && TurretService.memoryEnabled
                title: "Stored"
                subtitle: {
                    const by = root.stats.by_status || ({});
                    const act = by.active || 0;
                    const pend = (by.candidate || 0) + (by.quarantined || 0);
                    let s = act + (act === 1 ? " memory" : " memories");
                    if (pend > 0)
                        s += " · " + pend + " awaiting review";
                    if (TurretService.embedError !== "")
                        s += " · " + TurretService.embedError;
                    return s;
                }
                icon: Icons.notepad
                accent: TurretService.embedError !== "" ? Colors.warning : Colors.overSurface

                Button {
                    text: "Manage"
                    onClicked: memoryDialog.open()
                }
            }
        }
    }

    TurretMemoryDialog {
        id: memoryDialog
        onChanged: root.reload()
    }
}
