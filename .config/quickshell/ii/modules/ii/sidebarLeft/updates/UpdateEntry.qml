import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Item da lista de atualizações: nome do pacote, versão antiga -> nova.
 * Para Flatpak, só a versão atual (não dá pra saber a antiga sem consultar).
 */
Rectangle {
    id: entry

    property string packageName: ""
    property string oldVersion: ""
    property string newVersion: ""

    implicitHeight: Math.max(48, row.implicitHeight + 16)
    radius: Appearance.rounding.small
    color: Appearance.colors.colLayer2

    RowLayout {
        id: row
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 12
            rightMargin: 12
        }
        spacing: 10

        MaterialSymbol {
            text: "package_2"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.m3colors.m3primary
        }

        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: entry.packageName
            color: Appearance.colors.colOnLayer1
        }

        StyledText {
            visible: entry.oldVersion.length > 0
            text: entry.oldVersion
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }

        MaterialSymbol {
            visible: entry.oldVersion.length > 0
            text: "arrow_forward"
            iconSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }

        StyledText {
            text: entry.newVersion
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: Appearance.m3colors.m3primary
        }
    }
}