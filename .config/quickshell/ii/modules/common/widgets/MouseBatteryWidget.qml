import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Item de barra. Some quando o mouse está fora de alcance.
RowLayout {
    id: root

    spacing: 2
    visible: DarmosharkBattery.available

    // Se os nomes de cor abaixo não existirem no seu Appearance, confira com:
    //   rg -n 'colOnLayer1|m3error|colError' modules/common/Appearance.qml
    readonly property color fgColor: DarmosharkBattery.isLow
        ? Appearance.m3colors.m3error
        : Appearance.colors.colOnLayer1

    MaterialSymbol {
        text: "mouse"
        iconSize: Appearance.font.pixelSize.larger
        color: root.fgColor

        SequentialAnimation on opacity {
            running: DarmosharkBattery.isLow
            loops: Animation.Infinite
            NumberAnimation { to: 0.4; duration: 800; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutQuad }
        }
    }

    StyledText {
        text: DarmosharkBattery.label
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: root.fgColor
    }


}
