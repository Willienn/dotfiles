import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarLeft.updates
import qs.modules.ii.sidebarLeft.ports
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * Aba de atualizações: repo oficial (checkupdates), AUR (yay -Qua) e Flatpak.
 * Os botões abrem o kitty rodando o update correspondente.
 */
Item {
    id: root

    property real padding: 4
    property bool isActive: SwipeView.view ? SwipeView.isCurrentItem : true

    property string script: Qt.resolvedUrl("updates.sh").toString().replace("file://", "")

    property bool pacmanLocked: false
    property var repoUpdates: []
    property var aurUpdates: []
    property var flatpakUpdates: []

    readonly property int totalCount: root.repoUpdates.length + root.aurUpdates.length + root.flatpakUpdates.length

    function refresh() {
        if (updatesProc.running) return;
        updatesProc.buffer = "";
        updatesProc.running = true;
    }

    function parse(text) {
        const repo = [];
        const aur = [];
        const flat = [];
        let locked = false;

        for (const raw of text.split("\n")) {
            const line = raw.trim();
            if (line.length === 0) continue;

            if (line === "locked") {
                locked = true;
                continue;
            }

            const p = line.split(/\s+/);
            const kind = p[0];

            if (kind === "repo" || kind === "aur") {
                // formato: "repo nome 1.0 -> 2.0"
                // p = [kind, nome, antiga, "->", nova]
                const name = p[1];
                const oldV = p[2];
                const newV = p[p.length - 1];
                const item = { name: name, oldVersion: oldV, newVersion: newV };
                if (kind === "repo") repo.push(item);
                else aur.push(item);
            } else if (kind === "flatpak") {
                // formato: "flatpak id versao"
                const name = p[1];
                const version = p.slice(2).join(" ");
                flat.push({ name: name, oldVersion: "", newVersion: version });
            }
        }

        root.pacmanLocked = locked;
        root.repoUpdates = repo;
        root.aurUpdates = aur;
        root.flatpakUpdates = flat;
    }

    Timer {
        interval: 60000
        repeat: true
        triggeredOnStart: true
        running: root.isActive && root.visible
        onTriggered: root.refresh()
    }

    // Atualiza de novo pouco depois de fechar um terminal de update
    Timer {
        id: refreshDelay
        interval: 1500
        onTriggered: root.refresh()
    }

    Process {
        id: updatesProc
        command: ["sh", root.script]
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => {
                updatesProc.buffer += data + "\n";
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.parse(updatesProc.buffer);
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
                text: "Atualizações"
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                text: `${root.totalCount}`
                color: Appearance.colors.colSubtext
            }
            Item { Layout.fillWidth: true }
            PortActionButton {
                icon: "refresh"
                onClicked: root.refresh()
            }
        }

        // Aviso de banco ocupado
        Rectangle {
            visible: root.pacmanLocked
            Layout.fillWidth: true
            implicitHeight: lockRow.implicitHeight + 16
            radius: Appearance.rounding.small
            color: Qt.rgba(Appearance.m3colors.m3error.r, Appearance.m3colors.m3error.g, Appearance.m3colors.m3error.b, 0.15)

            RowLayout {
                id: lockRow
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                    rightMargin: 12
                }
                spacing: 8

                MaterialSymbol {
                    text: "lock"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.m3colors.m3error
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "Banco do pacman ocupado — outro processo está rodando"
                    color: Appearance.m3colors.m3error
                }
            }
        }

        // Lista
        StyledFlickable {
            id: listFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: listColumn.implicitHeight
            clip: true

            Column {
                id: listColumn
                width: listFlick.width
                spacing: 8

                // Repo oficial
                StyledText {
                    visible: root.repoUpdates.length > 0
                    width: parent.width
                    leftPadding: 6
                    topPadding: 4
                    text: `Repo oficial (${root.repoUpdates.length})`
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                }
                Repeater {
                    model: root.repoUpdates
                    delegate: UpdateEntry {
                        required property var modelData
                        width: listColumn.width
                        packageName: modelData.name
                        oldVersion: modelData.oldVersion
                        newVersion: modelData.newVersion
                    }
                }

                // AUR
                StyledText {
                    visible: root.aurUpdates.length > 0
                    width: parent.width
                    leftPadding: 6
                    topPadding: 4
                    text: `AUR (${root.aurUpdates.length})`
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                }
                Repeater {
                    model: root.aurUpdates
                    delegate: UpdateEntry {
                        required property var modelData
                        width: listColumn.width
                        packageName: modelData.name
                        oldVersion: modelData.oldVersion
                        newVersion: modelData.newVersion
                    }
                }

                // Flatpak
                StyledText {
                    visible: root.flatpakUpdates.length > 0
                    width: parent.width
                    leftPadding: 6
                    topPadding: 4
                    text: `Flatpak (${root.flatpakUpdates.length})`
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                }
                Repeater {
                    model: root.flatpakUpdates
                    delegate: UpdateEntry {
                        required property var modelData
                        width: listColumn.width
                        packageName: modelData.name
                        oldVersion: modelData.oldVersion
                        newVersion: modelData.newVersion
                    }
                }

                // Nada pendente
                StyledText {
                    visible: !root.pacmanLocked && root.totalCount === 0
                    width: parent.width
                    topPadding: 20
                    horizontalAlignment: Text.AlignHCenter
                    text: "Tudo atualizado"
                    color: Appearance.colors.colSubtext
                }
            }
        }

        // Botões de atualizar
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            UpdateButton {
                Layout.fillWidth: true
                icon: "download"
                label: "Repo + AUR"
                enabledState: !root.pacmanLocked && (root.repoUpdates.length + root.aurUpdates.length) > 0
                onClicked: {
                    Quickshell.execDetached(["kitty", "-e", "yay", "-Syu"]);
                    refreshDelay.restart();
                }
            }

            UpdateButton {
                Layout.fillWidth: true
                icon: "download"
                label: "Flatpak"
                enabledState: root.flatpakUpdates.length > 0
                onClicked: {
                    Quickshell.execDetached(["kitty", "-e", "flatpak", "update"]);
                    refreshDelay.restart();
                }
            }
        }
    }
}