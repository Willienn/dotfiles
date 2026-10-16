import qs.modules.common
import QtQuick

/**
 * Barra de progresso fina e arredondada. value vai de 0 a 1.
 */
Rectangle {
    id: bar

    property real value: 0
    property color barColor: Appearance.m3colors.m3primary

    implicitHeight: 6
    radius: height / 2
    color: Qt.rgba(barColor.r, barColor.g, barColor.b, 0.18)

    Rectangle {
        height: parent.height
        radius: height / 2
        width: parent.width * Math.max(0, Math.min(1, bar.value))
        color: bar.barColor
        Behavior on width {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }
}
