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
 * Lista portas abertas (TCP/UDP) usando `ss`, com opção de abrir no
 * navegador e encerrar o processo dono da porta.
 */
Item {
    id: root

    property real padding: 4
    property var entries: []
    property string lastOutput: ""
    property string filterText: ""
    property string protoFilter: "all" // "all" | "tcp" | "udp"

    // Só atualiza enquanto a aba está visível
    property bool isActive: SwipeView.view ? SwipeView.isCurrentItem : true

    property var visibleEntries: root.entries.filter(e => {
        if (root.protoFilter !== "all" && e.proto !== root.protoFilter) return false;
        const q = root.filterText.trim().toLowerCase();
        if (q.length === 0) return true;
        return String(e.port).includes(q)
            || e.name.toLowerCase().includes(q)
            || e.addresses.join(" ").toLowerCase().includes(q);
    })

    function refresh() {
        if (ssProc.running) return;
        ssProc.buffer = "";
        ssProc.running = true;
    }

    function parseSs(text) {
        const map = {};
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const parts = lines[i].trim().split(/\s+/);
            if (parts.length < 5) continue;

            const proto = parts[0];
            const local = parts[4];
            const idx = local.lastIndexOf(":");
            if (idx < 0) continue;

            let addr = local.substring(0, idx).replace(/^\[|\]$/g, "");
            addr = addr.split("%")[0];
            const port = parseInt(local.substring(idx + 1));
            if (isNaN(port)) continue;

            // users:(("node",pid=1234,fd=20),("node",pid=1235,fd=20))
            const procField = parts.slice(6).join(" ");
            const procs = [];
            const re = /\("([^"]+)",pid=(\d+)/g;
            let m;
            while ((m = re.exec(procField)) !== null) {
                procs.push({ name: m[1], pid: parseInt(m[2]) });
            }
            const first = procs.length > 0 ? procs[0] : null;

            const key = `${proto}:${port}:${first ? first.pid : "?"}`;
            if (!map[key]) {
                map[key] = {
                    key: key,
                    proto: proto,
                    port: port,
                    addresses: [],
                    name: first ? first.name : "",
                    pid: first ? first.pid : -1,
                    extraCount: Math.max(0, procs.length - 1)
                };
            }
            if (map[key].addresses.indexOf(addr) < 0) map[key].addresses.push(addr);
        }
        return Object.values(map).sort((a, b) => (a.port - b.port) || a.proto.localeCompare(b.proto));
    }

    function killEntry(entry, force) {
        if (entry.pid <= 0) return;
        Quickshell.execDetached(["kill", force ? "-9" : "-15", String(entry.pid)]);
        refreshDelay.restart();
    }

    Timer {
        interval: 3000
        repeat: true
        triggeredOnStart: true
        running: root.isActive && root.visible
        onTriggered: root.refresh()
    }

    Timer {
        id: refreshDelay
        interval: 500
        onTriggered: root.refresh()
    }

    Process {
        id: ssProc
        command: ["ss", "-tulpnH"]
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => {
                ssProc.buffer += data + "\n";
            }
        }
        onExited: (exitCode, exitStatus) => {
            // Evita recriar a lista se nada mudou
            if (ssProc.buffer === root.lastOutput) return;
            root.lastOutput = ssProc.buffer;
            root.entries = root.parseSs(ssProc.buffer);
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
                text: "Portas abertas"
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                text: `${root.visibleEntries.length}`
                color: Appearance.colors.colSubtext
            }
            Item { Layout.fillWidth: true }
            PortActionButton {
                icon: "refresh"
                onClicked: root.refresh()
            }
        }

        // Busca
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 40
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: 10
                    rightMargin: 10
                }
                spacing: 6

                MaterialSymbol {
                    text: "search"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colSubtext
                }
                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    background: null
                    color: Appearance.colors.colOnLayer1
                    placeholderText: "Porta, processo ou endereço"
                    placeholderTextColor: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.normal
                    onTextChanged: root.filterText = text
                }
            }
        }

        // Filtro de protocolo
        Row {
            Layout.leftMargin: 2
            spacing: 6

            Repeater {
                model: [
                    { id: "all", label: "Tudo" },
                    { id: "tcp", label: "TCP" },
                    { id: "udp", label: "UDP" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    property bool selected: root.protoFilter === modelData.id
                    implicitWidth: chipText.implicitWidth + 24
                    implicitHeight: 30
                    radius: 2
                    color: selected ? Appearance.m3colors.m3secondaryContainer : "transparent"
                    border.width: selected ? 0 : 1
                    border.color: Appearance.colors.colSubtext
                    Behavior on color { ColorAnimation { duration: 120 } }

                    StyledText {
                        id: chipText
                        anchors.centerIn: parent
                        text: modelData.label
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: parent.selected ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer1
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.protoFilter = modelData.id
                    }
                }
            }
        }

        // Lista
        StyledFlickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: listColumn.implicitHeight
            clip: true

            ColumnLayout {
                id: listColumn
                width: parent.width
                spacing: 6

                Repeater {
                    model: root.visibleEntries
                    delegate: PortEntry {
                        required property var modelData
                        Layout.fillWidth: true
                        portInfo: modelData
                        onKillRequested: force => root.killEntry(modelData, force)
                        onOpenRequested: Qt.openUrlExternally(`http://localhost:${modelData.port}`)
                    }
                }
            }
        }

        StyledText {
            visible: root.visibleEntries.length === 0
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 20
            text: root.entries.length === 0 ? "Nenhuma porta aberta" : "Nada encontrado"
            color: Appearance.colors.colSubtext
        }
    }
}
