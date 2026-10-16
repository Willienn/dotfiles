pragma Singleton

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string script: Quickshell.shellPath("scripts/darmoshark-battery.py")

    property int percentage: -1
    property int rawState: -1
    property int rawFlag: -1
    property bool connected: false
    property string lastError: ""

    readonly property bool available: percentage >= 0 && connected
    readonly property bool isLow: available
        && percentage <= (Config.options.battery?.low ?? 20)

    readonly property string label: available ? `${percentage}%` : "--"

    Process {
        id: proc
        command: [root.script]
        running: true

        stdout: SplitParser {
            onRead: line => {
                if (!line) return;
                let d;
                try {
                    d = JSON.parse(line);
                } catch (e) {
                    return;
                }

                if (d.error !== undefined) {
                    root.connected = false;
                    root.lastError = d.error;
                    return;
                }

                if (d.connected !== undefined) {
                    root.connected = true;
                    root.lastError = "";
                    return;
                }

                if (d.percentage !== undefined) {
                    root.connected = true;
                    root.percentage = d.percentage;
                    root.rawState = d.state;
                    root.rawFlag = d.flag;
                }
            }
        }

        onExited: {
            root.connected = false;
            respawn.start();
        }
    }

    Timer {
        id: respawn
        interval: 5000
        onTriggered: proc.running = true
    }
}
