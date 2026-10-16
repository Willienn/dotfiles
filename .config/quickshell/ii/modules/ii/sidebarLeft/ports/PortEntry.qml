import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Um item da lista de portas.
 * Clique no X arma o botão (fica vermelho); segundo clique envia SIGTERM.
 * Com o botão armado, clique direito envia SIGKILL.
 */
Rectangle {
    id: entry

    property var portInfo
    property bool armed: false
    readonly property bool killable: entry.portInfo && entry.portInfo.pid > 0
    readonly property color errorColor: Appearance.m3colors.m3error

    signal killRequested(bool force)
    signal openRequested()

    implicitHeight: row.implicitHeight + 16
    radius: Appearance.rounding.small
    color: entry.armed
        ? Qt.rgba(entry.errorColor.r, entry.errorColor.g, entry.errorColor.b, 0.15)
        : Appearance.colors.colLayer2
    Behavior on color { ColorAnimation { duration: 150 } }

    Timer {
        id: disarmTimer
        interval: 3000
        onTriggered: entry.armed = false
    }

    RowLayout {
        id: row
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 8
            rightMargin: 6
        }
        spacing: 10

        // Número da porta
        Rectangle {
            implicitWidth: Math.max(58, portText.implicitWidth + 16)
            implicitHeight: 36
            radius: Appearance.rounding.small
            color: Appearance.m3colors.m3secondaryContainer

            StyledText {
                id: portText
                anchors.centerIn: parent
                text: entry.portInfo.port
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
                color: Appearance.m3colors.m3onSecondaryContainer
            }
        }

        // Processo e detalhes
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: entry.killable
                    ? entry.portInfo.name + (entry.portInfo.extraCount > 0 ? ` +${entry.portInfo.extraCount}` : "")
                    : "Processo do sistema"
                color: entry.killable ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: `${entry.portInfo.proto.toUpperCase()} · ${entry.portInfo.addresses.join(", ")}`
                    + (entry.killable ? ` · pid ${entry.portInfo.pid}` : "")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }

        PortActionButton {
            visible: entry.portInfo.proto === "tcp"
            icon: "open_in_new"
            onClicked: entry.openRequested()
        }

        PortActionButton {
            icon: entry.armed ? "check" : "close"
            enabledState: entry.killable
            iconColor: entry.armed ? entry.errorColor : Appearance.colors.colOnLayer1
            onClicked: {
                if (entry.armed) {
                    entry.armed = false;
                    entry.killRequested(false);
                } else {
                    entry.armed = true;
                    disarmTimer.restart();
                }
            }
            onRightClicked: {
                if (entry.armed) {
                    entry.armed = false;
                    entry.killRequested(true);
                }
            }
        }
    }
}
