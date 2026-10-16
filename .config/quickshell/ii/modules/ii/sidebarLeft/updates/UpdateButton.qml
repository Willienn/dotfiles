import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Botão retangular com ícone + texto, para os botões de atualizar.
 * Feito à mão porque o GroupButton do end-4 não lida bem com contentItem livre.
 */
Rectangle {
    id: button

    property string icon: ""
    property string label: ""
    property bool enabledState: true

    signal clicked()

    implicitHeight: 44
    radius: Appearance.rounding.small
    color: {
        if (!button.enabledState) return Qt.rgba(Appearance.colors.colOnLayer1.r, Appearance.colors.colOnLayer1.g, Appearance.colors.colOnLayer1.b, 0.06);
        if (mouseArea.containsMouse) return Appearance.m3colors.m3primaryContainer;
        return Appearance.colors.colLayer2;
    }
    opacity: button.enabledState ? 1 : 0.5
    Behavior on color { ColorAnimation { duration: 120 } }

    RowLayout {
        anchors.centerIn: parent
        spacing: 8

        MaterialSymbol {
            text: button.icon
            iconSize: Appearance.font.pixelSize.larger
            color: button.enabledState ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
        }
        StyledText {
            text: button.label
            color: button.enabledState ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: button.enabledState
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}