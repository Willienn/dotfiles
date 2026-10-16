import qs.modules.ii.sidebarLeft.monitor
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarLeft.ports
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * Aba YT Music: música atual do pear-desktop via plugin API Server.
 * Controles básicos: play/pause, anterior, próxima.
 */
Item {
    id: root

    property real padding: 4
    property bool isActive: SwipeView.view ? SwipeView.isCurrentItem : true

    readonly property string apiBase: "http://localhost:26538/api/v1"

    // Estado
    property bool hasSong: false
    property string title: ""
    property string artist: ""
    property string imageUrl: ""
    property bool playing: false
    property real elapsed: 0
    property real duration: 0

    readonly property real progress: root.duration > 0
        ? Math.max(0, Math.min(1, root.elapsed / root.duration))
        : 0

    function formatTime(sec) {
        if (!isFinite(sec) || sec < 0) return "--:--";
        const m = Math.floor(sec / 60);
        const s = Math.floor(sec % 60);
        return m + ":" + (s < 10 ? "0" + s : s);
    }

    function refresh() {
        if (songProc.running) return;
        songProc.buffer = "";
        songProc.running = true;
    }

    function parseSong(text) {
        if (!text || text.length === 0) return;
        try {
            const s = JSON.parse(text);
            root.hasSong = true;
            root.title = s.title || "";
            root.artist = s.artist || "";
            root.imageUrl = s.imageSrc || "";
            root.playing = (s.isPaused === false) || (s.isPlaying === true);
            if (typeof s.songDuration === "number") root.duration = s.songDuration;
            if (typeof s.elapsedSeconds === "number") root.elapsed = s.elapsedSeconds;
        } catch (e) {
            // resposta inválida; mantém estado anterior
        }
    }

    function control(endpoint) {
        Quickshell.execDetached(["curl", "-s", "-X", "POST", root.apiBase + "/" + endpoint]);
        controlDelay.restart();
    }

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.isActive && root.visible
        onTriggered: root.refresh()
    }

    Timer {
        id: controlDelay
        interval: 350
        onTriggered: root.refresh()
    }

    Process {
        id: songProc
        command: ["curl", "-s", root.apiBase + "/song"]
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => { songProc.buffer += data; }
        }
        onExited: (code, status) => {
            root.parseSong(songProc.buffer);
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: 8

        // Cabeçalho
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            spacing: 6

            StyledText {
                text: "YT Music"
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
            Item { Layout.fillWidth: true }
            PortActionButton {
                icon: "refresh"
                onClicked: root.refresh()
            }
        }

        // Capa
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 240
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            clip: true

            Image {
                id: coverImage
                anchors.fill: parent
                source: root.imageUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                visible: status === Image.Ready
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: !coverImage.visible
                text: "music_note"
                iconSize: 64
                color: Appearance.colors.colSubtext
            }
        }

        // Título e artista
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.title.length > 0 ? root.title : "Nada tocando"
            font.pixelSize: Appearance.font.pixelSize.large
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.artist
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }

        Item { Layout.fillHeight: true }

        // Barra de progresso
        UsageBar {
            Layout.fillWidth: true
            value: root.progress
            barColor: Appearance.m3colors.m3primary
        }

        // Tempos
        RowLayout {
            Layout.fillWidth: true
            StyledText {
                text: root.formatTime(root.elapsed)
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
            Item { Layout.fillWidth: true }
            StyledText {
                text: root.formatTime(root.duration)
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }

        // Controles
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 4
            spacing: 16

            PortActionButton {
                icon: "skip_previous"
                onClicked: root.control("previous")
            }

            Rectangle {
                implicitWidth: 56
                implicitHeight: 56
                radius: width / 2
                color: mousePlay.containsMouse
                    ? Appearance.m3colors.m3primaryContainer
                    : Appearance.colors.colLayer2
                Behavior on color { ColorAnimation { duration: 120 } }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.playing ? "pause" : "play_arrow"
                    iconSize: 32
                    color: Appearance.colors.colOnLayer1
                }

                MouseArea {
                    id: mousePlay
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.control("toggle-play")
                }
            }

            PortActionButton {
                icon: "skip_next"
                onClicked: root.control("next")
            }
        }
    }
}