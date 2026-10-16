import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarLeft.monitor
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * Monitor do sistema: CPU, memória, GPU AMD, disco e processos.
 * A coleta roda em monitor/stats.sh e monitor/top.sh, só enquanto a aba está visível.
 */
Item {
    id: root

    property real padding: 4
    property bool isActive: SwipeView.view ? SwipeView.isCurrentItem : true
    readonly property int historySize: 60

    // Caminhos dos scripts, relativos a este arquivo
    property string statsScript: Qt.resolvedUrl("monitor/stats.sh").toString().replace("file://", "")
    property string topScript: Qt.resolvedUrl("monitor/top.sh").toString().replace("file://", "")

    // CPU
    property real cpuUsage: 0
    property real cpuTemp: -1
    property real prevTotal: 0
    property real prevIdle: 0

    // Memória (kB)
    property real memTotal: 0
    property real memUsed: 0
    property real swapTotal: 0
    property real swapUsed: 0

    // GPU
    property bool hasGpu: false
    property real gpuUsage: 0
    property real gpuTemp: -1
    property real gpuPower: -1
    property real vramUsed: 0
    property real vramTotal: 0

    // Disco (bytes)
    property real diskUsed: 0
    property real diskTotal: 0

    // Históricos (percentuais) e processos
    property var cpuHistory: []
    property var memHistory: []
    property var gpuHistory: []
    property var topList: []

    readonly property real memPercent: root.memTotal > 0 ? (root.memUsed / root.memTotal) * 100 : 0

    function pushHistory(arr, value) {
        return [...arr, value].slice(-root.historySize);
    }

    function formatBytes(bytes) {
        const gib = bytes / 1073741824;
        if (gib >= 100) return gib.toFixed(0) + " GiB";
        if (gib >= 1) return gib.toFixed(1) + " GiB";
        return (bytes / 1048576).toFixed(0) + " MiB";
    }

    function parseStats(text) {
        const lines = text.split("\n");
        let gotCpu = false;
        let gotGpu = false;

        for (const line of lines) {
            const p = line.trim().split(/\s+/);
            const key = p[0];

            if (key === "cpu" && p.length >= 5) {
                const v = p.slice(1).map(Number);
                const total = v.reduce((a, b) => a + b, 0);
                const idle = v[3] + (v[4] || 0);
                if (root.prevTotal > 0 && total > root.prevTotal) {
                    const dt = total - root.prevTotal;
                    const di = idle - root.prevIdle;
                    root.cpuUsage = Math.max(0, Math.min(100, (1 - di / dt) * 100));
                    gotCpu = true;
                }
                root.prevTotal = total;
                root.prevIdle = idle;
            } else if (key === "mem" && p.length >= 5) {
                const total = Number(p[1]);
                const avail = Number(p[2]);
                root.memTotal = total;
                root.memUsed = Math.max(0, total - avail);
                root.swapTotal = Number(p[3]);
                root.swapUsed = Math.max(0, Number(p[3]) - Number(p[4]));
            } else if (key === "cputemp") {
                root.cpuTemp = Number(p[1]) / 1000;
            } else if (key === "gpu" && p.length >= 4) {
                root.hasGpu = true;
                const busy = Number(p[1]);
                if (busy >= 0) root.gpuUsage = busy;
                root.vramUsed = Number(p[2]);
                root.vramTotal = Number(p[3]);
                gotGpu = true;
            } else if (key === "gputemp") {
                root.gpuTemp = Number(p[1]) / 1000;
            } else if (key === "gpupower") {
                root.gpuPower = Number(p[1]) / 1000000;
            } else if (key === "disk" && p.length >= 3) {
                root.diskUsed = Number(p[1]);
                root.diskTotal = Number(p[2]);
            }
        }

        if (gotCpu) root.cpuHistory = root.pushHistory(root.cpuHistory, root.cpuUsage);
        if (root.memTotal > 0) root.memHistory = root.pushHistory(root.memHistory, root.memPercent);
        if (gotGpu) root.gpuHistory = root.pushHistory(root.gpuHistory, root.gpuUsage);
    }

    function parseTop(text) {
        const list = [];
        for (const line of text.split("\n")) {
            const p = line.trim().split(/\s+/);
            if (p.length < 4) continue;
            list.push({
                pid: Number(p[0]),
                cpu: parseFloat(p[1]) || 0,
                mem: parseFloat(p[2]) || 0,
                name: p.slice(3).join(" ")
            });
        }
        root.topList = list;
    }

    function refreshStats() {
        if (statsProc.running) return;
        statsProc.buffer = "";
        statsProc.running = true;
    }

    function refreshTop() {
        if (topProc.running) return;
        topProc.buffer = "";
        topProc.running = true;
    }

    Timer {
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: root.isActive && root.visible
        onTriggered: root.refreshStats()
    }

    Timer {
        interval: 5000
        repeat: true
        triggeredOnStart: true
        running: root.isActive && root.visible
        onTriggered: root.refreshTop()
    }

    Process {
        id: statsProc
        command: ["sh", root.statsScript]
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => {
                statsProc.buffer += data + "\n";
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.parseStats(statsProc.buffer);
        }
    }

    Process {
        id: topProc
        command: ["sh", root.topScript]
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => {
                topProc.buffer += data + "\n";
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.parseTop(topProc.buffer);
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: 8

        StyledText {
            Layout.leftMargin: 6
            text: "Sistema"
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer1
        }

        StyledFlickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: cardsColumn.implicitHeight
            clip: true

            ColumnLayout {
                id: cardsColumn
                width: parent.width
                spacing: 8

                StatCard {
                    icon: "memory"
                    title: "CPU"
                    valueText: `${Math.round(root.cpuUsage)}%`
                    detailText: root.cpuTemp >= 0 ? `Temperatura ${Math.round(root.cpuTemp)}°C` : ""
                    history: root.cpuHistory
                    accent: Appearance.m3colors.m3primary
                    warn: root.cpuUsage > 90 || root.cpuTemp > 90
                }

                StatCard {
                    icon: "developer_board"
                    title: "Memória"
                    valueText: `${Math.round(root.memPercent)}%`
                    detailText: `${root.formatBytes(root.memUsed * 1024)} de ${root.formatBytes(root.memTotal * 1024)}`
                        + (root.swapTotal > 0 ? ` · swap ${root.formatBytes(root.swapUsed * 1024)}` : "")
                    history: root.memHistory
                    accent: Appearance.m3colors.m3tertiary
                    warn: root.memPercent > 92
                }

                StatCard {
                    visible: root.hasGpu
                    icon: "videogame_asset"
                    title: "GPU"
                    valueText: `${Math.round(root.gpuUsage)}%`
                    detailText: `VRAM ${root.formatBytes(root.vramUsed)} de ${root.formatBytes(root.vramTotal)}`
                        + (root.gpuTemp >= 0 ? ` · ${Math.round(root.gpuTemp)}°C` : "")
                        + (root.gpuPower >= 0 ? ` · ${Math.round(root.gpuPower)} W` : "")
                    history: root.gpuHistory
                    accent: Appearance.m3colors.m3secondary
                    warn: root.gpuUsage > 98 || root.gpuTemp > 95
                }

                StatCard {
                    icon: "hard_drive"
                    title: "Disco"
                    valueText: root.diskTotal > 0 ? `${Math.round(root.diskUsed / root.diskTotal * 100)}%` : "--"
                    detailText: `${root.formatBytes(root.diskUsed)} de ${root.formatBytes(root.diskTotal)}`
                    showGraph: false
                    barValue: root.diskTotal > 0 ? root.diskUsed / root.diskTotal : 0
                    accent: Appearance.m3colors.m3primary
                    warn: root.diskTotal > 0 && root.diskUsed / root.diskTotal > 0.92
                }

                // Processos
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: procColumn.implicitHeight + 24
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2

                    ColumnLayout {
                        id: procColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: 12
                        }
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            StyledText {
                                Layout.fillWidth: true
                                text: "Processos"
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.preferredWidth: 56
                                horizontalAlignment: Text.AlignRight
                                text: "CPU"
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {
                                Layout.preferredWidth: 56
                                horizontalAlignment: Text.AlignRight
                                text: "RAM"
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }

                        Repeater {
                            model: root.topList
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 8

                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: modelData.name
                                    color: Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    Layout.preferredWidth: 56
                                    horizontalAlignment: Text.AlignRight
                                    text: modelData.cpu.toFixed(1) + "%"
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    Layout.preferredWidth: 56
                                    horizontalAlignment: Text.AlignRight
                                    text: modelData.mem.toFixed(1) + "%"
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }

                        StyledText {
                            visible: root.topList.length === 0
                            Layout.alignment: Qt.AlignHCenter
                            text: "Coletando..."
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }
}
