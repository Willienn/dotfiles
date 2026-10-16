import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * Botão redondo de ícone, independente dos botões do end-4.
 */
Rectangle {
    id: button

    property string icon: ""
    property color iconColor: Appearance.colors.colOnLayer1
    property bool enabledState: true

    signal clicked()
    signal rightClicked()

    implicitWidth: 32
    implicitHeight: 32
    radius: width / 2
    opacity: button.enabledState ? 1 : 0.4
    color: mouseArea.containsMouse && button.enabledState
        ? Qt.rgba(button.iconColor.r, button.iconColor.g, button.iconColor.b, 0.12)
        : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }

    MaterialSymbol {
        anchors.centerIn: parent
        text: button.icon
        iconSize: Appearance.font.pixelSize.larger
        color: button.iconColor
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: button.enabledState
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) button.rightClicked();
            else button.clicked();
        }
    }
}
