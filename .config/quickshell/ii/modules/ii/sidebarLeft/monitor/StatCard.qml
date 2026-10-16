import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Cartão de uma métrica: ícone, título, valor grande, gráfico
 * de histórico opcional, barra opcional e uma linha de detalhes.
 */
Rectangle {
    id: card

    property string icon: ""
    property string title: ""
    property string valueText: ""
    property string detailText: ""
    property var history: []
    property bool showGraph: true
    property real barValue: -1 // 0..1; negativo esconde a barra
    property color accent: Appearance.m3colors.m3primary
    property bool warn: false

    readonly property color effectiveAccent: card.warn ? Appearance.m3colors.m3error : card.accent

    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + 24
    radius: Appearance.rounding.small
    color: Appearance.colors.colLayer2

    ColumnLayout {
        id: content
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 12
        }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                implicitWidth: 34
                implicitHeight: 34
                radius: width / 2
                color: Qt.rgba(card.effectiveAccent.r, card.effectiveAccent.g, card.effectiveAccent.b, 0.16)

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: card.icon
                    iconSize: Appearance.font.pixelSize.larger
                    color: card.effectiveAccent
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: card.title
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                text: card.valueText
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
                color: card.effectiveAccent
            }
        }

        Sparkline {
            visible: card.showGraph
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            values: card.history
            lineColor: card.effectiveAccent
        }

        UsageBar {
            visible: card.barValue >= 0
            Layout.fillWidth: true
            value: card.barValue
            barColor: card.effectiveAccent
        }

        StyledText {
            visible: card.detailText.length > 0
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: card.detailText
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }
}
